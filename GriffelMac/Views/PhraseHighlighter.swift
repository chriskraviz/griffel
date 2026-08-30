import SwiftUI

/// Renders known frequent phrases inside a result text in bold accent color.
@MainActor
enum PhraseHighlighter {
    /// Case-insensitive, diacritic-sensitive highlight of frequent phrases.
    /// The result text is at most a few lines and the phrase list is capped,
    /// so the repeated substring searches stay negligible.
    static func highlighted(_ text: String, accent: Color) -> AttributedString {
        var attributed = AttributedString(text)
        let phrases = PhraseStore.shared.matchPhrases(in: text)
        guard !phrases.isEmpty else { return attributed }

        for phrase in phrases {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: phrase, options: [.caseInsensitive], range: searchRange) {
                if let lower = AttributedString.Index(found.lowerBound, within: attributed),
                   let upper = AttributedString.Index(found.upperBound, within: attributed) {
                    attributed[lower..<upper].font = .system(size: 11, weight: .semibold)
                    attributed[lower..<upper].foregroundColor = accent
                }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return attributed
    }
}
