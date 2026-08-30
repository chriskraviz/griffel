import SwiftUI

// MARK: - Design Tokens

enum DS {
    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 16
}

// MARK: - Keycap Tokens

/// Surface tokens for the keycap look shared by `HotkeyBadge` and every
/// `VCButtonStyle` role. Griffel is driven by held key combos, so its
/// controls borrow the physics of a key: a hairline edge, a soft drop shadow
/// at rest, and a collapse into the surface when pressed.
enum Keycap {
    static let radius: CGFloat = 6
    static let shadowRadius: CGFloat = 1.2
    static let shadowY: CGFloat = 0.6

    static func label(_ scheme: ColorScheme, enabled: Bool = true) -> Color {
        guard enabled else {
            return scheme == .dark ? Color.white.opacity(0.34) : Color.black.opacity(0.26)
        }
        return scheme == .dark ? Color.white.opacity(0.84) : Color.black.opacity(0.72)
    }

    static func fill(_ scheme: ColorScheme, enabled: Bool = true) -> Color {
        guard enabled else {
            return scheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035)
        }
        return scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.09)
    }

    /// Resting fill plus a touch more presence while the pointer is over it.
    static func hoverFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14)
    }

    /// Darker than resting: the key has travelled down into the surface.
    static func pressedFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.18)
    }

    static func stroke(_ scheme: ColorScheme, enabled: Bool = true) -> Color {
        guard enabled else {
            return scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
        }
        return scheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.16)
    }

    static func shadow(_ scheme: ColorScheme, enabled: Bool = true) -> Color {
        guard enabled else { return .clear }
        return scheme == .dark ? Color.black.opacity(0.10) : Color.black.opacity(0.06)
    }
}

// MARK: - Buttons

/// Importance tier. A screen shows at most one `.primary`.
enum VCButtonRole {
    /// The one commit action: filled with the tint.
    case primary
    /// A real action that is not the commit action: neutral keycap, or a
    /// tinted one when the action carries a warning/danger/success meaning.
    case secondary
    /// Navigation and dismissal: no resting chrome, chrome on hover.
    case quiet
}

enum VCButtonSize {
    case regular
    case compact
    /// Square, for glyph-only controls. The glyph's own font stays with the
    /// call site — this only fixes the box.
    case icon
}

/// The app's button. Renders a keycap that depresses when pressed: the shadow
/// collapses, the fill darkens and the label sinks by a point.
struct VCButtonStyle: ButtonStyle {
    var role: VCButtonRole
    var size: VCButtonSize = .regular
    /// Drives label, fill and stroke together. Defaults to the system accent
    /// for `.primary` and to the neutral keycap for the other roles.
    var tint: Color?
    /// Fill the available width instead of hugging the label.
    var fill: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        KeycapSurface(configuration: configuration, role: role, size: size, tint: tint, fill: fill)
    }

    /// Holds the hover state a `ButtonStyle` value cannot own itself.
    struct KeycapSurface: View {
        let configuration: Configuration
        let role: VCButtonRole
        let size: VCButtonSize
        let tint: Color?
        let fill: Bool

        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var isPressed: Bool { configuration.isPressed }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Keycap.radius, style: .continuous)

            configuration.label
                .font(metrics.font)
                .foregroundStyle(labelColor)
                // A button label never wraps: a control that cannot fit is a
                // layout to restructure, not a multi-line block of text.
                .lineLimit(1)
                .fixedSize(horizontal: !fill, vertical: false)
                .padding(.horizontal, metrics.horizontal)
                .padding(.vertical, metrics.vertical)
                .frame(minWidth: metrics.minWidth, minHeight: metrics.minHeight)
                .frame(maxWidth: fill ? .infinity : nil)
                .background(shape.fill(surfaceFill))
                .overlay(shape.strokeBorder(stroke, lineWidth: 0.8))
                .shadow(color: shadow, radius: Keycap.shadowRadius, y: Keycap.shadowY)
                .offset(y: sinkOffset)
                .contentShape(shape)
                .animation(motion, value: isPressed)
                .animation(motion, value: isHovered)
                .onHover { hovering in isHovered = hovering }
        }

        // MARK: Geometry

        private var metrics: (horizontal: CGFloat, vertical: CGFloat, minWidth: CGFloat?, minHeight: CGFloat, font: Font) {
            switch size {
            case .regular:
                return (13, 6, nil, 26, .system(size: role == .primary ? 12 : 11.5,
                                                weight: role == .primary ? .semibold : .medium))
            case .compact:
                return (9, 3, nil, 21, .system(size: 10.5, weight: .medium))
            case .icon:
                return (0, 0, 26, 26, .system(size: 11, weight: .medium))
            }
        }

        // MARK: Surface

        /// `nil` tint means "no semantic colour" — the neutral keycap.
        private var accent: Color {
            tint ?? .accentColor
        }

        private var labelColor: Color {
            guard isEnabled else { return Keycap.label(scheme, enabled: false) }
            switch role {
            case .primary:
                return .white
            case .secondary:
                return tint ?? Keycap.label(scheme)
            case .quiet:
                if let tint { return tint }
                return isHovered ? Keycap.label(scheme) : Color.secondary
            }
        }

        private var surfaceFill: Color {
            guard isEnabled else {
                return role == .quiet ? .clear : Keycap.fill(scheme, enabled: false)
            }

            switch role {
            case .primary:
                if isPressed { return accent.opacity(0.78) }
                return isHovered ? accent.opacity(0.88) : accent
            case .secondary:
                if let tint {
                    if isPressed { return tint.opacity(0.24) }
                    return tint.opacity(isHovered ? 0.18 : 0.11)
                }
                if isPressed { return Keycap.pressedFill(scheme) }
                return isHovered ? Keycap.hoverFill(scheme) : Keycap.fill(scheme)
            case .quiet:
                if isPressed { return Keycap.pressedFill(scheme) }
                return isHovered ? Keycap.fill(scheme) : .clear
            }
        }

        private var stroke: Color {
            guard isEnabled else {
                return role == .quiet ? .clear : Keycap.stroke(scheme, enabled: false)
            }

            switch role {
            case .primary:
                return Color.black.opacity(scheme == .dark ? 0.28 : 0.12)
            case .secondary:
                if let tint { return tint.opacity(0.32) }
                return Keycap.stroke(scheme)
            case .quiet:
                return isHovered ? Keycap.stroke(scheme) : .clear
            }
        }

        // MARK: Press physics

        private var shadow: Color {
            guard isEnabled, role != .quiet, !isPressed else { return .clear }
            if role == .primary {
                return accent.opacity(scheme == .dark ? 0.34 : 0.26)
            }
            return Keycap.shadow(scheme)
        }

        private var sinkOffset: CGFloat {
            guard isPressed, isEnabled, !reduceMotion else { return 0 }
            return 1
        }

        private var motion: Animation? {
            reduceMotion ? nil : .easeOut(duration: 0.11)
        }
    }
}

