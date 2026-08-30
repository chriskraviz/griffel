import SwiftUI
import Observation
import AppKit

enum PopoverPage: Equatable {
    case main
    case onboarding
    case settings
    case workflow
    case stats
    case braindump
    case prompts
}

/// The one decision that determines where a dictation is processed. Derived
/// from `AppSettings.secureLocalModeEnabled`, never stored separately — a mode
/// that could disagree with the setting it represents would be a lie.
enum ProcessingMode: String, CaseIterable, Identifiable {
    /// Everything on this Mac: WhisperKit for audio, the on-device MLX model
    /// for text.
    case local
    /// OpenAI for audio and for text.
    case online

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "Lokal"
        case .online: return "Online"
        }
    }
}

enum MainWindowSection {
    case library
    case settings
}

enum HUDEvent {
    case show(workflow: any Workflow, displayName: String)
    case dismiss(after: TimeInterval)
}

@Observable
@MainActor
final class AppState {
    private static let pasteRetryInitialAttempts = 22
    private static let concealedPasteboardType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    var activeWorkflow: (any Workflow)?
    /// Which half of the Ablage window is showing. It lives here rather than
    /// in the view because ⌘, has to open the window straight into the
    /// settings from the app menu, before the view exists.
    var windowSection: MainWindowSection = .library
    var page: PopoverPage = .main
    var isPopoverShown = false
    var menuBarStatus: MenuBarStatus = .idle {
        didSet {
            guard oldValue != menuBarStatus else { return }
            onMenuBarStatusChange?(menuBarStatus)
        }
    }
    var accessibilityPermissionGranted = false
    var localModelDownloadProgress: Double?
    var localModelDownloadStatusText: String?
    var localModelDownloadErrorText: String?
    var localLLMDownloadProgress: Double?
    var localLLMDownloadStatusText: String?
    var localLLMDownloadErrorText: String?
    var onMenuBarStatusChange: ((MenuBarStatus) -> Void)?
    var onHUDEvent: ((HUDEvent) -> Void)?
    /// Set by the AppDelegate, which owns the window.
    var onOpenMainWindow: (() -> Void)?
    private var activeLaunchSource: WorkflowLaunchSource = .manual
    private var activePasteTarget: PasteTarget?
    private var lastPopoverPasteTarget: PasteTarget?
    /// What was in front when the current run started. Resolved at start, not
    /// at output: a 30-second braindump gives the user plenty of time to switch
    /// apps, and by then the frontmost app is often Griffel itself.
    private var activeCaptureContext: CaptureContext?
    /// Identifies the run a pending window-title lookup belongs to. Without it
    /// a slow lookup from one Braindump could land its title on the next one.
    private var captureContextGeneration = 0
    private var menuBarStatusResetTask: Task<Void, Never>?
    private var workflowCleanupTask: Task<Void, Never>?
    private var processingStartedAt: Date?

    // Persisted settings
    var appSettings: AppSettings {
        didSet {
            saveSettings()
            prewarmLocalTranscriptionIfNeeded()
            if oldValue.hotkeyBindings != appSettings.hotkeyBindings {
                hotkeyService.apply(bindings: appSettings.hotkeyBindings)
            }
        }
    }
    var transcriptionSettings: TranscriptionSettings {
        didSet { saveSettings() }
    }
    var textImprovementSettings: TextImprovementSettings {
        didSet { saveSettings() }
    }
    var glossarySettings: GlossarySettings {
        didSet { saveSettings() }
    }
    var formatProfileSettings: FormatProfileSettings {
        didSet { saveSettings() }
    }
    var localLLMSettings: LocalLLMSettings {
        didSet { saveSettings() }
    }
    var promptSettings: PromptSettings {
        didSet { saveSettings() }
    }
    var librarySettings: LibrarySettings {
        didSet {
            saveSettings()
            library.apply(settings: librarySettings)
        }
    }

    // Hotkeys
    let hotkeyService = HotkeyService()

    /// Filed recordings and their transcripts.
    let library = LibraryStore()
    /// Runs filed recordings through the engines, one at a time.
    let transcriptionQueue = TranscriptionQueue()

    // Computed
    var isConfigured: Bool {
        KeychainService.isConfigured || !LocalTranscriptionService.installedModels().isEmpty
    }
    var shouldShowOnboarding: Bool {
        !isConfigured && !appSettings.hasSeenOnboarding
    }

    var currentPhase: WorkflowPhase {
        activeWorkflow?.phase ?? .idle
    }

    /// Shared additions to every LLM system prompt: glossary spelling,
    /// Denglish handling, and filler-word removal. The filler instruction is
    /// omitted for local backends — small on-device models follow it
    /// unreliably, so workflows strip fillers locally instead.
    func llmExtraInstructions(for backend: LLMBackend?) -> [String] {
        var extras: [String] = []
        if let glossaryInstruction = GlossaryPromptBuilder.llmInstruction(glossarySettings) {
            extras.append(glossaryInstruction)
        }
        if let denglishInstruction = GlossaryPromptBuilder.denglishInstruction(for: transcriptionSettings.languageMode) {
            extras.append(denglishInstruction)
        }
        if transcriptionSettings.removeFillerWords, backend?.isLocal != true {
            extras.append(FillerWordService.llmInstruction)
        }
        if backend?.isLocal == true, promptSettings.localAddendumEnabled {
            let addendum = promptSettings.effectiveLocalAddendum
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !addendum.isEmpty {
                extras.append(addendum)
            }
        }
        return extras
    }

    /// The LLM engine a run started now would use. Secure local mode never
    /// resolves to OpenAI; nil means no rewrite feature can run.
    var resolvedLLMBackend: LLMBackend? {
        if appSettings.secureLocalModeEnabled {
            return localLLMIsReady ? .local(localLLMSettings) : nil
        }
        return KeychainService.isConfigured ? .openAI : nil
    }

