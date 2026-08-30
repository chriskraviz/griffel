import SwiftUI

/// Renders the *Ordnen* result. The prompt asks for exactly three kinds of
/// Markdown — `## ` headings, `- [ ] ` tasks and `- ` bullets — so a line-wise
/// renderer covers it. A Markdown parser would be a new dependency for three
/// prefixes, the same trade-off `TranscriptSidecar` makes for its header.
///
/// Inline syntax (`**fett**`) is deliberately left literal: passing the line
/// through `Text(LocalizedStringKey)` to get inline Markdown for free would
/// also make every transcribed sentence a lookup key.
struct BraindumpResultText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(for: line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var lines: [Line] {
        markdown.components(separatedBy: .newlines).map(Line.init(raw:))
    }

    @ViewBuilder
    private func row(for line: Line) -> some View {
        switch line.kind {
        case .blank:
            Color.clear.frame(height: 3)
        case .heading:
            Text(line.text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 5)
        case .task, .taskDone:
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: line.kind == .taskDone ? "checkmark.square" : "square")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(line.text)
                    .font(.system(size: 10.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\u{2022}")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Text(line.text)
                    .font(.system(size: 10.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .body:
            Text(line.text)
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    struct Line {
        enum Kind { case blank, heading, task, taskDone, bullet, body }

        let kind: Kind
        let text: String

        init(raw: String) {
            (kind, text) = Self.classify(raw.trimmingCharacters(in: .whitespaces))
        }

        /// A static function rather than a chain of `if`s inside `init`: a `let`
        /// may only be assigned once, so the prefix loops cannot write to the
        /// stored properties directly.
        private static func classify(_ line: String) -> (Kind, String) {
            if line.isEmpty { return (.blank, "") }
            for prefix in ["#### ", "### ", "## ", "# "] where line.hasPrefix(prefix) {
                return (.heading, String(line.dropFirst(prefix.count)))
            }
            for prefix in ["- [x] ", "- [X] ", "* [x] ", "* [X] "] where line.hasPrefix(prefix) {
                return (.taskDone, String(line.dropFirst(prefix.count)))
            }
            for prefix in ["- [ ] ", "* [ ] "] where line.hasPrefix(prefix) {
                return (.task, String(line.dropFirst(prefix.count)))
            }
            for prefix in ["- ", "* "] where line.hasPrefix(prefix) {
                return (.bullet, String(line.dropFirst(prefix.count)))
            }
            return (.body, line)
        }
    }
}
