import Foundation
import HuggingFace
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// One selectable local rewrite model. Mirrors `LocalTranscriptionModel` so the
/// settings UI can treat both model families the same way.
struct LocalLLMModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let sizeLabel: String
    let isInstalled: Bool
}

/// Every failure on the rewrite path must surface as one of these: callers
/// catch `LocalLLMError` to preserve the raw transcript on the clipboard, so an
/// escaping MLX or Hub error would silently cost the user their dictation.
enum LocalLLMError: LocalizedError {
    case modelNotInstalled(String)
    case downloadFailed(String)
    case loadFailed(String)
    case generationFailed(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let name):
            return "Lokales Sprachmodell fehlt: \(name). Bitte auf der Hauptseite laden."
        case .downloadFailed(let message):
            return "Das Sprachmodell konnte nicht geladen werden: \(message)"
        case .loadFailed(let message):
            return "Das lokale Sprachmodell konnte nicht gestartet werden: \(message)"
        case .generationFailed(let message):
            return "Die lokale Überarbeitung ist fehlgeschlagen: \(message)"
        case .noContent:
            return "Das lokale Sprachmodell hat keinen Text zurückgegeben. Bitte nochmal versuchen."
        }
    }
}

/// Runs the rewrite features on-device through MLX. Replaces the old Ollama
/// integration: no server to install, no loopback HTTP — the weights live in
/// Application Support and inference happens in-process on the GPU.
///
/// Apple Silicon only. MLX computes through Metal against unified memory and
/// has no x86_64 backend, which is why the app dropped its universal build.
actor LocalLLMService {
    static let shared = LocalLLMService()

    /// Qwen3 in 4-bit. The sizes are the on-disk download, not resident memory.
    private static let catalog: [(configuration: ModelConfiguration, displayName: String, sizeLabel: String)] = [
        (LLMRegistry.qwen3_1_7b_4bit, "Qwen3 1.7B", "≈ 1,0 GB"),
        (LLMRegistry.qwen3_4b_4bit, "Qwen3 4B", "≈ 2,3 GB"),
        (LLMRegistry.qwen3_8b_4bit, "Qwen3 8B", "≈ 4,7 GB"),
    ]

    static let defaultModelID = LLMRegistry.qwen3_4b_4bit.name

    private static let maxGeneratedTokens = 4096

    private var container: ModelContainer?
    private var loadedModelID: String?

    // MARK: - Catalog

    static func normalizedModelID(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultModelID : trimmed
    }

    static func displayName(for modelID: String) -> String {
        let normalized = normalizedModelID(modelID)
        return catalog.first { $0.configuration.name == normalized }?.displayName
            ?? normalized.split(separator: "/").last.map(String.init)
            ?? normalized
    }

    static func modelOptions() -> [LocalLLMModel] {
        catalog.map { entry in
            LocalLLMModel(
                id: entry.configuration.name,
                displayName: entry.displayName,
                sizeLabel: entry.sizeLabel,
                isInstalled: isModelInstalled(entry.configuration.name)
            )
        }
    }

    private static func configuration(for modelID: String) -> ModelConfiguration {
        let normalized = normalizedModelID(modelID)
        if let known = catalog.first(where: { $0.configuration.name == normalized }) {
            return known.configuration
        }
        // Unknown repo ids stay loadable — Qwen's end-of-turn token is the one
        // piece the registry entries add over a bare id.
        return ModelConfiguration(id: normalized, extraEOSTokens: ["<|im_end|>"])
    }

    // MARK: - Installation

    private static var cache: HubCache {
        HubCache(cacheDirectory: AppSupportPaths.mlxModelsDirectoryURL)
    }

    private static func hubClient() -> HubClient {
        HubClient(cache: cache)
    }

    /// True when the weights are already on disk, so a rewrite can start
    /// without touching the network.
    static func isModelInstalled(_ modelID: String) -> Bool {
        guard let snapshot = snapshotDirectory(for: normalizedModelID(modelID)) else { return false }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: snapshot.appendingPathComponent("config.json").path) else {
            return false
        }
        let contents = (try? fileManager.contentsOfDirectory(atPath: snapshot.path)) ?? []
        return contents.contains { $0.hasSuffix(".safetensors") }
    }

    private static func snapshotDirectory(for modelID: String) -> URL? {
        guard let repo = Repo.ID(rawValue: modelID) else { return nil }
        let cache = cache
        guard let commit = cache.resolveRevision(repo: repo, kind: .model, ref: "main") else {
            return nil
        }
        return try? cache.snapshotPath(repo: repo, kind: .model, commitHash: commit)
    }

    /// Downloads the weights and keeps the loaded model warm for the first run.
    func downloadAndInstall(
        modelID: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let normalized = Self.normalizedModelID(modelID)
        do {
            let loaded = try await Self.downloadContainer(modelID: normalized, progressHandler: progressHandler)
            container = loaded
            loadedModelID = normalized
            progressHandler(1)
        } catch {
            throw LocalLLMError.downloadFailed(error.localizedDescription)
        }
    }

    /// Loads the model into memory ahead of the first rewrite. Silent by design:
    /// a failed prewarm must not surface as an error, the real run reports it.
    func prepare(modelID: String) async throws {
        _ = try await modelContainer(modelID: modelID)
    }

    // MARK: - Generation

    func chat(
        text: String,
        systemPrompt: String,
        modelID: String,
        temperature: Double = 0.3
    ) async throws -> String {
        let container = try await modelContainer(modelID: modelID)

        var parameters = GenerateParameters()
        parameters.temperature = Float(temperature)
        // A 4-bit model can fall into a repetition loop on stuttered dictation
        // and then never emit its end token. Nothing else bounds this run — the
        // Ollama transport timeout this replaced is gone — so cap it. Generous
        // for a rewrite; a braindump digest lands far below it.
        parameters.maxTokens = Self.maxGeneratedTokens

        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: parameters,
            // Qwen3 is a hybrid reasoning model. A rewrite must return the text
            // and nothing else, so the thinking pass is switched off in the
            // chat template rather than filtered out afterwards.
            additionalContext: ["enable_thinking": false]
        )

        let response: String
        do {
            response = try await session.respond(to: text)
        } catch {
            throw LocalLLMError.generationFailed(error.localizedDescription)
        }
        let cleaned = Self.strippingReasoning(response)

        guard !cleaned.isEmpty else {
            throw LocalLLMError.noContent
        }
        return cleaned
    }

    private func modelContainer(modelID: String) async throws -> ModelContainer {
        let normalized = Self.normalizedModelID(modelID)
        if let container, loadedModelID == normalized {
            return container
        }

        // Load straight from the snapshot on disk. Going through the hub
        // downloader would contact huggingface.co to check for a newer revision
        // even when the weights are already local — which would both stall the
        // run on a bad network and break the promise that nothing leaves the
        // Mac in secure local mode.
        guard Self.isModelInstalled(normalized),
              let snapshot = Self.snapshotDirectory(for: normalized) else {
            throw LocalLLMError.modelNotInstalled(Self.displayName(for: normalized))
        }

        let loaded: ModelContainer
        do {
            loaded = try await loadModelContainer(
                from: snapshot,
                using: #huggingFaceTokenizerLoader()
            )
        } catch {
            throw LocalLLMError.loadFailed(error.localizedDescription)
        }
        container = loaded
        loadedModelID = normalized
        return loaded
    }

    /// Download path only — this is the one place that is allowed to reach the
    /// network. The run path loads from disk, see `modelContainer(modelID:)`.
    private static func downloadContainer(
        modelID: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> ModelContainer {
        try await loadModelContainer(
            from: #hubDownloader(hubClient()),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration(for: modelID),
            progressHandler: { progress in
                let fraction = progress.fractionCompleted
                progressHandler(fraction.isFinite ? fraction : 0)
            }
        )
    }

    /// Safety net for the `enable_thinking` switch: templates that ignore the
    /// flag still emit a `<think>` block, which must never reach the clipboard.
    private static func strippingReasoning(_ text: String) -> String {
        var result = text
        while let start = result.range(of: "<think>"),
              let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // An unterminated block means the model ran out of budget mid-thought;
        // everything after the opening tag is reasoning, not output.
        if let start = result.range(of: "<think>") {
            result.removeSubrange(start.lowerBound..<result.endIndex)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