    /// The on-device rewrite model is only usable once its weights are on disk.
    var localLLMIsReady: Bool {
        localLLMSettings.isConfigured && LocalLLMService.isModelInstalled(localLLMSettings.modelID)
    }

    var localLLMDisplayName: String {
        LocalLLMService.displayName(for: localLLMSettings.modelID)
    }

    private var transcriptionReady: Bool {
        appSettings.secureLocalModeEnabled
            ? selectedLocalModelIsInstalled
            : KeychainService.isConfigured
    }

    // MARK: - Processing Mode

    /// Reading and writing the mode goes through here so the side effects run
    /// wherever it is switched. Unlike the Ollama era there is no provider to
    /// reset on the way out: `resolvedLLMBackend` derives the engine from this
    /// one setting, so the two can never drift apart.
    var processingMode: ProcessingMode {
        get { appSettings.secureLocalModeEnabled ? .local : .online }
        set {
            switch newValue {
            case .local:
                enableSecureLocalMode()
            case .online:
                appSettings.secureLocalModeEnabled = false
            }
        }
    }

    /// What the mode does with audio and text, in one honest sentence. Never
    /// call a remote pass local — and never promise on-device rewriting before
    /// the weights are actually on disk.
    var modeStatusText: String {
        guard appSettings.secureLocalModeEnabled else {
            return KeychainService.isConfigured
                ? "OpenAI verarbeitet Audio und Text."
                : "OpenAI-Zugang fehlt."
        }

        if isDownloadingLocalModel {
            return localModelDownloadStatusText ?? "Lokales Modell wird geladen."
        }
        guard selectedLocalModelIsInstalled else {
            // The size belongs next to the install button, not two panes away:
            // it is the whole question the user is weighing here.
            if let size = LocalTranscriptionModel.downloadSizeLabel(for: selectedLocalModelName) {
                return "\(selectedLocalModelDisplayName) ist noch nicht installiert \u{00B7} einmaliger Download, \(size)."
            }
            return "\(selectedLocalModelDisplayName) ist noch nicht installiert."
        }

        if isDownloadingLocalLLM {
            return localLLMDownloadStatusText ?? "Sprachmodell wird geladen."
        }
        guard localLLMIsReady else {
            let size = LocalLLMService.modelOptions()
                .first { $0.id == localLLMSettings.modelID }?
                .sizeLabel
            let suffix = size.map { " \u{00B7} einmaliger Download, \($0)" } ?? ""
            return "\(selectedLocalModelDisplayName) l\u{00E4}uft. Umschreiben braucht \(localLLMDisplayName)\(suffix)."
        }
        return "Alles auf diesem Mac \u{00B7} \(selectedLocalModelDisplayName) + \(localLLMDisplayName)."
    }

    /// Green only when the active mode can actually run a dictation end to end.
    var modeIsReady: Bool {
        transcriptionReady
    }

    /// The one thing the mode card can do about the current setup, or nil when
    /// there is nothing left to do. Deliberately one at a time: transcription
    /// is the prerequisite for rewriting, and two install buttons side by side
    /// would break the single-primary rule this page keeps.
    enum ModeAction: Equatable {
        case installTranscriptionModel
        case installRewriteModel
        case openSettings

        var title: String {
            switch self {
            case .installTranscriptionModel: return "Installieren"
            case .installRewriteModel: return "Sprachmodell laden"
            case .openSettings: return "OpenAI-Zugang einrichten"
            }
        }
    }

    var modeAction: ModeAction? {
        guard appSettings.secureLocalModeEnabled else {
            return KeychainService.isConfigured ? nil : .openSettings
        }
        guard !isDownloadingLocalModel, !isDownloadingLocalLLM else { return nil }
        if !selectedLocalModelIsInstalled { return .installTranscriptionModel }
        return localLLMIsReady ? nil : .installRewriteModel
    }

    func perform(_ action: ModeAction) {
        switch action {
        case .installTranscriptionModel: installSelectedLocalModel()
        case .installRewriteModel: installLocalLLM()
        case .openSettings: page = .settings
        }
    }

    // MARK: - Availability

    /// The only source the popover list renders from. Modes the current setup
    /// cannot run are absent, not greyed out — the mode card says why.
    var availableWorkflows: [WorkflowType] {
        WorkflowType.allCases.filter(isWorkflowAvailable)
    }

    // MARK: - Hotkeys

    /// Starts global hotkey handling with the stored bindings. The service
    /// boots on defaults, so this has to run before the first keystroke.
    func startHotkeys() {
        hotkeyService.start()
        hotkeyService.apply(bindings: appSettings.hotkeyBindings)
    }

    func hotkey(for type: WorkflowType) -> Hotkey {
        appSettings.hotkeyBindings[type.rawValue] ?? .default(for: type)
    }

    /// What to print on a keycap. Everything user-facing goes through here, so
    /// a rebind updates the badges, the braindump hint and the settings list
    /// at once.
    func hotkeyLabel(for type: WorkflowType) -> String {
        hotkey(for: type).displayLabel
    }

    enum HotkeyAssignment: Equatable {
        case assigned
        /// Assigned, but something about it is worth knowing.
        case assignedWithWarning(String)
        case rejected(String)
    }

    /// Duplicates inside the app are refused outright — two modes on one
    /// combination means one of them is unreachable. A clash with the system
    /// is only reported: which of macOS's shortcuts matter is the user's call.
    @discardableResult
    func assignHotkey(_ hotkey: Hotkey, to type: WorkflowType) -> HotkeyAssignment {
        if let error = hotkey.validate() {
            return .rejected(error.message)
        }
        for other in WorkflowType.allCases where other != type {
            if self.hotkey(for: other) == hotkey {
                return .rejected(Hotkey.ValidationError.alreadyUsed(other.displayName).message)
            }
        }

        var bindings = appSettings.hotkeyBindings
        bindings[type.rawValue] = hotkey
        appSettings.hotkeyBindings = bindings

        // Registration is the authority on whether the combination is free;
        // the curated list below only supplies a friendlier name for it.
        if hotkeyService.registrationFailures.contains(type) {
            let owner = hotkey.systemConflictName ?? "einer anderen App"
            return .assignedWithWarning("Belegt von \(owner) \u{2014} das K\u{00FC}rzel bleibt wirkungslos.")
        }
        if let conflict = hotkey.systemConflictName {
            return .assignedWithWarning("\u{00DC}berschreibt \u{201E}\(conflict)\u{201C}, solange Griffel l\u{00E4}uft.")
        }
        return .assigned
    }

