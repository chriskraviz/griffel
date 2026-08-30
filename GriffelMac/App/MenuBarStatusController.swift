import AppKit

enum MenuBarStatus: Equatable {
    case idle
    case recording(WorkflowType)
    case processing(WorkflowType)
    case success(WorkflowType?)
    case error(WorkflowType?)
}

@MainActor
final class MenuBarStatusController {
    private weak var button: NSStatusBarButton?
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var currentStatus: MenuBarStatus = .idle

    func attach(to button: NSStatusBarButton) {
        self.button = button
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        renderCurrentStatus()
    }

    func update(to status: MenuBarStatus) {
        currentStatus = status
        animationFrame = 0
        configureAnimationIfNeeded()
        renderCurrentStatus()
    }

    private func configureAnimationIfNeeded() {
        stopAnimation()

        switch currentStatus {
        case .recording:
            startAnimation(interval: 0.12)
        case .processing:
            startAnimation(interval: 0.18)
        default:
            break
        }
    }

    private func startAnimation(interval: TimeInterval) {
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(animationTimer!, forMode: .common)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func tick() {
        animationFrame = (animationFrame + 1) % 4
        renderCurrentStatus()
    }

    private func renderCurrentStatus() {
        guard let button else { return }
        button.image = MenuBarStatusIconRenderer.makeImage(for: currentStatus, frame: animationFrame)
        button.image?.isTemplate = true
        button.toolTip = tooltip(for: currentStatus)
    }

    private func tooltip(for status: MenuBarStatus) -> String {
        switch status {
        case .idle:
            return "Griffel ist bereit"
        case .recording(let type):
            return "\(type.displayName): Aufnahme läuft"
        case .processing(let type):
            return "\(type.displayName): Verarbeitung läuft"
        case .success(let type):
            if let type {
                return "\(type.displayName): Fertig"
            }
            return "Griffel: Fertig"
        case .error(let type):
            if let type {
                return "\(type.displayName): Fehler"
            }
            return "Griffel: Fehler"
        }
    }

    deinit {
        animationTimer?.invalidate()
    }
}

private enum MenuBarStatusIconRenderer {
    static func makeImage(for status: MenuBarStatus, frame: Int) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            drawBaseIcon(in: bounds, status: status, frame: frame)

            switch status {
            case .recording(let type):
                drawActivityBadge(
                    type: type,
                    systemName: badgeSymbol(for: type),
                    in: bounds,
                    frame: frame,
                    phase: .recording
                )
            case .processing(let type):
                drawActivityBadge(
                    type: type,
                    systemName: badgeSymbol(for: type),
                    in: bounds,
                    frame: frame,
                    phase: .processing
                )
            case .success:
                drawBadge(systemName: "checkmark", in: bounds, fillOpacity: 1.0)
            case .error:
                drawBadge(systemName: "exclamationmark", in: bounds, fillOpacity: 1.0)
            default:
                break
            }

