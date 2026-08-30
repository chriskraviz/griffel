import AppKit
import SwiftUI

/// One filed recording. Pure layout over one item plus whatever the queue is
/// currently doing with it.
struct LibraryRowView: View {
    @Bindable var appState: AppState
    let item: LibraryItem
    let job: TranscriptionJob?
    let allTags: [(tag: String, count: Int)]
    let folderNames: [String]
    let onSelectTag: (String) -> Void

    private static let collapsedLineLimit = 5

    @State private var isExpanded = false
    @State private var isTagPopoverShown = false
    @State private var didCopy = false

    private var library: LibraryStore { appState.library }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            titleRow
            metaRow

            if let job, job.status.isRunning || job.status.isQueued {
                statusRow(job)
            } else if let failure = job?.status.failureText {
                failureRow(failure)
            }

            if !item.transcript.isEmpty {
                Text(item.transcript)
                    .font(.system(size: 11))
                    .textSelection(.enabled)
                    .lineLimit(isExpanded ? nil : Self.collapsedLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            tagRow
            actionRow
        }
        .padding(10)
        .glassCard(radius: DS.radiusS)
        .contextMenu { contextMenu }
    }

    // MARK: - Header

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.source.icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(item.title)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            audioChip
        }
    }

    /// Three states, and the middle one is the trap: no chip at all means the
    /// item never had audio (a spoken Braindump), which is not an error and
    /// must not look like one.
    @ViewBuilder
    private var audioChip: some View {
        if item.audioIsMissing {
            GlassChip {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                Text("Audio fehlt")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.orange)
            }
        } else if item.hasAudio {
            GlassChip {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                if let duration = item.audioDuration {
                    Text(Self.durationLabel(duration))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Audio")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 5) {
            Text(Self.timeFormatter.string(from: item.createdAt))
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.tertiary)

            if let engineLabel = item.engineLabel {
                metaSeparator
                Text(engineLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            if let capture = item.capture, let appName = capture.appName {
                metaSeparator
                // Only the app name is short and safe enough to always show;
                // the window title can be an email subject, so it stays in the
                // tooltip.
                Text("in \(appName)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .help(capture.displayText.map { "aufgenommen in \($0)" } ?? appName)
            }

            if let folderName = item.folderName {
                metaSeparator
                Text(folderName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
    }

    private var metaSeparator: some View {
        Text("\u{00B7}")
            .font(.system(size: 9.5))
            .foregroundStyle(.quaternary)
    }

    // MARK: - Status

    private func statusRow(_ job: TranscriptionJob) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.55)
                .frame(width: 10, height: 10)
            Text(statusText(job))
                .font(.system(size: 10))
                .foregroundStyle(.blue)
            Spacer(minLength: 0)
        }
    }

    private func failureRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func statusText(_ job: TranscriptionJob) -> String {
        switch job.status {
        case .queued:
            return "Wartet"
        case .transcribing:
            return job.configuration.backend == .local
                ? "Wird lokal transkribiert \u{2026}"
                : "Wird transkribiert \u{2026}"
        case .rewriting:
            return job.configuration.rewrite?.backend.isLocal == true
                ? "Wird lokal nachbearbeitet \u{2026}"
                : "Wird nachbearbeitet \u{2026}"
        case .failed(let message):
            return message
        }
    }

    // MARK: - Tags

    private var tagRow: some View {
        HStack(spacing: 5) {
            FlowLayout(spacing: 5) {
                ForEach(item.tags.prefix(4), id: \.self) { tag in
                    TagChip(name: tag, onTap: { onSelectTag(tag) })
                }
                if item.tags.count > 4 {
                    TagChip(name: "+\(item.tags.count - 4)", onTap: { isTagPopoverShown = true })
                }
            }

            Button {
                isTagPopoverShown = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "tag")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(item.tags.isEmpty ? "Tag" : "Tags")
                }
            }
            .buttonStyle(.vc(.quiet, .compact))
            .popover(isPresented: $isTagPopoverShown, arrowEdge: .bottom) {
                TagEditorPopover(
                    item: item,
                    existingTags: allTags,
                    onAdd: { library.addTag($0, toItemID: item.id) },
                    onRemove: { library.removeTag($0, fromItemID: item.id) }
                )
            }

            Spacer(minLength: 0)
        }
    }

    /// The five-line clamp hides text in two different ways, and character
    /// count only catches one of them: a short note with six hard line breaks
    /// is clipped just as surely as a long paragraph. Erring towards showing
    /// the control costs a no-op click; erring the other way makes text
    /// unreachable.
    private var transcriptMayBeClipped: Bool {
        if item.transcript.count > 320 { return true }
        return item.transcript.reduce(into: 0) { count, character in
            if character.isNewline { count += 1 }
        } >= Self.collapsedLineLimit
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 6) {
            if !item.transcript.isEmpty {
                Button {
                    appState.copyToClipboard(item.transcript)
                    didCopy = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        didCopy = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                        Text(didCopy ? "Kopiert" : "Kopieren")
                    }
                }
                .buttonStyle(.vc(.secondary, .compact, tint: didCopy ? .green : nil))

                if transcriptMayBeClipped {
                    Button(isExpanded ? "Weniger" : "Mehr") {
                        isExpanded.toggle()
                    }
                    .buttonStyle(.vc(.quiet, .compact))
                }
            } else if item.hasAudio, !item.audioIsMissing, job == nil, appState.canImportAudio {
                Button("Transkribieren") {
                    appState.retranscribe(item)
                }
                .buttonStyle(.vc(.secondary, .compact))
            }

            if job?.status.failureText != nil {
                Button("Nochmal") {
                    appState.retranscribe(item)
                }
                .buttonStyle(.vc(.secondary, .compact))
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    appState.transcriptionQueue.removeJob(forItem: item.id)
                    library.delete(itemID: item.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.destructive(.icon))
            .help("In den Papierkorb legen")
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Menu("Verschieben nach") {
            Button("Ohne Thema") { library.move(itemID: item.id, toFolder: nil) }
            if !folderNames.isEmpty {
                Divider()
                ForEach(folderNames, id: \.self) { name in
                    Button(name) { library.move(itemID: item.id, toFolder: name) }
                }
            }
        }

        Button("Im Finder zeigen") {
            // Resolved now, not from the snapshot this row was built with —
            // the item may have moved since.
            let current = library.item(id: item.id) ?? item
            let url = library.audioURL(for: current) ?? library.sidecarURL(for: current)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }

        if item.hasAudio {
            Button("Nur Aufnahme l\u{00F6}schen", role: .destructive) {
                library.deleteAudio(ofItemID: item.id)
            }
        }
    }

    static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
