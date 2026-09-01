import SwiftUI

@main
struct GriffelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // ⌘, is already in the app menu — SwiftUI puts it there for any
        // `Settings` scene — so the scene was reachable long before it had
        // anything in it. Hosting the popover's own `SettingsContentView`
        // here means the shortcut reaches the real settings rather than a
        // second copy of them: one view, two frames.
        // The scene exists only because SwiftUI needs one, and because it is
        // what puts „Einstellungen …“ (⌘,) in the app menu at all. Its own
        // window is never reached: `AppDelegate.retargetSettingsMenuItem()`
        // re-points that item at the Ablage window, where the settings now
        // live. One shortcut opening two different settings surfaces would be
        // worse than the blank window this replaces.
        Settings {
            EmptyView()
        }
    }
}


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let menuBarStatusController = MenuBarStatusController()
    private let hotkeyHUDController = HotkeyHUDController()
    let appState = AppState()
    private lazy var mainWindowController = MainWindowController(appState: appState)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            menuBarStatusController.attach(to: button)
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuBarView(appState: appState))

        NSApp.setActivationPolicy(.accessory)

        // Hotkey events
        appState.hotkeyService.onHotkeyEvent = { [weak self] event in
            self?.handleHotkeyEvent(event)
        }
        appState.onMenuBarStatusChange = { [weak self] status in
            self?.menuBarStatusController.update(to: status)
        }
        appState.onOpenMainWindow = { [weak self] in
            self?.showMainWindow()
        }
        appState.onHUDEvent = { [weak self] event in
            switch event {
            case .show(let workflow, let displayName):
                self?.hotkeyHUDController.show(workflow: workflow, displayName: displayName)
            case .dismiss(let delay):
                self?.hotkeyHUDController.dismiss(after: delay)
            }
        }
        appState.startHotkeys()

        // Listen for popover dismiss requests (from auto-paste)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissPopover),
            name: .dismissPopover,
            object: nil
        )

        DispatchQueue.main.async { [weak self] in
            self?.retargetSettingsMenuItem()
            self?.showOnboardingIfNeeded()
        }
    }

    /// Clicking the Dock icon (only present while the window is open) brings
    /// it back instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    /// Closing the window returns the app to the menu bar; it never quits it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// SwiftUI owns the „Einstellungen …“ item and offers no hook to change
    /// what it does, so it is re-pointed once the menu exists. Idempotent, and
    /// called again whenever the window opens because the menu is not
    /// guaranteed to be built by `applicationDidFinishLaunching`.
    private func retargetSettingsMenuItem() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let item = appMenu.items.first(where: { $0.keyEquivalent == "," }) else {
            return
        }
        item.target = self
        item.action = #selector(openWindowSettings)
    }

    @objc private func openWindowSettings() {
        appState.windowSection = .settings
        showMainWindow()
    }

    private func showMainWindow() {
        retargetSettingsMenuItem()
        if popover.isShown {
            popover.performClose(nil)
            appState.isPopoverShown = false
        }
        mainWindowController.show()
    }

    @objc private func handleDismissPopover() {
        appState.isPopoverShown = false
        popover.performClose(nil)
    }

    private func handleHotkeyEvent(_ event: HotkeyEvent) {
        switch event {
        case .down(let type):
            handleHotkeyDown(type)
        case .up(let type):
            handleHotkeyUp(type)
        case .cancel:
            handleHotkeyCancel()
        }
    }

    private func handleHotkeyDown(_ type: WorkflowType) {
        guard appState.isConfigured else { return }

        let mode = appState.appSettings.hotkeyMode

        switch mode {
        case .hold:
            // Hold mode: start recording on key down
            appState.startWorkflow(type, source: .hotkeyBackground)

        case .toggle:
            // Toggle mode: if already recording same workflow, stop it.
            // `isRecording`, not the phase: after a silence auto-stop the
            // phase is still .running while the transcript is produced, and
            // a press then means "next dictation", not "discard that work".
            if let active = appState.activeWorkflow,
               active.type == type,
               active.isRecording {
                active.stop()
            } else {
                appState.prepareForPopoverPresentation()
                appState.startWorkflow(type, source: .manual)
                showPopover()
            }
        }
    }

    private func handleHotkeyUp(_ type: WorkflowType) {
        let mode = appState.appSettings.hotkeyMode

        guard mode == .hold else { return }

        // Hold mode: stop recording on key release. `isRecording`, not the
        // .running phase: after a silence auto-stop the phase is still
        // .running ("Wird transkribiert ...") while the transcript is
        // produced, and stop() would then cancel that task — the release
        // that ends the hold must never cost the dictation its result.
        if let active = appState.activeWorkflow,
           active.type == type,
           active.isRecording {
            active.stop()
        }
    }

    private func handleHotkeyCancel() {
        appState.activeWorkflow?.stop()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            appState.isPopoverShown = false
        } else {
            appState.prepareForPopoverPresentation()
            showPopover()
        }
    }

    private func showOnboardingIfNeeded() {
        guard appState.shouldShowOnboarding else { return }
        appState.prepareForPopoverPresentation()
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        appState.isPopoverShown = true
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            appState.isPopoverShown = false
            switch appState.currentPhase {
            case .done, .error:
                appState.resetCurrentWorkflow()
            default:
                appState.page = .main
            }
        }
    }
}
