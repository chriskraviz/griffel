import SwiftUI

// MARK: - Design Tokens

enum DS {
    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 16
}

// MARK: - Proof Desk

/// The editorial world shared by the window, popover and HUD. These colours
/// deliberately stay a little warmer and quieter than the system palette;
/// interaction blue and recording red are the only saturated accents.
enum ProofDesk {
    static let paper = Color(red: 0.961, green: 0.949, blue: 0.929)
    static let sidebar = Color(red: 0.945, green: 0.945, blue: 0.937)
    static let ledger = Color(red: 0.922, green: 0.914, blue: 0.902)
    static let selection = Color(red: 0.933, green: 0.953, blue: 0.984)
    static let blue = Color(red: 0.0, green: 0.38, blue: 0.99)
    static let red = Color(red: 0.996, green: 0.325, blue: 0.31)
    static let marker = Color(red: 0.745, green: 0.804, blue: 0.565)
    static let ink = Color(red: 0.105, green: 0.102, blue: 0.094)
    /// Small utility copy must remain readable on every paper tone. At 64%
    /// this clears 4.5:1 even on the darker ledger surface.
    static let metadataInk = ink.opacity(0.64)
    /// Warm semantic fills are intentionally bright; dark ink is their
    /// accessible foreground rather than forcing white onto every primary.
    static let onWarmAccent = ink
    static let rule = Color.black.opacity(0.105)

    static let eyebrow = Font.system(size: 9.5, weight: .semibold)
    static let utility = Font.system(size: 11)
    static let editorialTitle = Font.system(size: 29, weight: .semibold, design: .serif)
    static let editorialBody = Font.system(size: 16, weight: .regular, design: .serif)
}

struct PaperSurfaceModifier: ViewModifier {
    var textureOpacity: Double = 0.12

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                ProofDesk.paper
                Rectangle()
                    .fill(ImagePaint(image: Image("UncoatedPaperTexture"), scale: 1))
                    .opacity(textureOpacity)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func proofPaper(textureOpacity: Double = 0.12) -> some View {
        modifier(PaperSurfaceModifier(textureOpacity: textureOpacity))
    }
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
    /// Optional semantic foreground for bright fills such as recording red
    /// and marker green. Primary no longer implies that white must be legible.
    var foreground: Color?
    /// Fill the available width instead of hugging the label.
    var fill: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        KeycapSurface(
            configuration: configuration,
            role: role,
            size: size,
            tint: tint,
            foreground: foreground,
            fill: fill
        )
    }

    /// Holds the hover state a `ButtonStyle` value cannot own itself.
    struct KeycapSurface: View {
        let configuration: Configuration
        let role: VCButtonRole
        let size: VCButtonSize
        let tint: Color?
        let foreground: Color?
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
                return foreground ?? .white
            case .secondary:
                return foreground ?? tint ?? Keycap.label(scheme)
            case .quiet:
                if let foreground { return foreground }
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
        foreground: Color? = nil,
        fill: Bool = false
    ) -> VCButtonStyle {
        VCButtonStyle(role: role, size: size, tint: tint, foreground: foreground, fill: fill)
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

/// Legacy call-site name, now rendered as a planar proof slip. Keeping the
/// modifier avoids a risky all-at-once rewrite while removing dashboard glass
/// from every secondary surface in the product.
struct GlassCardModifier: ViewModifier {
    var radius: CGFloat = DS.radiusM
    var tint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(
                cardBackground
                    .shadow(color: Color.black.opacity(0.035), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tint?.opacity(0.28) ?? ProofDesk.rule, lineWidth: 0.7)
            )
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(reduceTransparency ? ProofDesk.paper : Color.white.opacity(0.42))
            if let tint {
                shape.fill(tint.opacity(0.065))
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

/// Small metadata lozenge. It is intentionally flat and typographic.
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
            Capsule().fill(reduceTransparency ? ProofDesk.paper : Color.black.opacity(0.035))
        }
        .overlay(
            Capsule().strokeBorder(ProofDesk.rule, lineWidth: 0.6)
        )
    }
}