    func resetHotkey(for type: WorkflowType) {
        var bindings = appSettings.hotkeyBindings
        let restored = Hotkey.default(for: type)
        bindings[type.rawValue] = restored
        // Restoring a default can land on a combination another mode was
        // rebound to. `assignHotkey` refuses a duplicate because it makes one
        // mode unreachable; here there is nothing to refuse — the user asked
        // for the default back — so the mode that was squatting on it goes
        // home too. The shipped defaults are pairwise distinct, so this
        // settles in one pass.
        for other in WorkflowType.allCases where other != type {
            if bindings[other.rawValue] == restored {
                bindings[other.rawValue] = .default(for: other)
            }
        }
        appSettings.hotkeyBindings = bindings
    }

    func resetAllHotkeys() {
        appSettings.hotkeyBindings = Hotkey.defaultBindings
    }

    var hasCustomHotkeys: Bool {
        appSettings.hotkeyBindings != Hotkey.defaultBindings
    }

    /// Read once during init, before anything can trigger a save. `saveSettings()`
    /// no longer writes the legacy `ollama` section, so re-reading the file later
    /// would find it already gone — the helpers below persist on `didSet`.
    private let legacyOllamaRewritePrompt: String

    init() {
        LegacyMigrationService.migrateIfNeeded()
        self.legacyOllamaRewritePrompt = Self.loadLegacyOllamaRewritePrompt()
        self.appSettings = Self.loadAppSettings()
        self.transcriptionSettings = Self.loadTranscriptionSettings()
        self.textImprovementSettings = Self.loadTextImprovementSettings()
        self.glossarySettings = Self.loadGlossarySettings()
        self.formatProfileSettings = Self.loadFormatProfileSettings()
        self.localLLMSettings = Self.loadLocalLLMSettings()
        self.promptSettings = Self.loadPromptSettings()
        self.librarySettings = Self.loadLibrarySettings()
        library.apply(settings: librarySettings)
        transcriptionQueue.onTranscript = { [weak self] itemID, transcript, duration, engine in
            guard let self else { return false }
            return self.library.setTranscript(
                itemID: itemID,
                transcript: transcript,
                duration: duration,
                language: self.transcriptionSettings.languageMode.whisperLanguageCode,
                engine: engine
            )
        }
        refreshAccessibilityPermission()
        autoSelectFastLocalModelIfNeeded()
        prewarmLocalTranscriptionIfNeeded()
        seedGlossaryFromLegacyTermsIfNeeded()
        migrateLegacyOllamaRewritePromptIfNeeded()
        migrateLegacyCustomPromptIfNeeded()
    }

    /// A row's subtitle says what the mode is *for*. Which engine runs it is
    /// the mode card's line, one card above — naming it again per row cost the
    /// only place that explained the purpose, and said nothing new. These
    /// subtitles used to double as the reason a row was greyed out; rows are
    /// hidden rather than greyed out now, and the mode card carries the reason.
    func workflowSubtitle(for type: WorkflowType) -> String {
        guard type == .braindump else { return type.subtitle }
        // The one exception: a filled inbox is state the user has to act on,
        // not a restatement of the setup.
        let unprocessed = BraindumpStore.shared.unprocessedCount
        return unprocessed == 0 ? type.subtitle : "\(unprocessed) im Eingang."
    }

    var resolvedLocalModelName: String {
        LocalTranscriptionService.resolvedModelName(appSettings.selectedLocalTranscriptionModelName)
    }

    var selectedLocalModelDisplayName: String {
        LocalTranscriptionModel.displayName(for: selectedLocalModelName)
    }

    var selectedLocalModelName: String {
        LocalTranscriptionService.normalizedModelName(appSettings.selectedLocalTranscriptionModelName)
    }

    var selectedLocalModelIsInstalled: Bool {
        LocalTranscriptionService.isModelInstalled(selectedLocalModelName)
    }

    var isDownloadingLocalLLM: Bool {
        localLLMDownloadProgress != nil
    }

    var isDownloadingLocalModel: Bool {
        localModelDownloadProgress != nil
    }

    // MARK: - Audio Import

    func openMainWindow() {
        onOpenMainWindow?()
    }

    /// Dropped files use the same engine as a spoken run: WhisperKit in secure
    /// local mode, `whisper-1` online.
    var canImportAudio: Bool {
        isWorkflowAvailable(.transcription)
    }

    /// The optional rewrite pass needs a resolved LLM backend, exactly like
    /// Griffel+ does.
    var canRewriteImports: Bool {
        resolvedLLMBackend != nil
    }

    /// Files dropped recordings into the library and queues them for
    /// transcription. Returns the URLs that were not audio at all, so the
    /// caller can say what it ignored instead of dropping them silently.
    ///
    /// Imports stay out of `StatsStore` and `PhraseStore` on purpose: both
    /// describe the user's own dictation, and an imported recording may be
    /// someone else's voice entirely -- the same reason selection edit is
    /// excluded from phrase detection.
    @discardableResult
    func importAudioFiles(_ urls: [URL], intoFolder folderName: String? = nil) -> [URL] {
        // Without a transcription engine the drop zone already says what is
        // missing; reporting the files as "not audio" on top of that would be
        // the wrong reason.
        guard canImportAudio else { return [] }

        var rejected: [URL] = []
        let configuration = makeImportConfiguration()

        for url in urls {
            guard AudioImportService.accepts(url) else {
                rejected.append(url)
                continue
            }
            do {
                let reservation = try library.reserve(
                    sourceAudioURL: url,
                    folderName: folderName,
                    copyAudio: library.storesImportedAudio
                )
                // Transcribe the library copy when there is one: the file the
                // user dragged may live in a temporary folder its owner app
                // deletes the moment the drag ends.
                let audioURL = library.item(id: reservation.itemID).flatMap(library.audioURL(for:)) ?? url
                transcriptionQueue.enqueue(
                    itemID: reservation.itemID,
                    audioURL: audioURL,
                    displayName: url.lastPathComponent,
                    configuration: configuration
                )
            } catch {
                library.lastImportErrorText = error.localizedDescription
            }
        }

        return rejected
    }

