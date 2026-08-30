import Foundation

/// Pure text -> n-gram extraction for the frequent-phrase feature.
/// German-aware and deterministic; never stores or returns anything but
/// normalized 2-4-word phrases.
enum PhraseDetectionService {
    static let minWordsPerPhrase = 2
    static let maxWordsPerPhrase = 4
    static let minWordLength = 2

    /// Articles, pronouns, prepositions, conjunctions, auxiliaries, modal
    /// particles, and common fillers. Phrases may contain these inside
    /// ("grüße aus dem büro"), but never at the edges.
    static let germanStopwords: Set<String> = [
        // Articles
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines",
        // Pronouns
        "ich", "du", "er", "sie", "es", "wir", "ihr", "mich", "dich", "sich", "uns", "euch",
        "mir", "dir", "ihm", "ihnen", "mein", "meine", "meinen", "meinem", "meiner", "meins",
        "dein", "deine", "deinen", "deinem", "deiner", "sein", "seine", "seinen", "seinem", "seiner",
        "ihre", "ihren", "ihrem", "ihrer", "unser", "unsere", "unseren", "unserem", "unserer",
        "euer", "eure", "euren", "eurem", "eurer", "dies", "diese", "diesen", "diesem", "dieser", "dieses",
        "jene", "jenen", "jenem", "jener", "jenes", "man", "wer", "was", "welche", "welchen", "welchem",
        "welcher", "welches", "etwas", "nichts", "alles", "alle", "allen", "allem", "aller",
        // Prepositions
        "in", "im", "an", "am", "auf", "aus", "bei", "beim", "mit", "nach", "seit", "von", "vom",
        "zu", "zum", "zur", "über", "unter", "vor", "hinter", "neben", "zwischen", "durch",
        "für", "gegen", "ohne", "um", "bis", "ab", "per", "pro",
        // Conjunctions
        "und", "oder", "aber", "denn", "sondern", "doch", "weil", "dass", "ob", "wenn", "als",
        "wie", "damit", "obwohl", "während", "bevor", "nachdem", "sobald", "falls",
        // Auxiliaries and common verbs
        "bin", "bist", "ist", "sind", "seid", "war", "warst", "waren", "wart", "wäre", "wären",
        "habe", "hast", "hat", "haben", "habt", "hatte", "hatten", "hätte", "hätten",
        "werde", "wirst", "wird", "werden", "werdet", "wurde", "wurden", "würde", "würden",
        "kann", "kannst", "können", "könnt", "konnte", "konnten", "könnte", "könnten",
        "muss", "musst", "müssen", "müsst", "musste", "mussten", "müsste", "müssten",
        "soll", "sollst", "sollen", "sollt", "sollte", "sollten",
        "will", "willst", "wollen", "wollt", "wollte", "wollten",
        "darf", "darfst", "dürfen", "dürft", "durfte", "durften",
        "mag", "magst", "mögen", "möchte", "möchten",
        // Adverbs, modal particles, fillers
        "auch", "noch", "schon", "nur", "sehr", "dann", "da", "hier", "dort", "so", "ja", "nein",
        "nicht", "kein", "keine", "keinen", "keinem", "keiner", "mal", "halt", "eben", "eigentlich",
        "einfach", "quasi", "sozusagen", "irgendwie", "vielleicht", "wohl", "denn", "jetzt", "heute",
        "morgen", "gestern", "immer", "nie", "oft", "wieder", "mehr", "weniger", "ganz", "gar",
        "also", "genau", "okay", "gut", "gerne", "bitte", "danke",
    ]

    /// Distinct normalized 2-4-word n-grams for one workflow output.
    /// Returns a Set: each phrase counts at most once per dictation, so
    /// "frequent" means "recurs across dictations".
    static func extractPhrases(from text: String) -> Set<String> {
        var phrases: Set<String> = []

        for sentence in sentences(in: text) {
            let tokens = normalizedTokens(in: sentence)
            guard tokens.count >= minWordsPerPhrase else { continue }

            for length in minWordsPerPhrase...maxWordsPerPhrase {
                guard tokens.count >= length else { break }
                for start in 0...(tokens.count - length) {
                    let gram = Array(tokens[start..<(start + length)])
                    guard isAcceptable(gram) else { continue }
                    phrases.insert(gram.joined(separator: " "))
                }
            }
        }

        return phrases
    }

    // MARK: - Steps

    /// N-grams never cross sentence boundaries.
    private static func sentences(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?:;\n"))
    }

    private static func normalizedTokens(in sentence: String) -> [String] {
        sentence
            .split(whereSeparator: \.isWhitespace)
            .compactMap { rawToken in
                // Strip edge punctuation but keep internal hyphens ("E-Mail-Adresse").
                let token = rawToken
                    .trimmingCharacters(in: .punctuationCharacters.union(.symbols))
                    .lowercased(with: Locale(identifier: "de_DE"))
                guard token.count >= minWordLength,
                      token.rangeOfCharacter(from: .letters) != nil,
                      token.rangeOfCharacter(from: .decimalDigits) == nil else {
                    return nil
                }
                return token
            }
    }

    private static func isAcceptable(_ gram: [String]) -> Bool {
        guard let first = gram.first, let last = gram.last else { return false }
        // Stopwords are never phrase edges.
        if germanStopwords.contains(first) || germanStopwords.contains(last) {
            return false
        }
        // Two-word phrases must be fully content-bearing.
        if gram.count == 2 && gram.contains(where: germanStopwords.contains) {
            return false
        }
        // Longer phrases need more than stopword filler.
        if gram.allSatisfy(germanStopwords.contains) {
            return false
        }
        return true
    }
}
