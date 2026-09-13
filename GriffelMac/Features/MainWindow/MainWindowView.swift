import AppKit
import SwiftUI
import UniformTypeIdentifiers

/*
 THESIS: Griffel is a quiet native proof desk where captured speech becomes owned, legible work; it refuses the category’s usual stack of colorful dashboard cards.
 OWN-WORLD: Warm uncoated paper, graphite ink, hairline rules, editorial serif transcripts, compact system-sans controls, proof-blue selections, recording red, and one restrained marker-green highlight. Native macOS chrome frames planar ledger surfaces rather than floating glass panels.
 STORY: Capture without breaking focus → find every thought in one chronological ledger → review the transcript beside its provenance → file, copy, or continue working.
 FIRST VIEWPORT: A slim live capture ribbon sits beneath native chrome; a narrow navigation rail leads into Today’s mixed ledger, with the selected record opening as a generous proof sheet on the right.
 FORM: position/list composition; seed 4f0348d6.
 FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
 */

private enum WorkspaceRoute: String, CaseIterable, Identifiable {
    case today, library, braindump, stats

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Heute"
        case .library: return "Ablage"
        case .braindump: return "Braindump"
        case .stats: return "Statistik"
        }
    }
    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .library: return "tray.full"
        case .braindump: return "brain.head.profile"
        case .stats: return "chart.bar.xaxis"
        }
    }
}

private enum LedgerSelection: Hashable {
    case library(UUID)
    case braindump(UUID)
}

private struct LedgerRecord: Identifiable {
    enum Content {
        case library(LibraryItem)
        case braindump(BraindumpEntry)
    }

    let content: Content
    var id: String {
        switch content {
        case .library(let item): return "library-\(item.id)"
        case .braindump(let entry): return "braindump-\(entry.id)"
        }
    }
    var selection: LedgerSelection {
        switch content {
        case .library(let item): return .library(item.id)
        case .braindump(let entry): return .braindump(entry.id)
        }
    }
    var date: Date {
        switch content {
        case .library(let item): return item.createdAt
        case .braindump(let entry): return entry.createdAt
        }
    }
}

struct MainWindowView: View {
    @Bindable var appState: AppState

    static let defaultSize = CGSize(width: 1220, height: 760)
    static let minimumSize = CGSize(width: 1000, height: 600)

    @State private var filter = LibraryFilter()
    @State private var route: WorkspaceRoute = .today
    @State private var selection: LedgerSelection?
    @State private var isDropTargeted = false
    @State private var rejectedFileNames: [String] = []
    @State private var isTagPopoverShown = false

    private var library: LibraryStore { appState.library }

    var body: some View {
        VStack(spacing: 0) {
            windowHeader
            captureRibbon

            switch appState.windowSection {
            case .library:
                workspace
            case .settings:
                WideSettingsView(appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .proofPaper(textureOpacity: 0.08)
            }
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .background(ProofDesk.paper)
        .tint(ProofDesk.blue)
        .dropDestination(for: URL.self) { urls, _ in
            handleImport(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                Rectangle()
                    .strokeBorder(ProofDesk.blue, lineWidth: 2)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.14), value: isDropTargeted)
        .preferredColorScheme(.light)
        .onAppear {
            library.refresh()
            resolveSelection()
        }
        .onChange(of: recordIDs) { _, _ in resolveSelection() }
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            workspaceSidebar.frame(width: 206)
            Rectangle().fill(ProofDesk.rule).frame(width: 1)

            Group {
                switch route {
                case .today, .library:
                    ledgerWorkspace
                case .braindump:
                    BraindumpView(
                        appState: appState,
                        showsCaptureHeader: false,
                        allowsFiling: true,
                        filingFolderName: filter.scope.folderName
                    )
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .proofPaper()
                case .stats:
                    StatsView()
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .proofPaper()
                }
            }
        }
    }

    // MARK: - Native shell

    private var windowHeader: some View {
        HStack(spacing: 10) {
            Text("GRIFFEL")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(ProofDesk.ink)
            Text("PROOF DESK")
                .font(.system(size: 9, weight: .medium))
                .tracking(1.1)
                .foregroundStyle(.tertiary)
            Spacer()
            Label(engineLabel, systemImage: appState.appSettings.secureLocalModeEnabled ? "lock.fill" : "network")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Button {
                appState.windowSection = appState.windowSection == .settings ? .library : .settings
            } label: {
                Label(appState.windowSection == .settings ? "Arbeitsplatz" : "Einstellungen",
                      systemImage: appState.windowSection == .settings ? "rectangle.split.3x1" : "gearshape")
            }
            .buttonStyle(.vc(.quiet, .compact))
        }
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(ProofDesk.rule).frame(height: 1) }
    }

