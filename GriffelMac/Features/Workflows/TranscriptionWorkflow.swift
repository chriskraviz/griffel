import Foundation
import AppKit
import Observation
import OSLog

private let transcriptionLogger = Logger(subsystem: "app.griffel.mac", category: "Transcription")

private func elapsedMilliseconds(since start: Date, until end: Date = Date()) -> Int {
    Int((end.timeIntervalSince(start) * 1000).rounded())
}

@Observable
@MainActor
final class TranscriptionWorkflow: Workflow {
    let type: WorkflowType
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    private let recorder: AudioRecorder
    private let customTerms: [String]
    private let language: String
    private let backend: TranscriptionBackend
    private let localModelName: String
    private let removeFillers: Bool
    private let formatProfile: FormatProfile?
    private let llmBackend: LLMBackend?
    private let extraInstructions: [String]
    private let liveTranscription: LiveTranscriptionController?
    private let autoStop: SilenceAutoStopService?
    private var transcriptionTask: Task<Void, Never>?

    init(
        type: WorkflowType = .transcription,
        customTerms: [String] = [],
        language: String = "de",
        backend: TranscriptionBackend = .remote,
        localModelName: String = LocalTranscriptionService.recommendedFastModelName,
        inputDeviceUID: String? = nil,
        removeFillers: Bool = false,
        formatProfile: FormatProfile? = nil,
        llmBackend: LLMBackend? = nil,
        extraInstructions: [String] = [],
        liveTranscription: LiveTranscriptionController? = nil,
        autoStop: SilenceAutoStopService? = nil
    ) {
        self.type = type
        self.customTerms = customTerms
        self.language = language
        self.backend = backend
        self.localModelName = localModelName
        self.removeFillers = removeFillers
        self.formatProfile = formatProfile
        self.llmBackend = llmBackend
        self.extraInstructions = extraInstructions
        self.liveTranscription = liveTranscription
        self.autoStop = autoStop
        self.recorder = AudioRecorder(preferredDeviceUID: inputDeviceUID)
    }

    func start() {
        configureRecorderStreams()
        phase = .running("Aufnahme läuft ...")
        recorder.startRecording()

        if let error = recorder.errorMessage {
            liveTranscription?.stop()
            phase = .error(error)
        }
    }

    func stop() {
        if recorder.isRecording {
            liveTranscription?.stop()
            recorder.stopRecording()
            guard !TranscriptionQualityService.shouldRejectRecording(duration: recorder.lastRecordingDuration) else {
                recorder.discardRecording()
                phase = .error("Keine Aufnahme erkannt.")
                return
            }
            transcribe()
        } else {
            transcriptionTask?.cancel()
            phase = .idle
        }
    }

    func reset() {
        transcriptionTask?.cancel()
        liveTranscription?.stop()
        if recorder.isRecording {
            recorder.stopRecording()
        }
        recorder.discardRecording()
        phase = .idle
    }

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }
    var lastRecordingDuration: TimeInterval { recorder.lastRecordingDuration }
    var activeInputDevice: ActiveInputDevice? { recorder.activeInputDevice }

    var livePartialText: String? {
        guard let liveTranscription, isRecording else { return nil }
        let text = liveTranscription.partialText
        return text.isEmpty ? nil : text
    }

    private func configureRecorderStreams() {
        if let liveTranscription {
            recorder.onConvertedBuffer = { [weak liveTranscription] samples in
                liveTranscription?.append(samples)
            }
            liveTranscription.start()
        }
        if let autoStop {
            recorder.onLevelSample = { [weak autoStop] level in
                autoStop?.observe(level: level)
            }
            autoStop.onAutoStop = { [weak self] in
                guard let self, self.isRecording else { return }
                self.stop()
            }
        }
    }

    private func transcribe() {
        guard let url = recorder.recordingURL else {
            phase = .error("Keine Aufnahme vorhanden.")
            return
        }

        phase = .running(backend == .local ? "Wird lokal transkribiert ..." : "Wird transkribiert ...")
        let recordingDuration = recorder.lastRecordingDuration
        let vocabularyHints = recordingDuration >= 0.9 ? customTerms : []
        let requestLanguage = language
        let stopTime = Date()

        transcriptionTask = Task(priority: .userInitiated) {
            defer {
                try? FileManager.default.removeItem(at: url)
            }

            let requestStart = Date()
            do {
                let text: String
                switch backend {
                case .remote:
                    text = try await TranscriptionService.transcribe(
                        audioURL: url,
                        customTerms: vocabularyHints,
                        language: requestLanguage
                    )
                case .local:
                    text = try await LocalTranscriptionService.shared.transcribe(
                        audioURL: url,
                        language: requestLanguage,
                        modelName: localModelName,
                        vocabularyHints: vocabularyHints
                    )
                }
                try Task.checkCancellation()

                let responseReceivedAt = Date()
                var cleaned = TranscriptionQualityService.cleanedTranscript(text)
                if removeFillers {
                    cleaned = FillerWordService.removeFillers(from: cleaned)
                }
                guard !TranscriptionQualityService.isLikelyArtifact(cleaned, recordingDuration: recordingDuration) else {
                    transcriptionLogger.info(
                        "Transcription rejected short artifact after \(elapsedMilliseconds(since: stopTime)) ms"
                    )
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }

                transcriptionLogger.info(
                    "Transcription ready in \(elapsedMilliseconds(since: stopTime, until: responseReceivedAt)) ms (request \(elapsedMilliseconds(since: requestStart, until: responseReceivedAt)) ms)"
                )

                var output = cleaned
                // Formatting is an extra LLM pass; it only runs when a
                // backend was resolved (in secure local mode that is the
                // on-device model, never OpenAI — the privacy story stays
                // honest).
                if let formatProfile, let llmBackend {
                    phase = .running(llmBackend.isLocal ? "Wird lokal formatiert ..." : "Wird formatiert ...")
                    let formatted = try await TextGenerationService.formatTranscript(
                        text: cleaned,
                        profile: formatProfile,
                        extraInstructions: extraInstructions,
                        backend: llmBackend
                    )
                    try Task.checkCancellation()
                    output = TranscriptionQualityService.cleanedTranscript(formatted)
                }

                phase = .done(output)
                onOutput?(output)
            } catch {
                transcriptionLogger.error(
                    "Transcription failed after \(elapsedMilliseconds(since: stopTime)) ms: \(error.localizedDescription, privacy: .private)"
                )
                phase = .error(error.localizedDescription)
            }
        }
    }
}
