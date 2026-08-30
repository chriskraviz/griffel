import SwiftUI

extension WorkflowType {
    /// SwiftUI color for the `accentColor` token on this type.
    var accentUIColor: Color {
        switch accentColor {
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "indigo": return .indigo
        default: return .primary
        }
    }
}

/// Floating glass popup shown during background hotkey runs: a tinted pill
/// with a speech-bubble tail, a level orb at the leading end and the live
/// waveform filling the rest.
///
/// Observes the workflow directly, so it live-updates through every phase.
/// Entrance and icon motion come from `WorkflowType.hudAnimationStyle`;
/// with Reduce Motion only the tint identity remains.
struct HotkeyHUDView: View {
    let workflow: any Workflow
    let displayName: String

    private static let popupWidth: CGFloat = 340
    private static let orbDiameter: CGFloat = 46
    private static let contentRowHeight: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var doneBounce = false

    private var style: HUDAnimationStyle { workflow.type.hudAnimationStyle }
    private var accent: Color { workflow.type.accentUIColor }

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            orb

            VStack(alignment: .leading, spacing: 5) {
                headerRow
                contentRow
                inputDeviceRow
                if let partial = livePartialText {
                    Text(partial)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 11)
        .padding(.trailing, 16)
        .padding(.vertical, 11)
        .frame(width: Self.popupWidth)
        // Reserved strip for the tail, so no content sits inside it.
        .padding(.bottom, VoicePopupShape.Tail.bottom.height)
        .voicePopupSurface(tint: accent)
        .scaleEffect(hasAppeared ? 1.0 : style.entrance.startScale)
        .offset(hasAppeared ? .zero : style.entrance.startOffset)
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .onAppear {
            guard !reduceMotion else {
                hasAppeared = true
                return
            }
            withAnimation(style.entrance.spring) { hasAppeared = true }
        }
    }

    // MARK: - Orb

    private var orbMode: VoiceLevelOrb<AnyView>.Mode {
        if workflow.isRecording { return .listening }
        switch workflow.phase {
        case .done: return .success
        case .error: return .failure
        case .running: return .working
        case .idle: return .listening
        }
    }

    private var orb: some View {
        VoiceLevelOrb(
            tint: orbTint,
            level: workflow.audioLevel,
            mode: orbMode,
            diameter: Self.orbDiameter
        ) {
            AnyView(orbGlyph)
        }
    }

    private var orbTint: Color {
        switch orbMode {
        case .success: return .green
        case .failure: return .orange
        case .listening, .working: return accent
        }
    }

    @ViewBuilder
    private var orbGlyph: some View {
        switch orbMode {
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating, value: doneBounce)
                .onAppear {
                    guard !reduceMotion else { return }
                    doneBounce.toggle()
                }
        case .failure:
            Image(systemName: "exclamationmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
        case .listening, .working:
            workflowIcon
        }
    }

    /// Icon motion runs only while the workflow is actually working;
    /// terminal phases and Reduce Motion render a static icon.
    private var isIconAnimating: Bool {
        guard !reduceMotion else { return false }
        if case .running = workflow.phase { return true }
        return false
    }

    @ViewBuilder
    private var workflowIcon: some View {
        let base = Image(systemName: workflow.type.icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(accent)

        switch style.iconMotion {
        case .variableColorIterative:
            base.symbolEffect(.variableColor.iterative, options: .repeating, isActive: isIconAnimating)
        case .pulse:
            base.symbolEffect(.pulse, options: .repeating, isActive: isIconAnimating)
        case .breathe:
            if isIconAnimating {
                base.phaseAnimator([0.0, 1.0]) { view, phase in
                    view.scaleEffect(1.0 + phase * 0.1)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
            } else {
                base
            }
        }
    }

    // MARK: - Rows

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(displayName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 6)

            // The HUD only ever runs in hold mode — toggle mode opens the
            // popover instead — so the release hint is always accurate.
            if workflow.isRecording {
                Text("Taste loslassen")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var contentRow: some View {
        if workflow.isRecording {
            WaveformView(
                audioLevel: workflow.audioLevel,
                isRecording: true,
                accentColor: accent
            )
            .frame(height: Self.contentRowHeight)
        } else {
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(statusColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Self.contentRowHeight, alignment: .leading)
        }
    }

    /// Which microphone the run is actually on. Only while recording, because
    /// that is the only moment the answer is both true and useful.
    @ViewBuilder
    private var inputDeviceRow: some View {
        if let device = activeInputDevice {
            ActiveInputDeviceLabel(device: device)
        }
    }

    private var activeInputDevice: ActiveInputDevice? {
        guard workflow.isRecording else { return nil }
        return workflow.activeInputDevice
    }

    /// Cosmetic only, and only while the microphone is open — the pasted text
    /// always comes from the final batch pass.
    private var livePartialText: String? {
        guard workflow.isRecording else { return nil }
        return workflow.livePartialText
    }

    private var statusText: String {
        switch workflow.phase {
        case .idle: return "Bereit"
        case .running(let message): return message
        case .done: return doneStatusText
        case .error(let message): return message
        }
    }

    private var statusColor: Color {
        switch workflow.phase {
        case .done: return .green
        case .error: return .orange
        default: return .secondary
        }
    }

    private var doneStatusText: String {
        switch workflow.type {
        case .braindump: return "Im Eingang gespeichert"
        case .selectionEdit: return "Auswahl ersetzt"
        default: return "Eingefügt"
        }
    }
}