    /// Runs a filed recording through the engines again — after a failure, or
    /// after the user changed language, glossary or the rewrite setting.
    func retranscribe(_ item: LibraryItem) {
        guard canImportAudio else { return }

        // Prefer the library copy, but fall back to the path the job was
        // created with: with "Aufnahmen mitkopieren" off there is no library
        // copy, and a retry would otherwise be a permanent no-op.
        let existingJob = transcriptionQueue.job(forItem: item.id)
        let libraryAudio = item.audioIsMissing ? nil : library.audioURL(for: item)
        guard let audioURL = libraryAudio ?? existingJob?.audioURL else { return }

        let configuration = makeImportConfiguration()
        if existingJob != nil {
            // Both are re-read on purpose: the recording may have moved to
            // another topic, and the language, glossary or rewrite setting may
            // have changed since the run that failed.
            transcriptionQueue.retry(itemID: item.id, audioURL: audioURL, configuration: configuration)
            return
        }
        transcriptionQueue.enqueue(
            itemID: item.id,
            audioURL: audioURL,
            displayName: item.title,
            configuration: configuration
        )
    }

    /// Moves a Braindump entry out of the inbox into a topic folder. Eingang
    /// leeren heisst hier: ablegen, nicht wegwerfen.
    @discardableResult
    func fileBraindumpEntries(_ ids: Set<UUID>, intoFolder folderName: String?) -> Int {
        let entries = BraindumpStore.shared.entries.filter { ids.contains($0.id) }
        var filedIDs: Set<UUID> = []
        for entry in entries {
            do {
                _ = try library.addTranscript(
                    entry.text,
                    source: .braindump,
                    folderName: folderName,
                    language: transcriptionSettings.languageMode.whisperLanguageCode,
                    capture: entry.captureContext,
                    createdAt: entry.createdAt
                )
                filedIDs.insert(entry.id)
            } catch {
                library.lastImportErrorText = error.localizedDescription
            }
        }
        // Only the entries that actually reached the library leave the inbox;
        // a failure in the middle must not take its neighbours with it.
        if !filedIDs.isEmpty {
            BraindumpStore.shared.delete(filedIDs)
        }
        return filedIDs.count
    }

    /// Files a geordnetes Braindump-Ergebnis as its own note. It throws rather
    /// than swallowing the error into `library.lastImportErrorText`: the caller
    /// is the Braindump card, which shows the reason inline and — this is the
    /// point — leaves the entries in the inbox when the write did not happen.
    func fileBraindumpResult(_ text: String, title: String, intoFolder folderName: String?) throws {
        _ = try library.addTranscript(
            text,
            title: title,
            source: .braindump,
            folderName: folderName,
            language: transcriptionSettings.languageMode.whisperLanguageCode
        )
    }

    private func makeImportConfiguration() -> AudioImportConfiguration {
        let transcriptionBackend: TranscriptionBackend = appSettings.secureLocalModeEnabled ? .local : .remote
        let llmBackend = appSettings.importRewriteEnabled ? resolvedLLMBackend : nil

        let rewrite = llmBackend.map { backend in
            AudioImportConfiguration.Rewrite(
                settings: textImprovementSettings,
                prompts: promptSettings,
                extraInstructions: llmExtraInstructions(for: backend),
                backend: backend
            )
        }

        // Without a rewrite the fillers have to go locally. With one, the
        // remote model is told to drop them in the prompt instead -- mirroring
        // TextImprovementWorkflow, so an import reads like a dictation.
        let removeFillers = transcriptionSettings.removeFillerWords
            && (rewrite == nil || rewrite?.backend.isLocal == true)

        return AudioImportConfiguration(
            backend: transcriptionBackend,
            localModelName: selectedLocalModelName,
            language: transcriptionSettings.languageMode.whisperLanguageCode,
            vocabularyHints: GlossaryPromptBuilder.whisperHintTerms(glossarySettings),
            removeFillers: removeFillers,
            rewrite: rewrite
        )
    }

    // MARK: - Workflow Management

    /// Builds the live partial-transcript controller when the feature is
    /// enabled and the effective transcription backend is local WhisperKit —
    /// the only backend able to transcribe raw sample buffers on-device.
    /// Returns nil otherwise, leaving the workflow's live display dormant.
    private func makeLiveTranscription(
        backend: TranscriptionBackend,
        vocabularyHints: [String],
        languageCode: String
    ) -> LiveTranscriptionController? {
        guard appSettings.liveTranscriptEnabled, backend == .local else { return nil }
        return LiveTranscriptionController(
            modelName: selectedLocalModelName,
            language: languageCode,
            vocabularyHints: vocabularyHints
        )
    }

    /// Builds the silence auto-stop service when enabled. Level-driven, so it
    /// works with every transcription backend.
    private func makeAutoStop() -> SilenceAutoStopService? {
        guard appSettings.autoStopOnSilenceEnabled else { return nil }
        return SilenceAutoStopService(silenceDuration: appSettings.autoStopSilenceSeconds)
    }

