import Foundation

// MARK: - Workflow Types

enum WorkflowType: String, CaseIterable, Identifiable, Codable {
    case transcription
    case textImprover
    case braindump
    case selectionEdit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .transcription: return "Griffel"
        case .textImprover: return "Griffel+"
        case .braindump: return "Braindump"
        case .selectionEdit: return "Auswahl bearbeiten"
        }
    }

    var icon: String {
        switch self {
        case .transcription: return "mic.fill"
        case .textImprover: return "text.badge.checkmark"
        case .braindump: return "brain.head.profile"
        case .selectionEdit: return "wand.and.stars"
        }
    }

    var subtitle: String {
        switch self {
        case .transcription: return "Sprache rein. Text raus."
        case .textImprover: return "Geschrieben sprechen."
        case .braindump: return "Gedanke rein. Kopf frei."
        case .selectionEdit: return "Markieren. Sprechen. Fertig."
        }
    }

    var accentColor: String {
        switch self {
        case .transcription: return "blue"
        case .textImprover: return "purple"
        case .braindump: return "pink"
        case .selectionEdit: return "indigo"
        }
    }
}

// MARK: - Workflow State

enum WorkflowPhase: Equatable {
    case idle
    case running(String)
    case done(String)
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

enum WorkflowLaunchSource: Equatable {
    case manual
    case hotkeyBackground

    var presentsWorkflowPage: Bool {
        switch self {
        case .manual:
            return true
        case .hotkeyBackground:
            return false
        }
    }
}

typealias WorkflowOutputHandler = @MainActor (String) -> Void
typealias WorkflowPhaseChangeHandler = @MainActor (WorkflowPhase) -> Void

// MARK: - Workflow Protocol

@MainActor
protocol Workflow: AnyObject, Observable {
    var type: WorkflowType { get }
    var phase: WorkflowPhase { get set }
    var isRecording: Bool { get }
    var audioLevel: Float { get }
    var lastRecordingDuration: TimeInterval { get }
    /// Rolling partial transcript while recording locally; nil when the
    /// workflow does not support live transcription.
    var livePartialText: String? { get }
    /// The input the microphone is actually open on, resolved at recording
    /// start; nil before the first recording of this run.
    var activeInputDevice: ActiveInputDevice? { get }
    var onOutput: WorkflowOutputHandler? { get set }
    var onPhaseChange: WorkflowPhaseChangeHandler? { get set }

    func start()
    func stop()
    func reset()
}

extension Workflow {
    var lastRecordingDuration: TimeInterval { 0 }
    var livePartialText: String? { nil }
}

// MARK: - App Settings

/// What a Braindump records about its surroundings. Three states rather than
/// two booleans: "Fenstertitel an, App aus" is not a state that means anything.
enum BraindumpCaptureContext: String, Codable, CaseIterable, Identifiable {
    case off
    case appOnly
    case appAndWindow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Aus"
        case .appOnly: return "Nur App"
        case .appAndWindow: return "App und Fenstertitel"
        }
    }

    var explanation: String {
        switch self {
        case .off: return "Es wird nichts über die Umgebung notiert."
        case .appOnly: return "Notiert nur, in welcher App du gesprochen hast."
        case .appAndWindow: return "Notiert App und Fenstertitel \u{2014} Titel k\u{00F6}nnen Dokumentnamen, Betreffs oder URLs enthalten."
        }
    }

    var recordsApp: Bool { self != .off }
    var recordsWindowTitle: Bool { self == .appAndWindow }
}

struct AppSettings: Codable {
    var hotkeyMode: HotkeyMode = .hold
    var hasSeenOnboarding: Bool = false
    var secureLocalModeEnabled: Bool = false
    var selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName
    var hasAutoSelectedFastLocalModel: Bool = false
    var preferredInputDeviceUID: String?
    var hudEnabled: Bool = true
    var phraseDetectionEnabled: Bool = true
    var liveTranscriptEnabled: Bool = false
    var autoStopOnSilenceEnabled: Bool = false
    var autoStopSilenceSeconds: Double = 2.5
    /// Whether dropped audio files get the Griffel+ rewrite pass after
    /// transcription. Off by default: an import should read back what is on
    /// the recording before anything reformulates it.
    var importRewriteEnabled: Bool = false
    /// How much a Braindump records about the Mac around it. Local-only, but a
    /// window title is verbatim text out of someone else's document — so this
    /// is a visible three-way choice, not a hidden behaviour. `.appOnly` is the
    /// honest middle: "aus Safari" without the page title.
    var braindumpCaptureContext: BraindumpCaptureContext = .appAndWindow
    var didMigrateOllamaRewritePrompt: Bool = false
    var didMigrateCustomPrompt: Bool = false
    /// Keyed by `WorkflowType.rawValue`. A missing entry falls back to the
    /// shipped default, so a binding added later never strands a workflow.
    var hotkeyBindings: [String: Hotkey] = Hotkey.defaultBindings

