import AppKit

enum SelectionCaptureError: LocalizedError {
    case noSelection

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "Keine Auswahl gefunden. Markiere zuerst Text."
        }
    }
}

/// Grabs the frontmost app's text selection via a synthetic Cmd+C.
/// The previous clipboard is snapshotted so callers can restore it whenever
/// the edit does not complete.
@MainActor
enum SelectionCaptureService {
    struct PasteboardSnapshot {
        let changeCount: Int
        let string: String?
    }

    static func snapshot() -> PasteboardSnapshot {
        let pasteboard = NSPasteboard.general
        return PasteboardSnapshot(
            changeCount: pasteboard.changeCount,
            string: pasteboard.string(forType: .string)
        )
    }

    static func restore(_ snapshot: PasteboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let string = snapshot.string {
            pasteboard.setString(string, forType: .string)
        }
    }

    /// Returns the captured selection plus the pre-capture snapshot (only
    /// string contents — best effort). Restores the snapshot itself and
    /// throws when no selection lands on the pasteboard within the timeout;
    /// secure-input contexts (password fields) end up here too.
    static func captureSelectedText(
        timeout: TimeInterval = 0.6
    ) async throws -> (text: String, previous: PasteboardSnapshot) {
        let pasteboard = NSPasteboard.general
        let previous = snapshot()

        postCmdC()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            guard pasteboard.changeCount != previous.changeCount else { continue }

            let captured = pasteboard.string(forType: .string)
            if let captured, !captured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (text: captured, previous: previous)
            }
            break
        }

        restore(previous)
        throw SelectionCaptureError.noSelection
    }

    private static func postCmdC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
