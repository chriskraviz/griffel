import Foundation
import Observation

struct UsageEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    /// Stored as a raw string so events from newer app versions still decode.
    let workflowRawValue: String
    let wordCount: Int
    let recordingDuration: TimeInterval
    let processingDuration: TimeInterval
}

/// Local-only usage log backing the statistics page. Never leaves the Mac.
@Observable
@MainActor
final class StatsStore {
    static let shared = StatsStore()

    /// Average typing speed used for the "Zeit gespart" estimate.
    static let assumedTypingWordsPerMinute = 40.0

    private static let maxEvents = 20_000

    private(set) var events: [UsageEvent] = []
    private var saveTask: Task<Void, Never>?

    private init() {
        events = Self.loadEvents()
    }

    func record(
        workflowType: WorkflowType,
        wordCount: Int,
        recordingDuration: TimeInterval,
        processingDuration: TimeInterval
    ) {
        let event = UsageEvent(
            id: UUID(),
            date: Date(),
            workflowRawValue: workflowType.rawValue,
            wordCount: wordCount,
            recordingDuration: max(0, recordingDuration),
            processingDuration: max(0, processingDuration)
        )
        events.append(event)
        if events.count > Self.maxEvents {
            events.removeFirst(events.count - Self.maxEvents)
        }
        scheduleSave()
    }

    // MARK: - Aggregates

    var totalWords: Int {
        events.reduce(0) { $0 + $1.wordCount }
    }

    var totalSessions: Int {
        events.count
    }

    var averageWordsPerSession: Int {
        guard !events.isEmpty else { return 0 }
        return totalWords / events.count
    }

    /// `max(0, words / 40 WPM − (recording + processing))` summed per event.
    var estimatedTimeSavedSeconds: TimeInterval {
        events.reduce(0) { partial, event in
            let typingSeconds = Double(event.wordCount) / Self.assumedTypingWordsPerMinute * 60
            return partial + max(0, typingSeconds - event.recordingDuration - event.processingDuration)
        }
    }

    struct WeekBucket: Identifiable {
        let weekStart: Date
        let words: Int
        var id: Date { weekStart }
    }

    func wordsByWeek(lastWeeks: Int) -> [WeekBucket] {
        let calendar = Calendar.current
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return []
        }

        var buckets: [Date: Int] = [:]
        var weekStarts: [Date] = []
        for offset in stride(from: -(lastWeeks - 1), through: 0, by: 1) {
            if let weekStart = calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeekStart) {
                buckets[weekStart] = 0
                weekStarts.append(weekStart)
            }
        }

        for event in events {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: event.date)?.start,
                  buckets[weekStart] != nil else {
                continue
            }
            buckets[weekStart, default: 0] += event.wordCount
        }

        return weekStarts.map { WeekBucket(weekStart: $0, words: buckets[$0] ?? 0) }
    }

    struct WorkflowShare: Identifiable {
        let name: String
        let words: Int
        var id: String { name }
    }

    /// Workflows that no longer exist but whose events are still in the log.
    /// Without this the chart legend would print the bare slug and read like a
    /// bug — the history itself stays intact either way.
    private static let retiredWorkflowNames: [String: String] = [
        "dampfAblassen": "Griffel $%&! (entfernt)",
        "emojiText": "Griffel :) (entfernt)",
        "ollamaImprover": "Griffel Lokal+ (zusammengeführt)",
        "localTranscription": "Griffel Lokal (entfernt)",
    ]

    var wordsByWorkflow: [WorkflowShare] {
        var byRawValue: [String: Int] = [:]
        for event in events {
            byRawValue[event.workflowRawValue, default: 0] += event.wordCount
        }
        return byRawValue
            .map { rawValue, words in
                WorkflowShare(
                    name: WorkflowType(rawValue: rawValue)?.displayName
                        ?? Self.retiredWorkflowNames[rawValue]
                        ?? rawValue,
                    words: words
                )
            }
            .sorted { $0.words > $1.words }
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
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: AppSupportPaths.statsURL)
    }

    private static func loadEvents() -> [UsageEvent] {
        guard let data = try? Data(contentsOf: AppSupportPaths.statsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageEvent].self, from: data)) ?? []
    }
}
