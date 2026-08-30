import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            switch appState.page {
            case .main:
                mainPage
            case .onboarding:
                onboardingPage
            case .settings:
                settingsPage
            case .workflow:
                workflowPage
            case .stats:
                statsPage
            case .braindump:
                braindumpPage
            case .prompts:
                PromptsView(appState: appState)
            }
        }
        .frame(width: 340)
        .background(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.07), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: appState.page)
    }

    // MARK: - Main Page

    private var mainPage: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("Griffel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        appState.page = .settings
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.vc(.quiet, .icon))
                    .help("Einstellungen")
                    .overlay(alignment: .topTrailing) {
                        if !appState.accessibilityPermissionGranted {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                                .offset(x: 1, y: -1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.5)
            )

            if InstallLocationService.shouldOfferMoveToApplications {
                installHintBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            }

            // On screen whether or not anything is set up. An empty setup is
            // a state the card already names and can act on, so a local-only
            // user reaches the local mode right here instead of being sent to
            // the settings for an API key they will never enter.
            modeCard
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, appState.accessibilityPermissionGranted ? 6 : 4)

            if !appState.accessibilityPermissionGranted {
                accessibilityHintBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            // Only what the current mode can actually run. A mode that is
            // unavailable is absent, not greyed out — the mode card says why.
            VStack(spacing: 0) {
                ForEach(appState.availableWorkflows) { type in
                    WorkflowRowView(
                        type: type,
                        hotkeyTokens: appState.hotkey(for: type).keycapTokens,
                        subtitle: appState.workflowSubtitle(for: type)
                    ) {
                        // Braindump opens the inbox instead of recording;
                        // every other mode starts right away.
                        if type == .braindump {
                            appState.page = .braindump
                        } else {
                            appState.startWorkflow(type)
                        }
                    }
                }
            }
            .padding(.vertical, 2)

            // The explainer belongs to a row that is on screen; without the
            // row it would describe a mode the user cannot reach.
            if appState.availableWorkflows.contains(.selectionEdit) {
                selectionEditHint
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            appFooter
        }
    }

    /// Selection edit is the one mode with a precondition, so the requirement
    /// stays on screen instead of hiding behind a tap.
    private var selectionEditHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 16, height: 16)

            Text("F\u{00FC}r \u{201E}Auswahl bearbeiten\u{201C} zuerst Text in einer anderen App markieren, dann \(appState.hotkeyLabel(for: .selectionEdit)) halten und die Anweisung sprechen (z.B. \u{201E}mach es k\u{00FC}rzer\u{201C}).")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .glassCard(radius: DS.radiusS)
    }

    // MARK: - Mode Card

    /// The main page's one decision — where dictation is processed — plus the
    /// controls that belong to it. Mode, models and microphone live here and
    /// nowhere else: the settings pane used to repeat all of them, which made
    /// one setting look like two and left the copies free to disagree.
    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(
                get: { appState.processingMode },
                set: { appState.processingMode = $0 }
            )) {
                ForEach(ProcessingMode.allCases) { mode in
                    Text(mode.displayName)
                        .frame(maxWidth: .infinity)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            // A macOS segmented control keeps its intrinsic width whatever
            // frame it is offered, so align it with the card instead of
            // letting it centre against the left-aligned rows below.
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(appState.isDownloadingLocalModel || appState.isDownloadingLocalLLM)

            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(appState.modeIsReady ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)

                Text(appState.modeStatusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            Divider().opacity(0.4)

            modeCardRow(icon: "mic", label: "Mikrofon") {
                InputDevicePicker(appState: appState)
            }

            // Whisper turns audio into text, the MLX model turns text into
            // better text — two stages of the same run, never alternatives for
            // the same slot. Only the local mode picks either of them: the
            // online mode's models are OpenAI's and not ours to choose.
            if appState.processingMode == .local {
                modeCardRow(icon: "waveform", label: "Aufnahme") {
                    Picker("", selection: Binding(
                        get: { appState.selectedLocalModelName },
                        set: { appState.appSettings.selectedLocalTranscriptionModelName = $0 }
                    )) {
                        ForEach(LocalTranscriptionService.modelOptions()) { model in
                            // Only the ones still missing carry a marker: on
                            // the common case the extra word would be noise,
                            // and the status line above already states whether
                            // the selected model is there.
                            Text(model.isInstalled
                                 ? model.shortDisplayName
                                 : "\(model.shortDisplayName) \u{00B7} nicht geladen")
                                .tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(appState.isDownloadingLocalModel)
                }

                modeCardRow(icon: "sparkles", label: "Umschreiben") {
                    Picker("", selection: $appState.localLLMSettings.modelID) {
                        ForEach(LocalLLMService.modelOptions()) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(appState.isDownloadingLocalLLM)
                }
            }

            // A download in flight replaces the button it came from, and
            // `modeAction` hands back at most one thing to do — this card is
            // the page's only `.primary`.
            if appState.localModelDownloadProgress != nil || appState.localModelDownloadErrorText != nil {
                LocalModelDownloadStatus(appState: appState, showsModelName: false)
            } else if appState.localLLMDownloadProgress != nil || appState.localLLMDownloadErrorText != nil {
                LocalLLMDownloadStatus(appState: appState, showsModelName: false)
            } else if let action = appState.modeAction {
                Button(action.title) {
                    appState.perform(action)
                }
                .buttonStyle(.vc(.primary, fill: true))
            }
        }
        .padding(10)
        .glassCard()
    }

    /// One labelled control inside the mode card. The fixed label column keeps
    /// the popups flush with each other.
    private func modeCardRow<Control: View>(
        icon: String,
        label: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var accessibilityHintBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text("Einfügen braucht Bedienungshilfen.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Nach Updates kann macOS die Freigabe neu verlangen.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Freigeben") {
                appState.requestAccessibilityPermission()
            }
            .buttonStyle(.vc(.secondary, .compact))
        }
        .padding(10)
        .glassCard(tint: .orange)
    }

    private var installHintBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text("Für sauberen Anmeldestart nach /Applications verschieben.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Sonst entstehen leichter doppelte Login-Items oder uneinheitliche Updates.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Verschieben") {
                appState.page = .settings
            }
            .buttonStyle(.vc(.secondary, .compact))
        }
        .padding(10)
        .glassCard(tint: .orange)
    }

    private var onboardingPage: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Willkommen bei Griffel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button("Später") {
                    appState.page = .main
                }
                .buttonStyle(.vc(.quiet, .compact))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.5)
            )

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 42, height: 42)
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Einmal einrichten, dann direkt loslegen.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Eigenen OpenAI API Key eintragen. Danach sprechen und einfügen.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    if InstallLocationService.shouldOfferMoveToApplications {
                        onboardingInstallCard
                    }

                    onboardingStep(number: "1", title: "OpenAI Key speichern", detail: "Öffne die Einstellungen und trage deinen eigenen OpenAI API Key ein.")
                    onboardingStep(number: "2", title: "Berechtigungen erlauben", detail: "Mikrofon und Bedienungshilfen für das Einfügen freigeben.")
                    onboardingStep(number: "3", title: "Workflow wählen", detail: "Griffel oder einen der Verbesserer-Workflows direkt aus der Menüleiste starten.")
                }

                HStack(spacing: 8) {
                    Button("Jetzt einrichten") {
                        appState.page = .settings
                    }
                    .buttonStyle(.primary)

                    Text("Du findest alles später im Zahnrad.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Spacer(minLength: 0)

            appFooter
        }
    }

    private func onboardingStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.05))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var onboardingInstallCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text("Lege Griffel zuerst nach /Applications.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Das hält Anmeldestart, spätere Updates und das Entfernen sauber auf einer einzigen App-Kopie.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .glassCard(tint: .orange)
    }

    // MARK: - Settings Page

    private var settingsPage: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                BackButton { appState.page = .main }

                Spacer()

                Text("Einstellungen")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()
                settingsQuickAction
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            SettingsContentView(appState: appState)

            Spacer(minLength: 0)

            appFooter
        }
    }

    @ViewBuilder
    private var settingsQuickAction: some View {
        if !appState.accessibilityPermissionGranted {
            Button {
                appState.requestAccessibilityPermission()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Freigeben")
                }
            }
            .buttonStyle(.vc(.secondary, tint: .orange))
        } else {
            HeaderSpacer()
        }
    }

    // MARK: - Workflow Page

    private var workflowPage: some View {
        VStack(spacing: 0) {
            if let workflow = appState.activeWorkflow {
                // Header bar
                HStack {
                    BackButton { appState.resetCurrentWorkflow() }

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: workflow.type.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(workflowIconColor(workflow.type))
                        Text(workflow.type.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                // Content
                switch workflow.type {
                case .transcription, .braindump:
                    if let w = workflow as? TranscriptionWorkflow {
                        TranscriptionActiveView(
                            workflow: w,
                            doneTitle: workflow.type == .braindump
                                ? "Im Eingang gespeichert"
                                : "Eingef\u{00FC}gt"
                        )
                    }
                case .textImprover:
                    if let w = workflow as? TextImprovementWorkflow {
                        TextImproverActiveView(workflow: w)
                    }
                case .selectionEdit:
                    if let w = workflow as? SelectionEditWorkflow {
                        SelectionEditActiveView(workflow: w)
                    }
                }

                Spacer(minLength: 0)

                appFooter
            }
        }
    }

    private var appFooter: some View {
        HStack {
            if appState.page != .stats {
                Button {
                    appState.page = .stats
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Statistik")
                    }
                }
                .buttonStyle(.vc(.quiet, .compact))
            }

            Button {
                appState.openMainWindow()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 9, weight: .semibold))
                    // Names what you get, not the container it arrives in —
                    // the macwindow glyph already says it opens a window, and
                    // "Ablage" is the word the rest of the app uses for it.
                    Text("Ablage")
                }
            }
            .buttonStyle(.vc(.quiet, .compact))
            .help("\u{00D6}ffnet die Ablage im eigenen Fenster \u{2014} mit Datei-Import und Braindump daneben.")

            Spacer()

            Button("Griffel beenden") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.vc(.quiet, .compact))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Braindump Page

    private var braindumpPage: some View {
        VStack(spacing: 0) {
            HStack {
                BackButton { appState.page = .main }

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: WorkflowType.braindump.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(WorkflowType.braindump.accentUIColor)
                    Text("Braindump")
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer()
                HeaderSpacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            BraindumpView(appState: appState)

            appFooter
        }
    }

    // MARK: - Stats Page

    private var statsPage: some View {
        VStack(spacing: 0) {
            HStack {
                BackButton { appState.page = .main }

                Spacer()

                Text("Statistik")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()
                HeaderSpacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            StatsView()

            appFooter
        }
    }

    private func workflowIconColor(_ type: WorkflowType) -> Color {
        type.accentUIColor
    }
}

// MARK: - Page Header

/// Back affordance shared by every sub-page header.
private struct BackButton: View {
    let action: () -> Void

    /// Width the opposite side of a header must reserve to keep its title
    /// optically centred.
    static let reservedWidth: CGFloat = 72

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Zur\u{00FC}ck")
            }
        }
        .buttonStyle(.quiet)
    }
}

