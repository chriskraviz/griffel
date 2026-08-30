import SwiftUI

struct BraindumpView: View {
    @Bindable var appState: AppState
    /// Whether entries can be filed into the library from here. Only the
    /// window offers it — the 340pt popover has no room for a fourth button in
    /// that row, and no folder selection to file into.
    var allowsFiling: Bool = false
    /// Topic folder a filed entry lands in; nil files it at the library root.
    var filingFolderName: String? = nil

    private let store = BraindumpStore.shared

    @State private var selection: Set<UUID> = []
    @State private var isProcessing = false
    @State private var processedResult: String?
    /// The entries the open result was built from, frozen at the start of the
    /// run. A thought spoken by hotkey while the model was working is not part
    /// of the result and must survive the filing that follows.
    @State private var pendingIDs: Set<UUID> = []
    @State private var isFilingResult = false
    @State private var processErrorText: String?
    @State private var didCopyResult = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// Absolute on purpose. `dayFormatter` formats relatively, and a note
    /// called „Braindump — Heute" is wrong by the next morning. The template
    /// rather than `dateStyle`/`timeStyle`: those join the two halves with the
    /// UI language's word („at"), which lands next to a German title.
    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("ddMMyyyy HHmm")
        return formatter
    }()

    private static let resultAnchorID = "braindump-result"

    private var canUseLLM: Bool {
        appState.resolvedLLMBackend != nil
    }

    private var processingRunsLocally: Bool {
        appState.resolvedLLMBackend?.isLocal == true
    }

    private var targetEntries: [BraindumpEntry] {
        let all = store.entries
        let targets = selection.isEmpty ? all : all.filter { selection.contains($0.id) }
        return targets.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    recordCard

                    if let processedResult {
                        resultCard(processedResult)
                            .id(Self.resultAnchorID)
                    }

                    if let processErrorText {
                        Text(processErrorText)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if store.entries.isEmpty {
                        emptyState
                    } else {
                        inboxHeader
                        entriesList
                    }
                }
                .padding(16)
            }
            // The button sits below the card it fills. Without this the result
            // appears outside the visible area of the 340pt popover and the run
            // looks like it did nothing.
            .onChange(of: processedResult) { _, newValue in
                guard newValue != nil else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.resultAnchorID, anchor: .top)
                }
            }
        }
    }

    // MARK: - Record

    private var recordCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Gedanken einfach aussprechen")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("Auch von \u{00FC}berall per \(appState.hotkeyLabel(for: .braindump)).")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                appState.startWorkflow(.braindump, source: .manual)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Aufnehmen")
                }
            }
            .buttonStyle(.vc(.primary, tint: WorkflowType.braindump.accentUIColor))
            .disabled(!appState.isWorkflowAvailable(.braindump))
        }
        .padding(10)
        .glassCard()
    }

    // MARK: - Inbox

    private var entryCountLabel: String {
        let count = store.entries.count
        return count == 1 ? "1 Eintrag" : "\(count) Eintr\u{00E4}ge"
    }

    private var inboxHeader: some View {
        HStack(spacing: 8) {
            Text(selection.isEmpty
                 ? entryCountLabel
                 : "\(selection.count) ausgew\u{00E4}hlt")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            Spacer()

            if allowsFiling, !selection.isEmpty {
                Button("Ablegen") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        _ = appState.fileBraindumpEntries(selection, intoFolder: filingFolderName)
                        selection = []
                    }
                }
                .buttonStyle(.vc(.secondary, .compact))
                .help(filingHelpText)
            }

            if !selection.isEmpty {
                Button("L\u{00F6}schen") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        store.delete(selection)
                        selection = []
                    }
                }
                .buttonStyle(.destructive(.compact))
            }

            Button {
                processEntries()
            } label: {
                HStack(spacing: 4) {
                    if isProcessing {
                        ButtonSpinner()
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    Text(selection.isEmpty ? "Alle ordnen" : "Ordnen")
                }
            }
            .buttonStyle(.vc(.secondary, .compact))
            .disabled(isProcessing || !canUseLLM || store.entries.isEmpty)
            .help("Fasst die Gedanken zu Zusammenfassung, Aufgaben und Ideen zusammen.")
        }
    }

    /// The button label stays short; the destination lives in the tooltip, so
    /// a long topic name can never push the row past its 380pt column.
    private var filingHelpText: String {
        guard let filingFolderName else { return "Als Transkript in die Ablage verschieben" }
        return "Nach \u{201E}\(filingFolderName)\u{201C} verschieben"
    }

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !canUseLLM {
                Text(appState.appSettings.secureLocalModeEnabled
                     ? "Ordnen braucht im lokalen Modus das lokale Sprachmodell. Die Aufnahme in den Eingang funktioniert weiter."
                     : "F\u{00FC}r das Ordnen wird ein OpenAI API Key ben\u{00F6}tigt.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(groupedEntries, id: \.day) { group in
                Text(Self.dayFormatter.string(from: group.day))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)

                ForEach(group.entries) { entry in
                    entryRow(entry)
                }
            }

            Text(processingRunsLocally
                 ? "Ordnen l\u{00E4}uft lokal auf deinem Mac. Der Eingang bleibt ebenfalls lokal."
                 : "Ordnen sendet die Gedanken an OpenAI. Der Eingang selbst bleibt lokal auf deinem Mac.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func entryRow(_ entry: BraindumpEntry) -> some View {
        let isSelected = selection.contains(entry.id)
        return Button {
            if isSelected {
                selection.remove(entry.id)
            } else {
                selection.insert(entry.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.blue) : AnyShapeStyle(.quaternary))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.text)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)

                    HStack(spacing: 5) {
                        Text(Self.timeFormatter.string(from: entry.createdAt))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)

                        if let appName = entry.captureContext?.appName {
                            // Only the app name is short and safe enough for a
                            // row; a window title can be an email subject, so
                            // it stays in the tooltip.
                            Text("\u{00B7} in \(appName)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .help(entry.captureContext?.displayText.map { "aufgenommen in \($0)" } ?? appName)
                        }

                    }
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .glassCard(radius: DS.radiusS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("Der Eingang ist leer")
                .font(.system(size: 12, weight: .semibold))
            Text("Halte \(appState.hotkeyLabel(for: .braindump)) und sprich einen Gedanken aus \u{2014} er landet hier.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 12)
        .glassCard()
    }

    // MARK: - Result

    private func resultCard(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ergebnis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    processedResult = nil
                    pendingIDs = []
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.vc(.quiet, .icon))
                .help("Ergebnis schlie\u{00DF}en \u{2014} die Gedanken bleiben im Eingang")
            }

            BraindumpResultText(markdown: result)

            HStack(spacing: 6) {
                Spacer()

                Button {
                    appState.copyToClipboard(result)
                    didCopyResult = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        didCopyResult = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: didCopyResult ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                        Text(didCopyResult ? "Kopiert" : "Kopieren")
                    }
                }
                .buttonStyle(.vc(.secondary, .compact, tint: didCopyResult ? .green : nil))

                Button {
                    fileResult(result)
                } label: {
                    HStack(spacing: 4) {
                        if isFilingResult {
                            ButtonSpinner()
                        } else {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        Text("In Ablage speichern")
                    }
                }
                .buttonStyle(.vc(.primary, .compact))
                .disabled(isFilingResult)
                .help(resultFilingHelpText)
            }
        }
        .padding(10)
        .glassCard()
    }

    /// The destination lives in the tooltip for the same reason „Ablegen"'s
    /// does: a long topic name must not widen the row.
    private var resultFilingHelpText: String {
        guard let filingFolderName else {
            return "Als Notiz in die Ablage legen \u{2014} die geordneten Gedanken verlassen den Eingang"
        }
        return "Als Notiz nach \u{201E}\(filingFolderName)\u{201C} legen \u{2014} die geordneten Gedanken verlassen den Eingang"
    }

    /// Filing is the decision that empties the inbox. Copying is not: the
    /// clipboard is overwritten by the next Cmd+C, and an emptied inbox plus an
    /// overwritten clipboard would be a real loss.
    private func fileResult(_ result: String) {
        guard !isFilingResult else { return }
        isFilingResult = true
        processErrorText = nil
        do {
            try appState.fileBraindumpResult(
                result,
                title: "Braindump \u{2014} \(Self.titleFormatter.string(from: Date()))",
                intoFolder: filingFolderName
            )
            withAnimation(.easeOut(duration: 0.15)) {
                BraindumpStore.shared.delete(pendingIDs)
                pendingIDs = []
                processedResult = nil
            }
        } catch {
            // The note was not written, so the entries stay. Never half-tidy.
            processErrorText = error.localizedDescription
        }
        isFilingResult = false
    }

    // MARK: - Processing

    private func processEntries() {
        let targets = targetEntries
        guard !targets.isEmpty, !isProcessing,
              let backend = appState.resolvedLLMBackend else { return }

        isProcessing = true
        processedResult = nil
        pendingIDs = []
        processErrorText = nil
        didCopyResult = false

        let lines = targets.map { entry in
            "[\(Self.dayFormatter.string(from: entry.createdAt)), \(Self.timeFormatter.string(from: entry.createdAt))] \(entry.text)"
        }
        let ids = Set(targets.map(\.id))
        let extras = appState.llmExtraInstructions(for: backend)

        Task {
            do {
                let result = try await TextGenerationService.organizeBraindump(
                    entries: lines,
                    prompts: appState.promptSettings,
                    extraInstructions: extras,
                    backend: backend
                )
                processedResult = result
                pendingIDs = ids
                selection = []
            } catch {
                processErrorText = error.localizedDescription
            }
            isProcessing = false
        }
    }

    private var groupedEntries: [(day: Date, entries: [BraindumpEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.entries) { calendar.startOfDay(for: $0.createdAt) }
        return grouped
            .map { (day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }
}
