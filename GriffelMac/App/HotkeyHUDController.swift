import AppKit
import SwiftUI

/// Owns the floating, non-activating HUD panel for background hotkey runs.
/// The panel never takes focus (paste depends on the target app staying
/// frontmost) and ignores mouse events entirely.
@MainActor
final class HotkeyHUDController {
    private static let fallbackSize = NSSize(width: 376, height: 111)

    private var panel: NSPanel?
    private var hosting: NSHostingController<HotkeyHUDView>?
    private var hideTask: Task<Void, Never>?
    /// Bottom-center the popup is pinned to, captured once per run so a
    /// growing popup (live transcript line, two-line error) stays put instead
    /// of sliding down the screen.
    private var anchor: NSPoint?
    private var resizeObserver: NSObjectProtocol?

    func show(workflow: any Workflow, displayName: String) {
        hideTask?.cancel()
        hideTask = nil

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let hosting = NSHostingController(
            rootView: HotkeyHUDView(workflow: workflow, displayName: displayName)
        )
        // Lets the panel follow the popup when SwiftUI grows it mid-run.
        hosting.sizingOptions = [.preferredContentSize]
        self.hosting = hosting
        panel.contentViewController = hosting

        let size = hosting.view.fittingSize
        panel.setContentSize(size.width > 0 && size.height > 0 ? size : Self.fallbackSize)
        captureAnchor(for: panel)
        applyAnchor(to: panel)
        observeResize(of: panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func dismiss(after delay: TimeInterval) {
        guard panel != nil else { return }
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            self?.hideNow()
        }
    }

    private func hideNow() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.panel?.orderOut(nil)
                // Tears down the SwiftUI tree so the waveform timer stops.
                self.panel?.contentViewController = nil
                self.hosting = nil
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.fallbackSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }

    private func observeResize(of panel: NSPanel) {
        guard resizeObserver == nil else { return }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel else { return }
                self.applyAnchor(to: panel)
            }
        }
    }

    /// Bottom-center of the screen the mouse is on — the best available proxy
    /// for where the user is working on multi-screen setups.
    private func captureAnchor(for panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }

        let frame = screen.visibleFrame
        anchor = NSPoint(x: frame.midX, y: frame.minY + 120)
    }

    private func applyAnchor(to panel: NSPanel) {
        guard let anchor else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: anchor.x - size.width / 2, y: anchor.y))
    }

    deinit {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
    }
}
