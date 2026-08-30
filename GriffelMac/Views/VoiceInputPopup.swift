import SwiftUI
import AppKit

// MARK: - Shape

/// The voice popup silhouette: a pill with an optional speech-bubble tail.
///
/// Drawn as one continuous outline rather than a union of pill + triangle, so
/// `strokeBorder` traces pill *and* tail without a seam where they meet — and
/// so a single translucent fill covers both (two overlapping material fills
/// would double up into a visibly darker patch).
struct VoicePopupShape: InsettableShape {
    enum Tail {
        /// A plain pill.
        case none
        /// Speech-bubble tail, centered under the pill.
        case bottom

        var height: CGFloat {
            switch self {
            case .none: return 0
            case .bottom: return 9
            }
        }
    }

    var tail: Tail = .bottom
    /// The pill keeps this radius as it grows taller, so an extra row of
    /// content never stretches the silhouette into a stadium.
    var maxCornerRadius: CGFloat = 30
    var tailWidth: CGFloat = 26
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> VoicePopupShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let outer = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let tailHeight = max(0, tail.height - insetAmount)
        let body = CGRect(
            x: outer.minX,
            y: outer.minY,
            width: outer.width,
            height: outer.height - tailHeight
        )
        guard body.width > 0, body.height > 0 else { return Path() }

        let radius = min(min(body.height / 2, body.width / 2), maxCornerRadius)
        let tipWidth = max(0, min(tailWidth - insetAmount * 2, body.width - radius * 2))
        let centerX = body.midX
        let tipY = body.maxY + tailHeight

        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addArc(
            center: CGPoint(x: body.maxX - radius, y: body.minY + radius), radius: radius,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.addArc(
            center: CGPoint(x: body.maxX - radius, y: body.maxY - radius), radius: radius,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )

        if tailHeight > 0, tipWidth > 0 {
            path.addLine(to: CGPoint(x: centerX + tipWidth / 2, y: body.maxY))
            path.addQuadCurve(
                to: CGPoint(x: centerX, y: tipY),
                control: CGPoint(x: centerX + tipWidth * 0.16, y: tipY - tailHeight * 0.12)
            )
            path.addQuadCurve(
                to: CGPoint(x: centerX - tipWidth / 2, y: body.maxY),
                control: CGPoint(x: centerX - tipWidth * 0.16, y: tipY - tailHeight * 0.12)
            )
        }

        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.addArc(
            center: CGPoint(x: body.minX + radius, y: body.maxY - radius), radius: radius,
            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        path.addArc(
            center: CGPoint(x: body.minX + radius, y: body.minY + radius), radius: radius,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Surface

/// Glass surface for the popup: behind-window blur, a wash of the workflow
/// tint, a hairline light edge and a lifted shadow.
///
/// Unlike `glassCard`, the reduce-transparency fallback is *opaque*: the popup
/// floats in a borderless panel over the desktop, where a 5 % primary fill
/// would leave the text sitting on bare wallpaper.
struct VoicePopupSurface: ViewModifier {
    var tint: Color
    var shape: VoicePopupShape

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(shadowedBase)
                    shape.fill(tintWash)
                }
            }
            .overlay {
                shape.strokeBorder(edge, lineWidth: 0.9)
            }
    }

    private var base: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
            : AnyShapeStyle(.ultraThinMaterial)
    }

    /// The shadows ride on the *shape style*, not on a `.shadow` modifier
    /// around the view. A view-level shadow flattens its content into an
    /// offscreen layer, and a flattened material samples that layer instead
    /// of the desktop behind the panel — the blur would quietly die.
    private var shadowedBase: some ShapeStyle {
        base
            .shadow(.drop(color: .black.opacity(scheme == .dark ? 0.42 : 0.16), radius: 9, y: 4))
            .shadow(.drop(color: tint.opacity(scheme == .dark ? 0.24 : 0.18), radius: 18, y: 7))
    }

    private var tintWash: LinearGradient {
        LinearGradient(
            colors: [tint.opacity(scheme == .dark ? 0.20 : 0.14), tint.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var edge: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(scheme == .dark ? 0.34 : 0.62),
                Color.white.opacity(scheme == .dark ? 0.06 : 0.16),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    /// Wraps the view in the voice popup's glass pill.
    func voicePopupSurface(tint: Color, tail: VoicePopupShape.Tail = .bottom) -> some View {
        modifier(VoicePopupSurface(tint: tint, shape: VoicePopupShape(tail: tail)))
    }
}

// MARK: - Level Orb

/// The circular badge at the leading end of the popup — the mode's identity.
/// While listening, a soft ring breathes with the microphone level; while
/// working, the ring becomes a spinning arc.
struct VoiceLevelOrb<Glyph: View>: View {
    enum Mode {
        case listening
        case working
        case success
        case failure
    }

    var tint: Color
    var level: Float
    var mode: Mode
    var diameter: CGFloat = 46
    @ViewBuilder var glyph: Glyph

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spins = false

    var body: some View {
        ZStack {
            if mode == .listening, !reduceMotion {
                Circle()
                    .fill(tint.opacity(0.16))
                    .scaleEffect(1.0 + CGFloat(clampedLevel) * 0.26)
                    .animation(.easeOut(duration: 0.14), value: clampedLevel)
            }

            Circle().fill(tint.opacity(0.14))

            Circle()
                .strokeBorder(tint.opacity(mode == .working ? 0.22 : 0.55), lineWidth: 1.6)

            if mode == .working {
                if reduceMotion {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                } else {
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .padding(0.8)
                        .rotationEffect(.degrees(spins ? 360 : 0))
                        .animation(
                            .linear(duration: 1.05).repeatForever(autoreverses: false),
                            value: spins
                        )
                        .onAppear { spins = true }
                }
            }

            if mode != .working || !reduceMotion {
                glyph
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var clampedLevel: Float {
        min(1, max(0, level))
    }
}