            return true
        }
        image.isTemplate = true
        image.size = size
        return image
    }

    private enum ActivityPhase {
        case recording
        case processing
    }

    /// The mark: one stroke that begins on the left as a spoken wave and
    /// settles into a written line, with two started lines underneath — the
    /// gesture the app icon makes, drawn for 18 points.
    ///
    /// Every state comes through here, the resting one included. There used to
    /// be a `menubar_icon.png` for idle, and the two had quietly drifted apart:
    /// the PNG put the widest line at the top while this code put it at the
    /// bottom, so the mark flipped over the moment a recording started. One
    /// definition cannot disagree with itself.
    ///
    /// Index 0 is the topmost element, which is the order the alpha tables
    /// below read in.
    private static func drawBaseIcon(in bounds: CGRect, status: MenuBarStatus, frame: Int) {
        let alpha = baseAlphaValues(for: status, frame: frame)
        let inset: CGFloat = 1.8
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let lineWidth: CGFloat = 1.8

        // The wavelength is long against the amplitude on purpose: the radius
        // of curvature at a sine's crest is lambda^2 / (4*pi^2*A), and once it
        // approaches the half line width the crests render as blobs instead of
        // curves. At 18 points there is no room to get that wrong.
        let axis = bounds.minY + 12.8
        let amplitude: CGFloat = 1.5
        let wavelength: CGFloat = 10.0
        let waveEnd = left + wavelength

        let stroke = NSBezierPath()
        stroke.lineWidth = lineWidth
        stroke.lineCapStyle = .round
        stroke.lineJoinStyle = .round
        stroke.move(to: CGPoint(x: left, y: axis))
        var x = left
        while x < waveEnd {
            x = min(x + 0.25, waveEnd)
            let phase = Double(x - left) / Double(wavelength) * 2 * Double.pi
            stroke.line(to: CGPoint(x: x, y: axis + amplitude * CGFloat(sin(phase))))
        }
        stroke.line(to: CGPoint(x: right, y: axis))
        NSColor.black.withAlphaComponent(alpha[0]).setStroke()
        stroke.stroke()

        // The two started lines, in the app icon's proportions against the
        // stroke above it: roughly three quarters and just under half.
        //
        // Every state but idle puts a badge in the bottom-right corner, and it
        // is wide — 7.5 of the 18 points. The lines give way to it instead of
        // running underneath, because two black shapes that overlap at this
        // size are one muddy shape, not two. The wave never has to move: it
        // sits above the badge and carries the mark's identity on its own.
        let badged: Bool
        if case .idle = status {
            badged = false
        } else {
            badged = true
        }
        let startedLines: [(width: CGFloat, centerY: CGFloat)] = badged
            ? [(7.0, bounds.minY + 7.6), (4.3, bounds.minY + 3.6)]
            : [(10.5, bounds.minY + 7.6), (6.5, bounds.minY + 3.6)]
        for (index, line) in startedLines.enumerated() {
            let rect = CGRect(
                x: left,
                y: line.centerY - (lineWidth / 2),
                width: line.width,
                height: lineWidth
            )
            let path = NSBezierPath(
                roundedRect: rect,
                xRadius: lineWidth / 2,
                yRadius: lineWidth / 2
            )
            NSColor.black.withAlphaComponent(alpha[index + 1]).setFill()
            path.fill()
        }
    }

    private static func drawActivityBadge(
        type: WorkflowType,
        systemName: String,
        in bounds: CGRect,
        frame: Int,
        phase: ActivityPhase
    ) {
        let badgeSize: CGFloat = 7.5
        let badgeRect = CGRect(
            x: bounds.maxX - badgeSize - 0.8,
            y: bounds.minY + 0.8,
            width: badgeSize,
            height: badgeSize
        )

        let badgeOpacity: CGFloat
        let haloOpacity: CGFloat

        switch phase {
        case .recording:
            let values: [CGFloat]
            switch type {
            case .transcription, .braindump:
                values = [0.74, 1.0, 0.82, 0.92]
            case .textImprover, .selectionEdit:
                values = [0.66, 0.84, 1.0, 0.8]
            }
            badgeOpacity = values[frame % values.count]
            haloOpacity = 0.14 + (CGFloat(frame % 4) * 0.04)
        case .processing:
            let values: [CGFloat]
            switch type {
            case .transcription, .braindump:
                values = [0.58, 0.72, 0.9, 0.72]
            case .textImprover, .selectionEdit:
                values = [0.48, 0.68, 0.92, 0.84]
            }
            badgeOpacity = values[frame % values.count]
            haloOpacity = 0.12 + (CGFloat((frame + 2) % 4) * 0.03)
        }

        let haloInset = phase == .recording ? -0.8 : -0.45
        let haloRect = badgeRect.insetBy(dx: haloInset, dy: haloInset)
        let haloPath = NSBezierPath(ovalIn: haloRect)
        NSColor.black.withAlphaComponent(haloOpacity).setStroke()
        haloPath.lineWidth = phase == .recording ? 0.9 : 0.75
        haloPath.stroke()

        drawBadge(systemName: systemName, in: bounds, fillOpacity: badgeOpacity)

        if phase == .processing {
            drawProcessingDot(around: badgeRect, frame: frame)
        }
    }

    private static func drawBadge(systemName: String, in bounds: CGRect, fillOpacity: CGFloat) {
        let badgeSize: CGFloat = 7.5
        let badgeRect = CGRect(
            x: bounds.maxX - badgeSize - 0.8,
            y: bounds.minY + 0.8,
            width: badgeSize,
            height: badgeSize
        )

        let badgePath = NSBezierPath(ovalIn: badgeRect)
        NSColor.black.withAlphaComponent(fillOpacity).setFill()
        badgePath.fill()

        guard let symbol = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: nil
        ) else {
            return
        }

        let config = NSImage.SymbolConfiguration(pointSize: 5.5, weight: .bold)
        let configuredSymbol = symbol.withSymbolConfiguration(config) ?? symbol
        let symbolRect = badgeRect.insetBy(dx: 1.2, dy: 1.2)
        configuredSymbol.draw(
            in: symbolRect,
            from: .zero,
            operation: .destinationOut,
            fraction: 1.0
        )
    }

    private static func drawProcessingDot(around badgeRect: CGRect, frame: Int) {
        let orbitPoints: [CGPoint] = [
            CGPoint(x: badgeRect.midX, y: badgeRect.maxY + 0.35),
            CGPoint(x: badgeRect.maxX + 0.35, y: badgeRect.midY),
            CGPoint(x: badgeRect.midX, y: badgeRect.minY - 0.35),
            CGPoint(x: badgeRect.minX - 0.35, y: badgeRect.midY),
        ]
        let point = orbitPoints[frame % orbitPoints.count]
        let dotRect = CGRect(x: point.x - 0.85, y: point.y - 0.85, width: 1.7, height: 1.7)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor.black.withAlphaComponent(0.92).setFill()
        dotPath.fill()
    }

    /// Three values: the wave, then the two lines under it, top to bottom.
    /// Four patterns everywhere below, because the frame counter runs `% 4` —
    /// three would stutter on every fourth frame.
    private static func baseAlphaValues(for status: MenuBarStatus, frame: Int) -> [CGFloat] {
        switch status {
        case .idle:
            return [1.0, 0.78, 0.52]
        case .recording(let type):
            return recordingAlphaValues(for: type, frame: frame)
        case .processing(let type):
            return processingAlphaValues(for: type, frame: frame)
        case .success:
            return [1.0, 0.9, 0.74]
        case .error:
            return [1.0, 0.68, 0.48]
        }
    }

    private static func recordingAlphaValues(for type: WorkflowType, frame: Int) -> [CGFloat] {
        switch type {
        case .transcription, .braindump:
            // A sharp pulse running down the mark and sweeping back.
            let patterns: [[CGFloat]] = [
                [1.0, 0.4, 0.24],
                [0.74, 1.0, 0.38],
                [0.44, 0.74, 1.0],
                [0.7, 0.96, 0.44],
            ]
            return patterns[frame % patterns.count]
        case .textImprover, .selectionEdit:
            // The same travel, but broader — these two take longer anyway.
            let patterns: [[CGFloat]] = [
                [1.0, 0.88, 0.5],
                [0.86, 1.0, 0.84],
                [0.58, 0.88, 1.0],
                [0.82, 0.98, 0.8],
            ]
            return patterns[frame % patterns.count]
        }
    }

    private static func processingAlphaValues(for type: WorkflowType, frame: Int) -> [CGFloat] {
        switch type {
        case .transcription, .braindump:
            // Breathing, not travelling: waiting is not the same as listening.
            let patterns: [[CGFloat]] = [
                [1.0, 0.84, 0.66],
                [0.92, 0.78, 0.62],
                [0.84, 0.72, 0.58],
                [0.92, 0.78, 0.62],
            ]
            return patterns[frame % patterns.count]
        case .textImprover, .selectionEdit:
            let patterns: [[CGFloat]] = [
                [1.0, 0.76, 0.52],
                [0.86, 1.0, 0.74],
                [0.64, 0.88, 1.0],
                [0.82, 0.96, 0.76],
            ]
            return patterns[frame % patterns.count]
        }
    }

    /// The badge always shows the workflow's own glyph — keeping a second icon
    /// table here is how the two drifted apart in the first place.
    private static func badgeSymbol(for type: WorkflowType) -> String {
        type.icon
    }
}
