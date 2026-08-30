import SwiftUI

/// One runnable mode. Only rendered for modes the current setup can run, so
/// there is no disabled state to draw.
struct WorkflowRowView: View {
    let type: WorkflowType
    /// Passed in rather than read off the type — the combination is a user
    /// setting now, not a constant.
    let hotkeyTokens: [String]
    var subtitle: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon with monochrome background
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0.06))
                        .frame(width: 36, height: 36)

                    Image(systemName: type.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                // Name + subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle ?? type.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Hotkey badge
                HotkeyBadge(tokens: hotkeyTokens)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassCard(radius: DS.radiusS)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
                    .allowsHitTesting(false)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

}

// MARK: - Hotkey Badge

/// The literal keycap. Shares its surface tokens with `VCButtonStyle`, so the
/// hotkey hints and the app's buttons stay the same physical material.
struct HotkeyBadge: View {
    /// One keycap per token, already in display order.
    let tokens: [String]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Keycap.label(colorScheme))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: Keycap.radius, style: .continuous)
                            .fill(Keycap.fill(colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Keycap.radius, style: .continuous)
                            .strokeBorder(Keycap.stroke(colorScheme), lineWidth: 0.8)
                    )
                    .shadow(
                        color: Keycap.shadow(colorScheme),
                        radius: Keycap.shadowRadius,
                        y: Keycap.shadowY
                    )
            }
        }
    }
}