    init(
        hotkeyMode: HotkeyMode = .hold,
        hasSeenOnboarding: Bool = false,
        secureLocalModeEnabled: Bool = false,
        selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName,
        hasAutoSelectedFastLocalModel: Bool = false,
        preferredInputDeviceUID: String? = nil,
        hudEnabled: Bool = true,
        phraseDetectionEnabled: Bool = true,
        liveTranscriptEnabled: Bool = false,
        autoStopOnSilenceEnabled: Bool = false,
        autoStopSilenceSeconds: Double = 2.5,
        importRewriteEnabled: Bool = false,
        braindumpCaptureContext: BraindumpCaptureContext = .appAndWindow,
        didMigrateOllamaRewritePrompt: Bool = false,
        didMigrateCustomPrompt: Bool = false,
        hotkeyBindings: [String: Hotkey] = Hotkey.defaultBindings
    ) {
        self.hotkeyMode = hotkeyMode
        self.hasSeenOnboarding = hasSeenOnboarding
        self.secureLocalModeEnabled = secureLocalModeEnabled
        self.selectedLocalTranscriptionModelName = selectedLocalTranscriptionModelName
        self.hasAutoSelectedFastLocalModel = hasAutoSelectedFastLocalModel
        self.preferredInputDeviceUID = preferredInputDeviceUID
        self.hudEnabled = hudEnabled
        self.phraseDetectionEnabled = phraseDetectionEnabled
        self.liveTranscriptEnabled = liveTranscriptEnabled
        self.autoStopOnSilenceEnabled = autoStopOnSilenceEnabled
        self.autoStopSilenceSeconds = autoStopSilenceSeconds
        self.importRewriteEnabled = importRewriteEnabled
        self.braindumpCaptureContext = braindumpCaptureContext
        self.didMigrateOllamaRewritePrompt = didMigrateOllamaRewritePrompt
        self.didMigrateCustomPrompt = didMigrateCustomPrompt
        self.hotkeyBindings = hotkeyBindings
    }

    enum CodingKeys: String, CodingKey {
        case hotkeyMode
        case hasSeenOnboarding
        case secureLocalModeEnabled
        case selectedLocalTranscriptionModelName
        case hasAutoSelectedFastLocalModel
        case preferredInputDeviceUID
        case hudEnabled
        case phraseDetectionEnabled
        case liveTranscriptEnabled
        case autoStopOnSilenceEnabled
        case autoStopSilenceSeconds
        case importRewriteEnabled
        case braindumpCaptureContext
        case didMigrateOllamaRewritePrompt
        case didMigrateCustomPrompt
        case hotkeyBindings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyMode = try container.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode) ?? .hold
        hasSeenOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? false
        secureLocalModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .secureLocalModeEnabled) ?? false
        selectedLocalTranscriptionModelName = try container.decodeIfPresent(
            String.self,
            forKey: .selectedLocalTranscriptionModelName
        ) ?? LocalTranscriptionService.recommendedFastModelName
        hasAutoSelectedFastLocalModel = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasAutoSelectedFastLocalModel
        ) ?? false
        preferredInputDeviceUID = try container.decodeIfPresent(
            String.self,
            forKey: .preferredInputDeviceUID
        )
        hudEnabled = try container.decodeIfPresent(Bool.self, forKey: .hudEnabled) ?? true
        phraseDetectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .phraseDetectionEnabled) ?? true
        liveTranscriptEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveTranscriptEnabled) ?? false
        autoStopOnSilenceEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoStopOnSilenceEnabled) ?? false
        autoStopSilenceSeconds = try container.decodeIfPresent(Double.self, forKey: .autoStopSilenceSeconds) ?? 2.5
        importRewriteEnabled = try container.decodeIfPresent(Bool.self, forKey: .importRewriteEnabled) ?? false
        // Decoded as a raw String on purpose: `decodeIfPresent(SomeEnum.self, ...)`
        // does NOT return nil for an unknown raw value, it throws
        // `dataCorrupted` — which here would take every other setting down with
        // it. Mapping the string keeps a value from a newer build harmless.
        braindumpCaptureContext = (try container.decodeIfPresent(String.self, forKey: .braindumpCaptureContext))
            .flatMap(BraindumpCaptureContext.init(rawValue:)) ?? .appAndWindow
        didMigrateOllamaRewritePrompt = try container.decodeIfPresent(
            Bool.self,
            forKey: .didMigrateOllamaRewritePrompt
        ) ?? false
        didMigrateCustomPrompt = try container.decodeIfPresent(
            Bool.self,
            forKey: .didMigrateCustomPrompt
        ) ?? false
        // Merged over the defaults rather than replacing them, so a settings
        // file written before a workflow existed still yields a binding for it.
        // Entries that no longer make sense as a shortcut are dropped here
        // instead of being registered as a dead combination.
        let storedBindings = (try container.decodeIfPresent(
            [String: Hotkey].self,
            forKey: .hotkeyBindings
        ) ?? [:]).filter { $0.value.validate() == nil }
        hotkeyBindings = Hotkey.defaultBindings.merging(storedBindings) { _, stored in stored }
    }
}