/// Balances a header that has a `BackButton` on the other side.
private struct HeaderSpacer: View {
    var body: some View {
        Color.clear.frame(width: BackButton.reservedWidth, height: 1)
    }
}

// MARK: - Live Partial Transcript

/// Rolling partial transcript shown in the popover while recording locally.
/// Head-truncated so the newest words stay visible; cosmetic only — the
/// pasted text always comes from the final batch pass.
private struct LivePartialTranscriptView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .truncationMode(.head)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
    }
}

// MARK: - Transcription Active View

struct TranscriptionActiveView: View {
    @Bindable var workflow: TranscriptionWorkflow
    var doneTitle: String = "Eingef\u{00FC}gt"

    var body: some View {
        VStack(spacing: 0) {
            switch workflow.phase {
            case .idle, .running:
                if workflow.isRecording {
                    recordingView(onStop: { workflow.stop() })
                } else {
                    processingView(message: "Wird transkribiert \u{2026}")
                }

            case .done(let text):
                autoPasteView(text: text, title: doneTitle, accent: workflow.type.accentUIColor)

            case .error(let msg):
                errorView(message: msg) {
                    workflow.reset()
                    workflow.start()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func recordingView(onStop: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)

            VStack(spacing: 7) {
                WaveformView(audioLevel: workflow.audioLevel, isRecording: true)
                    .frame(height: 44)

                if let device = workflow.activeInputDevice {
                    ActiveInputDeviceLabel(device: device)
                }
            }
            .padding(.horizontal, 24)

            // Monochrome stop button
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.7))
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.plain)

            if let partial = workflow.livePartialText {
                LivePartialTranscriptView(text: partial)
            } else {
                Text("Ich h\u{00F6}re zu \u{2026} Klicke zum Stoppen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(height: 8)
        }
    }
}

// MARK: - Text Improver Active View

struct TextImproverActiveView: View {
    @Bindable var workflow: TextImprovementWorkflow

