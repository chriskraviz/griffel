import Foundation
import Observation

/// Publishes a rolling partial transcript while recording by periodically
/// re-transcribing the accumulating 16 kHz buffer with WhisperKit. Local-only
/// and purely cosmetic: the final paste always comes from the batch pass over
/// the finished recording, so a bad or missed partial never affects output.
@Observable
@MainActor
final class LiveTranscriptionController {
    private(set) var partialText: String = ""

    private let modelName: String
    private let language: String
    private let vocabularyHints: [String]
    private var samples: [Float] = []
    private var tickTask: Task<Void, Never>?
    private var isTranscribing = false

    private static let tickInterval: TimeInterval = 1.5
    private static let sampleRate = 16_000
    private static let minimumSampleCount = sampleRate
    /// Partials freeze beyond this window so re-transcription cost stays
    /// bounded on long dictations; the final pass still covers everything.
    private static let maximumSampleCount = 120 * sampleRate

    init(modelName: String, language: String, vocabularyHints: [String] = []) {
        self.modelName = modelName
        self.language = language
        self.vocabularyHints = vocabularyHints
    }

    func append(_ newSamples: [Float]) {
        guard tickTask != nil, samples.count < Self.maximumSampleCount else { return }
        samples.append(contentsOf: newSamples)
    }

    func start() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tickInterval))
                guard !Task.isCancelled else { return }
                await self?.tick()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        samples = []
    }

    private func tick() async {
        guard !isTranscribing else { return }
        let snapshot = samples
        guard snapshot.count >= Self.minimumSampleCount else { return }

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let text = try await LocalTranscriptionService.shared.transcribeSamples(
                snapshot,
                language: language,
                modelName: modelName,
                vocabularyHints: vocabularyHints
            )
            guard tickTask != nil else { return }

            let cleaned = TranscriptionQualityService.cleanedTranscript(text)
            let duration = Double(snapshot.count) / Double(Self.sampleRate)
            if !cleaned.isEmpty,
               !TranscriptionQualityService.isLikelyArtifact(cleaned, recordingDuration: duration) {
                partialText = cleaned
            }
        } catch {
            // Partials are cosmetic — errors are ignored, the batch pass decides.
        }
    }
}
