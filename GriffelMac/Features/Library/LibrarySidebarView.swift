import SwiftUI

/// Left column: the topic folders. A source list, so it is an *exclusive*
/// scope selector — one folder at a time. Tags are multi-select and orthogonal
/// and live in the list's filter bar, not here.
struct LibrarySidebarView: View {
    @Bindable var appState: AppState
    @Bindable var filter: LibraryFilter

    @State private var editingFolder: String?
    @State private var draftName = ""
    @State private var isCreating = false
    @State private var folderPendingDeletion: String?
    @FocusState private var nameFieldFocused: Bool

    private var library: LibraryStore { appState.library }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THEMENBEREICHE")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    scopeRow(
                        title: "Alle",
                        icon: "tray.full",
                        count: library.items.count,
                        scope: .all,
                        folderName: nil
                    )
                    scopeRow(
                        title: "Ohne Thema",
                        icon: "tray",
                        count: library.itemCount(inFolder: nil),
                        scope: .unfiled,
                        folderName: nil
                    )

                    if !library.folders.isEmpty {
                        Divider()
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                    }

                    ForEach(library.folders) { folder in
                        if editingFolder == folder.name {
                            nameField(commit: { commitRename(from: folder.name) })
                        } else {
                            scopeRow(
                                title: folder.name,
                                icon: "folder",
                                count: folder.itemCount,
                                scope: .folder(folder.name),
                                folderName: folder.name
                            )
                            .contextMenu {
                                Button("Umbenennen") { beginRename(folder.name) }
                                Button("Bereich l\u{00F6}schen", role: .destructive) {
                                    folderPendingDeletion = folder.name
                                }
                            }
                        }
                    }

                    if isCreating {
                        nameField(commit: commitCreate)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            Divider()

            Button {
                beginCreate()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("Neuer Bereich")
                }
            }
            .buttonStyle(.vc(.quiet, .compact))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

        }
        .confirmationDialog(
            folderPendingDeletion.map { "\u{201E}\($0)\u{201C} l\u{00F6}schen" } ?? "",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("L\u{00F6}schen", role: .destructive) {
                if let name = folderPendingDeletion {
                    if filter.scope == .folder(name) { filter.scope = .all }
                    library.deleteFolder(name)
                }
                folderPendingDeletion = nil
            }
            Button("Abbrechen", role: .cancel) { folderPendingDeletion = nil }
        } message: {
            if let name = folderPendingDeletion {
                Text(deletionMessage(for: name))
            }
        }
    }

    private func deletionMessage(for name: String) -> String {
        switch library.itemCount(inFolder: name) {
        case 0:
            return "Der Bereich ist leer und verschwindet einfach."
        case 1:
            return "Die eine Aufnahme wandert zur\u{00FC}ck nach \u{201E}Ohne Thema\u{201C}. Nichts wird gel\u{00F6}scht."
        case let count:
            return "Die \(count) Aufnahmen wandern zur\u{00FC}ck nach \u{201E}Ohne Thema\u{201C}. Nichts wird gel\u{00F6}scht."
        }
    }

    // MARK: - Rows

    private func scopeRow(
        title: String,
        icon: String,
        count: Int,
        scope: LibraryFilter.Scope,
        folderName: String?
    ) -> some View {
        let isSelected = filter.scope == scope
        return Button {
            filter.scope = scope
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10.5))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text("\(count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Keycap.radius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Dropping straight onto a topic files the recording there.
        .dropDestination(for: URL.self) { urls, _ in
            appState.importAudioFiles(urls, intoFolder: folderName)
            filter.scope = scope
            return true
        }
    }

    private func nameField(commit: @escaping () -> Void) -> some View {
        TextField("Name des Bereichs", text: $draftName)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .focused($nameFieldFocused)
            .onSubmit(commit)
            .onExitCommand { cancelEditing() }
            // Clicking elsewhere abandons the edit rather than committing it:
            // without this the row stays a text field forever, and silently
            // renaming a topic because someone clicked away is worse than
            // losing a half-typed name.
            .onChange(of: nameFieldFocused) { _, isFocused in
                if !isFocused { cancelEditing() }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }

    // MARK: - Actions

    private func beginCreate() {
        draftName = ""
        editingFolder = nil
        isCreating = true
        nameFieldFocused = true
    }

    private func beginRename(_ name: String) {
        draftName = name
        isCreating = false
        editingFolder = name
        nameFieldFocused = true
    }

    private func commitCreate() {
        let name = draftName
        cancelEditing()
        guard let created = library.createFolder(named: name) else { return }
        filter.scope = .folder(created)
    }

    private func commitRename(from oldName: String) {
        let name = draftName
        cancelEditing()
        guard let renamed = library.renameFolder(oldName, to: name) else { return }
        if filter.scope == .folder(oldName) { filter.scope = .folder(renamed) }
    }

    private func cancelEditing() {
        isCreating = false
        editingFolder = nil
        draftName = ""
        nameFieldFocused = false
    }
}
