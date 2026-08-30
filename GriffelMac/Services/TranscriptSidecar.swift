import Foundation

/// Reads and writes the `.md` file that holds one transcript.
///
/// The file is the single source of truth for the library — there is no index
/// to fall out of sync with it. That is what makes the "bevorzugter
/// Speicherort" an honest promise: the folder stays readable, greppable and
/// Spotlight-indexable without Griffel.
///
/// The header looks like YAML front matter but is deliberately **not** parsed
/// as YAML: adding a parser dependency for six single-line fields would be a
/// new external dependency for nothing. The grammar is fixed and narrow:
///
/// ```
/// ---
/// schema: 1
/// id: <uuid>
/// title: Idee für die Onboarding-Seite
/// ---
/// Der eigentliche Transkripttext ...
/// ```
///
/// * the file must start with a line that is exactly `---`
/// * the header ends at the **first** following line that is exactly `---`,
///   so a `---` inside the transcript body is harmless
/// * each header line splits at its first `": "`; values are single-line
/// * unknown keys are preserved verbatim so a newer build's fields survive a
///   round trip through an older one
///
/// Parsing never throws away content: a file with a broken or missing header
/// still yields an item whose body is the whole file.
enum TranscriptSidecar {
    static let fileExtension = "md"
    private static let delimiter = "---"
    private static let currentSchema = 1

    private enum Key {
        static let schema = "schema"
        static let id = "id"
        static let title = "title"
        static let created = "created"
        static let updated = "updated"
        static let source = "source"
        static let tags = "tags"
        static let audio = "audio"
        static let duration = "duration"
        static let language = "language"
        static let engine = "engine"
        static let capturedApp = "captured-app"
        static let capturedBundle = "captured-bundle"
        static let capturedWindow = "captured-window"

        static let known: Set<String> = [
            schema, id, title, created, updated, source, tags, audio,
            duration, language, engine, capturedApp, capturedBundle, capturedWindow
        ]
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Write

    static func serialize(_ item: LibraryItem) -> String {
        var lines: [String] = [delimiter]
        lines.append("\(Key.schema): \(currentSchema)")
        lines.append("\(Key.id): \(item.id.uuidString)")
        lines.append("\(Key.title): \(singleLine(item.title))")
        lines.append("\(Key.created): \(dateFormatter.string(from: item.createdAt))")
        lines.append("\(Key.updated): \(dateFormatter.string(from: item.updatedAt))")
        lines.append("\(Key.source): \(item.source.rawValue)")

        if !item.tags.isEmpty {
            lines.append("\(Key.tags): \(item.tags.map(singleLine).joined(separator: ", "))")
        }
        if let audioFileName = item.audioFileName {
            lines.append("\(Key.audio): \(singleLine(audioFileName))")
        }
        if let duration = item.audioDuration {
            lines.append("\(Key.duration): \(String(format: "%.1f", duration))")
        }
        if !item.language.isEmpty {
            lines.append("\(Key.language): \(singleLine(item.language))")
        }
        if !item.engine.isEmpty {
            lines.append("\(Key.engine): \(singleLine(item.engine))")
        }
        if let capture = item.capture {
            if let appName = capture.appName {
                lines.append("\(Key.capturedApp): \(singleLine(appName))")
            }
            if let bundleIdentifier = capture.bundleIdentifier {
                lines.append("\(Key.capturedBundle): \(singleLine(bundleIdentifier))")
            }
            if let windowTitle = capture.windowTitle {
                lines.append("\(Key.capturedWindow): \(singleLine(windowTitle))")
            }
        }
        for key in item.extra.keys.sorted() {
            guard let value = item.extra[key] else { continue }
            lines.append("\(key): \(singleLine(value))")
        }

        lines.append(delimiter)
        lines.append("")
        lines.append(item.transcript)
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Read

    /// `fileURL` supplies the fallbacks a broken header cannot: the base name
    /// becomes the title, and the file's own dates stand in for missing ones.
    static func parse(_ contents: String, fileURL: URL) -> LibraryItem {
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let fallbackDate = fileCreationDate(fileURL) ?? Date()

        var header: [(key: String, value: String)] = []
        var body = contents

        let lines = contents.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == delimiter {
            var closingIndex: Int?
            for index in 1..<lines.count where lines[index].trimmingCharacters(in: .whitespaces) == delimiter {
                closingIndex = index
                break
            }
            if let closingIndex {
                for index in 1..<closingIndex {
                    guard let pair = splitHeaderLine(lines[index]) else { continue }
                    header.append(pair)
                }
                body = lines[(closingIndex + 1)...]
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        var fields: [String: String] = [:]
        for pair in header where fields[pair.key] == nil {
            fields[pair.key] = pair.value
        }

        let capture = CaptureContext(
            appName: fields[Key.capturedApp],
            bundleIdentifier: fields[Key.capturedBundle],
            windowTitle: fields[Key.capturedWindow]
        )

        var extra: [String: String] = [:]
        for pair in header where !Key.known.contains(pair.key) {
            extra[pair.key] = pair.value
        }

        return LibraryItem(
            id: fields[Key.id].flatMap(UUID.init(uuidString:)) ?? UUID(),
            title: fields[Key.title] ?? baseName,
            createdAt: fields[Key.created].flatMap { dateFormatter.date(from: $0) } ?? fallbackDate,
            updatedAt: fields[Key.updated].flatMap { dateFormatter.date(from: $0) } ?? fallbackDate,
            source: LibrarySource(rawValue: fields[Key.source] ?? ""),
            folderName: nil,
            tags: parseTags(fields[Key.tags]),
            transcript: body,
            audioFileName: fields[Key.audio].flatMap { $0.isEmpty ? nil : $0 },
            audioDuration: fields[Key.duration].flatMap(Double.init),
            language: fields[Key.language] ?? "",
            engine: fields[Key.engine] ?? "",
            capture: capture.isEmpty ? nil : capture,
            extra: extra,
            baseName: baseName
        )
    }

    // MARK: - Helpers

    private static func splitHeaderLine(_ line: String) -> (key: String, value: String)? {
        guard let separator = line.range(of: ": ") else {
            // "key:" with an empty value is still a key.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix(":"), trimmed.count > 1 else { return nil }
            return (String(trimmed.dropLast()), "")
        }
        let key = String(line[line.startIndex..<separator.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let value = String(line[separator.upperBound...])
            .trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : (key, value)
    }

    private static func parseTags(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        var tags: [String] = []
        for piece in raw.components(separatedBy: ",") {
            guard let normalized = LibraryTag.normalize(piece) else { continue }
            tags = LibraryTag.merged(tags, adding: normalized)
        }
        return tags
    }

    /// Values are single-line by construction; a stray newline would silently
    /// swallow the rest of the header.
    private static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func fileCreationDate(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }
}