    func startWorkflow(_ type: WorkflowType, source: WorkflowLaunchSource = .manual) {
        guard isWorkflowAvailable(type) else {
            if source == .manual {
                page = .settings
            }
            return
        }

        activeWorkflow?.stop()
        menuBarStatusResetTask?.cancel()
        workflowCleanupTask?.cancel()
        activeLaunchSource = source
        activePasteTarget = capturePasteTarget(for: source)
        beginCaptureContext(for: type, source: source)
        processingStartedAt = nil

        let vocabularyHints = GlossaryPromptBuilder.whisperHintTerms(glossarySettings)
        let languageCode = transcriptionSettings.languageMode.whisperLanguageCode
        let llmBackend = resolvedLLMBackend
        let transcriptionBackend: TranscriptionBackend = appSettings.secureLocalModeEnabled ? .local : .remote
        // Formatting depends on where the result will be pasted. It is an
        // extra LLM pass, so it needs a resolved backend — in secure local
        // mode that means on-device via MLX, never OpenAI.
        let formatProfile = llmBackend == nil
            ? nil
            : FormatProfileService.profile(
                for: activePasteTarget?.bundleIdentifier,
                settings: formatProfileSettings
            )
        let extraInstructions = llmExtraInstructions(for: llmBackend)
        var rewriteInstructions = extraInstructions
        if let formatProfile {
            rewriteInstructions.append(formatProfile.promptInstruction)
        }
        let removeFillers = transcriptionSettings.removeFillerWords

        switch type {
        case .transcription:
            let workflow = TranscriptionWorkflow(
                customTerms: vocabularyHints,
                language: languageCode,
                backend: transcriptionBackend,
                localModelName: selectedLocalModelName,
                inputDeviceUID: appSettings.preferredInputDeviceUID,
                removeFillers: removeFillers,
                formatProfile: formatProfile,
                llmBackend: llmBackend,
                extraInstructions: extraInstructions,
                liveTranscription: makeLiveTranscription(
                    backend: transcriptionBackend,
                    vocabularyHints: vocabularyHints,
                    languageCode: languageCode
                ),
                autoStop: makeAutoStop()
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .textImprover:
            guard let llmBackend else { return }
            let workflow = TextImprovementWorkflow(
                settings: textImprovementSettings,
                customTerms: vocabularyHints,
                language: languageCode,
                transcriptionBackend: transcriptionBackend,
                localModelName: selectedLocalModelName,
                inputDeviceUID: appSettings.preferredInputDeviceUID,
                removeFillers: removeFillers,
                llmBackend: llmBackend,
                prompts: promptSettings,
                extraInstructions: rewriteInstructions,
                liveTranscription: makeLiveTranscription(
                    backend: transcriptionBackend,
                    vocabularyHints: vocabularyHints,
                    languageCode: languageCode
                ),
                autoStop: makeAutoStop()
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .braindump:
            let workflow = TranscriptionWorkflow(
                type: .braindump,
                customTerms: vocabularyHints,
                language: languageCode,
                backend: appSettings.secureLocalModeEnabled ? .local : .remote,
                localModelName: selectedLocalModelName,
                inputDeviceUID: appSettings.preferredInputDeviceUID,
                removeFillers: transcriptionSettings.removeFillerWords,
                liveTranscription: makeLiveTranscription(
                    backend: transcriptionBackend,
                    vocabularyHints: vocabularyHints,
                    languageCode: languageCode
                )
            )
            configureBraindumpHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .selectionEdit:
            // Capturing the selection and pasting the result both require
            // the Accessibility permission — bail out early without it.
            let trusted = AccessibilityPermissionService.isTrusted(promptIfNeeded: true)
            accessibilityPermissionGranted = trusted
            guard trusted else {
                menuBarStatus = .error(.selectionEdit)
                scheduleMenuBarStatusReset(after: 1.6)
                if source == .manual {
                    page = .settings
                }
                return
            }

            guard let llmBackend else { return }
            let workflow = SelectionEditWorkflow(
                customTerms: vocabularyHints,
                language: languageCode,
                transcriptionBackend: transcriptionBackend,
                localModelName: selectedLocalModelName,
                inputDeviceUID: appSettings.preferredInputDeviceUID,
                llmBackend: llmBackend,
                prompts: promptSettings,
                extraInstructions: extraInstructions,
                liveTranscription: makeLiveTranscription(
                    backend: transcriptionBackend,
                    vocabularyHints: vocabularyHints,
                    languageCode: languageCode
                ),
                autoStop: makeAutoStop()
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        }

        if source == .hotkeyBackground,
           appSettings.hudEnabled,
           let workflow = activeWorkflow {
            onHUDEvent?(.show(workflow: workflow, displayName: workflow.type.displayName))
        }

        page = source.presentsWorkflowPage ? .workflow : .main
    }

    func isWorkflowAvailable(_ type: WorkflowType) -> Bool {
        switch type {
        case .transcription, .braindump:
            return transcriptionReady
        case .textImprover, .selectionEdit:
            // Available with any resolved LLM backend — in secure local mode
            // that is only the on-device MLX model, never OpenAI.
            return transcriptionReady && resolvedLLMBackend != nil
        }
    }

    func stopCurrentWorkflow() {
        activeWorkflow?.stop()
    }

    func resetCurrentWorkflow() {
        activeWorkflow?.reset()
        activeWorkflow = nil
        activePasteTarget = nil
        activeCaptureContext = nil
        activeLaunchSource = .manual
        menuBarStatusResetTask?.cancel()
        workflowCleanupTask?.cancel()
        menuBarStatus = .idle
        page = .main
    }

    func enableSecureLocalMode() {
        appSettings.secureLocalModeEnabled = true
        if !selectedLocalModelIsInstalled {
            installSelectedLocalModel()
        }
    }

    func installSelectedLocalModel() {
        guard !isDownloadingLocalModel else { return }

        let modelName = selectedLocalModelName
        localModelDownloadProgress = 0
        localModelDownloadStatusText = "Download startet..."
        localModelDownloadErrorText = nil

        Task {
            do {
                let installedURL = try await LocalTranscriptionService.shared.downloadAndInstall(
                    modelName: modelName
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let clampedProgress = min(max(progress, 0), 1)
                        self.localModelDownloadProgress = clampedProgress
                        self.localModelDownloadStatusText = "Download \(Int(clampedProgress * 100)) %"
                    }
                }

                appSettings.selectedLocalTranscriptionModelName = installedURL.lastPathComponent
                appSettings.secureLocalModeEnabled = true
                localModelDownloadProgress = nil
                localModelDownloadStatusText = "\(LocalTranscriptionModel.displayName(for: modelName)) ist installiert."
                localModelDownloadErrorText = nil

                try? await LocalTranscriptionService.shared.prepare(modelName: modelName)
            } catch {
                localModelDownloadProgress = nil
                localModelDownloadStatusText = nil
                localModelDownloadErrorText = error.localizedDescription
            }
        }
    }

    func installLocalLLM() {
        guard !isDownloadingLocalLLM else { return }

        let modelID = localLLMSettings.modelID
        localLLMDownloadProgress = 0
        localLLMDownloadStatusText = "Download startet..."
        localLLMDownloadErrorText = nil

        Task {
            do {
                try await LocalLLMService.shared.downloadAndInstall(modelID: modelID) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let clampedProgress = min(max(progress, 0), 1)
                        self.localLLMDownloadProgress = clampedProgress
                        self.localLLMDownloadStatusText = "Download \(Int(clampedProgress * 100)) %"
                    }
                }

                localLLMDownloadProgress = nil
                localLLMDownloadStatusText = "\(LocalLLMService.displayName(for: modelID)) ist installiert."
                localLLMDownloadErrorText = nil
            } catch {
                localLLMDownloadProgress = nil
                localLLMDownloadStatusText = nil
                localLLMDownloadErrorText = error.localizedDescription
            }
        }
    }

