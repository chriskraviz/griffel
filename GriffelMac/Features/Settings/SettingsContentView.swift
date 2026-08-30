import SwiftUI
import AppKit

struct SettingsContentView: View {
    @Bindable var appState: AppState
    /// How to reach the Prompts editor. `nil` keeps the popover's own page
    /// navigation, which is the only thing that works there; the Settings
    /// window has no pages and passes a closure that presents a sheet instead.
    /// Leaving it optional is what keeps the popover call site unchanged.
    var onOpenPrompts: (() -> Void)?
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Two-tab segmented picker
            Picker("", selection: $selectedTab) {
                Text("Anpassen").tag(0)
                Text("Zugang").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                if selectedTab == 0 {
                    CustomizeSettingsView(appState: appState, onOpenPrompts: onOpenPrompts)
                } else {
                    AccessSettingsView(appState: appState)
                }
            }
        }
        .onAppear {
            appState.refreshAccessibilityPermission()
            selectedTab = defaultTabSelection
        }
    }

    private var defaultTabSelection: Int {
        Self.defaultSection(for: appState) == .customize ? 0 : 1
    }

    /// Which half to open on. Shared with `WideSettingsView` so the popover
    /// and the window agree about what needs attention first — a missing
    /// permission or an unfinished install outranks the tweaking pane.
    static func defaultSection(for appState: AppState) -> WideSettingsView.Section {
        if !appState.accessibilityPermissionGranted {
            return .access
        }
        if appState.isConfigured && !InstallLocationService.shouldOfferMoveToApplications {
            return .customize
        }
        return .access
    }
}

// MARK: - Section Label (quiet style)

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Access Settings (Tab 1: Zugang)

struct AccessSettingsView: View {
    private static let openAIAPIKeyPattern = #"^sk-[A-Za-z0-9_-]{20,}$"#

    @Bindable var appState: AppState

    private enum FieldFocus {
        case openAIAPIKey
    }