extension ButtonStyle where Self == VCButtonStyle {
    /// The one commit action on a screen.
    static var primary: VCButtonStyle { .vc(.primary) }

    /// A real action that is not the commit action.
    static var secondary: VCButtonStyle { .vc(.secondary) }

    /// Navigation and dismissal.
    static var quiet: VCButtonStyle { .vc(.quiet) }

    /// Deletes and cleanup — a red-tinted secondary.
    static var destructive: VCButtonStyle { .vc(.secondary, tint: .red) }

    static func destructive(_ size: VCButtonSize) -> VCButtonStyle {
        .vc(.secondary, size, tint: .red)
    }

    /// The one factory every shorthand above is built from.
    static func vc(
        _ role: VCButtonRole,
        _ size: VCButtonSize = .regular,
        tint: Color? = nil,
        fill: Bool = false
    ) -> VCButtonStyle {
        VCButtonStyle(role: role, size: size, tint: tint, fill: fill)
    }
}

/// Spinner sized to sit inside a button label without changing its height.
struct ButtonSpinner: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .scaleEffect(0.6)
            .frame(width: 10, height: 10)
    }
}

/// Chrome-free button for use *inside* a `GlassChip`, where the chip itself is
/// the affordance. Adds the hover and disabled feedback a bare label lacks.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChipSurface(configuration: configuration)
    }

    struct ChipSurface: View {
        let configuration: Configuration

        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .opacity(opacity)
                .contentShape(Rectangle())
                .animation(motion, value: configuration.isPressed)
                .animation(motion, value: isHovered)
                .onHover { hovering in isHovered = hovering }
        }

        private var opacity: Double {
            guard isEnabled else { return 0.4 }
            if configuration.isPressed { return 0.5 }
            return isHovered ? 0.75 : 1.0
        }

        private var motion: Animation? {
            reduceMotion ? nil : .easeOut(duration: 0.1)
        }
    }
}

extension ButtonStyle where Self == ChipButtonStyle {
    static var chip: ChipButtonStyle { ChipButtonStyle() }
}

// MARK: - Glass Card

/// Translucent "glass" surface: material fill, gradient edge highlight and a
/// soft shadow. Falls back to a solid fill when the user reduces transparency.
struct GlassCardModifier: ViewModifier {
    var radius: CGFloat = DS.radiusM
    var tint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(
                cardBackground
                    .shadow(color: Color.black.opacity(0.10), radius: 5, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            if reduceTransparency {
                shape.fill(Color.primary.opacity(0.05))
            } else {
                shape.fill(.ultraThinMaterial)
            }
            if let tint {
                shape.fill(tint.opacity(0.08))
            }
        }
    }
}

extension View {
    func glassCard(radius: CGFloat = DS.radiusM, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(radius: radius, tint: tint))
    }
}

// MARK: - Glass Chip

/// Small capsule chip for terms and tags.
struct GlassChip<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 3) {
            content
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if reduceTransparency {
                Capsule().fill(Color.primary.opacity(0.06))
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        }
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
        )
    }
}