    func copyToClipboard(_ text: String) {
        writeSensitiveTextToPasteboard(text)
    }

    // MARK: - Auto-Paste

    /// Copies the text, restores focus when needed, then simulates Cmd+V.
    /// The text intentionally remains on the clipboard as a fallback if paste is blocked.
    private func pasteAtCursor(_ text: String, target: PasteTarget? = nil) {
        writeSensitiveTextToPasteboard(text)

        if isPopoverShown {
            NotificationCenter.default.post(name: .dismissPopover, object: nil)
        }

        let trusted = AccessibilityPermissionService.isTrusted(promptIfNeeded: true)
        accessibilityPermissionGranted = trusted
        guard trusted else {
            menuBarStatus = .error(activeWorkflow?.type)
            return
        }

        attemptPasteTrusted(
            target: target,
            attemptsRemaining: Self.pasteRetryInitialAttempts
        )
    }

    private func writeSensitiveTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.declareTypes([.string, Self.concealedPasteboardType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: Self.concealedPasteboardType)
    }

    func prepareForPopoverPresentation() {
        lastPopoverPasteTarget = captureCurrentFrontmostApp()
        if let activeWorkflow, activeWorkflow.phase.isActive {
            page = .workflow
        } else if shouldShowOnboarding {
            page = .onboarding
            markOnboardingSeen()
        } else if page == .workflow || page == .onboarding || page == .stats {
            page = .main
        }
    }

    func markOnboardingSeen() {
        guard !appSettings.hasSeenOnboarding else { return }
        appSettings.hasSeenOnboarding = true
    }

    // MARK: - API Key Status

    func apiKeyDisplayValue(for key: KeychainKey) -> String {
        guard let value = KeychainService.load(key: key), !value.isEmpty else {
            return ""
        }
        if value.count > 8 {
            return String(value.prefix(4)) + " \u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
        }
        return "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
    }

    func hasValue(for key: KeychainKey) -> Bool {
        guard let value = KeychainService.load(key: key) else { return false }
        return !value.isEmpty
    }

    // MARK: - Settings Persistence

    private static let settingsURL: URL = {
        try? AppSupportPaths.ensureAppSupportDirectoryExists()
        return AppSupportPaths.settingsURL
    }()

    private func saveSettings() {
        let container = SettingsContainer(
            app: appSettings,
            transcription: transcriptionSettings,
            textImprovement: textImprovementSettings,
            glossary: glossarySettings,
            formatProfiles: formatProfileSettings,
            localLLM: localLLMSettings,
            prompts: promptSettings,
            library: librarySettings
        )
        if let data = try? JSONEncoder().encode(container) {
            try? data.write(to: Self.settingsURL)
        }
    }

    private static func loadAppSettings() -> AppSettings {
        loadContainer()?.app ?? AppSettings()
    }

    private static func loadTranscriptionSettings() -> TranscriptionSettings {
        loadContainer()?.transcription ?? TranscriptionSettings()
    }

    private static func loadTextImprovementSettings() -> TextImprovementSettings {
        loadContainer()?.textImprovement ?? TextImprovementSettings()
    }

    private static func loadGlossarySettings() -> GlossarySettings {
        loadContainer()?.glossary ?? GlossarySettings()
    }

    private static func loadFormatProfileSettings() -> FormatProfileSettings {
        loadContainer()?.formatProfiles ?? FormatProfileSettings()
    }

    private static func loadLocalLLMSettings() -> LocalLLMSettings {
        loadContainer()?.localLLM ?? LocalLLMSettings()
    }

    private static func loadPromptSettings() -> PromptSettings {
        loadContainer()?.prompts ?? PromptSettings()
    }

    private static func loadLibrarySettings() -> LibrarySettings {
        loadContainer()?.library ?? LibrarySettings()
    }

    private static func loadLegacyOllamaRewritePrompt() -> String {
        loadContainer()?.ollama?.systemPrompt ?? ""
    }

