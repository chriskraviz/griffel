import AppKit
import Foundation
import Observation

/// The filed recordings and their transcripts.
///
/// There is **no index file**: the `.md` sidecars in the library folder are the
/// only source of truth, and loading means scanning them. That costs a
/// directory walk on open and grows with the library, but it removes the whole
/// class of bugs where a cache and the disk disagree — and it means a folder
/// the user moved, renamed or edited in Finder simply reads back correctly.
///
/// Owned by `AppState`, not a singleton: the root comes from settings and has
/// to follow a change, which a `.shared` created at launch cannot.
@Observable
@MainActor
final class LibraryStore {
    private(set) var items: [LibraryItem] = []
    private(set) var folderNames: [String] = []
    private(set) var isScanning = false
    /// Set when the configured folder cannot be written to — an unmounted
    /// volume, a folder the user deleted. Writes refuse while this is set.
    private(set) var unavailableReason: String?
    private(set) var lastErrorText: String?
    /// Surfaced by the drop zone: why the last drop could not be filed.
    var lastImportErrorText: String?

    private var settings = LibrarySettings()
    /// Bumped by every write. A scan that started before a write must not
    /// replace `items` with a snapshot that predates it — the disk is already
    /// right, so the fix is to scan again rather than to publish stale state.
    private var mutationToken = 0

    // MARK: - Root