    var body: some View {
        VStack(spacing: 0) {
            switch workflow.phase {
            case .idle, .running:
                if workflow.isRecording {
                    recordingView(onStop: { workflow.stop() })
                } else {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 24)
                        ProgressView()
                            .scaleEffect(0.7)
                            .controlSize(.small)
                        if case .running(let msg) = workflow.phase {
                            Text(msg)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer().frame(height: 24)
                    }
                }

            case .done(let text):
                autoPasteView(text: text, accent: workflow.type.accentUIColor)

            case .error(let msg):
                errorView(message: msg) {
                    workflow.reset()
                    workflow.start()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func recordingView(onStop: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)

            VStack(spacing: 7) {
                WaveformView(audioLevel: workflow.audioLevel, isRecording: true)
                    .frame(height: 44)

                if let device = workflow.activeInputDevice {
                    ActiveInputDeviceLabel(device: device)
                }
            }
            .padding(.horizontal, 24)

            // Monochrome stop button
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.7))
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.plain)

            if let partial = workflow.livePartialText {
                LivePartialTranscriptView(text: partial)
            } else {
                Text("Ich h\u{00F6}re zu \u{2026} Klicke zum Stoppen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(height: 8)
        }
    }
}

// MARK: - Selection Edit Active View

struct SelectionEditActiveView: View {
    @Bindable var workflow: SelectionEditWorkflow