    /// One-time import of the pre-glossary "Eigennamen" list. The legacy list
    /// is cleared afterwards so terms are not applied twice in LLM prompts.
    private func seedGlossaryFromLegacyTermsIfNeeded() {
        guard !glossarySettings.didImportLegacyTerms else { return }

        var seeded = glossarySettings
        if !textImprovementSettings.customTerms.isEmpty {
            seeded.entries = textImprovementSettings.customTerms.map { GlossaryEntry(term: $0) }
        }
        seeded.didImportLegacyTerms = true
        glossarySettings = seeded
        if !textImprovementSettings.customTerms.isEmpty {
            textImprovementSettings.customTerms = []
        }
    }

    /// One-time carry-over from the retired "Griffel Lokal+" workflow,
    /// whose own rewrite instruction lived on OllamaSettings. Griffel+
    /// now owns the single instruction, so an existing custom prompt moves
    /// over — but never overwrites one the user already set there.
    private func migrateLegacyOllamaRewritePromptIfNeeded() {
        guard !appSettings.didMigrateOllamaRewritePrompt else { return }

        let legacy = legacyOllamaRewritePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacy.isEmpty,
           textImprovementSettings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textImprovementSettings.systemPrompt = legacy
            // The legacy prompt was a conservative cleanup instruction, so keep
            // the matching scope rather than silently upgrading it to a rewrite.
            textImprovementSettings.rewriteScope = .korrektur
        }

