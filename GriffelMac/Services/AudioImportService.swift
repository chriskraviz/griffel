import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum AudioImportError: LocalizedError {
    case unsupportedFormat(String)
    case unsupportedRemoteFormat(String)
    case tooLargeForRemote(Int64)
    case unreadable(String)
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return ext.isEmpty
                ? "Dateityp wird nicht unterstützt."
                : "Dateityp .\(ext) wird nicht unterstützt."
        case .unsupportedRemoteFormat(let ext):
            return "Online-Whisper nimmt .\(ext) nicht an. Im sicheren lokalen Modus geht es."
        case .tooLargeForRemote(let bytes):
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return "Zu groß für Online-Whisper (\(size), Grenze 25 MB). Im sicheren lokalen Modus gibt es kein Limit."
        case .unreadable(let reason):
            return "Datei nicht lesbar: \(reason)"
        case .noSpeech:
            return "In der Aufnahme wurde keine Sprache erkannt."
        }
    }
}

/// Everything one imported file needs to become a transcript. Captured when
/// the file is queued, so a run keeps the configuration it started with even
/// if the user flips a setting while the queue is still working.
struct AudioImportConfiguration {
    /// Optional rewrite pass after transcription, mirroring Griffel+.
    struct Rewrite {
        let settings: TextImprovementSettings
        let prompts: PromptSettings
        let extraInstructions: [String]
        let backend: LLMBackend
    }

    let backend: TranscriptionBackend
    let localModelName: String
    let language: String
    let vocabularyHints: [String]
    let removeFillers: Bool
    let rewrite: Rewrite?

    /// Recorded in the transcript's sidecar so a filed recording says which
    /// engine produced it — the same distinction the UI prints as
    /// "lokal" / "online".
    var engineLabel: String {
        var label = backend == .local ? "whisperkit:\(localModelName)" : "openai:whisper-1"
        if let rewrite {
            label += rewrite.backend.isLocal ? " + mlx" : " + openai"
        }
        return label
    }
}

/// Transcribes audio files the user dropped into the window. Same engines as
/// a spoken run — WhisperKit locally, `whisper-1` online — but fed from disk
/// instead of the microphone.
enum AudioImportService {
    /// Everything the window accepts on a drop. The per-backend check happens
    /// later, so an unsupported combination fails with a readable reason
    /// instead of silently ignoring the file.
    static let acceptedExtensions: Set<String> = [
        "aac", "aif", "aifc", "aiff", "caf", "flac", "m4a", "m4b", "m4v",
        "mov", "mp3", "mp4", "mpeg", "mpga", "oga", "ogg", "wav", "webm"
    ]

    /// What the OpenAI transcriptions endpoint accepts.
    private static let remoteExtensions: Set<String> = [
        "flac", "m4a", "mp3", "mp4", "mpeg", "mpga", "oga", "ogg", "wav", "webm"
    ]

    /// OpenAI rejects uploads above 25 MB.
    static let remoteByteLimit: Int64 = 25 * 1024 * 1024

    static func accepts(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return acceptedExtensions.contains(url.pathExtension.lowercased())
    }

    static func byteSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    static func duration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    /// Copies the file to a temporary location first: the remote path deletes
    /// the file it uploads, and the user's original must survive an import.
    static func transcribe(
        url: URL,
        configuration: AudioImportConfiguration
    ) async throws -> String {
        let fileExtension = url.pathExtension.lowercased()
        guard acceptedExtensions.contains(fileExtension) else {
            throw AudioImportError.unsupportedFormat(fileExtension)
        }

        if configuration.backend == .remote {
            guard remoteExtensions.contains(fileExtension) else {
                throw AudioImportError.unsupportedRemoteFormat(fileExtension)
            }
            let size = byteSize(of: url)
            guard size <= remoteByteLimit else {
                throw AudioImportError.tooLargeForRemote(size)
            }
        }

        let workingURL = try copyToTemporaryFile(url, fileExtension: fileExtension)
        // Idempotent: the remote path removes the upload itself, so this is
        // the cleanup for the local path and for every error in between.
        defer { try? FileManager.default.removeItem(at: workingURL) }

        let raw: String
        switch configuration.backend {
        case .remote:
            raw = try await TranscriptionService.transcribe(
                audioURL: workingURL,
                customTerms: configuration.vocabularyHints,
                language: configuration.language,
                // Neutral name: OpenAI only needs the extension to pick the
                // decoder, and the user's file name never has to leave the Mac.
                fileName: "audio.\(fileExtension)"
            )
        case .local:
            raw = try await LocalTranscriptionService.shared.transcribe(
                audioURL: workingURL,
                language: configuration.language,
                modelName: configuration.localModelName,
                vocabularyHints: configuration.vocabularyHints
            )
        }

        var text = TranscriptionQualityService.cleanedTranscript(raw)
        if configuration.removeFillers {
            text = FillerWordService.removeFillers(from: text)
        }
        guard !text.isEmpty else { throw AudioImportError.noSpeech }
        return text
    }

    static func rewrite(
        text: String,
        using rewrite: AudioImportConfiguration.Rewrite
    ) async throws -> String {
        let improved = try await TextGenerationService.improve(
            text: text,
            settings: rewrite.settings,
            prompts: rewrite.prompts,
            extraInstructions: rewrite.extraInstructions,
            backend: rewrite.backend
        )
        let cleaned = TranscriptionQualityService.cleanedTranscript(improved)
        return cleaned.isEmpty ? text : cleaned
    }

    private static func copyToTemporaryFile(_ url: URL, fileExtension: String) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw AudioImportError.unreadable(url.lastPathComponent)
        }

        let destination = fileManager.temporaryDirectory
            .appendingPathComponent("vc-import-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        do {
            try fileManager.copyItem(at: url, to: destination)
        } catch {
            throw AudioImportError.unreadable(error.localizedDescription)
        }
        return destination
    }
}
