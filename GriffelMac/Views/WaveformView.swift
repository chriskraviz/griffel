import SwiftUI
import Combine

/// Manages waveform bar levels and an internal display timer.
/// Lives as a reference type so the Timer closure always reads fresh state.
@MainActor
final class WaveformState: ObservableObject {
    /// Resting height of a bar with no signal — kept above zero so the
    /// hollow outline of a silent bar still reads.
    static let floorLevel: CGFloat = 0.05
    static let barCount = 32

    @Published var levels: [CGFloat] = Array(repeating: floorLevel, count: barCount)

    /// The current audio level fed from the parent -- updated on every
    /// SwiftUI body evaluation so the timer always has the latest value.
    var currentAudioLevel: Float = 0

    /// Jitter and breathing are decoration on top of the real signal; with
    /// Reduce Motion the bars move only as much as the microphone does.
    var synthesizesMotion = true

    private var phase: Double = 0
    private var timer: Timer?

    func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        levels = Array(repeating: Self.floorLevel, count: Self.barCount)
        phase = 0
    }

    private func tick() {
        phase += 0.15
        let base = CGFloat(currentAudioLevel)
        let jitter = synthesizesMotion ? CGFloat.random(in: -0.06...0.06) : 0
        let breathe = synthesizesMotion ? sin(phase) * 0.03 : 0
        let newLevel = max(Self.floorLevel, min(1.0, base + jitter + breathe))
        levels.removeFirst()
        levels.append(newLevel)
    }

    deinit {
        timer?.invalidate()
    }
}

/// Scrolling voice waveform: mirrored capsule bars, newest at the trailing
/// edge. A bar is drawn solid once its level clears `voicedThreshold` and
/// hollow below it, so speech and the pauses between it read at a glance.
struct WaveformView: View {
    var audioLevel: Float
    var isRecording: Bool
    var accentColor: Color = .primary
    var barWidth: CGFloat = 4
    var minBarHeight: CGFloat = 5
    /// Share of the row a silent bar still occupies. Without it a pause
    /// collapses the outlined bars into dots; the waveform should read as a
    /// bed of hollow bars with speech rising out of it.
    var restingHeightFraction: CGFloat = 0.32
    /// Level above which a bar is filled instead of outlined.
    var voicedThreshold: CGFloat = 0.26

    @StateObject private var state = WaveformState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            draw(in: &context, size: size)
        }
        .onChange(of: audioLevel) { _, newLevel in
            state.currentAudioLevel = newLevel
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                state.currentAudioLevel = audioLevel
                state.synthesizesMotion = !reduceMotion
                state.startTimer()
            } else {
                state.stopTimer()
                state.reset()
            }
        }
        .onAppear {
            state.currentAudioLevel = audioLevel
            state.synthesizesMotion = !reduceMotion
            if isRecording {
                state.startTimer()
            }
        }
        .onDisappear {
            state.stopTimer()
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let levels = state.levels
        guard !levels.isEmpty, size.width > 0, size.height > 0 else { return }

        let slot = size.width / CGFloat(levels.count)
        let width = min(barWidth, slot * 0.62)
        let radius = width / 2
        let midY = size.height / 2
        let lastIndex = max(1, levels.count - 1)

        for (index, level) in levels.enumerated() {
            let envelope = restingHeightFraction + (1 - restingHeightFraction) * min(1, max(0, level))
            let height = max(minBarHeight, min(size.height, envelope * size.height))
            let rect = CGRect(
                x: CGFloat(index) * slot + (slot - width) / 2,
                y: midY - height / 2,
                width: width,
                height: height
            )
            // Older samples fade out towards the leading edge, so the live
            // end of the waveform is the one the eye lands on.
            let presence = 0.45 + 0.55 * (Double(index) / Double(lastIndex))

            if level >= voicedThreshold {
                context.fill(
                    Path(roundedRect: rect, cornerRadius: radius),
                    with: .color(accentColor.opacity(presence))
                )
            } else {
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: 0.55, dy: 0.55), cornerRadius: max(0.5, radius - 0.55)),
                    with: .color(accentColor.opacity(presence * 0.85)),
                    lineWidth: 1.1
                )
            }
        }
    }
}
