import Foundation

// MARK: - Backend Selection

/// The backend resolved for one workflow run. Carries the local model settings
/// as a value so a run keeps the configuration it started with even if the
/// user edits the settings mid-run.
enum LLMBackend {
    case openAI
    case local(LocalLLMSettings)

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
}

/// Provider boundary for every rewrite/organize feature: the feature prompts
/// live here once and run against either LLMService (OpenAI) or the on-device
/// MLX model. Errors keep their provider type (LLMError / LocalLLMError) so
/// callers can react — e.g. preserving the raw transcript on the clipboard when
/// the local step fails.
enum TextGenerationService {
    // MARK: - Features

    static func improve(
        text: String,
        settings: TextImprovementSettings,
        prompts: PromptSettings,
        extraInstructions: [String] = [],
        backend: LLMBackend
    ) async throws -> String {
        try await run(
            text: text,
            systemPrompt: improveSystemPrompt(settings: settings, prompts: prompts),
            extraInstructions: extraInstructions,
            openAIModel: .fastEdit,
            temperature: 0.3,
            backend: backend
        )
    }

    static func editSelection(
        selection: String,
        instruction: String,
        prompts: PromptSettings,
        extraInstructions: [String] = [],
        backend: LLMBackend
    ) async throws -> String {
        let systemPrompt = prompts.effectiveSelectionEdit
        let userMessage = """
        Anweisung: \(instruction)

        Markierter Text:
        \(selection)
        """
        return try await run(
            text: userMessage,
            systemPrompt: systemPrompt,
            extraInstructions: extraInstructions,
            openAIModel: .quality,
            temperature: 0.2,
            backend: backend
        )
    }

    static func formatTranscript(
        text: String,
        profile: FormatProfile,
        extraInstructions: [String] = [],
        backend: LLMBackend
    ) async throws -> String {
        let systemPrompt = """
        Du erhaeltst ein gesprochenes Transkript. Bereite es fuer sein Ziel auf. \(profile.promptInstruction) \
        Behalte die Bedeutung exakt bei und gib NUR den formatierten Text zurueck, keine Erklaerungen.
        """
        return try await run(
            text: text,
            systemPrompt: systemPrompt,
            extraInstructions: extraInstructions,
            openAIModel: .fastEdit,
            temperature: 0.2,
            backend: backend
        )
    }

    static func organizeBraindump(
        entries: [String],
        prompts: PromptSettings,
        extraInstructions: [String] = [],
        backend: LLMBackend
    ) async throws -> String {
        let systemPrompt = prompts.effectiveBraindump
        return try await run(
            text: entries.joined(separator: "\n"),
            systemPrompt: systemPrompt,
            extraInstructions: extraInstructions,
            openAIModel: .quality,
            temperature: 0.3,
            backend: backend
        )
    }

    // MARK: - Routing

    private static func run(
        text: String,
        systemPrompt: String,
        extraInstructions: [String],
        openAIModel: RewriteModel,
        temperature: Double,
        backend: LLMBackend
    ) async throws -> String {
        let fullPrompt = appending(extraInstructions, to: systemPrompt)
        switch backend {
        case .openAI:
            return try await LLMService.complete(
                text: text,
                systemPrompt: fullPrompt,
                model: openAIModel,
                temperature: temperature
            )
        case .local(let settings):
            return try await LocalLLMService.shared.chat(
                text: text,
                systemPrompt: fullPrompt,
                modelID: settings.modelID,
                temperature: temperature
            )
        }
    }

    private static func appending(_ extraInstructions: [String], to systemPrompt: String) -> String {
        guard !extraInstructions.isEmpty else { return systemPrompt }
        return systemPrompt + "\n\n" + extraInstructions.joined(separator: "\n")
    }

    // MARK: - Prompts

    /// The prompt follows the user's `rewriteScope`: `.korrektur` cleans the
    /// dictation up and leaves the wording alone, `.lektorat` rewrites it and
    /// honours tone + context. Both texts are editable on the Prompts page;
    /// `PromptSettings` falls back to `PromptDefaults` when they are untouched.
    /// Glossary terms apply either way — a name has to be spelled right in
    /// both modes.
    private static func improveSystemPrompt(
        settings: TextImprovementSettings,
        prompts: PromptSettings
    ) -> String {
        var prompt: String

        switch settings.rewriteScope {
        case .korrektur:
            prompt = prompts.effectiveKorrektur

        case .lektorat:
            prompt = prompts.effectiveLektorat

            switch settings.tone {
            case .formal:
                prompt += "\n- Verwende einen formellen, professionellen Ton"
            case .neutral:
                prompt += "\n- Verwende einen neutralen, klaren Ton"
            case .casual:
                prompt += "\n- Verwende einen lockeren, natuerlichen Ton"
            }
        }

        if !settings.customTerms.isEmpty {
            prompt += "\n\nWichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: \(settings.customTerms.joined(separator: ", "))"
        }

        if settings.rewriteScope.usesToneAndContext,
           !settings.context.isEmpty {
            prompt += "\n\nKontext: \(settings.context)"
        }

        return prompt
    }
}
