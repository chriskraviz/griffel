import Foundation
import AppKit
import Observation

/// Voice-instructed editing of the current selection in any app:
/// capture selection (synthetic Cmd+C) → record spoken instruction →
/// transcribe → apply via LLM → the result replaces the selection through
/// the normal auto-paste path. The edit runs on the resolved LLM backend
/// (OpenAI, or the on-device MLX model in secure local mode).
@Observable
@MainActor
final class SelectionEditWorkflow: Workflow {
    let type = WorkflowType.selectionEdit
    var phase: WorkflowPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    var onOutput: WorkflowOutputHandler?
    var onPhaseChange: WorkflowPhaseChangeHandler?

    private enum Stage {
        case idle
        case capturing
        case recording
        case processing
    }

    private let recorder: AudioRecorder
    private let customTerms: [String]
    private let language: String
    private let transcriptionBackend: TranscriptionBackend
    private let localModelName: String
    private let llmBackend: LLMBackend
    private let prompts: PromptSettings
    private let extraInstructions: [String]
    private let liveTranscription: LiveTranscriptionController?
    private let autoStop: SilenceAutoStopService?

    private var stage: Stage = .idle
    private var stopDuringCaptureRequested = false
    private var capturedSelection: String?
    private var pasteboardSnapshot: SelectionCaptureService.PasteboardSnapshot?
    private var captureTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    init(
        customTerms: [String] = [],
        language: String = "de",
        transcriptionBackend: TranscriptionBackend = .remote,
        localModelName: String = LocalTranscriptionService.recommendedFastModelName,
        inputDeviceUID: String? = nil,
        llmBackend: LLMBackend = .openAI,
        prompts: PromptSettings,
        extraInstructions: [String] = [],
        liveTranscription: LiveTranscriptionController? = nil,
        autoStop: SilenceAutoStopService? = nil
    ) {
        self.customTerms = customTerms
        self.language = language
        self.transcriptionBackend = transcriptionBackend
        self.localModelName = localModelName
        self.llmBackend = llmBackend
        self.prompts = prompts
        self.extraInstructions = extraInstructions
        self.liveTranscription = liveTranscription
        self.autoStop = autoStop
        self.recorder = AudioRecorder(preferredDeviceUID: inputDeviceUID)
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

    // MARK: - Workflow Protocol

    func start() {
        stage = .capturing
        stopDuringCaptureRequested = false
        phase = .running("Auswahl wird gelesen ...")

        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let capture = try await SelectionCaptureService.captureSelectedText()
                self.capturedSelection = capture.text
                self.pasteboardSnapshot = capture.previous

                // Keys were released while we were still copying — treat as cancel.
                guard !self.stopDuringCaptureRequested else {
                    self.restoreSnapshotIfNeeded()
                    self.stage = .idle
                    self.phase = .idle
                    return
                }

                self.stage = .recording
                self.phase = .running("Anweisung sprechen ...")
                self.configureRecorderStreams()
                self.recorder.startRecording()

                if let error = self.recorder.errorMessage {
                    self.fail(error)
                }
            } catch {
                // The capture service already restored the clipboard.
                self.stage = .idle
                self.phase = .error(error.localizedDescription)
            }
        }
    }

    func stop() {
        switch stage {
        case .idle:
            phase = .idle

        case .capturing:
            stopDuringCaptureRequested = true

        case .recording:
            liveTranscription?.stop()
            recorder.stopRecording()
            guard !TranscriptionQualityService.shouldRejectRecording(duration: recorder.lastRecordingDuration) else {
                recorder.discardRecording()
                fail("Keine Anweisung erkannt.")
                return
            }
            stage = .processing
            processRecording()

        case .processing:
            processingTask?.cancel()
            restoreSnapshotIfNeeded()
            stage = .idle
            phase = .idle
        }
    }

    func reset() {
        captureTask?.cancel()
        processingTask?.cancel()
        liveTranscription?.stop()
        if recorder.isRecording {
            recorder.stopRecording()
        }
        recorder.discardRecording()
        if case .done = phase {
            // Success: the edited text intentionally stays on the clipboard.
        } else {
            restoreSnapshotIfNeeded()
        }
        stage = .idle
        phase = .idle
    }

    // MARK: - Processing

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

    private func processRecording() {
        guard let url = recorder.recordingURL,
              let selection = capturedSelection else {
            fail("Keine Aufnahme vorhanden.")
            return
        }

        phase = .running("Anweisung wird transkribiert ...")
        let recordingDuration = recorder.lastRecordingDuration
        let vocabularyHints = recordingDuration >= 0.9 ? customTerms : []

        processingTask = Task {
            defer {
                try? FileManager.default.removeItem(at: url)
            }

            do {
                let rawInstruction: String
                switch transcriptionBackend {
                case .remote:
                    rawInstruction = try await TranscriptionService.transcribe(
                        audioURL: url,
                        customTerms: vocabularyHints,
                        language: language
                    )
                case .local:
                    rawInstruction = try await LocalTranscriptionService.shared.transcribe(
                        audioURL: url,
                        language: language,
                        modelName: localModelName,
                        vocabularyHints: vocabularyHints
                    )
                }
                let instruction = TranscriptionQualityService.cleanedTranscript(rawInstruction)
                guard !TranscriptionQualityService.isLikelyArtifact(instruction, recordingDuration: recordingDuration) else {
                    fail("Keine Anweisung erkannt.")
                    return
                }

                try Task.checkCancellation()

                phase = .running(llmBackend.isLocal ? "Wird lokal angewendet ..." : "Wird angewendet ...")
                let edited = try await TextGenerationService.editSelection(
                    selection: selection,
                    instruction: instruction,
                    prompts: prompts,
                    extraInstructions: extraInstructions,
                    backend: llmBackend
                )
                let cleanedEdit = TranscriptionQualityService.cleanedTranscript(edited)

                try Task.checkCancellation()

                stage = .idle
                phase = .done(cleanedEdit)
                onOutput?(cleanedEdit)
            } catch is CancellationError {
                restoreSnapshotIfNeeded()
                stage = .idle
                phase = .idle
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        liveTranscription?.stop()
        restoreSnapshotIfNeeded()
        stage = .idle
        phase = .error(message)
    }

    private func restoreSnapshotIfNeeded() {
        guard let snapshot = pasteboardSnapshot else { return }
        pasteboardSnapshot = nil
        SelectionCaptureService.restore(snapshot)
    }
}