    var body: some View {
        VStack(spacing: 0) {
            switch workflow.phase {
            case .idle, .running:
                if workflow.isRecording {
                    VStack(spacing: 16) {
                        Spacer().frame(height: 20)

                        VStack(spacing: 7) {
                            WaveformView(audioLevel: workflow.audioLevel, isRecording: true)
                                .frame(height: 44)

                            if let device = workflow.activeInputDevice {
                                ActiveInputDeviceLabel(device: device)
                            }
                        }
                        .padding(.horizontal, 24)

                        Button {
                            workflow.stop()
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
                                    .frame(width: 44, height: 44)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.primary.opacity(0.7))
                                    .frame(width: 14, height: 14)
                            }
                        }
                        .buttonStyle(.plain)

                        if let partial = workflow.livePartialText {
                            LivePartialTranscriptView(text: partial)
                        } else {
                            Text("Anweisung sprechen \u{2026} Klicke zum Anwenden.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer().frame(height: 8)
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 24)
                        ProgressView()
                            .scaleEffect(0.7)
                            .controlSize(.small)
                        if case .running(let msg) = workflow.phase {
                            Text(msg)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer().frame(height: 24)
                    }
                }

            case .done(let text):
                autoPasteView(text: text, title: "Auswahl ersetzt", accent: workflow.type.accentUIColor)

            case .error(let msg):
                errorView(message: msg) {
                    workflow.reset()
                    workflow.start()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Shared Result / Error Views

private func processingView(message: String) -> some View {
    VStack(spacing: 12) {
        Spacer().frame(height: 24)
        ProgressView()
            .scaleEffect(0.7)
            .controlSize(.small)
        Text(message)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
        Spacer().frame(height: 24)
    }
}

@MainActor
private func autoPasteView(text: String, title: String = "Eingef\u{00FC}gt", accent: Color = .blue) -> some View {
    VStack(spacing: 12) {
        Spacer().frame(height: 20)

        ZStack {
            Circle()
                .fill(Color.green.opacity(0.1))
                .frame(width: 44, height: 44)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.green)
        }

        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)

        Text(PhraseHighlighter.highlighted(text, accent: accent))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)

        Spacer().frame(height: 12)
    }
}

private func errorView(message: String, onRetry: @escaping () -> Void) -> some View {
    VStack(spacing: 10) {
        Spacer().frame(height: 16)

        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.1))
                .frame(width: 40, height: 40)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
        }

        Text(message)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)

        Button("Nochmal versuchen", action: onRetry)
            .buttonStyle(.primary)

        Spacer().frame(height: 4)
    }
}