        appSettings.didMigrateOllamaRewritePrompt = true
    }

    /// One-time move of the retired "Eigene Anweisung" onto the Prompts page.
    /// It used to override both Bearbeitungsgrade at once; the per-scope prompt
    /// editors replaced it, so the text lands on the scope the user had active.
    /// Runs after the Ollama carry-over, which writes into the same field.
    private func migrateLegacyCustomPromptIfNeeded() {
        guard !appSettings.didMigrateCustomPrompt else { return }

        let legacy = textImprovementSettings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacy.isEmpty {
            switch textImprovementSettings.rewriteScope {
            case .korrektur:
                if promptSettings.korrektur.isEmpty { promptSettings.korrektur = legacy }
            case .lektorat:
                if promptSettings.lektorat.isEmpty { promptSettings.lektorat = legacy }
            }
            textImprovementSettings.systemPrompt = ""
        }

        appSettings.didMigrateCustomPrompt = true
    }

    private static func loadContainer() -> SettingsContainer? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONDecoder().decode(SettingsContainer.self, from: data)
    }

    func refreshAccessibilityPermission() {
        accessibilityPermissionGranted = AccessibilityPermissionService.currentStatus()
    }

    func requestAccessibilityPermission() {
        accessibilityPermissionGranted = AccessibilityPermissionService.requestPermissionPrompt()
        AccessibilityPermissionService.openSystemSettings()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshAccessibilityPermission()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.refreshAccessibilityPermission()
        }
    }

    private func autoSelectFastLocalModelIfNeeded() {
        guard !appSettings.hasAutoSelectedFastLocalModel,
              LocalTranscriptionService.shouldAutoSelectRecommendedFastModel(
                currentModelName: appSettings.selectedLocalTranscriptionModelName
              ) else {
            return
        }

        appSettings.selectedLocalTranscriptionModelName = LocalTranscriptionService.recommendedFastModelName
        appSettings.hasAutoSelectedFastLocalModel = true
    }

    private func prewarmLocalTranscriptionIfNeeded() {
        guard appSettings.secureLocalModeEnabled,
              LocalTranscriptionService.isModelInstalled(resolvedLocalModelName) else {
            return
        }

        let modelName = resolvedLocalModelName
        Task.detached(priority: .utility) {
            try? await LocalTranscriptionService.shared.prepare(modelName: modelName)
        }
    }

    private func handleWorkflowOutput(_ text: String) {
        ingestPhrasesIfEnabled(outputText: text)
        recordUsageEvent(outputText: text)
        pasteAtCursor(text, target: activePasteTarget)
        if activeLaunchSource == .hotkeyBackground {
            page = .main
        }
        scheduleWorkflowCleanup(after: 1.05)
    }

    /// Feeds the local phrase-frequency store. Selection edit is excluded:
    /// its output transforms arbitrary pre-existing text, not the user's
    /// own dictation, and would quietly index foreign text.
    private func ingestPhrasesIfEnabled(outputText: String) {
        guard appSettings.phraseDetectionEnabled,
              let type = activeWorkflow?.type,
              type != .selectionEdit else { return }
        PhraseStore.shared.ingest(text: outputText)
    }

    private func recordUsageEvent(outputText: String) {
        guard let workflow = activeWorkflow else { return }
        let wordCount = outputText.split { $0.isWhitespace || $0.isNewline }.count
        StatsStore.shared.record(
            workflowType: workflow.type,
            wordCount: wordCount,
            recordingDuration: workflow.lastRecordingDuration,
            processingDuration: processingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        )
        processingStartedAt = nil
    }

    private func configureWorkflowHandlers<T: Workflow>(_ workflow: T) {
        workflow.onOutput = { [weak self] text in
            self?.handleWorkflowOutput(text)
        }
        workflow.onPhaseChange = { [weak self, weak workflow] phase in
            guard let self, let workflow else { return }
            self.handleWorkflowPhaseChange(phase, workflow: workflow)
        }
    }

    /// Braindump captures like a transcription but never pastes: the result
    /// goes into the local inbox instead.
    private func configureBraindumpHandlers(_ workflow: TranscriptionWorkflow) {
        workflow.onOutput = { [weak self] text in
            guard let self else { return }
            self.ingestPhrasesIfEnabled(outputText: text)
            self.recordUsageEvent(outputText: text)
            BraindumpStore.shared.add(text: text, captureContext: self.activeCaptureContext)
            if self.isPopoverShown, self.page == .workflow {
                self.page = .braindump
            }
            self.scheduleWorkflowCleanup(after: 1.05)
        }
        workflow.onPhaseChange = { [weak self, weak workflow] phase in
            guard let self, let workflow else { return }
            self.handleWorkflowPhaseChange(phase, workflow: workflow)
        }
    }

    private func handleWorkflowPhaseChange(_ phase: WorkflowPhase, workflow: any Workflow) {
        menuBarStatusResetTask?.cancel()

        switch phase {
        case .idle:
            if activeWorkflow == nil {
                menuBarStatus = .idle
            }
            onHUDEvent?(.dismiss(after: 0))

        case .running:
            if !workflow.isRecording, processingStartedAt == nil {
                processingStartedAt = Date()
            }
            menuBarStatus = workflow.isRecording
                ? .recording(workflow.type)
                : .processing(workflow.type)

        case .done:
            menuBarStatus = .success(workflow.type)
            onHUDEvent?(.dismiss(after: 0.9))

        case .error:
            menuBarStatus = .error(workflow.type)
            onHUDEvent?(.dismiss(after: 1.6))
            if activeLaunchSource == .hotkeyBackground {
                activeWorkflow = nil
                activePasteTarget = nil
                page = .main
            }
            scheduleMenuBarStatusReset(after: 1.6)
        }
    }

    private func scheduleWorkflowCleanup(after delay: TimeInterval) {
        guard let workflow = activeWorkflow else { return }

        workflowCleanupTask?.cancel()
        let workflowID = ObjectIdentifier(workflow)

        workflowCleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, let activeWorkflow = self.activeWorkflow else { return }
            guard ObjectIdentifier(activeWorkflow) == workflowID else { return }

            activeWorkflow.reset()
            self.activeWorkflow = nil
            self.activePasteTarget = nil
            self.activeCaptureContext = nil
            self.activeLaunchSource = .manual
            if !self.isPopoverShown {
                self.page = .main
            }
            self.menuBarStatus = .idle
        }
    }

    private func scheduleMenuBarStatusReset(after delay: TimeInterval) {
        menuBarStatusResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            if self.activeWorkflow == nil || !(self.activeWorkflow?.phase.isActive ?? false) {
                self.menuBarStatus = .idle
            }
        }
    }

    /// Notes which app and window the user was in, for Braindump only — the
    /// other modes paste their result straight back into that app, so the note
    /// would say nothing the user cannot see.
    ///
    /// The window title costs an Accessibility round trip into the other app,
    /// so it is resolved off the recording-start path and filled in afterwards;
    /// the transcript is seconds away and never waits for it.
    private func beginCaptureContext(for type: WorkflowType, source: WorkflowLaunchSource) {
        activeCaptureContext = nil
        captureContextGeneration &+= 1
        let generation = captureContextGeneration

        let mode = appSettings.braindumpCaptureContext
        guard type == .braindump, mode.recordsApp else { return }

        let application: NSRunningApplication?
        switch source {
        case .hotkeyBackground:
            application = CaptureContextService.frontmostApplication()
        case .manual:
            // The popover has focus by now, so the app that was in front is the
            // one snapshotted when the popover opened. It is cleared when our
            // own window takes focus, so a run started there records nothing
            // rather than something hours out of date.
            application = lastPopoverPasteTarget?.application
        }
        guard let application else { return }

        activeCaptureContext = CaptureContextService.identity(of: application)
        guard mode.recordsWindowTitle else { return }

        let processIdentifier = application.processIdentifier
        Task { @MainActor [weak self] in
            let title = await Task.detached(priority: .utility) {
                CaptureContextService.focusedWindowTitle(for: processIdentifier)
            }.value
            guard let self, let title, self.captureContextGeneration == generation else { return }
            self.activeCaptureContext?.windowTitle = title
        }
    }

    /// The main window taking focus invalidates the popover's snapshot of
    /// "which app was in front" — both for pasting and for the note on a
    /// Braindump.
    func mainWindowDidBecomeKey() {
        lastPopoverPasteTarget = nil
        captureContextGeneration &+= 1
        library.refresh()
    }

    private func capturePasteTarget(for source: WorkflowLaunchSource) -> PasteTarget? {
        switch source {
        case .manual:
            return lastPopoverPasteTarget
        case .hotkeyBackground:
            return captureCurrentFrontmostApp()
        }
    }

    private func attemptPasteTrusted(
        target: PasteTarget?,
        attemptsRemaining: Int
    ) {
        let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if let target {
            if frontmostPid == target.processIdentifier {
                performPaste()
                return
            }

            target.application.activate(options: [])
        } else {
            return
        }

        guard attemptsRemaining > 0 else {
            return
        }

        let delay: TimeInterval
        switch attemptsRemaining {
        case 16...:
            delay = 0.015
        case 8...15:
            delay = 0.025
        default:
            delay = 0.04
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.attemptPasteTrusted(
                target: target,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func performPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func captureCurrentFrontmostApp() -> PasteTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let ownPid = NSRunningApplication.current.processIdentifier
        guard app.processIdentifier != ownPid else { return nil }

        return PasteTarget(
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier,
            application: app
        )
    }
}

/// Every section is optional, which tolerates a section being **absent**.
/// It does not tolerate one being unreadable: `decodeIfPresent` returns nil
/// only for a missing key or JSON `null`, and a present-but-malformed section
/// still throws and takes the whole container with it. Per-field
/// `decodeIfPresent` inside each struct is the only thing that buys that — see
/// the note on `loadContainer()`.
private struct SettingsContainer: Codable {
    var app: AppSettings?
    var transcription: TranscriptionSettings?
    var textImprovement: TextImprovementSettings?
    var glossary: GlossarySettings?
    var formatProfiles: FormatProfileSettings?
    var localLLM: LocalLLMSettings?
    var prompts: PromptSettings?
    var library: LibrarySettings?
    /// Read-only legacy section from the retired Ollama integration; kept for
    /// the one-time rewrite-prompt carry-over and never written back.
    var ollama: LegacyOllamaSettings?
}

// MARK: - Notification for Popover Dismissal

extension Notification.Name {
    static let dismissPopover = Notification.Name("dismissPopover")
}

private struct PasteTarget {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let application: NSRunningApplication
}
