import SwiftUI

/// Editor for the feature prompts. Each card shows the text that actually runs:
/// an untouched prompt renders its `PromptDefaults` text, so the editor is never
/// an empty box the user has to guess the shape of. Editing stores the text;
/// "Zurücksetzen" clears it again and hands the prompt back to the default.
struct PromptsView: View {
    @Bindable var appState: AppState
    /// How to leave the editor. `nil` walks the popover back to its settings
    /// page; presented as a sheet there is no page to walk back to, so the
    /// window passes a dismiss instead.
    var onBack: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PromptEditorCard(
                        title: "Griffel+ · Korrektur",
                        subtitle: "Räumt das Diktat auf, ohne die Wortwahl anzufassen.",
                        defaultText: PromptDefaults.korrektur,
                        text: $appState.promptSettings.korrektur
                    )

                    PromptEditorCard(
                        title: "Griffel+ · Lektorat",
                        subtitle: "Formuliert um. Ton und Kontext werden zusätzlich angehängt.",
                        defaultText: PromptDefaults.lektorat,
                        text: $appState.promptSettings.lektorat
                    )

                    PromptEditorCard(
                        title: "Auswahl bearbeiten",
                        subtitle: "Wendet die gesprochene Anweisung auf den markierten Text an.",
                        defaultText: PromptDefaults.selectionEdit,
                        text: $appState.promptSettings.selectionEdit
                    )

                    PromptEditorCard(
                        title: "Braindump ordnen",
                        subtitle: "Ordnet den Eingang zu Zusammenfassung, Aufgaben und Ideen.",
                        defaultText: PromptDefaults.braindump,
                        text: $appState.promptSettings.braindump
                    )

                    PromptEditorCard(
                        title: "Zusatz für das lokale Modell",
                        subtitle: "Wird nur angehängt, wenn das Sprachmodell auf deinem Mac rechnet — kleine Modelle kürzen sonst gern.",
                        defaultText: PromptDefaults.localAddendum,
                        text: $appState.promptSettings.localAddendum,
                        isEnabled: $appState.promptSettings.localAddendumEnabled
                    )

                    Text("Glossar, Denglisch-Modus und Füllwort-Einstellung werden weiterhin automatisch angehängt. App-Profile bringen ihre eigene Formatierungsanweisung mit.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                if let onBack {
                    onBack()
                } else {
                    appState.page = .settings
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Einstellungen")
                }
            }
            .buttonStyle(.vc(.quiet, .compact))

            Spacer()

            Text("Prompts")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.5)
        )
    }
}

/// One prompt: identity, state, editor, and a way back to the default.
private struct PromptEditorCard: View {
    let title: String
    let subtitle: String
    let defaultText: String
    @Binding var text: String
    /// Only the local addendum may be switched off entirely. The four feature
    /// prompts always run, so they pass nil and get no switch.
    var isEnabled: Binding<Bool>?

    private var switchedOff: Bool {
        isEnabled?.wrappedValue == false
    }

    private var isCustomized: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != defaultText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The editor always shows what would actually run, so an untouched prompt
    /// reads as its default rather than as an empty field.
    private var displayed: Binding<String> {
        Binding(
            get: { text.isEmpty ? defaultText : text },
            set: { text = $0 }
        )
    }

    /// These prompts differ a lot in length — the braindump instruction is six
    /// times the local addendum. A fixed height either clips the long one mid
    /// word or leaves the short one mostly empty, and empty space costs
    /// scrolling on a 340pt popover, so the box follows its content.
    private var editorHeight: CGFloat {
        let text = displayed.wrappedValue
        // ~45 characters fit one line at 11pt in the card's usable width.
        let wrapped = text.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / 45.0))) }
        return min(max(CGFloat(wrapped) * 15 + 18, 60), 190)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let isEnabled {
                    Toggle("", isOn: isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                } else {
                    Text(isCustomized ? "Angepasst" : "Standard")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isCustomized ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                }
            }

            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if switchedOff {
                Text("Aus \u{2014} das lokale Modell bekommt keinen Zusatz.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                HStack(spacing: 6) {
                    Text(isCustomized ? "Angepasst" : "Standard")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isCustomized ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                    Spacer(minLength: 0)
                }
                .opacity(isEnabled == nil ? 0 : 1)
                .frame(height: isEnabled == nil ? 0 : nil)

                TextEditor(text: displayed)
                    .font(.system(size: 11))
                    .frame(height: editorHeight)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            }

            // A control with nothing to do is removed, not disabled.
            if isCustomized, !switchedOff {
                HStack {
                    Spacer(minLength: 0)
                    Button("Zurücksetzen") {
                        text = ""
                    }
                    .buttonStyle(.vc(.quiet, .compact))
                }
            }
        }
        .padding(12)
        .glassCard(radius: DS.radiusS)
    }
}
