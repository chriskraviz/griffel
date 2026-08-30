import Foundation
import Observation

struct TrackedPhrase: Codable, Identifiable, Hashable {
    let phrase: String
    var count: Int
    var lastSeenAt: Date
    var isIgnored: Bool = false

    var id: String { phrase }

    enum CodingKeys: String, CodingKey {
        case phrase
        case count
        case lastSeenAt
        case isIgnored
    }

    init(phrase: String, count: Int, lastSeenAt: Date, isIgnored: Bool = false) {
        self.phrase = phrase
        self.count = count
        self.lastSeenAt = lastSeenAt
        self.isIgnored = isIgnored
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phrase = try container.decode(String.self, forKey: .phrase)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt) ?? Date()
        isIgnored = try container.decodeIfPresent(Bool.self, forKey: .isIgnored) ?? false
    }
}

/// Frequency counts of recurring 2-4-word phrases across dictations.
/// Privacy contract: this store holds aggregated, normalized n-grams with
/// counts only — never raw transcripts and never per-occurrence records.
/// Lives in its own file (phrases.json) so the stats.json promise
/// ("never transcript content") stays intact.
@Observable
@MainActor
final class PhraseStore {
    static let shared = PhraseStore()

    static let minOccurrencesForFrequent = 3
    private static let maxTrackedPhrases = 2_000
    private static let staleAfterDays = 90
    private static let singleUseStaleAfterDays = 14

    private(set) var phrases: [String: TrackedPhrase] = [:]
    private var saveTask: Task<Void, Never>?

    private init() {
        phrases = Self.loadPhrases()
        pruneStaleOnLoad()
    }

    // MARK: - Ingestion

    func ingest(text: String) {
        let extracted = PhraseDetectionService.extractPhrases(from: text)
        guard !extracted.isEmpty else { return }

        let now = Date()
        for phrase in extracted {
            if var tracked = phrases[phrase] {
                tracked.count += 1
                tracked.lastSeenAt = now
                phrases[phrase] = tracked
            } else {
                phrases[phrase] = TrackedPhrase(phrase: phrase, count: 1, lastSeenAt: now)
            }
        }

        pruneIfOverCap()
        scheduleSave()
    }

    // MARK: - Queries

    /// Frequent phrases with longest-match subsumption: a phrase that is
    /// contained in a longer surviving phrase with at least the same count
    /// is hidden ("guten morgen zusammen" hides "guten morgen").
    func frequentPhrases(limit: Int = 20) -> [TrackedPhrase] {
        let candidates = phrases.values
            .filter { $0.count >= Self.minOccurrencesForFrequent && !$0.isIgnored }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                let words0 = $0.phrase.split(separator: " ").count
                let words1 = $1.phrase.split(separator: " ").count
                if words0 != words1 { return words0 > words1 }
                return $0.phrase < $1.phrase
            }

        var result: [TrackedPhrase] = []
        for candidate in candidates {
            let isSubsumed = result.contains { longer in
                longer.count >= candidate.count
                    && longer.phrase != candidate.phrase
                    && wordBoundaryContains(longer.phrase, candidate.phrase)
            }
            if !isSubsumed {
                result.append(candidate)
            }
            if result.count >= limit { break }
        }
        return result
    }

    func glossarySuggestions(existingTerms: [String], limit: Int = 6) -> [TrackedPhrase] {
        let existing = Set(existingTerms.map { $0.lowercased(with: Locale(identifier: "de_DE")) })
        return frequentPhrases(limit: 20)
            .filter { !existing.contains($0.phrase) }
            .prefix(limit)
            .map { $0 }
    }

    /// Frequent phrases that occur in the given text (for highlighting).
    func matchPhrases(in text: String) -> [String] {
        let lowered = text.lowercased(with: Locale(identifier: "de_DE"))
        return frequentPhrases(limit: 20)
            .map(\.phrase)
            .filter { lowered.contains($0) }
    }

    // MARK: - Mutations

    func ignore(_ phrase: String) {
        guard var tracked = phrases[phrase] else { return }
        tracked.isIgnored = true
        phrases[phrase] = tracked
        scheduleSave()
    }

    func deleteAll() {
        phrases = [:]
        saveTask?.cancel()
        try? FileManager.default.removeItem(at: AppSupportPaths.phrasesURL)
    }

    // MARK: - Pruning

    private func pruneStaleOnLoad() {
        let cutoff = Date().addingTimeInterval(-TimeInterval(Self.staleAfterDays) * 86_400)
        let before = phrases.count
        phrases = phrases.filter { $0.value.lastSeenAt >= cutoff }
        if phrases.count != before {
            scheduleSave()
        }
    }

    private func pruneIfOverCap() {
        guard phrases.count > Self.maxTrackedPhrases else { return }

        // First drop one-off phrases that have not recurred for a while.
        let singleUseCutoff = Date().addingTimeInterval(-TimeInterval(Self.singleUseStaleAfterDays) * 86_400)
        phrases = phrases.filter { $0.value.count > 1 || $0.value.lastSeenAt >= singleUseCutoff }

        guard phrases.count > Self.maxTrackedPhrases else { return }

        // Still over: evict lowest-count, oldest first.
        let sorted = phrases.values.sorted {
            if $0.count != $1.count { return $0.count < $1.count }
            return $0.lastSeenAt < $1.lastSeenAt
        }
        for tracked in sorted.prefix(phrases.count - Self.maxTrackedPhrases) {
            phrases.removeValue(forKey: tracked.phrase)
        }
    }

    private func wordBoundaryContains(_ longer: String, _ shorter: String) -> Bool {
        let longerWords = longer.split(separator: " ")
        let shorterWords = shorter.split(separator: " ")
        guard shorterWords.count < longerWords.count else { return false }
        for start in 0...(longerWords.count - shorterWords.count) {
            if Array(longerWords[start..<(start + shorterWords.count)]) == shorterWords {
                return true
            }
        }
        return false
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        try? AppSupportPaths.ensureAppSupportDirectoryExists()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Array(phrases.values)) else { return }
        try? data.write(to: AppSupportPaths.phrasesURL)
    }

    private static func loadPhrases() -> [String: TrackedPhrase] {
        guard let data = try? Data(contentsOf: AppSupportPaths.phrasesURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = (try? decoder.decode([TrackedPhrase].self, from: data)) ?? []
        return Dictionary(entries.map { ($0.phrase, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