    @State private var launchAtLoginService = LaunchAtLoginService()
    @State private var currentInstallLocation = InstallLocationService.currentInstallLocation
    @State private var openAIAPIKey = ""
    @State private var editingAPIKey = false
    @State private var saved = false
    @State private var saveErrorText: String?
    @State private var installActionErrorText: String?
    @State private var showCleanupOptions = false
    @State private var deleteLocalDataOnCleanup = true
    /// Off by default: recordings and transcripts are the user's own content,
    /// not app state, and this is the one action that cannot be undone.
    @State private var deleteLibraryOnCleanup = false
    @State private var cleanupStatusText: String?
    @State private var cleanupErrorText: String?
    @FocusState private var focusedField: FieldFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Berechtigungen")

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: appState.accessibilityPermissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appState.accessibilityPermissionGranted ? .green : .orange)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.accessibilityPermissionGranted ? "Direktes Einfügen ist freigegeben." : "Direktes Einfügen ist noch nicht freigegeben.")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(appState.accessibilityPermissionGranted
                             ? "Griffel darf Text direkt in die aktive App einfügen."
                             : "Öffne Bedienungshilfen und aktiviere Griffel. Falls Griffel schon aktiv ist, einmal aus- und wieder einschalten.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Nothing to grant while the permission holds — the row comes
                // back on its own if macOS revokes it after an update.
                if !appState.accessibilityPermissionGranted {
                    HStack(spacing: 8) {
                        Button("Bedienungshilfen öffnen") {
                            appState.requestAccessibilityPermission()
                        }
                        .buttonStyle(.secondary)

                        Button("Erneut prüfen") {
                            appState.refreshAccessibilityPermission()
                        }
                        .buttonStyle(.quiet)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: "OpenAI API Key")
                    Spacer()
                    if appState.hasValue(for: .openAIAPIKey) && !editingAPIKey {
                        Button("\u{00C4}ndern") { editingAPIKey = true }
                            .buttonStyle(.vc(.quiet, .compact))
                    }
                }

                if appState.hasValue(for: .openAIAPIKey) && !editingAPIKey {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green.opacity(0.8))
                        Text(appState.apiKeyDisplayValue(for: .openAIAPIKey))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                } else {
                    HStack(spacing: 8) {
                        SecureField("sk-...", text: $openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                            .focused($focusedField, equals: .openAIAPIKey)

                        Button("Einf\u{00FC}gen") {
                            pasteAPIKeyFromClipboard()
                        }
                        .buttonStyle(.secondary)
                    }
                }

                Text("Dein Key bleibt lokal in dieser App. Audio und Text werden direkt an die OpenAI API gesendet.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let saveErrorText {
                    Text(saveErrorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The tab's one commit action, next to the only field that
                // needs it — everything else on this tab binds live.
                HStack {
                    Spacer()
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 5) {
                            if saved {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(saved ? "Gespeichert" : "API Key speichern")
                        }
                    }
                    .buttonStyle(.vc(.primary, tint: saved ? .green : nil))
                    .animation(.easeInOut(duration: 0.2), value: saved)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Installation & Updates")

                Text(installationHeadline)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(installationDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(InstallLocationService.bundleURL.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !InstallLocationService.otherInstalledBundleURLs.isEmpty {
                    Text("Weitere Griffel-Kopien auf diesem Mac können doppelte Login-Items auslösen.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Lead action on its own row — three buttons never fit the
                // 340pt popover side by side. Stays secondary: this tab's one
                // primary is "API Key speichern" at the bottom.
                VStack(alignment: .leading, spacing: 8) {
                    if InstallLocationService.shouldOfferMoveToApplications {
                        Button("Nach /Applications bewegen") {
                            moveToApplications()
                        }
                        .buttonStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button("Im Finder zeigen") {
                            revealInFinder(urls: [InstallLocationService.bundleURL])
                        }
                        .buttonStyle(.vc(.quiet, .compact))

                        if !InstallLocationService.otherInstalledBundleURLs.isEmpty {
                            Button("Weitere Kopien zeigen") {
                                revealInFinder(urls: InstallLocationService.otherInstalledBundleURLs)
                            }
                            .buttonStyle(.vc(.quiet, .compact))
                        }
                    }
                }

                if let installActionErrorText {
                    Text(installActionErrorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Version \(Self.appVersionText)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Griffel hat keinen \u{00F6}ffentlichen Update-Feed \u{2014} baue neue Versionen selbst aus dem Repo.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Launch at Login
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Beim Anmelden")

                Toggle("Griffel automatisch starten", isOn: Binding(
                    get: { launchAtLoginService.isEnabled },
                    set: { launchAtLoginService.setEnabled($0) }
                ))
                .toggleStyle(.switch)

                Text(launchAtLoginService.errorText ?? launchAtLoginService.helperText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        launchAtLoginService.errorText == nil
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(.red)
                    )
                    .fixedSize(horizontal: false, vertical: true)

                if LegacyMigrationService.didMigrateThisLaunch && !launchAtLoginService.isEnabled {
                    Text("Nach dem Update auf Griffel bitte einmal neu aktivieren.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Sauber Entfernen")

                Text("Vor dem Löschen Griffel erst auf diesem Mac bereinigen. So verschwinden Anmeldestart und lokale Daten sauber aus dem Weg.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showCleanupOptions {
                    Toggle("Zugangsdaten und Einstellungen dieses Macs löschen", isOn: $deleteLocalDataOnCleanup)
                        .toggleStyle(.switch)

                    if deleteLocalDataOnCleanup {
                        // The switch only exists for the default folder inside
                        // Application Support. A folder the user picked is
                        // theirs; an uninstaller must not delete a directory in
                        // the user's own space, so it is not offered at all
                        // rather than offered and quietly ignored.
                        if libraryIsInsideAppSupport {
                            Toggle("Aufnahmen und Transkripte ebenfalls löschen", isOn: $deleteLibraryOnCleanup)
                                .toggleStyle(.switch)
                        }

                        Text(libraryCleanupHint)
                            .font(.system(size: 10.5))
                            .foregroundStyle(deleteLibraryOnCleanup && libraryIsInsideAppSupport ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Danach Griffel beenden und die App aus /Applications löschen. Bereits verwaiste alte Login-Items können in den Systemeinstellungen einmalig manuell entfernt werden.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button("Jetzt bereinigen") {
                            runCleanup()
                        }
                        .buttonStyle(.destructive)

                        Button("Abbrechen") {
                            showCleanupOptions = false
                        }
                        .buttonStyle(.quiet)
                    }
                } else {
                    Button("Entfernung vorbereiten") {
                        showCleanupOptions = true
                    }
                    .buttonStyle(.secondary)
                }

                if let cleanupStatusText {
                    Text(cleanupStatusText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let cleanupErrorText {
                    Text(cleanupErrorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        }
        .padding(16)
        .onAppear {
            launchAtLoginService.refresh()
            refreshInstallState()
            load()
            if !appState.hasValue(for: .openAIAPIKey) {
                editingAPIKey = true
                focusedField = .openAIAPIKey
            }
        }
    }

    private func load() {
        openAIAPIKey = ""
    }

    private func save() {
        saveErrorText = nil
        cleanupStatusText = nil
        cleanupErrorText = nil
        KeychainService.invalidateCache()
        let trimmedAPIKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if editingAPIKey || !appState.hasValue(for: .openAIAPIKey) {
            guard !trimmedAPIKey.isEmpty else {
                saveErrorText = "Bitte trage deinen OpenAI API Key ein."
                return
            }
            do {
                try KeychainService.save(key: .openAIAPIKey, value: trimmedAPIKey)
                openAIAPIKey = ""
                editingAPIKey = false
            } catch {
                saveErrorText = "OpenAI API Key konnte nicht gespeichert werden."
                return
            }
        }

        KeychainService.invalidateCache()
        if !appState.hasValue(for: .openAIAPIKey) {
            saveErrorText = "OpenAI API Key wurde nicht persistent gespeichert. Bitte App neu starten und erneut versuchen."
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) { saved = false }
        }
    }

    private func pasteAPIKeyFromClipboard() {
        guard let rawText = NSPasteboard.general.string(forType: .string) else {
            saveErrorText = "Zwischenablage enthält keinen Text."
            return
        }

        let firstLine = rawText.components(separatedBy: .newlines).first ?? rawText
        let trimmedKey = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.range(of: Self.openAIAPIKeyPattern, options: .regularExpression) != nil else {
            saveErrorText = "Zwischenablage enthält keinen plausiblen OpenAI API Key."
            return
        }

        openAIAPIKey = trimmedKey
        NSPasteboard.general.clearContents()
        saveErrorText = nil
    }

    private var installationHeadline: String {
        switch currentInstallLocation {
        case .applications:
            return "Griffel liegt am richtigen Ort."
        case .userApplications:
            return "Griffel liegt noch in ~/Applications."
        case .outsideApplications:
            return "Griffel liegt noch nicht in /Applications."
        case .unknown:
            return "Der Installationsort konnte nicht sicher erkannt werden."
        }
    }

    private var installationDetail: String {
        switch currentInstallLocation {
        case .applications:
            if InstallLocationService.otherInstalledBundleURLs.isEmpty {
                return "Für stabile Login-Items und Updates nur diese Kopie weiterverwenden."
            }
            return "Diese Kopie ist korrekt. Zusätzliche Kopien solltest du später entfernen."
        case .userApplications:
            return "F\u{00FC}r stabile Hotkeys und Login-Items sollte Griffel nur aus /Applications laufen."
        case .outsideApplications:
            return "Verschiebe Griffel einmal nach /Applications, damit Anmeldestart und Hotkeys sauber bleiben."
        case .unknown:
            return "Öffne Griffel möglichst direkt aus /Applications."
        }
    }

    /// "1.5.0 (15)" — MARKETING_VERSION plus build number, the pair a bug
    /// report or screenshot needs to name the running build.
    private static var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func refreshInstallState() {
        currentInstallLocation = InstallLocationService.currentInstallLocation
        installActionErrorText = nil
    }

    private func moveToApplications() {
        installActionErrorText = nil

        do {
            try InstallLocationService.moveToApplicationsAndRelaunch()
        } catch {
            installActionErrorText = error.localizedDescription
        }
    }

    private func runCleanup() {
        cleanupStatusText = nil
        cleanupErrorText = nil

        let report = deleteLocalDataOnCleanup
            ? AppCleanupService.cleanupUserData(
                libraryRootURL: appState.library.rootURL,
                deletesLibrary: deleteLibraryOnCleanup && libraryIsInsideAppSupport
              )
            : AppCleanupService.removeLaunchAtLoginRegistration()

        KeychainService.invalidateCache()
        launchAtLoginService.refresh()
        refreshInstallState()

        if deleteLocalDataOnCleanup {
            openAIAPIKey = ""
            editingAPIKey = true
        }

        if report.failedItems.isEmpty {
            var status = deleteLocalDataOnCleanup
                ? "Anmeldestart und lokale Daten wurden bereinigt. Jetzt Griffel beenden und aus /Applications löschen."
                : "Anmeldestart wurde deaktiviert. Jetzt Griffel beenden und aus /Applications löschen."
            if let preserved = report.preservedLibraryURL {
                status += "\n\nAufnahmen und Transkripte liegen weiterhin in \(preserved.path)."
            }
            cleanupStatusText = status
            showCleanupOptions = false

            let urlsToReveal = report.knownInstallBundleURLs.isEmpty
                ? [InstallLocationService.bundleURL]
                : report.knownInstallBundleURLs
            revealInFinder(urls: urlsToReveal)
            return
        }

        let failureSummary = report.failedItems
            .map { "\($0.url.lastPathComponent): \($0.errorDescription)" }
            .joined(separator: "\n")
        cleanupErrorText = "Nicht alles konnte bereinigt werden:\n\(failureSummary)"
    }

    /// The library only counts as app data while it sits in the app's own
    /// Application Support folder.
    private var libraryIsInsideAppSupport: Bool {
        let root = AppSupportPaths.appSupportDirectoryURL.standardizedFileURL.path
        let candidate = appState.library.rootURL.standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private var libraryCleanupHint: String {
        let path = appState.library.rootURL.path
        guard libraryIsInsideAppSupport else {
            return "Deine Aufnahmen liegen in \(path) und bleiben dort. Diesen Ordner löschst du selbst, wenn du ihn nicht mehr brauchst."
        }
        if deleteLibraryOnCleanup {
            return "Löscht auch \(path) mit allen Aufnahmen und Transkripten. Das lässt sich nicht rückgängig machen."
        }
        return "Aus: \(path) bleibt unangetastet."
    }

    private func revealInFinder(urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

// MARK: - Customize Settings (Tab 2: Anpassen)

struct CustomizeSettingsView: View {
    @Bindable var appState: AppState
    /// Threaded down from `SettingsContentView` — see the note there.
    var onOpenPrompts: (() -> Void)?
    @State private var newGlossaryTerm = ""
    @State private var newGlossaryDefinition = ""
    /// Last outcome of a rebind: what to say, and whether the combination was
    /// refused outright or merely worth a warning.
    @State private var hotkeyFeedback: (message: String, isError: Bool)?
    /// Which shortcut row currently owns the keyboard. One at a time — see
    /// `HotkeyRecorderField`.
    @State private var recordingHotkeyType: WorkflowType?

    /// Scans the models directory once; nil below the threshold so the note
    /// costs nothing when there is nothing to say.
    private var extraModelsNote: String? {
        let count = LocalTranscriptionService.installedModels().count
        return count > 1 ? "\(count) Modelle liegen lokal auf diesem Mac." : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: Lokale Modelle
            // Inventory, not a second set of controls: mode, models and
            // microphone are the main page's decision, and repeating them here
            // only made one setting look like two.
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Lokale Modelle")

                LocalModelCard(appState: appState)
                    .padding(10)
                    .glassCard(radius: DS.radiusS)

                if let extraModelsNote {
                    Text(extraModelsNote)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                LocalLLMCard(appState: appState)
                    .padding(10)
                    .glassCard(radius: DS.radiusS)

                Text("Das Sprachmodell \u{00FC}bernimmt im lokalen Modus die \u{00DC}berarbeitung, die Auswahl-Bearbeitung und den Braindump. Es rechnet auf deinem Mac \u{2014} nichts davon verl\u{00E4}sst das Ger\u{00E4}t.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Modus, Modelle und Mikrofon w\u{00E4}hlst du auf der Hauptseite. Hier steht, was davon schon auf diesem Mac liegt.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Ablage
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Ablage")

                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text(libraryRootDisplayPath)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(appState.library.rootURL.path)

                    Spacer(minLength: 4)

                    Button("Ordner w\u{00E4}hlen \u{2026}") { chooseLibraryFolder() }
                        .buttonStyle(.vc(.secondary, .compact))

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([appState.library.rootURL])
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.vc(.quiet, .icon))
                    .help("Im Finder zeigen")
                }

                if !appState.library.isUsingDefaultRoot {
                    Button("Standardordner verwenden") {
                        appState.librarySettings.rootPath = ""
                    }
                    .buttonStyle(.vc(.quiet, .compact))
                }

                if let reason = appState.library.unavailableReason {
                    Text(reason)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Importierte Aufnahmen mitkopieren", isOn: $appState.librarySettings.storeImportedAudio)
                    .toggleStyle(.switch)

                Text("Transkripte liegen als .md-Dateien im Ablage-Ordner und bleiben ohne Griffel lesbar. Wird der Ordner gewechselt, bleiben bisherige Aufnahmen im alten liegen \u{2014} sie lassen sich im Finder her\u{00FC}berziehen.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Braindump-Kontext
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Braindump-Kontext")

                Picker("", selection: $appState.appSettings.braindumpCaptureContext) {
                    ForEach(BraindumpCaptureContext.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(appState.appSettings.braindumpCaptureContext.explanation)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Bleibt lokal auf diesem Mac und geht nie an ein Sprachmodell. Der Fenstertitel braucht die Bedienungshilfen-Freigabe \u{2014} ohne sie wird nur die App notiert.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Tastenkuerzel
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Tastenk\u{00FC}rzel")

                VStack(spacing: 4) {
                    ForEach(WorkflowType.allCases) { type in
                        HStack(spacing: 8) {
                            Text(type.displayName)
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            HotkeyRecorderField(
                                type: type,
                                hotkey: appState.hotkey(for: type),
                                isDefault: appState.hotkey(for: type) == .default(for: type),
                                recordingType: $recordingHotkeyType,
                                onRecord: { recorded in
                                    hotkeyFeedback = nil
                                    switch appState.assignHotkey(recorded, to: type) {
                                    case .assigned:
                                        break
                                    case .assignedWithWarning(let message):
                                        hotkeyFeedback = (message, false)
                                    case .rejected(let message):
                                        hotkeyFeedback = (message, true)
                                    }
                                },
                                onReset: {
                                    hotkeyFeedback = nil
                                    appState.resetHotkey(for: type)
                                },
                                // The global combinations have to let go while
                                // a new one is being read, or an existing
                                // binding swallows the very keystroke needed.
                                onRecordingChange: { isRecording in
                                    if isRecording {
                                        hotkeyFeedback = nil
                                        appState.hotkeyService.suspend()
                                    } else {
                                        appState.hotkeyService.resume()
                                    }
                                }
                            )
                        }
                    }
                }

                if let feedback = hotkeyFeedback {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: feedback.isError ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(feedback.isError ? .red : .orange)
                        Text(feedback.message)
                            .font(.system(size: 10.5))
                            .foregroundStyle(feedback.isError ? .red : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }

                Text("Klick auf ein K\u{00FC}rzel und dr\u{00FC}cke die neue Kombination. Reine Modifier-Akkorde wie fn\u{00A0}+\u{00A0}Shift eignen sich am besten zum Halten \u{2014} sie tippen nichts. Esc bricht die Aufnahme ab.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if appState.hasCustomHotkeys {
                    Button("Alle K\u{00FC}rzel zur\u{00FC}cksetzen") {
                        hotkeyFeedback = nil
                        appState.resetAllHotkeys()
                    }
                    .buttonStyle(.vc(.secondary, .compact))
                }

                // Mode picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modus")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $appState.appSettings.hotkeyMode) {
                        ForEach(HotkeyMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("Aufnahme-Anzeige am Bildschirmrand", isOn: $appState.appSettings.hudEnabled)
                    .toggleStyle(.switch)

                Text("Zeigt bei Hotkey-Aufnahmen ein kleines Statusfenster am unteren Bildschirmrand.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Live-Transkript anzeigen", isOn: $appState.appSettings.liveTranscriptEnabled)
                    .toggleStyle(.switch)

                Text("Zeigt w\u{00E4}hrend der Aufnahme einen vorl\u{00E4}ufigen Text an. Nur mit lokalem Modell (WhisperKit); der endg\u{00FC}ltige Text kommt weiterhin aus der vollst\u{00E4}ndigen Auswertung.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Automatisch bei Stille stoppen", isOn: $appState.appSettings.autoStopOnSilenceEnabled)
                    .toggleStyle(.switch)

                if appState.appSettings.autoStopOnSilenceEnabled {
                    HStack(spacing: 10) {
                        Text("Stille")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Slider(value: $appState.appSettings.autoStopSilenceSeconds, in: 1.0...5.0, step: 0.5)
                        Text(String(format: "%.1f\u{202F}s", appState.appSettings.autoStopSilenceSeconds))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                Text("Beendet die Aufnahme automatisch nach einer Sprechpause \u{2013} erst, nachdem gesprochen wurde.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Griffel+
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Griffel+")

                // Rewrite scope — replaces the retired "Griffel Lokal+"
                // workflow, whose only real difference was a gentler prompt.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bearbeitungsgrad")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $appState.textImprovementSettings.rewriteScope) {
                        ForEach(TextImprovementSettings.RewriteScope.allCases) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(appState.textImprovementSettings.rewriteScope.explanation)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Tone — only reaches the prompt in Lektorat mode.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Schreibstil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $appState.textImprovementSettings.tone) {
                        ForEach(TextImprovementSettings.TextTone.allCases) { tone in
                            Text(tone.displayName).tag(tone)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .disabled(!appState.textImprovementSettings.rewriteScope.usesToneAndContext)
                .opacity(appState.textImprovementSettings.rewriteScope.usesToneAndContext ? 1 : 0.45)

                // The free-text override moved to the Prompts page, where the
                // preset it used to replace is visible and editable itself.
                HStack(spacing: 8) {
                    Text("Prompts")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Button {
                        if let onOpenPrompts {
                            onOpenPrompts()
                        } else {
                            appState.page = .prompts
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Bearbeiten")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .buttonStyle(.vc(.quiet, .compact))
                }

                Text("Wortlaut der Anweisungen f\u{00FC}r Korrektur, Lektorat, Auswahl bearbeiten und Braindump \u{2014} inklusive eines Zusatzes nur f\u{00FC}rs lokale Modell.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Context
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kontext")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("z.B. \"E-Mails im Bereich Unternehmensberatung\"", text: $appState.textImprovementSettings.context)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
                .disabled(!appState.textImprovementSettings.rewriteScope.usesToneAndContext)
                .opacity(appState.textImprovementSettings.rewriteScope.usesToneAndContext ? 1 : 0.45)

                Text("Mit OpenAI API Key l\u{00E4}uft die \u{00DC}berarbeitung online. Im Sicheren Lokalen Modus \u{00FC}bernimmt das lokale Sprachmodell.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: App-Profile
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "App-Profile")

                Toggle("Format an Ziel-App anpassen", isOn: $appState.formatProfileSettings.enabled)
                    .toggleStyle(.switch)

                Text("Formatiert Transkripte passend zur App, in die eingef\u{00FC}gt wird \u{2014} z.B. E-Mail-Stil in Outlook, knapper Stil im Terminal. Nur online, im lokalen Modus pausiert.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if appState.formatProfileSettings.enabled {
                    VStack(spacing: 6) {
                        ForEach($appState.formatProfileSettings.rules) { $rule in
                            HStack(spacing: 6) {
                                Text(appDisplayName(for: rule.bundleIdentifier))
                                    .font(.system(size: 10.5))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .help(rule.bundleIdentifier)

                                Picker("", selection: $rule.profile) {
                                    ForEach(FormatProfile.allCases) { profile in
                                        Text(profile.displayName).tag(profile)
                                    }
                                }
                                .labelsHidden()
                                .controlSize(.mini)
                                .frame(width: 128)

                                Button {
                                    appState.formatProfileSettings.rules.removeAll { $0.id == rule.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.vc(.quiet, .icon))
                                .help("Regel entfernen")
                            }
                        }
                    }

                    Menu {
                        ForEach(addableRunningApps, id: \.bundleIdentifier) { app in
                            Button(app.name) {
                                appState.formatProfileSettings.rules.append(
                                    FormatRule(bundleIdentifier: app.bundleIdentifier, profile: .chat)
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                            Text("App hinzuf\u{00FC}gen")
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.secondary)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }

            // MARK: Wörterbuch
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "W\u{00F6}rterbuch")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sprache")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $appState.transcriptionSettings.languageMode) {
                        ForEach(LanguageMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if appState.transcriptionSettings.languageMode == .autoDenglish {
                        Text("Erkennt gemischtes Deutsch/Englisch automatisch und beh\u{00E4}lt englische Begriffe bei.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Toggle("F\u{00FC}llw\u{00F6}rter entfernen", isOn: $appState.transcriptionSettings.removeFillerWords)
                    .toggleStyle(.switch)

                Text("Entfernt z.B. \"\u{00E4}hm\", \"\u{00E4}h\", \"hm\" automatisch aus der Transkription.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Eigene Begriffe")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if !appState.glossarySettings.entries.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(appState.glossarySettings.entries) { entry in
                            GlassChip {
                                Button {
                                    beginEditingGlossaryEntry(entry)
                                } label: {
                                    Text(entry.definition.isEmpty ? entry.term : "\(entry.term) \u{00B7} \(entry.definition)")
                                        .font(.system(size: 10.5))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.chip)

                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        appState.glossarySettings.entries.removeAll { $0.id == entry.id }
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.chip)
                            }
                        }
                    }
                }

                if appState.appSettings.phraseDetectionEnabled && !glossarySuggestions.isEmpty {
                    Text("Vorschl\u{00E4}ge aus deinen Diktaten")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 5) {
                        ForEach(glossarySuggestions) { suggestion in
                            GlassChip {
                                Button {
                                    acceptGlossarySuggestion(suggestion.phrase)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.blue.opacity(0.7))
                                        Text(suggestion.phrase)
                                            .font(.system(size: 10.5))
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.chip)

                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        PhraseStore.shared.ignore(suggestion.phrase)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.chip)
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("Begriff", text: $newGlossaryTerm)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit { addGlossaryEntry() }

                    TextField("Bedeutung (optional)", text: $newGlossaryDefinition)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit { addGlossaryEntry() }

                    Button { addGlossaryEntry() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.vc(.secondary, .icon))
                    .disabled(newGlossaryTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Begriff hinzuf\u{00FC}gen")
                }

                Text("Begriffe flie\u{00DF}en in Transkription und Umformulierung ein. Chip antippen zum Bearbeiten.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("H\u{00E4}ufige Phrasen erkennen", isOn: $appState.appSettings.phraseDetectionEnabled)
                    .toggleStyle(.switch)

                Text("Erkennt lokal wiederkehrende Formulierungen f\u{00FC}r Statistik und Vorschl\u{00E4}ge. Es werden nur Z\u{00E4}hlwerte gespeichert, keine Texte.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .padding(16)
    }

    /// Home-relative when it sits under the user's home folder, so the row
    /// shows "~/Dropbox/Notizen" instead of a full path nobody reads.
    private var libraryRootDisplayPath: String {
        let path = appState.library.rootURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Ordner w\u{00E4}hlen"
        panel.message = "Wo sollen Aufnahmen und Transkripte liegen?"
        panel.directoryURL = appState.library.rootURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.librarySettings.rootPath = url.path
    }

    private var glossarySuggestions: [TrackedPhrase] {
        PhraseStore.shared.glossarySuggestions(
            existingTerms: appState.glossarySettings.entries.map(\.term)
        )
    }

    private func acceptGlossarySuggestion(_ phrase: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            let exists = appState.glossarySettings.entries.contains {
                $0.term.caseInsensitiveCompare(phrase) == .orderedSame
            }
            if !exists {
                appState.glossarySettings.entries.append(GlossaryEntry(term: phrase))
            }
        }
    }

    private func addGlossaryEntry() {
        let term = newGlossaryTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        let definition = newGlossaryDefinition.trimmingCharacters(in: .whitespaces)

        withAnimation(.easeOut(duration: 0.15)) {
            if let index = appState.glossarySettings.entries.firstIndex(
                where: { $0.term.caseInsensitiveCompare(term) == .orderedSame }
            ) {
                appState.glossarySettings.entries[index].definition = definition
            } else {
                appState.glossarySettings.entries.append(GlossaryEntry(term: term, definition: definition))
            }
        }
        newGlossaryTerm = ""
        newGlossaryDefinition = ""
    }

    private func beginEditingGlossaryEntry(_ entry: GlossaryEntry) {
        newGlossaryTerm = entry.term
        newGlossaryDefinition = entry.definition
        withAnimation(.easeOut(duration: 0.15)) {
            appState.glossarySettings.entries.removeAll { $0.id == entry.id }
        }
    }

    private func appDisplayName(for bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private var addableRunningApps: [(name: String, bundleIdentifier: String)] {
        let existing = Set(appState.formatProfileSettings.rules.map { $0.bundleIdentifier.lowercased() })
        let ownBundleID = Bundle.main.bundleIdentifier?.lowercased()

        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (name: String, bundleIdentifier: String)? in
                guard let bundleID = app.bundleIdentifier,
                      bundleID.lowercased() != ownBundleID,
                      !existing.contains(bundleID.lowercased()) else {
                    return nil
                }
                return (name: app.localizedName ?? bundleID, bundleIdentifier: bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Flow Layout (for term tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
