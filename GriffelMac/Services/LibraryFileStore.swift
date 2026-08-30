import AppKit
import Foundation

enum LibraryError: LocalizedError {
    case rootUnavailable(String)
    case folderExists(String)
    case invalidFolderName

    var errorDescription: String? {
        switch self {
        case .rootUnavailable(let path):
            return "Der Ablage-Ordner ist nicht erreichbar: \(path)"
        case .folderExists(let name):
            return "Der Bereich „\(name)“ existiert bereits."
        case .invalidFolderName:
            return "Dieser Name geht nicht."
        }
    }
}

/// Every filesystem operation the library performs. Deliberately `nonisolated`
/// and free of app state so callers can push the slow parts (a full scan, an
/// audio copy) off the main actor.
enum LibraryFileStore {
    /// Marks a directory as a Griffel library. Its real job is telling
    /// "the volume is not mounted" apart from "the library is empty" — without
    /// it, an unmounted `/Volumes/Archiv` looks like an empty folder that
    /// `createDirectory(withIntermediateDirectories:)` would happily recreate
    /// on the boot disk, quietly forking the user's library in two.
    static let markerFileName = ".vc-bibliothek.json"

    // MARK: - Root

    static func markerURL(root: URL) -> URL {
        root.appendingPathComponent(markerFileName)
    }

