import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class TextImprovementWorkflow: Workflow {
    let type = WorkflowType.textImprover
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    private let recorder: AudioRecorder
    private let settings: TextImprovementSettings
    private let customTerms: [String]
    private let language: String
    private let transcriptionBackend: TranscriptionBackend
    private let localModelName: String
    private let removeFillers: Bool
    private let llmBackend: LLMBackend
    private let prompts: PromptSettings
    private let extraInstructions: [String]
    private let liveTranscription: LiveTranscriptionController?
    private let autoStop: SilenceAutoStopService?
    private var processingTask: Task<Void, Never>?

    init(
        settings: TextImprovementSettings,
        customTerms: [String] = [],
        language: String = "de",
        transcriptionBackend: TranscriptionBackend = .remote,
        localModelName: String = LocalTranscriptionService.recommendedFastModelName,
        inputDeviceUID: String? = nil,
        removeFillers: Bool = false,
        llmBackend: LLMBackend = .openAI,
        prompts: PromptSettings,
        extraInstructions: [String] = [],
        liveTranscription: LiveTranscriptionController? = nil,
        autoStop: SilenceAutoStopService? = nil
    ) {
        self.settings = settings
        self.customTerms = customTerms
        self.language = language
        self.transcriptionBackend = transcriptionBackend
        self.localModelName = localModelName
        self.removeFillers = removeFillers
        self.llmBackend = llmBackend
        self.prompts = prompts
        self.extraInstructions = extraInstructions
        self.liveTranscription = liveTranscription
        self.autoStop = autoStop
        self.recorder = AudioRecorder(preferredDeviceUID: inputDeviceUID)
    }

    // MARK: - Recording State

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }
    var lastRecordingDuration: TimeInterval { recorder.lastRecordingDuration }
    var activeInputDevice: ActiveInputDevice? { recorder.activeInputDevice }

    var livePartialText: String? {
        guard let liveTranscription, isRecording else { return nil }
        let text = liveTranscription.partialText
        return text.isEmpty ? nil : text
    }

    // MARK: - Workflow Protocol

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
            processRecording()
        } else {
            processingTask?.cancel()
            phase = .idle
        }
    }

    func reset() {
        processingTask?.cancel()
        liveTranscription?.stop()
        if recorder.isRecording {
            recorder.stopRecording()
        }
        recorder.discardRecording()
        phase = .idle
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

    // MARK: - Two-Phase Processing: Whisper -> GPT

    private func processRecording() {
        guard let url = recorder.recordingURL else {
            phase = .error("Keine Aufnahme vorhanden.")
            return
        }

        phase = .running(transcriptionBackend == .local ? "Wird lokal transkribiert ..." : "Wird transkribiert ...")
        let recordingDuration = recorder.lastRecordingDuration
        let vocabularyHints = recordingDuration >= 0.9 ? customTerms : []

        processingTask = Task {
            defer {
                try? FileManager.default.removeItem(at: url)
            }

            do {
                // Phase 1: Whisper transcription
                let rawText: String
                switch transcriptionBackend {
                case .remote:
                    rawText = try await TranscriptionService.transcribe(
                        audioURL: url,
                        customTerms: vocabularyHints,
                        language: language
                    )
                case .local:
                    rawText = try await LocalTranscriptionService.shared.transcribe(
                        audioURL: url,
                        language: language,
                        modelName: localModelName,
                        vocabularyHints: vocabularyHints
                    )
                }
                var cleanedRawText = TranscriptionQualityService.cleanedTranscript(rawText)
                if removeFillers && llmBackend.isLocal {
                    // Applied locally instead of relying on the prompt:
                    // small local models follow instructions less reliably.
                    cleanedRawText = FillerWordService.removeFillers(from: cleanedRawText)
                }
                guard !TranscriptionQualityService.isLikelyArtifact(cleanedRawText, recordingDuration: recordingDuration) else {
                    phase = .error("Keine Aufnahme erkannt.")
                    return
                }

                if Task.isCancelled { return }

                // Phase 2: LLM improvement
                phase = .running(llmBackend.isLocal ? "Wird lokal verbessert ..." : "Text wird verbessert ...")

                let improved: String
                do {
                    improved = try await TextGenerationService.improve(
                        text: cleanedRawText,
                        settings: settings,
                        prompts: prompts,
                        extraInstructions: extraInstructions,
                        backend: llmBackend
                    )
                } catch let error as LocalLLMError {
                    // The spoken words are otherwise unrecoverable — keep
                    // the transcript so the dictation is not lost.
                    preserveTranscriptOnClipboard(cleanedRawText)
                    phase = .error(error.localizedDescription + " Das Roh-Transkript liegt in der Zwischenablage.")
                    return
                }

                let cleanedImproved = TranscriptionQualityService.cleanedTranscript(improved)
                phase = .done(cleanedImproved)
                onOutput?(cleanedImproved)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    private func preserveTranscriptOnClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
