import Cocoa
import Carbon.HIToolbox
import Observation

enum HotkeyMode: String, Codable, CaseIterable, Identifiable {
    case hold    // Tasten halten = aufnehmen, loslassen = stoppen
    case toggle  // Einmal drücken = starten, nochmal/Escape = stoppen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold: return "Halten"
        case .toggle: return "Drücken"
        }
    }

    var description: String {
        switch self {
        case .hold: return "Tasten halten zum Aufnehmen, loslassen zum Stoppen"
        case .toggle: return "Einmal drücken zum Starten, nochmal oder Escape zum Stoppen"
        }
    }
}

enum HotkeyEvent {
    case down(WorkflowType)  // Keys pressed
    case up(WorkflowType)    // Keys released (for hold mode)
    case cancel              // Escape pressed
}

@Observable
@MainActor
final class HotkeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyMonitor: Any?

    /// Which chord is currently held, and which registered key combo is
    /// currently down. Tracked apart because they arrive on different paths.
    private var activeChord: WorkflowType?
    private var activeKeyCombo: WorkflowType?

    /// Chords pre-sorted longest-first: `fn+Cmd+Shift` has to win over the
    /// `fn+Shift` subset the user passes through on the way to it.
    private var sortedChords: [(type: WorkflowType, flags: NSEvent.ModifierFlags)] = []

    private var registrations: [WorkflowType: EventHotKeyRef] = [:]
    private var carbonHandler: EventHandlerRef?
    private var bindings: [String: Hotkey] = Hotkey.defaultBindings

    /// Counted, not a flag: two recorder fields can be armed for a moment
    /// while one hands over to the other, and a plain Bool would let the
    /// first `resume()` re-arm every combination while the second field is
    /// still reading a keystroke.
    private var suspendCount = 0

    /// True while the settings pane records a new shortcut. Carbon
    /// registrations are torn down for the duration — otherwise the combination
    /// being recorded would be swallowed before the recorder ever sees it.
    var isSuspended: Bool { suspendCount > 0 }

    /// Combinations the system refused, keyed by workflow. The settings pane
    /// reads this to say so instead of leaving a dead shortcut on screen.
    private(set) var registrationFailures: Set<WorkflowType> = []

    var onHotkeyEvent: ((HotkeyEvent) -> Void)?

    private static let hotkeySignature: OSType = 0x56434D44 // 'VCMD'

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlags(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlags(event)
            }
            return event
        }
        // Escape key monitor for toggle mode
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                if event.keyCode == 53 { // Escape
                    self?.handleEscape()
                }
            }
        }
        installCarbonHandler()
        apply(bindings: bindings)
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        globalMonitor = nil
        localMonitor = nil
        keyMonitor = nil
        unregisterAll()
        if let carbonHandler {
            RemoveEventHandler(carbonHandler)
            self.carbonHandler = nil
        }
    }

    // MARK: - Bindings

    func hotkey(for type: WorkflowType) -> Hotkey {
        bindings[type.rawValue] ?? .default(for: type)
    }

    /// Rebuilds both paths from one source. Called on every settings change,
    /// so a rebind takes effect without restarting the app.
    func apply(bindings: [String: Hotkey]) {
        self.bindings = bindings
        activeChord = nil
        activeKeyCombo = nil

        sortedChords = WorkflowType.allCases
            .map { ($0, hotkey(for: $0)) }
            .filter { $0.1.isChord && $0.1.validate() == nil }
            .sorted { $0.1.modifierCount > $1.1.modifierCount }
            .map { ($0.0, $0.1.modifierFlags) }

        guard !isSuspended else { return }
        registerAll()
    }

    /// Frees the combinations so a recorder can see the raw keystrokes.
    func suspend() {
        suspendCount += 1
        guard suspendCount == 1 else { return }
        activeChord = nil
        activeKeyCombo = nil
        unregisterAll()
    }

    func resume() {
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        guard suspendCount == 0 else { return }
        registerAll()
    }

    // MARK: - Chords

    private func handleFlags(_ event: NSEvent) {
        guard !isSuspended else { return }
        let flags = event.modifierFlags.intersection(Hotkey.relevantMask)

        if let match = sortedChords.first(where: { $0.flags == flags })?.type {
            if activeChord == nil {
                activeChord = match
                onHotkeyEvent?(.down(match))
            }
            return
        }

        if let chord = activeChord {
            activeChord = nil
            onHotkeyEvent?(.up(chord))
        }

        // Safety net for hold mode: Carbon's release event goes missing when
        // the modifiers are let go before the key, which is how people
        // actually release a chord. Dropping all modifiers ends the run.
        if flags.isEmpty, let keyCombo = activeKeyCombo {
            activeKeyCombo = nil
            onHotkeyEvent?(.up(keyCombo))
        }
    }

    private func handleEscape() {
        activeChord = nil
        activeKeyCombo = nil
        onHotkeyEvent?(.cancel)
    }

    // MARK: - Registered key combinations

    private func installCarbonHandler() {
        guard carbonHandler == nil else { return }
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                guard status == noErr else { return noErr }
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                // Carbon dispatches on the main run loop, so the isolation is
                // real — asserting it keeps press and release strictly ordered.
                MainActor.assumeIsolated {
                    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                    service.handleCarbonHotkey(id: hotkeyID.id, pressed: pressed)
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &carbonHandler
        )
    }

    private func handleCarbonHotkey(id: UInt32, pressed: Bool) {
        guard !isSuspended,
              let type = Self.workflow(forHotkeyID: id) else { return }

        // The state transition is decided here and now, so press and release
        // stay strictly ordered no matter what the handler does with them.
        var event: HotkeyEvent?
        if pressed {
            if activeKeyCombo == nil {
                activeKeyCombo = type
                event = .down(type)
            }
        } else if activeKeyCombo == type {
            activeKeyCombo = nil
            event = .up(type)
        }
        guard let event else { return }

        // Delivered on the next main-actor turn, never from inside this
        // callback — the same hop the chord path takes, so both shapes reach
        // the handler under identical conditions. Carbon dispatches this
        // synchronously out of -[NSApplication sendEvent:], and the handler is
        // not event-dispatch code: it starts a workflow (which blocks the main
        // thread inside AVAudioEngine until CoreAudio answers) and in toggle
        // mode shows the popover and calls NSApp.activate. None of that
        // belongs on the stack of the event that triggered it.
        Task { @MainActor [weak self] in
            self?.onHotkeyEvent?(event)
        }
    }

    private func registerAll() {
        unregisterAll()
        var failures: Set<WorkflowType> = []

        for type in WorkflowType.allCases {
            let hotkey = self.hotkey(for: type)
            guard !hotkey.isChord, hotkey.validate() == nil, let keyCode = hotkey.keyCode else { continue }

            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: Self.hotkeySignature, id: Self.hotkeyID(for: type))
            let status = RegisterEventHotKey(
                UInt32(keyCode),
                hotkey.carbonModifiers,
                identifier,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                registrations[type] = reference
            } else {
                failures.insert(type)
            }
        }
        registrationFailures = failures
    }

    private func unregisterAll() {
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
        registrations.removeAll()
    }

    private static func hotkeyID(for type: WorkflowType) -> UInt32 {
        UInt32((WorkflowType.allCases.firstIndex(of: type) ?? 0) + 1)
    }

    private static func workflow(forHotkeyID id: UInt32) -> WorkflowType? {
        let index = Int(id) - 1
        guard WorkflowType.allCases.indices.contains(index) else { return nil }
        return WorkflowType.allCases[index]
    }
}