    static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Prepares a root for writing. `mayCreate` is true only for the default
    /// location inside Application Support — a folder the user picked is never
    /// conjured back into existence, because a missing one means "not mounted",
    /// not "please make a new one".
    static func prepareRoot(_ root: URL, mayCreate: Bool) throws {
        if !directoryExists(root) {
            guard mayCreate else {
                throw LibraryError.rootUnavailable(root.path)
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        try writeMarkerIfNeeded(root: root)
    }

    private static func writeMarkerIfNeeded(root: URL) throws {
        let url = markerURL(root: root)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let payload = """
        {
          "schema": 1,
          "app": "Griffel",
          "hinweis": "Dieser Ordner ist die Griffel-Ablage. Die .md-Dateien sind die Transkripte und lassen sich mit jedem Editor lesen."
        }

        """
        try payload.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // MARK: - Scan

    struct ScanResult {
        var items: [LibraryItem] = []
        var folderNames: [String] = []
    }

    /// Reads the whole library from disk. The sidecars are the source of
    /// truth, so this is also how edits made in Finder — a moved file, a
    /// deleted one, a hand-written note — find their way back in.
    static func scan(root: URL) -> ScanResult {
        var result = ScanResult()
        guard directoryExists(root) else { return result }

        var seenIDs = Set<UUID>()

        func collect(directory: URL, folderName: String?) {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if directoryExists(url) {
                    guard folderName == nil else { continue }  // one level only
                    result.folderNames.append(url.lastPathComponent)
                    collect(directory: url, folderName: url.lastPathComponent)
                    continue
                }

                guard url.pathExtension.lowercased() == TranscriptSidecar.fileExtension,
                      let contents = try? String(contentsOf: url, encoding: .utf8) else {
                    continue
                }

                var item = TranscriptSidecar.parse(contents, fileURL: url)
                item.folderName = folderName

                // A file duplicated in Finder carries the same id; the copy
                // gets a fresh one so both stay addressable.
                if !seenIDs.insert(item.id).inserted {
                    item.id = UUID()
                    try? writeSidecar(item, root: root)
                }

                if let audioFileName = item.audioFileName {
                    let audioURL = directory.appendingPathComponent(audioFileName)
                    item.audioIsMissing = !FileManager.default.fileExists(atPath: audioURL.path)
                }

                result.items.append(item)
            }
        }

        collect(directory: root, folderName: nil)
        result.items.sort { $0.createdAt > $1.createdAt }
        result.folderNames.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return result
    }

    // MARK: - Paths

    static func directoryURL(root: URL, folderName: String?) -> URL {
        guard let folderName, !folderName.isEmpty else { return root }
        return root.appendingPathComponent(folderName, isDirectory: true)
    }

    static func sidecarURL(root: URL, item: LibraryItem) -> URL {
        directoryURL(root: root, folderName: item.folderName)
            .appendingPathComponent(item.baseName)
            .appendingPathExtension(TranscriptSidecar.fileExtension)
    }

    static func audioURL(root: URL, item: LibraryItem) -> URL? {
        guard let audioFileName = item.audioFileName else { return nil }
        return directoryURL(root: root, folderName: item.folderName)
            .appendingPathComponent(audioFileName)
    }

    // MARK: - Write

    static func writeSidecar(_ item: LibraryItem, root: URL) throws {
        let directory = directoryURL(root: root, folderName: item.folderName)
        if !directoryExists(directory) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let text = TranscriptSidecar.serialize(item)
        // Atomic: this is the user's only copy of the transcript, and the
        // folder may well be inside Dropbox or iCloud Drive.
        try text.data(using: .utf8)?.write(to: sidecarURL(root: root, item: item), options: .atomic)
    }

    /// Copies the audio next to the sidecar and returns the stored file name.
    /// The source is never moved — dropping a file conventionally copies, and
    /// the user's original has to survive.
    static func copyAudio(from sourceURL: URL, item: LibraryItem, root: URL) throws -> String {
        let directory = directoryURL(root: root, folderName: item.folderName)
        if !directoryExists(directory) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let fileExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let destination = directory
            .appendingPathComponent(item.baseName)
            .appendingPathExtension(fileExtension)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination.lastPathComponent
    }

    // MARK: - Move / delete

    /// Order matters: the audio moves first, then the destination sidecar is
    /// written, then the source sidecar goes. If the sidecar write fails the
    /// audio is moved back, so a failed move leaves the item exactly where it
    /// was instead of stranding a recording no scan can see (scan only reads
    /// `.md` files). Removing the source is **not** swallowed — two sidecars
    /// with one id would leave a permanent duplicate behind.
    static func move(_ item: LibraryItem, to folderName: String?, root: URL) throws -> LibraryItem {
        var moved = item
        moved.folderName = folderName
        let targetDirectory = directoryURL(root: root, folderName: folderName)
        if !directoryExists(targetDirectory) {
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        }
        moved.baseName = uniqueBaseName(item.baseName, in: targetDirectory)

        var audioRollback: (from: URL, to: URL)?
        if let sourceAudio = audioURL(root: root, item: item),
           FileManager.default.fileExists(atPath: sourceAudio.path) {
            let destination = targetDirectory
                .appendingPathComponent(moved.baseName)
                .appendingPathExtension(sourceAudio.pathExtension)
            try FileManager.default.moveItem(at: sourceAudio, to: destination)
            audioRollback = (from: destination, to: sourceAudio)
            moved.audioFileName = destination.lastPathComponent
        }

        let sourceSidecar = sidecarURL(root: root, item: item)
        do {
            try writeSidecar(moved, root: root)
        } catch {
            if let audioRollback {
                try? FileManager.default.moveItem(at: audioRollback.from, to: audioRollback.to)
            }
            throw error
        }

        if sourceSidecar != sidecarURL(root: root, item: moved) {
            try FileManager.default.removeItem(at: sourceSidecar)
        }
        return moved
    }

    /// Moves both files to the Trash rather than unlinking them. There is no
    /// undo inside the app, and Finder's already works.
    static func trash(_ item: LibraryItem, root: URL, audioOnly: Bool = false) throws {
        if let audioURL = audioURL(root: root, item: item),
           FileManager.default.fileExists(atPath: audioURL.path) {
            try FileManager.default.trashItem(at: audioURL, resultingItemURL: nil)
        }
        guard !audioOnly else { return }
        let sidecar = sidecarURL(root: root, item: item)
        if FileManager.default.fileExists(atPath: sidecar.path) {
            try FileManager.default.trashItem(at: sidecar, resultingItemURL: nil)
        }
    }

    // MARK: - Folders

    static func sanitizedFolderName(_ raw: String) -> String? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !cleaned.isEmpty, cleaned != ".", cleaned != "..", !cleaned.hasPrefix(".") else { return nil }
        return String(cleaned.prefix(64))
    }

    static func createFolder(named raw: String, root: URL) throws -> String {
        guard let name = sanitizedFolderName(raw) else { throw LibraryError.invalidFolderName }
        let url = directoryURL(root: root, folderName: name)
        // APFS is case-insensitive by default, so compare that way when
        // creating; a second "Ideen" would otherwise silently land in the first.
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        if existing.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            throw LibraryError.folderExists(name)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return name
    }

    static func renameFolder(_ oldName: String, to raw: String, root: URL) throws -> String {
        guard let newName = sanitizedFolderName(raw) else { throw LibraryError.invalidFolderName }
        guard newName.localizedCaseInsensitiveCompare(oldName) != .orderedSame else { return oldName }

        let existing = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        if existing.contains(where: { $0.localizedCaseInsensitiveCompare(newName) == .orderedSame }) {
            throw LibraryError.folderExists(newName)
        }
        try FileManager.default.moveItem(
            at: directoryURL(root: root, folderName: oldName),
            to: directoryURL(root: root, folderName: newName)
        )
        return newName
    }

    /// Removes the directory only after its contents were moved out — the
    /// caller does that first, so a topic folder never takes recordings with it.
    /// Returns false when something else of the user's is still in there;
    /// silently doing nothing would let the caller report a success that did
    /// not happen.
    @discardableResult
    static func removeEmptyFolder(_ name: String, root: URL) throws -> Bool {
        let url = directoryURL(root: root, folderName: name)
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let meaningful = remaining.filter { !$0.hasPrefix(".") }
        guard meaningful.isEmpty else { return false }
        try FileManager.default.removeItem(at: url)
        return true
    }

    // MARK: - Naming

    /// `2026-08-21-1432-idee-fuer-die-ablage`
    static func baseName(for title: String, date: Date, in directory: URL) -> String {
        let stamp = timestampFormatter.string(from: date)
        let slug = self.slug(title)
        let candidate = slug.isEmpty ? stamp : "\(stamp)-\(slug)"
        return uniqueBaseName(candidate, in: directory)
    }

    static func uniqueBaseName(_ candidate: String, in directory: URL) -> String {
        var name = candidate
        var suffix = 2
        while !isFree(name, in: directory) {
            name = "\(candidate)-\(suffix)"
            suffix += 1
            if suffix > 999 { break }
        }
        return name
    }

    private static func isFree(_ baseName: String, in directory: URL) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return !contents.contains { ($0 as NSString).deletingPathExtension == baseName }
    }

    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        var pieces: [String] = []
        for word in folded.components(separatedBy: CharacterSet.alphanumerics.inverted) where !word.isEmpty {
            pieces.append(word.lowercased())
            if pieces.count == 6 { break }
        }
        return String(pieces.joined(separator: "-").prefix(48))
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()

    /// A first line worth showing in a list, derived from the transcript.
    static func title(from transcript: String, fallback: String) -> String {
        let firstLine = transcript
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return fallback }
        if firstLine.count <= 72 { return firstLine }
        let cut = firstLine.prefix(72)
        if let lastSpace = cut.lastIndex(of: " ") {
            return String(cut[cut.startIndex..<lastSpace]) + "\u{2026}"
        }
        return String(cut) + "\u{2026}"
    }
}
