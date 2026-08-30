import SwiftUI

/// The one place tags are written. Row density is already three lines; a live
/// text field on every row would put dozens of them in one scroll view.
struct TagEditorPopover: View {
    let item: LibraryItem
    let existingTags: [(tag: String, count: Int)]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var suggestions: [String] {
        let own = Set(item.tags.map(LibraryTag.key))
        return existingTags
            .map(\.tag)
            .filter { !own.contains(LibraryTag.key($0)) }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if item.tags.isEmpty {
                Text("Noch keine Tags")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 5) {
                    ForEach(item.tags, id: \.self) { tag in
                        TagChip(name: tag, onRemove: { onRemove(tag) })
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Tag hinzuf\u{00FC}gen", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .focused($fieldFocused)
                    .onSubmit(commit)

                Button {
                    commit()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.vc(.secondary, .icon))
                .disabled(LibraryTag.normalize(draft) == nil)
            }

            if !suggestions.isEmpty {
                Text("Vorhandene Tags")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)

                FlowLayout(spacing: 5) {
                    ForEach(suggestions, id: \.self) { tag in
                        TagChip(name: tag, onTap: { onAdd(tag) })
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear { fieldFocused = true }
    }

    private func commit() {
        guard let tag = LibraryTag.normalize(draft) else { return }
        onAdd(tag)
        draft = ""
        fieldFocused = true
    }
}
