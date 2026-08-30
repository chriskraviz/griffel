import Foundation
import Observation

/// Which folder, which tags, which search term. Lives outside both the sidebar
/// and the list so neither has to own the other's state — and so the question
/// "would this query hit outside the current folder?" has exactly one home.
@Observable
@MainActor
final class LibraryFilter {
    enum Scope: Hashable {
        /// Everything, regardless of folder.
        case all
        /// Items sitting at the library root.
        case unfiled
        case folder(String)

        var folderName: String? {
            if case .folder(let name) = self { return name }
            return nil
        }
    }

    var query: String = ""
    var scope: Scope = .all
    var selectedTags: Set<String> = []

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isFiltering: Bool {
        !trimmedQuery.isEmpty || !selectedTags.isEmpty
    }

    func reset() {
        query = ""
        selectedTags = []
    }

    func toggleTag(_ tag: String) {
        let key = LibraryTag.key(tag)
        if selectedTags.contains(key) {
            selectedTags.remove(key)
        } else {
            selectedTags.insert(key)
        }
    }

    func isTagActive(_ tag: String) -> Bool {
        selectedTags.contains(LibraryTag.key(tag))
    }

    // MARK: - Matching

    func matchesScope(_ item: LibraryItem) -> Bool {
        switch scope {
        case .all: return true
        case .unfiled: return item.folderName == nil
        case .folder(let name): return item.folderName == name
        }
    }

    /// Title, transcript and tags. Deliberately not folder names: a folder
    /// match would return everything inside it and bury the real text hits,
    /// and the folder list is right there anyway.
    func matchesQueryAndTags(_ item: LibraryItem) -> Bool {
        if !selectedTags.isEmpty {
            let itemKeys = Set(item.tags.map(LibraryTag.key))
            guard selectedTags.isSubset(of: itemKeys) else { return false }
        }

        let needle = trimmedQuery
        guard !needle.isEmpty else { return true }

        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if item.title.range(of: needle, options: options) != nil { return true }
        if item.transcript.range(of: needle, options: options) != nil { return true }
        if item.tags.contains(where: { $0.range(of: needle, options: options) != nil }) { return true }
        if let capture = item.capture?.displayText,
           capture.range(of: needle, options: options) != nil { return true }
        return false
    }

    func apply(to items: [LibraryItem]) -> [LibraryItem] {
        items.filter { matchesScope($0) && matchesQueryAndTags($0) }
    }

    /// How many items the current query and tags would hit if the scope were
    /// dropped — this is what makes „In allen Bereichen suchen" honest instead
    /// of a button that leads to another empty list.
    func matchCountIgnoringScope(_ items: [LibraryItem]) -> Int {
        items.filter { matchesQueryAndTags($0) }.count
    }
}
