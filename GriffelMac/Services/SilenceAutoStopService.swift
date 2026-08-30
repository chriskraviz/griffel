import Foundation

/// Stops a recording after a stretch of silence, fed by AudioRecorder's
/// throttled level updates (normalized 0...1, log-scaled). Arms only after
/// speech was actually heard so a run never ends before the user starts
/// talking, and fires at most once per recording.
@MainActor
final class SilenceAutoStopService {
    var onAutoStop: (() -> Void)?

    private let silenceDuration: TimeInterval
    private let speechThreshold: Float
    private let silenceThreshold: Float
    private var hasHeardSpeech = false
    private var silenceStartedAt: Date?
    private var didFire = false

    init(
        silenceDuration: TimeInterval,
        speechThreshold: Float = 0.3,
        silenceThreshold: Float = 0.2
    ) {
        self.silenceDuration = silenceDuration
        self.speechThreshold = speechThreshold
        self.silenceThreshold = silenceThreshold
    }

    func observe(level: Float) {
        guard !didFire else { return }

        if level >= speechThreshold {
            hasHeardSpeech = true
            silenceStartedAt = nil
            return
        }

        guard hasHeardSpeech else { return }

        if level >= silenceThreshold {
            silenceStartedAt = nil
            return
        }

        if let start = silenceStartedAt {
            if Date().timeIntervalSince(start) >= silenceDuration {
                didFire = true
                onAutoStop?()
            }
        } else {
            silenceStartedAt = Date()
        }
    }

    func reset() {
        hasHeardSpeech = false
        silenceStartedAt = nil
        didFire = false
    }
}
