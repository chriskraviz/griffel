import Foundation

/// Removes spoken filler words from transcripts.
/// Tier 1 (`removeFillers`) is a conservative local pass for plain
/// transcription; tier 2 (`llmInstruction`) lets the LLM handle the
/// ambiguous fillers context-aware in rewrite workflows.
enum FillerWordService {
    /// Only unambiguous hesitation sounds are removed as standalone words.
    /// "um" and "like" carry meaning in German/English and are only removed
    /// when they are clearly parenthetical (delimited by commas).
    private static let unambiguousFillers = #"ähm+|ähh+|äh|ehm+|öhm+|hmm+|hm|mhm+|uhm+|erm+"#
    private static let commaDelimitedFillers = #"ähm+|ähh+|äh|ehm+|öhm+|hmm+|hm|mhm+|uhm+|erm+|um|like|you know"#

    static func removeFillers(from text: String) -> String {
        var result = text

        // ", filler," is a parenthetical hesitation — both commas go.
        result = replacing("(?i),\\s*(?:\(commaDelimitedFillers))\\s*,", in: result, with: " ")
        // ", filler." before sentence end keeps only the closing punctuation.
        result = replacing("(?i),\\s*(?:\(commaDelimitedFillers))\\s*([.!?;:])", in: result, with: "$1")
        // Remaining standalone hesitation sounds.
        result = replacing("(?i)\\b(?:\(unambiguousFillers))\\b", in: result, with: "")

        // Tidy up what the removals left behind.
        result = replacing(#"\s+([,.!?;:])"#, in: result, with: "$1")
        result = replacing(#",{2,}"#, in: result, with: ",")
        result = replacing(#"([.!?]),"#, in: result, with: "$1")
        result = replacing(#"^\s*[,;:]\s*"#, in: result, with: "")
        result = replacing(#"([.!?])\s*[,;:]\s*"#, in: result, with: "$1 ")
        result = replacing(#"\s{2,}"#, in: result, with: " ")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only punctuation left means the recording was fillers-only.
        if result.range(of: #"^[\s,.!?;:…\-–]*$"#, options: .regularExpression) != nil {
            return ""
        }

        return capitalizingSentenceStarts(result)
    }

    /// Context-aware instruction for LLM rewrite flows (covers the ambiguous list).
    static let llmInstruction = """
    Entferne Fuellwoerter und Verzoegerungslaute (z.B. aehm, aeh, hm, halt, quasi, sozusagen, \
    im Prinzip, like, um, you know), wenn sie keine inhaltliche Bedeutung tragen. \
    Behalte Woerter, die im Satz eine echte Funktion haben (z.B. "um 5 Uhr", "halt fest").
    """

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func capitalizingSentenceStarts(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var characters = Array(text)
        var capitalizeNext = true
        for index in characters.indices {
            let character = characters[index]
            if capitalizeNext, character.isLetter {
                characters[index] = Character(String(character).uppercased())
                capitalizeNext = false
            } else if ".!?".contains(character) {
                capitalizeNext = true
            } else if !character.isWhitespace {
                capitalizeNext = false
            }
        }
        return String(characters)
    }
}
