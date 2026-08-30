import SwiftUI

/// The settings laid out for the Ablage window rather than for the popover.
///
/// Same halves — `CustomizeSettingsView` and `AccessSettingsView` — because
/// they were already separate views; only the frame around them changes. The
/// popover has to stack a segmented picker on top of one 340pt column, which
/// is the compromise a 340pt popover forces. Given a window there is room to
/// put the two sections side by side with the content instead of above it.
///
/// The content column is capped rather than stretched. More width should buy
/// rows that stop truncating, not lines of text running the full 1180pt — a
/// settings row 900pt wide is harder to read, not easier.
struct WideSettingsView: View {
    @Bindable var appState: AppState

    @State private var section: Section = .customize
    @State private var showsPrompts = false

    /// Matches the library sidebar, so switching between Ablage and
    /// Einstellungen does not shift the window's vertical rule sideways.
    private static let sidebarWidth: CGFloat = 200
    /// Comfortable measure for a column of labelled controls.
    private static let contentWidth: CGFloat = 620

    enum Section: String, CaseIterable, Identifiable {
        case customize, access
        var id: String { rawValue }
        var title: String {
            switch self {
            case .customize: return "Anpassen"
            case .access: return "Zugang"
            }
        }
        var icon: String {
            switch self {
            case .customize: return "slider.horizontal.3"
            case .access: return "key.fill"
            }
        }
        var blurb: String {
            switch self {
            case .customize: return "Kurzbefehle, Wörterbuch, Prompts"
            case .access: return "Berechtigungen, API-Key, Ablage"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            appState.refreshAccessibilityPermission()
            section = SettingsContentView.defaultSection(for: appState)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Section.allCases) { candidate in
                Button {
                    showsPrompts = false
                    section = candidate
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: candidate.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(candidate.title)
                                .font(.system(size: 12, weight: .medium))
                            Text(candidate.blurb)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(section == candidate && !showsPrompts
                                  ? AnyShapeStyle(.selection)
                                  : AnyShapeStyle(.clear))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            Group {
                if showsPrompts {
                    PromptsView(appState: appState) { showsPrompts = false }
                } else if section == .customize {
                    CustomizeSettingsView(appState: appState) { showsPrompts = true }
                } else {
                    AccessSettingsView(appState: appState)
                }
            }
            // A maximum rather than a fixed width, so the column still
            // shrinks if the window minimum ever drops below sidebar +
            // contentWidth. Today it cannot: 1000 - 201 leaves 799pt.
            .frame(maxWidth: Self.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}
