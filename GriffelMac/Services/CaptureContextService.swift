import AppKit
import ApplicationServices

/// Where a dictation was spoken: the app that was in front, and the title of
/// its focused window. Every field is optional — the context is a nice-to-have
/// note on an entry, never a precondition for capturing one.
struct CaptureContext: Codable, Hashable {
    var appName: String?
    var bundleIdentifier: String?
    var windowTitle: String?

    var isEmpty: Bool {
        appName == nil && bundleIdentifier == nil && windowTitle == nil
    }

    /// "Safari — Tagesschau" / "Safari" / nil.
    var displayText: String? {
        let name = appName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (name?.isEmpty == false ? name : nil, title?.isEmpty == false ? title : nil) {
        case let (name?, title?):
            // Many apps title their window after themselves; saying it twice
            // reads like a bug.
            return title.caseInsensitiveCompare(name) == .orderedSame ? name : "\(name) \u{2014} \(title)"
        case let (name?, nil):
            return name
        case let (nil, title?):
            return title
        case (nil, nil):
            return nil
        }
    }

    init(appName: String? = nil, bundleIdentifier: String? = nil, windowTitle: String? = nil) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
    }

    enum CodingKeys: String, CodingKey {
        case appName
        case bundleIdentifier
        case windowTitle
    }

    /// Field by field with defaults, like every persisted struct in this app —
    /// this rides along in `braindump.json`, and a decode failure there would
    /// take the user's whole inbox with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
    }
}

/// Reads the frontmost app and its focused window title.
///
/// The window title comes from the Accessibility API (`kAXFocusedWindow` ->
/// `kAXTitle`) — the same permission the app already needs for auto-paste.
/// It deliberately does **not** use `CGWindowListCopyWindowInfo`: since macOS
/// 14 `kCGWindowName` is gated behind Screen Recording, and this app has no
/// business asking for that.
enum CaptureContextService {
    /// Ceiling for one AX round trip. An unresponsive target app would
    /// otherwise block the caller for the system default of 6 seconds.
    private static let messagingTimeout: Float = 0.35

    /// The app/window in front right now, or nil for Griffel itself —
    /// a dictation started from our own window has no foreign context worth
    /// recording, and claiming one would be a lie.
    @MainActor
    static func frontmostApplication() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return nil
        }
        return app
    }

    /// App identity only. Cheap and permission-free.
    @MainActor
    static func identity(of app: NSRunningApplication) -> CaptureContext {
        CaptureContext(
            appName: app.localizedName,
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: nil
        )
    }

    /// The focused window's title, or nil when Accessibility is not granted,
    /// the app exposes no focused window, or it does not answer in time.
    /// Safe off the main thread — the AX call is synchronous, so it belongs
    /// off it.
    nonisolated static func focusedWindowTitle(for processIdentifier: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)

        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success else {
            return nil
        }
        guard let window = focusedWindow, CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return nil
        }

        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            kAXTitleAttribute as CFString,
            &title
        ) == .success else {
            return nil
        }

        let text = (title as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    /// Full context: identity now, title resolved off the main actor. Callers
    /// start this when a run begins and read the result when the transcript
    /// lands, so the AX round trip never sits in the recording-start path.
    @MainActor
    static func capture(from app: NSRunningApplication) async -> CaptureContext {
        var context = identity(of: app)
        let processIdentifier = app.processIdentifier
        context.windowTitle = await Task.detached(priority: .utility) {
            focusedWindowTitle(for: processIdentifier)
        }.value
        return context
    }
}