    var rootURL: URL {
        let path = settings.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return AppSupportPaths.defaultLibraryDirectoryURL }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    var isUsingDefaultRoot: Bool {
        settings.rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var storesImportedAudio: Bool {
        settings.storeImportedAudio
    }

    var isAvailable: Bool { unavailableReason == nil }

    func apply(settings newSettings: LibrarySettings) {
        let rootChanged = newSettings.rootPath != settings.rootPath
        settings = newSettings
        if rootChanged {
            items = []
            folderNames = []
            // Invalidates a scan already in flight, so the old root's contents
            // can never be published into the new root's list.
            mutationToken += 1
            refresh()
        }
    }

    /// Resolves the root and makes sure it is ready for writing. The default
    /// root is created on demand; a folder the user picked is never recreated,
    /// because "missing" there means "not mounted", not "make me a new one".
    @discardableResult
    func prepareRoot() -> URL? {
        let root = rootURL
        do {
            try LibraryFileStore.prepareRoot(root, mayCreate: isUsingDefaultRoot)
            unavailableReason = nil
            return root
        } catch {
            unavailableReason = error.localizedDescription
            return nil
        }
    }

    // MARK: - Loading

    func refresh() {
        guard !isScanning else { return }
        guard prepareRoot() != nil else {
            items = []
            folderNames = []
            return
        }

        isScanning = true
        Task { @MainActor [weak self] in
            defer { self?.isScanning = false }
            // Bounded: each retry needs a write — or a root change — to have
            // landed during the previous scan. The root is read fresh each
            // round, so a scan that started against the old folder is retried
            // against the new one rather than published into it.
            for _ in 0..<4 {
                guard let self, let root = self.prepareRoot() else { return }
                let token = self.mutationToken
                let result = await Task.detached(priority: .userInitiated) {
                    LibraryFileStore.scan(root: root)
                }.value
                guard self.mutationToken == token else { continue }
                self.items = result.items
                self.folderNames = result.folderNames
                return
            }
        }
    }

    // MARK: - Derived

    func itemCount(inFolder folderName: String?) -> Int {
        items.filter { $0.folderName == folderName }.count
    }

    var folders: [LibraryFolder] {
        folderNames.map { LibraryFolder(name: $0, itemCount: itemCount(inFolder: $0)) }
    }

    /// Every tag in use with its count, most used first.
    var tagCounts: [(tag: String, count: Int)] {
        var counts: [String: (display: String, count: Int)] = [:]
        for item in items {
            for tag in item.tags {
                let key = LibraryTag.key(tag)
                if let existing = counts[key] {
                    counts[key] = (existing.display, existing.count + 1)
                } else {
                    counts[key] = (tag, 1)
                }
            }
        }
        return counts.values
            .map { (tag: $0.display, count: $0.count) }
            .sorted {
                $0.count == $1.count
                    ? $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending
                    : $0.count > $1.count
            }
    }

    func clearLastError() {
        lastErrorText = nil
    }

    func item(id: UUID) -> LibraryItem? {
        items.first { $0.id == id }
    }

    func audioURL(for item: LibraryItem) -> URL? {
        LibraryFileStore.audioURL(root: rootURL, item: item)
    }

    func sidecarURL(for item: LibraryItem) -> URL {
        LibraryFileStore.sidecarURL(root: rootURL, item: item)
    }

    // MARK: - Creating

    /// A place on disk reserved before a transcript exists.
    ///
    /// The audio is copied in at *enqueue* time on purpose: a file dragged out
    /// of Mail or Messages lives at a temporary path the sending app may delete
    /// as soon as the drag ends, and a retry hours later has to have something
    /// to read.
    struct Reservation {
        let itemID: UUID
        let baseName: String
        let folderName: String?
        let audioFileName: String?
        let createdAt: Date
    }

    /// Files a dropped recording immediately: audio copied in, sidecar written
    /// with an empty transcript. The row is visible while it transcribes, and
    /// a failure leaves a filed recording that can be retried rather than
    /// nothing at all.
    func reserve(
        sourceAudioURL: URL,
        folderName: String?,
        copyAudio: Bool
    ) throws -> Reservation {
        guard let root = prepareRoot() else {
            throw LibraryError.rootUnavailable(rootURL.path)
        }

        let createdAt = Date()
        let directory = LibraryFileStore.directoryURL(root: root, folderName: folderName)
        if !LibraryFileStore.directoryExists(directory) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let originalName = sourceAudioURL.deletingPathExtension().lastPathComponent
        let baseName = LibraryFileStore.baseName(for: originalName, date: createdAt, in: directory)

        var item = LibraryItem(
            title: sourceAudioURL.lastPathComponent,
            createdAt: createdAt,
            updatedAt: createdAt,
            source: .fileImport,
            folderName: folderName,
            transcript: "",
            baseName: baseName
        )

        if copyAudio {
            item.audioFileName = try LibraryFileStore.copyAudio(from: sourceAudioURL, item: item, root: root)
            item.audioDuration = nil
        }

        try LibraryFileStore.writeSidecar(item, root: root)
        mutationToken += 1
        insertOrReplace(item)

        return Reservation(
            itemID: item.id,
            baseName: baseName,
            folderName: folderName,
            audioFileName: item.audioFileName,
            createdAt: createdAt
        )
    }

    /// Files a transcript that has no audio — a Braindump entry the user moved
    /// into a topic folder, for instance.
    @discardableResult
    func addTranscript(
        _ transcript: String,
        title: String? = nil,
        source: LibrarySource,
        folderName: String?,
        tags: [String] = [],
        language: String = "",
        engine: String = "",
        capture: CaptureContext? = nil,
        createdAt: Date = Date()
    ) throws -> LibraryItem {
        guard let root = prepareRoot() else {
            throw LibraryError.rootUnavailable(rootURL.path)
        }

        let directory = LibraryFileStore.directoryURL(root: root, folderName: folderName)
        if !LibraryFileStore.directoryExists(directory) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let resolvedTitle = title ?? LibraryFileStore.title(from: transcript, fallback: source.displayName)
        let item = LibraryItem(
            title: resolvedTitle,
            createdAt: createdAt,
            updatedAt: Date(),
            source: source,
            folderName: folderName,
            tags: tags,
            transcript: transcript,
            language: language,
            engine: engine,
            capture: capture,
            baseName: LibraryFileStore.baseName(for: resolvedTitle, date: createdAt, in: directory)
        )
        try LibraryFileStore.writeSidecar(item, root: root)
        mutationToken += 1
        insertOrReplace(item)
        return item
    }

    /// Fills in the transcript once the engine is done. Falls back to disk
    /// when the item is not in memory — a refresh may have replaced the array
    /// while the engine was running, and the transcript is the whole point of
    /// the run.
    @discardableResult
    func setTranscript(
        itemID: UUID,
        transcript: String,
        duration: TimeInterval?,
        language: String,
        engine: String
    ) -> Bool {
        guard var item = item(id: itemID) ?? reloadedItem(id: itemID) else { return false }
        item.transcript = transcript
        item.title = LibraryFileStore.title(from: transcript, fallback: item.title)
        item.updatedAt = Date()
        if let duration { item.audioDuration = duration }
        item.language = language
        item.engine = engine
        return write(item)
    }

    // MARK: - Editing

    /// Every mutation takes an **id**, never an item value. A row's value is a
    /// snapshot: a context menu opened before a transcription finished would
    /// otherwise write its empty transcript back over the real one.

    func setTags(_ tags: [String], onItemID id: UUID) {
        guard var item = item(id: id) else { return }
        item.tags = tags
        item.updatedAt = Date()
        write(item)
    }

    func addTag(_ tag: String, toItemID id: UUID) {
        guard let item = item(id: id) else { return }
        setTags(LibraryTag.merged(item.tags, adding: tag), onItemID: id)
    }

    func removeTag(_ tag: String, fromItemID id: UUID) {
        guard let item = item(id: id) else { return }
        setTags(LibraryTag.removed(item.tags, removing: tag), onItemID: id)
    }

    func move(itemID id: UUID, toFolder folderName: String?) {
        guard let item = item(id: id), item.folderName != folderName else { return }
        guard let root = prepareRoot() else { return }
        do {
            let moved = try LibraryFileStore.move(item, to: folderName, root: root)
            mutationToken += 1
            insertOrReplace(moved)
            lastErrorText = nil
        } catch {
            lastErrorText = error.localizedDescription
        }
    }

    func delete(itemID id: UUID) {
        guard let item = item(id: id), let root = prepareRoot() else { return }
        do {
            try LibraryFileStore.trash(item, root: root)
            mutationToken += 1
            items.removeAll { $0.id == id }
            lastErrorText = nil
        } catch {
            lastErrorText = error.localizedDescription
        }
    }

    /// Trashes the recording but keeps the transcript — the big object and the
    /// valuable object are not the same object here.
    func deleteAudio(ofItemID id: UUID) {
        guard var item = item(id: id), item.hasAudio, let root = prepareRoot() else { return }
        do {
            try LibraryFileStore.trash(item, root: root, audioOnly: true)
            item.audioFileName = nil
            item.audioDuration = nil
            item.audioIsMissing = false
            item.updatedAt = Date()
            write(item)
            lastErrorText = nil
        } catch {
            lastErrorText = error.localizedDescription
        }
    }

    // MARK: - Folders

    @discardableResult
    func createFolder(named name: String) -> String? {
        guard let root = prepareRoot() else { return nil }
        do {
            let created = try LibraryFileStore.createFolder(named: name, root: root)
            mutationToken += 1
            if !folderNames.contains(created) {
                folderNames.append(created)
                folderNames.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
            lastErrorText = nil
            return created
        } catch {
            lastErrorText = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func renameFolder(_ oldName: String, to newName: String) -> String? {
        guard let root = prepareRoot() else { return nil }
        do {
            let renamed = try LibraryFileStore.renameFolder(oldName, to: newName, root: root)
            mutationToken += 1
            folderNames.removeAll { $0 == oldName }
            if !folderNames.contains(renamed) { folderNames.append(renamed) }
            folderNames.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            for index in items.indices where items[index].folderName == oldName {
                items[index].folderName = renamed
            }
            lastErrorText = nil
            return renamed
        } catch {
            lastErrorText = error.localizedDescription
            return nil
        }
    }

    /// Deleting a topic never deletes recordings: everything in it moves back
    /// to the library root first.
    func deleteFolder(_ name: String) {
        guard let root = prepareRoot() else { return }
        for id in items.filter({ $0.folderName == name }).map(\.id) {
            move(itemID: id, toFolder: nil)
        }
        do {
            let removed = try LibraryFileStore.removeEmptyFolder(name, root: root)
            mutationToken += 1
            if removed {
                folderNames.removeAll { $0 == name }
                lastErrorText = nil
            } else {
                // The recordings are out, but something else of the user's is
                // still in there. Saying "done" while the folder is still on
                // disk would be the lie.
                lastErrorText = "\u{201E}\(name)\u{201C} enth\u{00E4}lt noch andere Dateien und wurde nicht gel\u{00F6}scht."
            }
        } catch {
            lastErrorText = error.localizedDescription
        }
    }

    // MARK: - Internals

    @discardableResult
    private func write(_ item: LibraryItem) -> Bool {
        guard let root = prepareRoot() else {
            lastErrorText = unavailableReason
            return false
        }
        do {
            try LibraryFileStore.writeSidecar(item, root: root)
            mutationToken += 1
            insertOrReplace(item)
            lastErrorText = nil
            return true
        } catch {
            lastErrorText = error.localizedDescription
            return false
        }
    }

    /// Last resort for an item the in-memory array lost: find its sidecar on
    /// disk by id.
    private func reloadedItem(id: UUID) -> LibraryItem? {
        guard LibraryFileStore.directoryExists(rootURL) else { return nil }
        return LibraryFileStore.scan(root: rootURL).items.first { $0.id == id }
    }

    private func insertOrReplace(_ item: LibraryItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
            items.sort { $0.createdAt > $1.createdAt }
        }
    }
}
