import SwiftUI

/// Records a shortcut by watching what the user actually presses.
///
/// The two shapes are told apart by what arrives: any `keyDown` makes it a key
/// combination, while modifiers that go down and come back up without one make
/// it a chord. A *local* monitor is enough — and necessary, since it can
/// swallow the keystroke so recording `⌘W` does not close anything.
struct HotkeyRecorderField: View {
    let type: WorkflowType
    let hotkey: Hotkey
    let isDefault: Bool
    /// Which field currently owns the keyboard, if any. Arming one disarms the
    /// others: two live monitors would race for the same keystroke, and
    /// whichever finished first would re-arm the global shortcuts while the
    /// other was still swallowing keys.
    @Binding var recordingType: WorkflowType?
    /// Called with the recorded combination; the caller validates and stores.
    let onRecord: (Hotkey) -> Void
    let onReset: () -> Void
    /// Frees the global combinations while recording, so an existing binding
    /// does not swallow the keystroke before it can be read.
    let onRecordingChange: (Bool) -> Void

    @State private var monitor: Any?
    @State private var capturedFlags: NSEvent.ModifierFlags = []
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var isRecording: Bool { recordingType == type }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Group {
                    if isRecording {
                        Text(capturedFlags.isEmpty ? "Drücke ein Kürzel …" : Hotkey(modifiers: capturedFlags).displayLabel)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        // Keycap symbols, not the word form — the same
                        // spelling the badges on the main page use.
                        HotkeyBadge(tokens: hotkey.keycapTokens)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Esc bricht ab" : "Klicken und neues Kürzel drücken")

            // Nothing to reset on a default binding, so the control is absent
            // rather than sitting there disabled.
            if !isDefault && !isRecording {
                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.vc(.quiet, .icon))
                .help("Auf Standard zurücksetzen")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous)
                .fill(isRecording ? Color.accentColor.opacity(0.14)
                                  : Color.primary.opacity(isHovered ? 0.06 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous)
                .strokeBorder(isRecording ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        // Another field took over, so let go of the keyboard.
        .onChange(of: recordingType) { _, newValue in
            if newValue != type { tearDownMonitor() }
        }
        .onDisappear(perform: stopRecording)
    }

    // MARK: - Recording

    private func startRecording() {
        guard monitor == nil else { return }
        capturedFlags = []
        recordingType = type
        onRecordingChange(true)
        // A local monitor only sees events delivered to this app, and an
        // accessory app can have its popover on screen without being active.
        // Without this the field would sit there recording nothing.
        NSApp.activate(ignoringOtherApps: true)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let flags = event.modifierFlags.intersection(Hotkey.relevantMask)

            if event.type == .keyDown {
                if event.keyCode == 53 { // Escape cancels without changing anything
                    stopRecording()
                    return nil
                }
                let recorded = Hotkey(keyCode: event.keyCode, modifiers: flags)
                stopRecording()
                onRecord(recorded)
                return nil
            }

            // flagsChanged: grow while keys go down, commit when they all go up.
            if flags.isEmpty {
                let recorded = Hotkey(modifiers: capturedFlags)
                let hadModifiers = !capturedFlags.isEmpty
                stopRecording()
                if hadModifiers {
                    onRecord(recorded)
                }
            } else {
                capturedFlags.formUnion(flags)
            }
            return nil
        }
    }

    private func stopRecording() {
        let wasRecording = tearDownMonitor()
        if wasRecording, recordingType == type {
            recordingType = nil
        }
    }

    /// Releases the keyboard without touching whose turn it is — that is the
    /// caller's business, and on a hand-over it already belongs to someone else.
    @discardableResult
    private func tearDownMonitor() -> Bool {
        guard let monitor else { return false }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        capturedFlags = []
        onRecordingChange(false)
        return true
    }
}
