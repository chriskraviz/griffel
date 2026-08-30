import AppKit
import SwiftUI

/// Owns the app's one real window. Griffel is a menu bar app
/// (`LSUIElement`), so the activation policy is raised to `.regular` only
/// while the window is open — that is what gives it a Dock icon, an app menu
/// with working Cut/Copy/Paste, and normal keyboard focus. Closing it drops
/// back to `.accessory`, and the app is a menu bar extra again.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: MainWindowView(appState: appState))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Griffel"
        // The window draws its own header, so the titlebar only carries the
        // traffic lights.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(MainWindowView.defaultSize)
        window.contentMinSize = MainWindowView.minimumSize
        window.center()
        window.setFrameAutosaveName("GriffelMainWindow")
        return window
    }

    nonisolated func windowDidBecomeKey(_ notification: Notification) {
        Task { @MainActor [appState] in
            appState.mainWindowDidBecomeKey()
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        // After the close completes, so the window is not torn down while the
        // policy change is still settling.
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