enum TranscriptionBackend: String, Codable {
    case remote
    case local
}

// MARK: - Workflow Settings

enum LanguageMode: String, Codable, CaseIterable, Identifiable {
    case deutsch
    case english
    case autoDenglish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deutsch: return "Deutsch"
        case .english: return "English"
        case .autoDenglish: return "Denglish (Auto)"
        }
    }

    /// Whisper language parameter; empty string means auto-detect.
    var whisperLanguageCode: String {
        switch self {
        case .deutsch: return "de"
        case .english: return "en"
        case .autoDenglish: return ""
        }
    }
}

struct TranscriptionSettings: Codable {
    /// Legacy free-form language string from pre-glossary settings files.
    var language: String = "de"
    var languageMode: LanguageMode = .deutsch
    var removeFillerWords: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case language
        case languageMode
        case removeFillerWords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "de"
        if let mode = try container.decodeIfPresent(LanguageMode.self, forKey: .languageMode) {
            languageMode = mode
        } else {
            switch language.trimmingCharacters(in: .whitespaces) {
            case "en": languageMode = .english
            case "": languageMode = .autoDenglish
            default: languageMode = .deutsch
            }
        }
        removeFillerWords = try container.decodeIfPresent(Bool.self, forKey: .removeFillerWords) ?? false
    }
}

/// The four editable feature prompts plus the on-device addendum. An empty
/// value means "use `PromptDefaults`" rather than a stored copy of it, so a
/// prompt the user never touched keeps following the built-in text.
struct PromptSettings: Codable {
    var korrektur: String = ""
    var lektorat: String = ""
    var selectionEdit: String = ""
    var braindump: String = ""
    var localAddendum: String = ""
    /// The addendum is the one prompt that may legitimately be switched off, so
    /// "off" is its own flag rather than an overloaded empty string — empty
    /// keeps meaning "use the default" here exactly as it does for the others.
    var localAddendumEnabled: Bool = true

    var effectiveKorrektur: String { Self.effective(korrektur, default: PromptDefaults.korrektur) }
    var effectiveLektorat: String { Self.effective(lektorat, default: PromptDefaults.lektorat) }
    var effectiveSelectionEdit: String { Self.effective(selectionEdit, default: PromptDefaults.selectionEdit) }
    var effectiveBraindump: String { Self.effective(braindump, default: PromptDefaults.braindump) }
    var effectiveLocalAddendum: String { Self.effective(localAddendum, default: PromptDefaults.localAddendum) }

    private static func effective(_ stored: String, default fallback: String) -> String {
        stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : stored
    }

