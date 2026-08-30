import SwiftUI
import AppKit

/// Progress and errors for an in-flight local model download. Shared by the
/// Settings card and the menu bar mode panel.
struct LocalModelDownloadStatus: View {
    let appState: AppState
    var showsModelName = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = appState.localModelDownloadProgress {
                if showsModelName {
                    HStack(spacing: 8) {
                        Text(appState.selectedLocalModelDisplayName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        Text(progress.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                ProgressView(value: progress)

                Text(appState.localModelDownloadStatusText ?? "Modell wird geladen \u{2026}")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorText = appState.localModelDownloadErrorText {
                Text(errorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Identity, state and actions for the selected local WhisperKit model.
///
/// Replaces the older layout where the download control was a disabled button
/// whose label was a status sentence ("… ist installiert") sitting next to a
/// bare "Modellseite" link. Here the model's state is text, the button label is
/// a verb, and the button disappears once there is nothing left to install.
///
/// The caller supplies the surface, matching the rest of the app.
struct LocalModelCard: View {
    let appState: AppState

    var body: some View {
        // One installed-check per body pass — it stats the model directory.
        let isInstalled = appState.selectedLocalModelIsInstalled

        VStack(alignment: .leading, spacing: 8) {
            if appState.localModelDownloadProgress != nil {
                LocalModelDownloadStatus(appState: appState)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isInstalled ? .green : .blue)
                        .frame(width: 16, height: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.selectedLocalModelDisplayName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(statusDetail(isInstalled: isInstalled))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    if !isInstalled {
                        Button("Installieren") {
                            appState.installSelectedLocalModel()
                        }
                        .buttonStyle(.primary)
                    }

                    modelPageButton

                    Spacer(minLength: 0)
                }

                if appState.localModelDownloadErrorText != nil {
                    LocalModelDownloadStatus(appState: appState)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelPageButton: some View {
        let url = LocalTranscriptionService.modelPageURL(for: appState.selectedLocalModelName)
        return Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 10, weight: .semibold))
                Text("Auf Hugging Face ansehen")
            }
        }
        .buttonStyle(.secondary)
        .help(url.absoluteString)
    }

    private func statusDetail(isInstalled: Bool) -> String {
        if isInstalled {
            return "Installiert \u{00B7} l\u{00E4}uft vollst\u{00E4}ndig auf deinem Mac."
        }
        if let size = LocalTranscriptionModel.downloadSizeLabel(for: appState.selectedLocalModelName) {
            return "Nicht installiert \u{00B7} einmaliger Download, \(size)."
        }
        return "Nicht installiert \u{00B7} wird beim Installieren lokal gespeichert."
    }
}

/// Progress and errors for an in-flight local rewrite model download.
struct LocalLLMDownloadStatus: View {
    let appState: AppState
    var showsModelName = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = appState.localLLMDownloadProgress {
                if showsModelName {
                    HStack(spacing: 8) {
                        Text(appState.localLLMDisplayName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        Text(progress.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                ProgressView(value: progress)

                Text(appState.localLLMDownloadStatusText ?? "Sprachmodell wird geladen \u{2026}")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorText = appState.localLLMDownloadErrorText {
                Text(errorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Identity, state and actions for the on-device rewrite model. Same shape as
/// `LocalModelCard`: the state is text, the button label is a verb, and the
/// button disappears once there is nothing left to install.
struct LocalLLMCard: View {
    let appState: AppState

    var body: some View {
        // One installed-check per body pass — it stats the model directory.
        let isInstalled = appState.localLLMIsReady

        VStack(alignment: .leading, spacing: 8) {
            if appState.localLLMDownloadProgress != nil {
                LocalLLMDownloadStatus(appState: appState)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isInstalled ? .green : .blue)
                        .frame(width: 16, height: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.localLLMDisplayName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(statusDetail(isInstalled: isInstalled))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    if !isInstalled {
                        Button("Installieren") {
                            appState.installLocalLLM()
                        }
                        // Only the lead action on this screen may be primary.
                        // While the transcription model is still missing that
                        // is the card above — transcription is the prerequisite
                        // — so this one steps down rather than competing with it.
                        .buttonStyle(.vc(appState.selectedLocalModelIsInstalled ? .primary : .secondary))
                    }

                    modelPageButton

                    Spacer(minLength: 0)
                }

                if appState.localLLMDownloadErrorText != nil {
                    LocalLLMDownloadStatus(appState: appState)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelPageButton: some View {
        let url = URL(string: "https://huggingface.co/\(appState.localLLMSettings.modelID)")!
        return Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 10, weight: .semibold))
                Text("Auf Hugging Face ansehen")
            }
        }
        .buttonStyle(.secondary)
        .help(url.absoluteString)
    }

    private func statusDetail(isInstalled: Bool) -> String {
        if isInstalled {
            return "Installiert \u{00B7} \u{00DC}berarbeitung l\u{00E4}uft vollst\u{00E4}ndig auf deinem Mac."
        }
        let options = LocalLLMService.modelOptions()
        if let size = options.first(where: { $0.id == appState.localLLMSettings.modelID })?.sizeLabel {
            return "Nicht installiert \u{00B7} einmaliger Download, \(size)."
        }
        return "Nicht installiert \u{00B7} wird beim Installieren lokal gespeichert."
    }
}
