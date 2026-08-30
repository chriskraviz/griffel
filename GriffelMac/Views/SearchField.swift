import SwiftUI

/// Glass search field. The clear button exists only while there is something
/// to clear — a control with nothing to do is removed, not disabled.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Suche zur\u{00FC}cksetzen")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: Keycap.radius, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            } else {
                RoundedRectangle(cornerRadius: Keycap.radius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Keycap.radius, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.14),
                    lineWidth: isFocused ? 1.2 : 0.8
                )
        )
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}