    init(
        korrektur: String = "",
        lektorat: String = "",
        selectionEdit: String = "",
        braindump: String = "",
        localAddendum: String = "",
        localAddendumEnabled: Bool = true
    ) {
        self.korrektur = korrektur
        self.lektorat = lektorat
        self.selectionEdit = selectionEdit
        self.braindump = braindump
        self.localAddendum = localAddendum
        self.localAddendumEnabled = localAddendumEnabled
    }

    enum CodingKeys: String, CodingKey {
        case korrektur
        case lektorat
        case selectionEdit
        case braindump
        case localAddendum
        case localAddendumEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        korrektur = try container.decodeIfPresent(String.self, forKey: .korrektur) ?? ""
        lektorat = try container.decodeIfPresent(String.self, forKey: .lektorat) ?? ""
        selectionEdit = try container.decodeIfPresent(String.self, forKey: .selectionEdit) ?? ""
        braindump = try container.decodeIfPresent(String.self, forKey: .braindump) ?? ""
        localAddendum = try container.decodeIfPresent(String.self, forKey: .localAddendum) ?? ""
        localAddendumEnabled = try container.decodeIfPresent(Bool.self, forKey: .localAddendumEnabled) ?? true
    }
}

struct LocalLLMSettings: Codable {
    var modelID: String = LocalLLMService.defaultModelID

    /// A model is only usable once its weights are on disk. Kept separate from
    /// the stored setting so a missing download never looks like a config.
    var isConfigured: Bool {
        !modelID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init(modelID: String = LocalLLMService.defaultModelID) {
        self.modelID = modelID
    }

    enum CodingKeys: String, CodingKey {
        case modelID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
            ?? LocalLLMService.defaultModelID
    }
}

/// Decode-only remnant of the retired Ollama integration. Nothing writes this
/// section any more; it exists so the one-time rewrite-prompt carry-over in
/// `AppState.migrateLegacyOllamaRewritePromptIfNeeded()` still finds the prompt
/// in an old settings file.
struct LegacyOllamaSettings: Codable {
    var systemPrompt: String = ""

    init(systemPrompt: String = "") {
        self.systemPrompt = systemPrompt
    }

    enum CodingKeys: String, CodingKey {
        case systemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
    }
}

struct TextImprovementSettings: Codable {
    var systemPrompt: String = ""
    var customTerms: [String] = []
    var context: String = ""
    var tone: TextTone = .neutral
    var rewriteScope: RewriteScope = .lektorat

    /// How far Griffel+ may go when rewriting a dictation. Replaces the
    /// retired "Griffel Lokal+" workflow, whose only real difference was
    /// a more conservative prompt.
    enum RewriteScope: String, Codable, CaseIterable, Identifiable {
        /// Clean up only — meaning, tone and wording stay the user's own.
        case korrektur
        /// Full editorial rewrite; `tone` and `context` shape the result.
        case lektorat

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .korrektur: return "Korrektur"
            case .lektorat: return "Lektorat"
            }
        }

        var explanation: String {
            switch self {
            case .korrektur: return "Nur Rechtschreibung, Grammatik und Füllwörter. Deine Formulierung bleibt."
            case .lektorat: return "Formuliert um und glättet den Lesefluss. Schreibstil und Kontext wirken."
            }
        }

        /// `tone` and `context` only reach the prompt for `.lektorat`.
        var usesToneAndContext: Bool { self == .lektorat }
    }

    enum TextTone: String, Codable, CaseIterable, Identifiable {
        case formal
        case neutral
        case casual

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .formal: return "Formell"
            case .neutral: return "Neutral"
            case .casual: return "Locker"
            }
        }
    }

    init() {}

    enum CodingKeys: String, CodingKey {
        case systemPrompt
        case customTerms
        case context
        case tone
        case rewriteScope
    }

    /// Decoded field by field with defaults so older settings files — which
    /// predate `rewriteScope` — keep loading instead of failing the whole
    /// SettingsContainer decode and resetting every unrelated setting.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        customTerms = try container.decodeIfPresent([String].self, forKey: .customTerms) ?? []
        context = try container.decodeIfPresent(String.self, forKey: .context) ?? ""
        tone = try container.decodeIfPresent(TextTone.self, forKey: .tone) ?? .neutral
        rewriteScope = try container.decodeIfPresent(RewriteScope.self, forKey: .rewriteScope) ?? .lektorat
    }
}
