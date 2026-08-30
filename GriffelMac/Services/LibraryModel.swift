import Foundation

/// Where the user's recordings and their transcripts live on disk.
///
/// An empty `rootPath` means the default under Application Support — not
/// "unconfigured". The library always has a home, so a dropped file is never
/// silently discarded for want of a setting.
struct LibrarySettings: Codable {
    var rootPath: String = ""
    /// Copy the dropped file into the library. Off keeps only the transcript,
    /// for people who already have their audio filed somewhere else.
    var storeImportedAudio: Bool = true

    init(rootPath: String = "", storeImportedAudio: Bool = true) {
        self.rootPath = rootPath
        self.storeImportedAudio = storeImportedAudio
    }

    enum CodingKeys: String, CodingKey {
        case rootPath
        case storeImportedAudio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rootPath = try container.decodeIfPresent(String.self, forKey: .rootPath) ?? ""
        storeImportedAudio = try container.decodeIfPresent(Bool.self, forKey: .storeImportedAudio) ?? true
    }
}

/// How a transcript came to be. Stored as a raw string in the sidecar, so a
/// value written by a newer build reads back as `.unknown` instead of losing
/// the item.
enum LibrarySource: String, CaseIterable {
    case fileImport
    case braindump
    case dictation
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "fileImport": self = .fileImport
        case "braindump": self = .braindump
        case "dictation": self = .dictation
        default: self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .fileImport: return "Import"
        case .braindump: return "Braindump"
        case .dictation: return "Diktat"
        case .unknown: return "Notiz"
        }
    }

    var icon: String {
        switch self {
        case .fileImport: return "square.and.arrow.down"
        case .braindump: return "brain.head.profile"
        case .dictation: return "mic.fill"
        case .unknown: return "doc.text"
        }
    }
}

/// One filed recording: a transcript, optionally the audio it came from.
///
/// `id` lives in the sidecar rather than in an index, so moving the pair
/// between folders in Finder keeps the item instead of creating a new one.
struct LibraryItem: Identifiable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var source: LibrarySource
    /// Directory under the library root; nil means the root itself.
    var folderName: String?
    var tags: [String]
    var transcript: String
    /// File name inside the same directory, nil when there is no audio at all.
    var audioFileName: String?
    var audioDuration: TimeInterval?
    var language: String
    /// Free-form engine note, e.g. "whisperkit:openai_whisper-small_216MB".
    var engine: String
    var capture: CaptureContext?
    /// Front-matter keys this build does not know, kept so a newer build's
    /// data survives a round trip through an older one.
    var extra: [String: String]

    /// Base name shared by the sidecar and the audio file, without extension.
    var baseName: String
    /// False when the sidecar names an audio file that is not on disk.
    var audioIsMissing: Bool

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        source: LibrarySource,
        folderName: String? = nil,
        tags: [String] = [],
        transcript: String,
        audioFileName: String? = nil,
        audioDuration: TimeInterval? = nil,
        language: String = "",
        engine: String = "",
        capture: CaptureContext? = nil,
        extra: [String: String] = [:],
        baseName: String = "",
        audioIsMissing: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.folderName = folderName
        self.tags = tags
        self.transcript = transcript
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
        self.language = language
        self.engine = engine
        self.capture = capture
        self.extra = extra
        self.baseName = baseName
        self.audioIsMissing = audioIsMissing
    }

    var hasAudio: Bool { audioFileName != nil }

    /// "lokal" / "online" / nil — the same vocabulary the import rows use.
    var engineLabel: String? {
        if engine.hasPrefix("whisperkit") || engine.hasPrefix("mlx") { return "lokal" }
        if engine.hasPrefix("openai") { return "online" }
        return nil
    }
}

/// A topic folder is a real directory under the root; there is nothing about
/// it worth persisting separately, so its name is its identity.
struct LibraryFolder: Identifiable, Hashable {
    var name: String
    var itemCount: Int

    var id: String { name }
}

// MARK: - Tags

enum LibraryTag {
    /// Tags compare case- and diacritic-insensitively but keep the spelling
    /// the user first typed, so "Kunde" does not become "kunde" behind them.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func key(_ tag: String) -> String {
        tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func merged(_ existing: [String], adding tag: String) -> [String] {
        guard let normalized = normalize(tag) else { return existing }
        let existingKeys = Set(existing.map(key))
        guard !existingKeys.contains(key(normalized)) else { return existing }
        return existing + [normalized]
    }

    static func removed(_ existing: [String], removing tag: String) -> [String] {
        let target = key(tag)
        return existing.filter { key($0) != target }
    }
}
