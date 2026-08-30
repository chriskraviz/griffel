import Foundation
import Observation

/// One filed recording waiting for, or going through, an engine.
struct TranscriptionJob: Identifiable {
    enum Status {
        case queued
        case transcribing
        case rewriting
        case failed(String)

        var isQueued: Bool {
            if case .queued = self { return true }
            return false
        }

        var isRunning: Bool {
            switch self {
            case .transcribing, .rewriting: return true
            default: return false
            }
        }

        var failureText: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    let id = UUID()
    /// The library item this job fills in. The recording is already filed
    /// before the job runs, so a failure leaves something to retry rather than
    /// nothing at all.
    let itemID: UUID
    var audioURL: URL
    let displayName: String
    var configuration: AudioImportConfiguration
    var status: Status = .queued
}

/// Runs dropped recordings through the engines, one at a time — both backends
/// are single-pipeline anyway (the WhisperKit actor locally, one upload at a
/// time online), so parallelism would only make each file slower.
///
/// The queue owns no results: it writes them straight into `LibraryStore`
/// through its callbacks, so there is exactly one list of recordings in the UI.
@Observable
@MainActor
final class TranscriptionQueue {
    private(set) var jobs: [TranscriptionJob] = []

    /// Returns false when the store could not keep the transcript — a library
    /// folder that vanished mid-run, an item that is gone. The queue then holds
    /// the row as failed instead of reporting a success nobody can see.
    var onTranscript: ((_ itemID: UUID, _ transcript: String, _ duration: TimeInterval?, _ engine: String) -> Bool)?

    private var runningTask: Task<Void, Never>?
    private var runningJobID: UUID?

    var isBusy: Bool {
        jobs.contains { !($0.status.failureText != nil) }
    }

    var pendingCount: Int {
        jobs.filter { $0.status.failureText == nil }.count
    }

    func job(forItem itemID: UUID) -> TranscriptionJob? {
        jobs.first { $0.itemID == itemID }
    }

    func enqueue(itemID: UUID, audioURL: URL, displayName: String, configuration: AudioImportConfiguration) {
        jobs.append(
            TranscriptionJob(
                itemID: itemID,
                audioURL: audioURL,
                displayName: displayName,
                configuration: configuration
            )
        )
        startNextIfIdle()
    }

    func removeJob(forItem itemID: UUID) {
        guard let job = jobs.first(where: { $0.itemID == itemID }) else { return }
        jobs.removeAll { $0.itemID == itemID }
        // Removing the row the queue is working on stops that work too, rather
        // than leaving a transcription running for a file nobody waits for.
        if runningJobID == job.id {
            runningTask?.cancel()
        }
    }

    /// `audioURL` is refreshed on every retry: the recording may have been
    /// moved into another topic since the job was created, which renames the
    /// file on disk.
    func retry(itemID: UUID, audioURL: URL? = nil, configuration: AudioImportConfiguration? = nil) {
        guard let index = jobs.firstIndex(where: { $0.itemID == itemID }) else { return }
        if let audioURL { jobs[index].audioURL = audioURL }
        if let configuration { jobs[index].configuration = configuration }
        jobs[index].status = .queued
        startNextIfIdle()
    }

    func clearFailed() {
        jobs.removeAll { $0.status.failureText != nil }
    }

    // MARK: - Queue

    private func startNextIfIdle() {
        guard runningTask == nil else { return }
        guard let next = jobs.first(where: { $0.status.isQueued }) else { return }

        let jobID = next.id
        let itemID = next.itemID
        let audioURL = next.audioURL
        let configuration = next.configuration
        update(jobID) { $0.status = .transcribing }
        runningJobID = jobID

        runningTask = Task { @MainActor [weak self] in
            await self?.run(jobID: jobID, itemID: itemID, audioURL: audioURL, configuration: configuration)
            self?.runningJobID = nil
            self?.runningTask = nil
            self?.startNextIfIdle()
        }
    }

    private func run(
        jobID: UUID,
        itemID: UUID,
        audioURL: URL,
        configuration: AudioImportConfiguration
    ) async {
        do {
            let transcript = try await AudioImportService.transcribe(url: audioURL, configuration: configuration)
            try Task.checkCancellation()
            guard jobs.contains(where: { $0.id == jobID }) else { return }

            var output = transcript
            if let rewrite = configuration.rewrite {
                update(jobID) { $0.status = .rewriting }
                do {
                    output = try await AudioImportService.rewrite(text: transcript, using: rewrite)
                    try Task.checkCancellation()
                } catch is CancellationError {
                    return
                } catch {
                    // The transcript is the valuable part — keep it and say the
                    // rewrite is what failed, rather than losing both.
                    let duration = await AudioImportService.duration(of: audioURL)
                    let stored = onTranscript?(itemID, transcript, duration, configuration.engineLabel) ?? false
                    update(jobID) {
                        $0.status = .failed(stored
                            ? "Transkript fertig, Nachbearbeitung fehlgeschlagen: \(error.localizedDescription)"
                            : "Nachbearbeitung fehlgeschlagen und das Transkript konnte nicht abgelegt werden: \(error.localizedDescription)")
                    }
                    return
                }
            }

            let duration = await AudioImportService.duration(of: audioURL)
            guard onTranscript?(itemID, output, duration, configuration.engineLabel) == true else {
                // Never drop a finished transcript silently.
                update(jobID) { $0.status = .failed("Transkript fertig, konnte aber nicht abgelegt werden. Ablage-Ordner pr\u{00FC}fen.") }
                return
            }
            jobs.removeAll { $0.id == jobID }
        } catch is CancellationError {
            // The row is already gone; nothing left to report.
        } catch {
            update(jobID) { $0.status = .failed(error.localizedDescription) }
        }
    }

    private func update(_ jobID: UUID, _ mutate: (inout TranscriptionJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        mutate(&jobs[index])
    }
}
