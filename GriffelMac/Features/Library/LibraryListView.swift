import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Middle column: the drop zone, the filter bar, and the recordings that
/// survived both. One list — a recording is filed the moment it is dropped, so
/// there is no separate "in flight" pile to reconcile with.
struct LibraryListView: View {
    @Bindable var appState: AppState
    @Bindable var filter: LibraryFilter
    var isDropTargeted: Bool
    /// The sidebar folds away in a narrow window; the folder menu takes over
    /// so every topic stays reachable at every size.
    var showsFolderMenu: Bool
    @Binding var rejectedFileNames: [String]
    let onImport: ([URL]) -> Void

    private var library: LibraryStore { appState.library }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private var visibleItems: [LibraryItem] {
        filter.apply(to: library.items)
    }

    private var scopeLabel: String {
        switch filter.scope {
        case .all: return "allen Bereichen"
        case .unfiled: return "\u{201E}Ohne Thema\u{201C}"
        case .folder(let name): return "\u{201E}\(name)\u{201C}"
        }
    }

    private var dropTargetLabel: String {
        switch filter.scope {
        case .all, .unfiled: return "landet in \u{201E}Ohne Thema\u{201C}"
        case .folder(let name): return "landet in \u{201E}\(name)\u{201C}"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    dropZone

                    if let reason = library.unavailableReason {
                        unavailableNotice(reason)
                    }

                    if let errorText = library.lastErrorText {
                        noticeRow(errorText, icon: "exclamationmark.triangle.fill", tint: .orange) {
                            library.clearLastError()
                        }
                    }

                    if let errorText = library.lastImportErrorText {
                        noticeRow(errorText, icon: "exclamationmark.triangle.fill", tint: .orange) {
                            library.lastImportErrorText = nil
                        }
                    }

                    if !rejectedFileNames.isEmpty {
                        noticeRow(
                            "Keine Audiodatei: \(rejectedFileNames.joined(separator: ", "))",
                            icon: "doc.badge.ellipsis",
                            tint: .secondary
                        ) {
                            rejectedFileNames = []
                        }
                    }

                    if visibleItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedItems, id: \.day) { group in
                            Text(Self.dayFormatter.string(from: group.day))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)

                            ForEach(group.items) { item in
                                LibraryRowView(
                                    appState: appState,
                                    item: item,
                                    job: appState.transcriptionQueue.job(forItem: item.id),
                                    allTags: library.tagCounts,
                                    folderNames: library.folderNames,
                                    onSelectTag: { filter.toggleTag($0) }
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if showsFolderMenu {
                    folderMenu
                }

                SearchField(
                    text: $filter.query,
                    placeholder: "In \(scopeLabel) suchen"
                )

                tagMenu
            }

            if filter.isFiltering {
                HStack(spacing: 5) {
                    FlowLayout(spacing: 5) {
                        ForEach(activeTagNames, id: \.self) { tag in
                            TagChip(name: tag, isActive: true, onRemove: { filter.toggleTag(tag) })
                        }
                    }

                    Text(visibleItems.count == 1 ? "1 Treffer" : "\(visibleItems.count) Treffer")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Button("Filter zur\u{00FC}cksetzen") { filter.reset() }
                        .buttonStyle(.vc(.quiet, .compact))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var activeTagNames: [String] {
        library.tagCounts
            .map(\.tag)
            .filter { filter.isTagActive($0) }
    }

    private var folderMenu: some View {
        Menu {
            Button("Alle") { filter.scope = .all }
            Button("Ohne Thema") { filter.scope = .unfiled }
            if !library.folders.isEmpty {
                Divider()
                ForEach(library.folders) { folder in
                    Button("\(folder.name) (\(folder.itemCount))") { filter.scope = .folder(folder.name) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(shortScopeName)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.vc(.secondary, .compact))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Themenbereich w\u{00E4}hlen")
    }

    private var shortScopeName: String {
        switch filter.scope {
        case .all: return "Alle"
        case .unfiled: return "Ohne Thema"
        case .folder(let name): return name
        }
    }

    private var tagMenu: some View {
        Menu {
            if library.tagCounts.isEmpty {
                Text("Noch keine Tags")
            } else {
                ForEach(library.tagCounts, id: \.tag) { entry in
                    Button {
                        filter.toggleTag(entry.tag)
                    } label: {
                        if filter.isTagActive(entry.tag) {
                            Label("\(entry.tag) (\(entry.count))", systemImage: "checkmark")
                        } else {
                            Text("\(entry.tag) (\(entry.count))")
                        }
                    }
                }
                if !filter.selectedTags.isEmpty {
                    Divider()
                    Button("Alle Tags abw\u{00E4}hlen") { filter.selectedTags = [] }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.system(size: 9.5, weight: .semibold))
                Text("Tags")
            }
        }
        .menuStyle(.button)
        .buttonStyle(.vc(.secondary, .compact))
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Drop zone

    /// Two states: a full card while there is nothing to look at, a 44pt strip
    /// once the list has content — a permanent 130pt card would spend a third
    /// of the column on an affordance the user already understands.
    @ViewBuilder
    private var dropZone: some View {
        if library.items.isEmpty || isDropTargeted {
            fullDropZone
        } else {
            compactDropZone
        }
    }

    private var fullDropZone: some View {
        VStack(spacing: 9) {
            Image(systemName: isDropTargeted ? "square.and.arrow.down.fill" : "waveform.badge.plus")
                .font(.system(size: 22))
                .foregroundStyle(isDropTargeted ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.tertiary))

            VStack(spacing: 3) {
                Text(isDropTargeted ? "Loslassen \u{2014} \(dropTargetLabel)" : "Sprachaufnahmen hierher ziehen")
                    .font(.system(size: 12.5, weight: .semibold))

                Text(engineHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                if appState.canImportAudio {
                    Button("Dateien w\u{00E4}hlen \u{2026}") { chooseFiles() }
                        .buttonStyle(.vc(.secondary, .compact))
                }

                rewriteMenu
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 14)
        .background(dropZoneBackground)
        .overlay(dropZoneBorder)
        .animation(.easeOut(duration: 0.14), value: isDropTargeted)
    }

    private var compactDropZone: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            // Without an engine the strip must not invite a drop that would
            // then do nothing at all.
            Text(appState.canImportAudio
                 ? "Aufnahme hierher ziehen \u{2014} \(dropTargetLabel)"
                 : engineHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(appState.canImportAudio ? "" : engineHint)

            Spacer(minLength: 6)

            if appState.canImportAudio {
                Button("Dateien w\u{00E4}hlen \u{2026}") { chooseFiles() }
                    .buttonStyle(.vc(.quiet, .compact))
            }

            rewriteMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(dropZoneBackground)
        .overlay(dropZoneBorder)
    }

    private var dropZoneBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous)
            .fill(Color.blue.opacity(isDropTargeted ? 0.10 : 0))
    }

    private var dropZoneBorder: some View {
        RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous)
            .strokeBorder(
                isDropTargeted ? Color.blue.opacity(0.75) : Color.primary.opacity(0.16),
                style: StrokeStyle(lineWidth: isDropTargeted ? 1.6 : 1.1, dash: [5, 4])
            )
    }

    private var rewriteMenu: some View {
        Menu {
            if appState.canRewriteImports {
                Toggle("Nachbearbeiten", isOn: $appState.appSettings.importRewriteEnabled)
            }
            Text(rewriteHint)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10, weight: .medium))
        }
        .menuStyle(.button)
        .buttonStyle(.vc(.quiet, .icon))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Was mit importierten Aufnahmen passiert")
    }

    private var engineHint: String {
        guard appState.canImportAudio else {
            return appState.appSettings.secureLocalModeEnabled
                ? "Zuerst das lokale WhisperKit-Modell laden."
                : "Zuerst einen OpenAI API Key hinterlegen."
        }
        let formats = "m4a, mp3, wav, mp4 \u{2026}"
        return appState.appSettings.secureLocalModeEnabled
            ? "\(formats) \u{2014} lokal via \(appState.selectedLocalModelDisplayName), ohne Gr\u{00F6}\u{00DF}enlimit."
            : "\(formats) \u{2014} online via Whisper bei OpenAI, bis 25 MB pro Datei."
    }

    private var rewriteHint: String {
        guard appState.canRewriteImports else {
            return appState.appSettings.secureLocalModeEnabled
                ? "Braucht das lokale Sprachmodell."
                : "Braucht einen OpenAI API Key."
        }
        return appState.appSettings.importRewriteEnabled
            ? "\(appState.textImprovementSettings.rewriteScope.displayName) l\u{00E4}uft nach der Transkription."
            : "Aus: das Transkript bleibt wortgetreu."
    }

    // MARK: - Notices and empty states

    private func unavailableNotice(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.badge.questionmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text("Ablage-Ordner nicht erreichbar")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            Text("\(reason)\n\nNichts wird angelegt, solange der Ordner fehlt \u{2014} sonst l\u{00E4}ge deine Ablage am Ende an zwei Orten.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Erneut versuchen") { library.refresh() }
                .buttonStyle(.vc(.secondary, .compact))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(tint: .orange)
    }

    private func noticeRow(
        _ text: String,
        icon: String,
        tint: Color,
        onDismiss: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.vc(.quiet, .icon))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if filter.isFiltering {
            let globalCount = filter.matchCountIgnoringScope(library.items)
            VStack(alignment: .leading, spacing: 7) {
                Text("Nichts gefunden")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(noResultsText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if globalCount > 0, filter.scope != .all {
                        Button("In allen Bereichen suchen") { filter.scope = .all }
                            .buttonStyle(.vc(.secondary, .compact))
                    }
                    Button("Filter zur\u{00FC}cksetzen") { filter.reset() }
                        .buttonStyle(.vc(.quiet, .compact))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassCard()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(library.items.isEmpty ? "Noch nichts abgelegt" : "\(scopeLabel) ist leer")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(library.items.isEmpty
                     ? "Zieh eine Sprachaufnahme ins Fenster, oder sprich einen Gedanken per \(appState.hotkeyLabel(for: .braindump)) und leg ihn von rechts hier ab."
                     : "Zieh Aufnahmen hierher oder verschieb sie \u{00FC}ber das Kontextmen\u{00FC} einer Zeile.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassCard()
        }
    }

    private var noResultsText: String {
        let query = filter.trimmedQuery
        if query.isEmpty {
            return "Keine Aufnahme mit diesen Tags in \(scopeLabel)."
        }
        return filter.scope == .all
            ? "Kein Treffer f\u{00FC}r \u{201E}\(query)\u{201C}."
            : "Kein Treffer f\u{00FC}r \u{201E}\(query)\u{201C} in \(scopeLabel)."
    }

    private var groupedItems: [(day: Date, items: [LibraryItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleItems) { calendar.startOfDay(for: $0.createdAt) }
        return grouped
            .map { (day: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }

    // MARK: - Actions

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Audio, .mp3, .wav, .aiff]
        panel.prompt = "Importieren"
        panel.message = "Sprachaufnahmen ausw\u{00E4}hlen"

        // A sheet rather than `runModal()`: the window is right there, and a
        // modal loop would freeze the list behind it while the user browses.
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK else { return }
                onImport(panel.urls)
            }
        } else if panel.runModal() == .OK {
            onImport(panel.urls)
        }
    }
}