    @ViewBuilder
    private var captureRibbon: some View {
        if let workflow = appState.activeWorkflow, workflow.phase.isActive {
            WindowActivityBar(workflow: workflow) { appState.stopCurrentWorkflow() }
        } else {
            HStack(spacing: 11) {
                Circle().fill(ProofDesk.red).frame(width: 7, height: 7)
                Text(idleCaptureReadinessLabel)
                    .font(ProofDesk.eyebrow)
                    .tracking(0.9)
                Text("Halte \(appState.hotkeyLabel(for: idleCaptureWorkflow)) – sprich – lass los.")
                    .font(ProofDesk.utility)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { appState.startWorkflow(idleCaptureWorkflow) } label: {
                    Label(idleCaptureButtonLabel, systemImage: "mic.fill")
                }
                .buttonStyle(.vc(
                    .primary,
                    .compact,
                    tint: ProofDesk.red,
                    foreground: ProofDesk.onWarmAccent
                ))
                .disabled(!appState.isWorkflowAvailable(idleCaptureWorkflow))
            }
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Color.white.opacity(0.28))
        }
    }

    private var idleCaptureWorkflow: WorkflowType {
        appState.windowSection == .library && route == .braindump
            ? .braindump
            : .transcription
    }

    private var idleCaptureReadinessLabel: String {
        idleCaptureWorkflow == .braindump
            ? "BEREIT FÜR BRAINDUMP"
            : "BEREIT ZUM DIKTIEREN"
    }

    private var idleCaptureButtonLabel: String {
        idleCaptureWorkflow == .braindump ? "Gedanke aufnehmen" : "Aufnehmen"
    }

    private var engineLabel: String {
        appState.appSettings.secureLocalModeEnabled
            ? "Lokal · \(appState.selectedLocalModelDisplayName)"
            : "Online · Whisper"
    }

    // MARK: - Sidebar

    private var workspaceSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                ForEach(WorkspaceRoute.allCases) { candidate in
                    Button {
                        route = candidate
                        if candidate == .today { filter.scope = .all }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: candidate.icon)
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 15)
                            Text(candidate.title)
                                .font(.system(size: 12, weight: route == candidate ? .semibold : .regular))
                            Spacer()
                            if candidate == .braindump, BraindumpStore.shared.unprocessedCount > 0 {
                                Text("\(BraindumpStore.shared.unprocessedCount)")
                                    .font(.system(size: 9.5).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(route == candidate ? ProofDesk.selection : .clear)
                        .overlay(alignment: .leading) {
                            if route == candidate { Rectangle().fill(ProofDesk.blue).frame(width: 2) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            Rectangle().fill(ProofDesk.rule).frame(height: 1)
            LibrarySidebarView(
                appState: appState,
                filter: filter,
                isActive: route == .library,
                onScopeSelected: { route = .library }
            )
        }
        .background(ProofDesk.sidebar)
    }

    // MARK: - Ledger

    private var ledgerWorkspace: some View {
        HStack(spacing: 0) {
            ledger.frame(width: 390)
            Rectangle().fill(ProofDesk.rule).frame(width: 1)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var ledger: some View {
        VStack(spacing: 0) {
            ledgerHeader
            Rectangle().fill(ProofDesk.rule).frame(height: 1)
            ledgerNotices
            if records.isEmpty {
                ledgerEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(records) { record in
                            ledgerRow(record)
                            Rectangle().fill(ProofDesk.rule).frame(height: 1)
                        }
                    }
                }
            }
        }
        .background(ProofDesk.ledger)
    }

    @ViewBuilder
    private var ledgerNotices: some View {
        if let reason = library.unavailableReason {
            ledgerNotice(
                title: "Ablage nicht verfügbar",
                message: reason,
                icon: "externaldrive.badge.exclamationmark",
                actionTitle: "Erneut prüfen",
                onAction: { library.refresh() }
            )
        }

        if let errorText = library.lastErrorText {
            ledgerNotice(
                title: "Änderung nicht gespeichert",
                message: errorText,
                icon: "exclamationmark.triangle.fill",
                onDismiss: { library.clearLastError() }
            )
        }

        if let errorText = library.lastImportErrorText {
            ledgerNotice(
                title: "Import fehlgeschlagen",
                message: errorText,
                icon: "waveform.badge.exclamationmark",
                actionTitle: "Erneut wählen",
                onAction: {
                    library.lastImportErrorText = nil
                    chooseFiles()
                },
                onDismiss: { library.lastImportErrorText = nil }
            )
        }

        if !rejectedFileNames.isEmpty {
            ledgerNotice(
                title: "Nicht importiert",
                message: "Keine Audiodatei: \(rejectedFileNames.joined(separator: ", "))",
                icon: "doc.badge.ellipsis",
                onDismiss: { rejectedFileNames = [] }
            )
        }
    }

    private func ledgerNotice(
        title: String,
        message: String,
        icon: String,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(.orange)
                    .frame(width: 14)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(ProofDesk.metadataInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let actionTitle, let onAction {
                    Button(actionTitle, action: onAction)
                        .buttonStyle(.vc(.secondary, .compact, tint: .orange))
                }
                if let onDismiss {
                    Button(action: onDismiss) { Image(systemName: "xmark") }
                        .buttonStyle(.vc(.quiet, .icon))
                        .accessibilityLabel("Hinweis schließen")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.orange.opacity(0.08))
            Rectangle().fill(ProofDesk.rule).frame(height: 1)
        }
    }

    private var ledgerHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(route == .today ? "HEUTE" : "ABLAGE")
                        .font(ProofDesk.eyebrow)
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(route == .today ? "Der Tageslauf" : scopeTitle)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                }
                Spacer()
                Button { chooseFiles() } label: { Image(systemName: "plus") }
                    .buttonStyle(.vc(.quiet, .icon))
                    .accessibilityLabel("Audio importieren")
                    .help("Audio importieren")
            }
            HStack(spacing: 8) {
                SearchField(
                    text: $filter.query,
                    placeholder: route == .today ? "Im Tageslauf suchen" : "In Transkripten suchen"
                )
                Menu {
                    if library.tagCounts.isEmpty {
                        Text("Noch keine Tags")
                    } else {
                        ForEach(library.tagCounts, id: \.tag) { entry in
                            Button {
                                filter.toggleTag(entry.tag)
                            } label: {
                                Label("\(entry.tag) (\(entry.count))",
                                      systemImage: filter.isTagActive(entry.tag) ? "checkmark" : "tag")
                            }
                        }
                        if !filter.selectedTags.isEmpty {
                            Divider()
                            Button("Tag-Filter löschen") { filter.selectedTags = [] }
                        }
                    }
                } label: { Image(systemName: "tag") }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.vc(.secondary, .icon))
                .accessibilityLabel("Aufzeichnungen nach Tags filtern")
                .accessibilityValue(tagFilterAccessibilityValue)
                .help("Aufzeichnungen nach Tags filtern")
            }
            if filter.isFiltering {
                HStack(spacing: 8) {
                    if !activeTagNames.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(activeTagNames, id: \.self) { tag in
                                    TagChip(
                                        name: tag,
                                        isActive: true,
                                        onRemove: { filter.toggleTag(tag) }
                                    )
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Text(records.count == 1 ? "1 Treffer" : "\(records.count) Treffer")
                        .font(.system(size: 10))
                        .foregroundStyle(ProofDesk.metadataInk)
                        .fixedSize()
                    Button("Zurücksetzen") { filter.reset() }
                        .buttonStyle(.vc(.quiet, .compact))
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.22))
    }

    private func ledgerRow(_ record: LedgerRecord) -> some View {
        let isSelected = selection == record.selection
        return Button { selection = record.selection } label: {
            HStack(alignment: .top, spacing: 11) {
                Text(Self.timeFormatter.string(from: record.date))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(ProofDesk.metadataInk)
                    .frame(width: 38, alignment: .leading)
                Rectangle().fill(recordAccent(record)).frame(width: 2, height: 42)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: recordIcon(record))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(recordAccent(record))
                        Text(recordKind(record).uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.65)
                            .foregroundStyle(ProofDesk.metadataInk)
                        Spacer()
                        ledgerStatus(record)
                    }
                    Text(recordTitle(record))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(ProofDesk.ink)
                        .lineLimit(1)
                    Text(recordExcerpt(record))
                        .font(.system(size: 11.5, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? ProofDesk.selection : .clear)
            .overlay(alignment: .trailing) {
                if isSelected { Rectangle().fill(ProofDesk.blue).frame(width: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recordAccessibilityLabel(record))
        .accessibilityValue(isSelected ? "Ausgewählt" : recordStatusText(record))
        .accessibilityHint("Öffnet den Eintrag im Prüfblatt")
    }

    private var ledgerEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(filter.isFiltering ? "KEIN TREFFER" : "NOCH KEIN EINTRAG")
                .font(ProofDesk.eyebrow)
                .tracking(1)
                .foregroundStyle(.secondary)
            Text(filter.isFiltering ? "Nichts passt zu diesem Filter." : "Sprich den ersten Gedanken des Tages.")
                .font(.system(size: 22, weight: .medium, design: .serif))
            Text(filter.isFiltering
                 ? "Ändere die Suche oder setze alle Filter zurück. Deine Einträge bleiben unverändert."
                 : "Diktate, Braindumps und importierte Aufnahmen erscheinen hier in einem gemeinsamen Tageslauf.")
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if filter.isFiltering {
                Button("Filter zurücksetzen") { filter.reset() }
                    .buttonStyle(.vc(.primary, tint: ProofDesk.blue))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Proof sheet

    @ViewBuilder
    private var detail: some View {
        if let selection {
            switch selection {
            case .library(let id):
                if let item = library.item(id: id) { libraryDetail(item) } else { noSelection }
            case .braindump(let id):
                if let entry = BraindumpStore.shared.entries.first(where: { $0.id == id }) {
                    braindumpDetail(entry)
                } else { noSelection }
            }
        } else { noSelection }
    }

    private func libraryDetail(_ item: LibraryItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                proofMasthead(kind: item.source.displayName, date: item.createdAt, accent: sourceAccent(item.source))
                Text(item.title)
                    .font(ProofDesk.editorialTitle)
                    .foregroundStyle(ProofDesk.ink)
                    .textSelection(.enabled)
                    .padding(.top, 28)

                HStack(spacing: 7) {
                    if let appName = item.capture?.appName { Label(appName, systemImage: "macwindow") }
                    if let folder = item.folderName { Label(folder, systemImage: "folder") }
                    if let engine = item.engineLabel {
                        Label(engine, systemImage: engine == "lokal" ? "lock.fill" : "network")
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

                Rectangle().fill(ProofDesk.ink.opacity(0.72)).frame(height: 1).padding(.vertical, 22)
                HStack(alignment: .top, spacing: 30) {
                    Group {
                        if item.transcript.isEmpty {
                            pendingTranscript(item)
                        } else {
                            VStack(alignment: .leading, spacing: 18) {
                                if let failure = appState.transcriptionQueue
                                    .job(forItem: item.id)?.status.failureText {
                                    transcriptionFailure(failure, item: item)
                                }
                                Text(item.transcript)
                                    .font(ProofDesk.editorialBody)
                                    .lineSpacing(6)
                                    .foregroundStyle(ProofDesk.ink.opacity(0.92))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    marginNotes(item).frame(width: 145, alignment: .leading)
                }

                HStack(spacing: 6) {
                    if !item.tags.isEmpty {
                        ForEach(item.tags, id: \.self) { tag in
                            Text(tag.uppercased())
                                .font(.system(size: 8.5, weight: .semibold))
                                .tracking(0.6)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(ProofDesk.marker.opacity(0.42))
                        }
                    }
                    Button {
                        isTagPopoverShown = true
                    } label: {
                        Label(item.tags.isEmpty ? "Tag hinzufügen" : "Bearbeiten", systemImage: "plus")
                    }
                    .buttonStyle(.vc(.quiet, .compact))
                    .popover(isPresented: $isTagPopoverShown, arrowEdge: .bottom) {
                        TagEditorPopover(
                            item: item,
                            existingTags: library.tagCounts,
                            onAdd: { library.addTag($0, toItemID: item.id) },
                            onRemove: { library.removeTag($0, fromItemID: item.id) }
                        )
                    }
                }
                .padding(.top, 28)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 38)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom) { proofActions(item) }
        .proofPaper()
    }

    private func proofMasthead(kind: String, date: Date, accent: Color) -> some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(kind.uppercased()).font(ProofDesk.eyebrow).tracking(1.1)
            }
            Spacer()
            Text(Self.fullDateFormatter.string(from: date).uppercased())
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(ProofDesk.metadataInk)
        }
    }

    private func pendingTranscript(_ item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let job = appState.transcriptionQueue.job(forItem: item.id) {
                if let failure = job.status.failureText {
                    transcriptionFailure(failure, item: item)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("Transkription läuft")
                        Text(job.status.isQueued
                             ? "Die Aufnahme wartet auf die Transkription …"
                             : "Das Transkript wird erstellt …")
                    }
                }
            } else {
                Text("Diese Aufnahme hat noch kein Transkript.")
                if item.hasAudio, !item.audioIsMissing, appState.canImportAudio {
                    Button("Jetzt transkribieren") { appState.retranscribe(item) }
                        .buttonStyle(.vc(.primary, tint: ProofDesk.blue))
                }
            }
        }
        .font(.system(size: 13, design: .serif))
        .foregroundStyle(.secondary)
    }

    private func transcriptionFailure(_ message: String, item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Verarbeitung nicht abgeschlossen", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(ProofDesk.metadataInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Erneut versuchen") { appState.retranscribe(item) }
                    .buttonStyle(.vc(.primary, .compact, tint: ProofDesk.blue))
                    .disabled(!appState.canImportAudio)
                Button("Meldung ausblenden") {
                    appState.transcriptionQueue.removeJob(forItem: item.id)
                }
                .buttonStyle(.vc(.quiet, .compact))
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
    }

    private func marginNotes(_ item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("RANDNOTIZ").font(ProofDesk.eyebrow).tracking(0.8).foregroundStyle(ProofDesk.blue)
            if let context = item.capture?.displayText {
                Text("Aufgenommen in \(context).")
                    .font(.system(size: 10.5, design: .serif))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Ohne App-Kontext aufgenommen.")
                    .font(.system(size: 10.5, design: .serif))
                    .foregroundStyle(.secondary)
            }
            if let duration = item.audioDuration {
                Text("AUFNAHME  \(LibraryRowView.durationLabel(duration))")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(ProofDesk.metadataInk)
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) { Rectangle().fill(ProofDesk.blue.opacity(0.45)).frame(width: 1) }
    }

    private func proofActions(_ item: LibraryItem) -> some View {
        HStack(spacing: 8) {
            Button { appState.copyToClipboard(item.transcript) } label: {
                Label("Kopieren", systemImage: "doc.on.doc")
            }
            .buttonStyle(.vc(.primary, .compact, tint: ProofDesk.blue))
            .disabled(item.transcript.isEmpty)

            if let audioURL = library.audioURL(for: item), !item.audioIsMissing {
                Button { NSWorkspace.shared.open(audioURL) } label: {
                    Label("Im Player öffnen", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.vc(.secondary, .compact))
                .help("Öffnet die Aufnahme im Standardplayer")
                Text(item.audioDuration.map(LibraryRowView.durationLabel) ?? "Audio")
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(ProofDesk.metadataInk)
            }
            Menu("Ablegen") {
                Button("Ohne Thema") { library.move(itemID: item.id, toFolder: nil) }
                Divider()
                ForEach(library.folderNames, id: \.self) { folder in
                    Button(folder) { library.move(itemID: item.id, toFolder: folder) }
                }
            }
            .menuStyle(.button)
            .controlSize(.small)
            Spacer()
            Button {
                let url = library.audioURL(for: item) ?? library.sidecarURL(for: item)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: { Image(systemName: "folder") }
            .buttonStyle(.vc(.quiet, .icon))
            .accessibilityLabel("Im Finder zeigen")
            .help("Im Finder zeigen")
            Button {
                library.delete(itemID: item.id)
                selection = nil
            } label: { Image(systemName: "trash") }
            .buttonStyle(.destructive(.icon))
            .accessibilityLabel("Aufnahme in den Papierkorb legen")
            .help("In den Papierkorb legen")
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(ProofDesk.rule).frame(height: 1) }
    }

    private func braindumpDetail(_ entry: BraindumpEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    proofMasthead(kind: "Braindump", date: entry.createdAt, accent: ProofDesk.marker)
                    Text("Unsortierter Gedanke").font(ProofDesk.editorialTitle)
                    Rectangle().fill(ProofDesk.ink.opacity(0.72)).frame(height: 1)
                    Text(entry.text).font(ProofDesk.editorialBody).lineSpacing(6).textSelection(.enabled)
                    if let context = entry.captureContext?.displayText {
                        Text("AUFGENOMMEN IN  \(context.uppercased())")
                            .font(ProofDesk.eyebrow).tracking(0.7).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(38)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            HStack {
                Button("Braindump ordnen") { route = .braindump }
                    .buttonStyle(.vc(
                        .primary,
                        .compact,
                        tint: ProofDesk.marker,
                        foreground: ProofDesk.onWarmAccent
                    ))
                Button("Kopieren") { appState.copyToClipboard(entry.text) }
                    .buttonStyle(.vc(.secondary, .compact))
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(.bar)
            .overlay(alignment: .top) { Rectangle().fill(ProofDesk.rule).frame(height: 1) }
        }
        .proofPaper()
    }

    private var noSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(records.isEmpty ? "GRIFFEL PRÜFBLATT" : "GRIFFEL ARCHIV")
                .font(ProofDesk.eyebrow)
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Text(records.isEmpty ? "Hier entsteht dein Prüfblatt." : "Wähle links einen Eintrag.")
                .font(ProofDesk.editorialTitle)
            Text(records.isEmpty
                 ? "Nach deiner ersten Aufnahme liest du hier das Transkript, prüfst Herkunft und Audio und legst das Ergebnis ab."
                 : "Hier liest du das Transkript in Ruhe, prüfst Herkunft und Aufnahme und legst das Ergebnis ab.")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 430, alignment: .leading)
        }
        .padding(44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .proofPaper()
    }

    // MARK: - Data

    private var records: [LedgerRecord] {
        let calendar = Calendar.current
        let visibleLibrary = filter.apply(to: library.items).filter {
            route != .today || calendar.isDateInToday($0.createdAt)
        }
        var result = visibleLibrary.map { LedgerRecord(content: .library($0)) }
        if route == .today, filter.selectedTags.isEmpty {
            result.append(contentsOf: BraindumpStore.shared.entries
                .filter {
                    calendar.isDateInToday($0.createdAt) && matchesBraindumpQuery($0)
                }
                .map { LedgerRecord(content: .braindump($0)) })
        }
        return result.sorted { $0.date > $1.date }
    }

    private func matchesBraindumpQuery(_ entry: BraindumpEntry) -> Bool {
        let needle = filter.trimmedQuery
        guard !needle.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if entry.text.range(of: needle, options: options) != nil { return true }
        if let context = entry.captureContext?.displayText,
           context.range(of: needle, options: options) != nil { return true }
        return false
    }

    private var recordIDs: [String] { records.map(\.id) }

    private func resolveSelection() {
        guard !records.isEmpty else { selection = nil; return }
        if let selection, records.contains(where: { $0.selection == selection }) { return }
        selection = records.first?.selection
    }

    private var scopeTitle: String {
        switch filter.scope {
        case .all: return "Alle Aufzeichnungen"
        case .unfiled: return "Ohne Thema"
        case .folder(let name): return name
        }
    }

    private var activeTagNames: [String] {
        library.tagCounts
            .map(\.tag)
            .filter { filter.isTagActive($0) }
    }

    private var tagFilterAccessibilityValue: String {
        switch activeTagNames.count {
        case 0: return "Keine Tags ausgewählt"
        case 1: return "1 Tag ausgewählt: \(activeTagNames[0])"
        default: return "\(activeTagNames.count) Tags ausgewählt"
        }
    }

    private func recordKind(_ record: LedgerRecord) -> String {
        switch record.content {
        case .library(let item): return item.source.displayName
        case .braindump: return "Braindump"
        }
    }
    private func recordIcon(_ record: LedgerRecord) -> String {
        switch record.content {
        case .library(let item): return item.source.icon
        case .braindump: return "brain.head.profile"
        }
    }
    private func recordAccent(_ record: LedgerRecord) -> Color {
        switch record.content {
        case .library(let item): return sourceAccent(item.source)
        case .braindump: return ProofDesk.marker
        }
    }
    private func sourceAccent(_ source: LibrarySource) -> Color {
        switch source {
        case .dictation: return ProofDesk.red
        case .braindump: return ProofDesk.marker
        case .fileImport: return ProofDesk.blue
        case .unknown: return .secondary
        }
    }
    private func recordTitle(_ record: LedgerRecord) -> String {
        switch record.content {
        case .library(let item): return item.title
        case .braindump: return "Unsortierter Gedanke"
        }
    }
    private func recordExcerpt(_ record: LedgerRecord) -> String {
        switch record.content {
        case .library(let item):
            if let failure = appState.transcriptionQueue.job(forItem: item.id)?.status.failureText {
                return failure
            }
            return item.transcript.isEmpty ? "Transkript steht noch aus." : item.transcript
        case .braindump(let entry): return entry.text
        }
    }

    @ViewBuilder
    private func ledgerStatus(_ record: LedgerRecord) -> some View {
        if case .library(let item) = record.content,
           let job = appState.transcriptionQueue.job(forItem: item.id) {
            if job.status.failureText != nil {
                Label("Fehlgeschlagen", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text(job.status.isQueued ? "Wartet" : "In Arbeit")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(ProofDesk.metadataInk)
            }
        } else if recordHasAudio(record) {
            Image(systemName: "waveform")
                .font(.system(size: 9))
                .foregroundStyle(ProofDesk.metadataInk)
                .accessibilityLabel("Aufnahme vorhanden")
        }
    }

    private func recordStatusText(_ record: LedgerRecord) -> String {
        guard case .library(let item) = record.content,
              let job = appState.transcriptionQueue.job(forItem: item.id) else {
            return recordHasAudio(record) ? "Aufnahme vorhanden" : "Bereit"
        }
        if job.status.failureText != nil { return "Verarbeitung fehlgeschlagen" }
        if job.status.isQueued { return "Wartet auf Transkription" }
        return "Wird verarbeitet"
    }

    private func recordAccessibilityLabel(_ record: LedgerRecord) -> String {
        let time = Self.timeFormatter.string(from: record.date)
        return "\(recordKind(record)), \(recordTitle(record)), \(time). \(recordExcerpt(record))"
    }

    private func recordHasAudio(_ record: LedgerRecord) -> Bool {
        if case .library(let item) = record.content { return item.hasAudio }
        return false
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .wav, .aiff]
        guard panel.runModal() == .OK else { return }
        handleImport(panel.urls)
    }

    private func handleImport(_ urls: [URL]) {
        let rejected = appState.importAudioFiles(urls, intoFolder: filter.scope.folderName)
        rejectedFileNames = rejected.map(\.lastPathComponent)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.setLocalizedDateFormatFromTemplate("EEEE dd MMMM yyyy HHmm")
        return formatter
    }()
}

struct WindowActivityBar: View {
    let workflow: any Workflow
    let onStop: () -> Void

    private var accent: Color { workflow.isRecording ? ProofDesk.red : ProofDesk.blue }

    var body: some View {
        HStack(spacing: 11) {
            Circle().fill(accent).frame(width: 7, height: 7)
            Text(workflow.type.displayName.uppercased()).font(ProofDesk.eyebrow).tracking(0.8)
            if workflow.isRecording {
                WaveformView(audioLevel: workflow.audioLevel, isRecording: true, accentColor: accent, barWidth: 2, minBarHeight: 2)
                    .frame(width: 150, height: 18)
            }
            Text(phaseText).font(ProofDesk.utility).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if workflow.isRecording {
                Button("Stopp") { onStop() }.buttonStyle(.vc(.secondary, .compact, tint: ProofDesk.red))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(accent.opacity(0.07))
        .overlay(alignment: .bottom) { Rectangle().fill(ProofDesk.rule).frame(height: 1) }
    }

    private var phaseText: String {
        switch workflow.phase {
        case .idle: return "Bereit"
        case .running(let message): return message
        case .done: return "Fertig"
        case .error(let message): return message
        }
    }
}
