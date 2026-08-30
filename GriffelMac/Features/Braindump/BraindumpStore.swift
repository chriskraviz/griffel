import Foundation
import Observation

struct BraindumpEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    var text: String
    /// Legacy. Older builds set this once an entry's text had been sent to the
    /// LLM. Nothing writes it any more: filing a result is what removes the
    /// entries it came from, so „im Eingang" and „offen" are the same thing.
    /// The key stays so an existing `braindump.json` keeps decoding and an
    /// older build still finds what it expects.
    var isProcessed: Bool = false
    /// Which app and window were in front when the thought was spoken. Nil
    /// when the capture was switched off, Accessibility is not granted, or the
    /// run started from Griffel's own UI.
    var captureContext: CaptureContext?

    init(
        id: UUID,
        createdAt: Date,
        text: String,
        isProcessed: Bool = false,
        captureContext: CaptureContext? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.isProcessed = isProcessed
        self.captureContext = captureContext
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case text
        case isProcessed
        case captureContext
    }

    /// Field by field with defaults. `loadEntries()` decodes behind a `try?`,
    /// so a single `keyNotFound` here would not surface as an error — it would
    /// silently return an empty inbox and look like the user's thoughts were
    /// never there. Synthesized decoding does **not** fall back to a property's
    /// default value, so every new field has to be handled here.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        isProcessed = try container.decodeIfPresent(Bool.self, forKey: .isProcessed) ?? false
        captureContext = try container.decodeIfPresent(CaptureContext.self, forKey: .captureContext)
    }
}

/// Local inbox for spoken thoughts. Lives in its own file (not settings.json)
/// because it is growing user content, and it never leaves the Mac.
@Observable
@MainActor
final class BraindumpStore {
    static let shared = BraindumpStore()

    private(set) var entries: [BraindumpEntry] = []
    private var saveTask: Task<Void, Never>?

    private init() {
        entries = Self.loadEntries()
    }

    /// Everything in the inbox is open. There is no second state where an entry
    /// is already dealt with but still lying here.
    var unprocessedCount: Int {
        entries.count
    }

    func add(text: String, captureContext: CaptureContext? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(
            BraindumpEntry(
                id: UUID(),
                createdAt: Date(),
                text: trimmed,
                captureContext: captureContext?.isEmpty == true ? nil : captureContext
            ),
            at: 0
        )
        scheduleSave()
    }

    func delete(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        try? AppSupportPaths.ensureAppSupportDirectoryExists()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: AppSupportPaths.braindumpURL)
    }

    private static func loadEntries() -> [BraindumpEntry] {
        guard let data = try? Data(contentsOf: AppSupportPaths.braindumpURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BraindumpEntry].self, from: data)) ?? []
    }
}
