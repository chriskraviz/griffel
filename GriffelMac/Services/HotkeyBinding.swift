import AppKit
import Carbon.HIToolbox

/// A user-assignable shortcut.
///
/// Two shapes, because macOS needs two different mechanisms for them. A pure
/// modifier chord (`fn + Shift`) can only be *observed* through
/// `NSEvent.flagsChanged` — which is fine, because modifiers type nothing. A
/// combination with a real key must be *registered* with Carbon instead, so
/// the keystroke is consumed rather than typed into whatever app is in front:
/// holding a plain global monitor's key would fill the frontmost document with
/// repeats while the user is still speaking.
struct Hotkey: Codable, Hashable {
    /// Carbon virtual key code. nil means this is a pure modifier chord.
    var keyCode: UInt16?
    /// `NSEvent.ModifierFlags.rawValue`, device-independent subset only.
    var modifiers: UInt

    /// Deliberately narrower than `.deviceIndependentFlagsMask`, which also
    /// carries caps lock (a chord would never resolve while it is on) and
    /// `.numericPad` (set by the arrow keys). Only these five ever belong to a
    /// shortcut.
    static let relevantMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command, .function]

    /// Key codes that set `.function` all by themselves. AppKit raises
    /// `NSEventModifierFlagFunction` for the whole *function-key group* — the F
    /// keys and the navigation keys — not just the physical fn key, and both
    /// share bit 1<<23. So the flag alone cannot tell "held fn" from "pressed
    /// F5", and only the key code can: without this, recording `⌘F5` would be
    /// refused as an fn combination the user never pressed.
    private static let functionGroupKeyCodes: Set<UInt16> = {
        var codes: Set<UInt16> = [
            UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow),
            UInt16(kVK_UpArrow), UInt16(kVK_DownArrow),
            UInt16(kVK_Home), UInt16(kVK_End),
            UInt16(kVK_PageUp), UInt16(kVK_PageDown),
            UInt16(kVK_ForwardDelete), UInt16(kVK_Help),
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
            kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
            kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for key in functionKeys { codes.insert(UInt16(key)) }
        return codes
    }()

    /// One place that decides which bits a stored shortcut keeps, so the
    /// recorder, the decoder and `validate()` can never disagree.
    private static func normalized(_ modifiers: NSEvent.ModifierFlags, keyCode: UInt16?) -> NSEvent.ModifierFlags {
        var relevant = modifiers.intersection(relevantMask)
        if let keyCode, functionGroupKeyCodes.contains(keyCode) {
            relevant.remove(.function)
        }
        return relevant
    }

    init(keyCode: UInt16? = nil, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = Self.normalized(modifiers, keyCode: keyCode).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.relevantMask)
    }

    var isChord: Bool { keyCode == nil }

    /// Chords are matched longest-first, so this is what orders them.
    var modifierCount: Int {
        Self.orderedModifiers.reduce(into: 0) { count, entry in
            if modifierFlags.contains(entry.flag) { count += 1 }
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    /// Field by field with a default, like every other stored settings type
    /// here: a `keyNotFound` thrown from one binding is decoded inside
    /// `AppSettings`, whose own `try?` would reset *every* setting the user has.
    /// A binding that decodes to nonsense fails `validate()` and is dropped
    /// back to the shipped default rather than stranding a workflow.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)
        let stored = try container.decodeIfPresent(UInt.self, forKey: .modifiers) ?? 0
        modifiers = Self.normalized(NSEvent.ModifierFlags(rawValue: stored), keyCode: keyCode).rawValue
    }

    // MARK: - Display

    /// Ordered the way macOS prints modifiers, so a badge reads the same as a
    /// menu shortcut does. Two spellings: symbols stay narrow enough that a
    /// four-part combination still fits on keycaps, words read better inside a
    /// sentence.
    private static let orderedModifiers: [(flag: NSEvent.ModifierFlags, symbol: String, word: String)] = [
        (.function, "fn", "fn"),
        (.control, "\u{2303}", "Ctrl"),
        (.option, "\u{2325}", "Option"),
        (.shift, "\u{21E7}", "Shift"),
        (.command, "\u{2318}", "Cmd"),
    ]

    /// One token per keycap.
    var keycapTokens: [String] {
        var tokens = Self.orderedModifiers
            .filter { modifierFlags.contains($0.flag) }
            .map(\.symbol)
        if let keyCode {
            tokens.append(KeyCodeNames.name(for: keyCode))
        }
        return tokens
    }

    /// For running text: "fn + Shift" rather than "fn + \u{21E7}".
    var displayLabel: String {
        var tokens = Self.orderedModifiers
            .filter { modifierFlags.contains($0.flag) }
            .map(\.word)
        if let keyCode {
            tokens.append(KeyCodeNames.name(for: keyCode))
        }
        return tokens.isEmpty ? "\u{2014}" : tokens.joined(separator: " + ")
    }

    // MARK: - Validation

    enum ValidationError: Equatable {
        /// A single modifier is held constantly during normal typing.
        case chordNeedsTwoModifiers
        case keyNeedsModifier
        /// Carbon has no fn bit, so an fn key combo cannot be registered and
        /// would be typed into the frontmost app instead of being consumed.
        case functionKeyNotCombinable
        case alreadyUsed(String)

        var message: String {
            switch self {
            case .chordNeedsTwoModifiers:
                return "Ein K\u{00FC}rzel ohne Taste braucht mindestens zwei Modifier."
            case .keyNeedsModifier:
                return "Mit einer Taste braucht es mindestens einen Modifier."
            case .functionKeyNotCombinable:
                return "fn l\u{00E4}sst sich nicht mit einer Taste kombinieren \u{2014} nimm Ctrl, Option, Shift oder Cmd."
            case .alreadyUsed(let name):
                return "Schon von \u{201E}\(name)\u{201C} belegt."
            }
        }
    }

    /// Shape validation only. Whether the system already owns the combination
    /// is answered by `RegisterEventHotKey`, not guessed at here.
    func validate() -> ValidationError? {
        guard keyCode != nil else {
            return modifierCount >= 2 ? nil : .chordNeedsTwoModifiers
        }
        if modifierFlags.contains(.function) {
            return .functionKeyNotCombinable
        }
        let usable: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        return modifierFlags.intersection(usable).isEmpty ? .keyNeedsModifier : nil
    }

    /// Carbon's own modifier bits. fn has no equivalent and is dropped — a key
    /// combo carrying it never passes `validate()`.
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifierFlags.contains(.command) { value |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { value |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { value |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    // MARK: - Defaults

    /// The combos the app shipped with. Chords throughout: they are the best
    /// fit for push-to-talk, since holding one types nothing.
    static func `default`(for type: WorkflowType) -> Hotkey {
        switch type {
        case .transcription: return Hotkey(modifiers: [.function, .shift])
        case .textImprover: return Hotkey(modifiers: [.function, .control])
        case .braindump: return Hotkey(modifiers: [.function, .command, .shift])
        case .selectionEdit: return Hotkey(modifiers: [.function, .option, .shift])
        }
    }

    static var defaultBindings: [String: Hotkey] {
        WorkflowType.allCases.reduce(into: [:]) { result, type in
            result[type.rawValue] = .default(for: type)
        }
    }

    /// Well-known system shortcuts. Only used for a warning — the user decides,
    /// and `RegisterEventHotKey` still has the final say on whether it works.
    var systemConflictName: String? {
        guard let keyCode else { return nil }
        let usable = modifierFlags.intersection([.control, .option, .shift, .command])
        for entry in Self.knownSystemShortcuts
        where entry.keyCode == keyCode && entry.modifiers == usable {
            return entry.name
        }
        return nil
    }

    private static let knownSystemShortcuts: [(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, name: String)] = [
        (UInt16(kVK_Space), [.command], "Spotlight"),
        (UInt16(kVK_Space), [.control, .command], "Zeichen\u{00FC}bersicht"),
        (UInt16(kVK_Space), [.control], "Eingabequelle wechseln"),
        (UInt16(kVK_Tab), [.command], "App-Umschalter"),
        (UInt16(kVK_ANSI_Q), [.command], "App beenden"),
        (UInt16(kVK_ANSI_W), [.command], "Fenster schlie\u{00DF}en"),
        (UInt16(kVK_ANSI_3), [.shift, .command], "Bildschirmfoto"),
        (UInt16(kVK_ANSI_4), [.shift, .command], "Bildschirmfoto-Auswahl"),
        (UInt16(kVK_ANSI_5), [.shift, .command], "Bildschirmfoto-Optionen"),
        (UInt16(kVK_ANSI_5), [.command], "Bildschirmfoto-Optionen"),
        (UInt16(kVK_UpArrow), [.control], "Mission Control"),
        (UInt16(kVK_DownArrow), [.control], "App-Fenster"),
    ]
}

// MARK: - Key names

/// Turns a virtual key code into what is actually printed on this Mac's
/// keyboard. Translating through the live layout matters: on a German layout
/// `kVK_ANSI_Y` is the Z key, and a badge showing "Y" would simply be wrong.
enum KeyCodeNames {
    static func name(for keyCode: UInt16) -> String {
        if let special = specialNames[keyCode] { return special }
        if let character = character(for: keyCode), !character.isEmpty {
            return character.uppercased()
        }
        return "#\(keyCode)"
    }

    private static let specialNames: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_ANSI_KeypadEnter): "Enter",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Delete): "L\u{00F6}schen",
        UInt16(kVK_ForwardDelete): "Entf",
        UInt16(kVK_Escape): "Esc",
        UInt16(kVK_Home): "Pos1",
        UInt16(kVK_End): "Ende",
        UInt16(kVK_PageUp): "Bild\u{2191}",
        UInt16(kVK_PageDown): "Bild\u{2193}",
        UInt16(kVK_LeftArrow): "\u{2190}",
        UInt16(kVK_RightArrow): "\u{2192}",
        UInt16(kVK_UpArrow): "\u{2191}",
        UInt16(kVK_DownArrow): "\u{2193}",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]

    private static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(-1)
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
