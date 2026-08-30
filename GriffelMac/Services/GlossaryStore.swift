import Foundation

// MARK: - Glossary Models

struct GlossaryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var term: String
    var definition: String = ""
}

struct GlossarySettings: Codable {
    var entries: [GlossaryEntry] = []
    var didImportLegacyTerms: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case entries
        case didImportLegacyTerms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([GlossaryEntry].self, forKey: .entries) ?? []
        didImportLegacyTerms = try container.decodeIfPresent(Bool.self, forKey: .didImportLegacyTerms) ?? false
    }
}

// MARK: - Prompt Building

enum GlossaryPromptBuilder {
    /// Terms for the Whisper `prompt` bias hint (remote) and prompt tokens (local).
    static func whisperHintTerms(_ settings: GlossarySettings) -> [String] {
        settings.entries
            .map { $0.term.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Instruction for LLM system prompts, including definitions when present.
    static func llmInstruction(_ settings: GlossarySettings) -> String? {
        let parts = settings.entries.compactMap { entry -> String? in
            let term = entry.term.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { return nil }
            let definition = entry.definition.trimmingCharacters(in: .whitespaces)
            return definition.isEmpty ? term : "\(term) (= \(definition))"
        }
        guard !parts.isEmpty else { return nil }
        return "Wichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: \(parts.joined(separator: ", "))"
    }

    static func denglishInstruction(for mode: LanguageMode) -> String? {
        guard mode == .autoDenglish else { return nil }
        return "Der Text kann Deutsch und Englisch mischen (Denglish). Behalte englische Begriffe und Fachausdruecke exakt bei und uebersetze sie nicht."
    }
}
