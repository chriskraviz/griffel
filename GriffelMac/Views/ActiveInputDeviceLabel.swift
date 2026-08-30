import SwiftUI

/// Names the input the microphone is actually open on during a recording.
///
/// Reads `Workflow.activeInputDevice`, never `AppSettings`: `AudioRecorder`
/// falls back to the system default when the picked device is gone, and it
/// does so silently on purpose — a vanished microphone must not fail a
/// recording. A label built from the setting would therefore confidently name
/// a device that is not plugged in, which is worse than no label at all.
/// `· Standardgerät` is what keeps that fallback from reading as the setting
/// having changed itself.
struct ActiveInputDeviceLabel: View {
    let device: ActiveInputDevice

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mic.fill")
                .font(.system(size: 9))
            // The name yields and the marker does not: a long device name
            // must not be what truncates `· Standardgerät` away, since that
            // suffix is the whole reason the label is worth reading.
            Text(device.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if device.isFallback {
                Text("· Standardger\u{00E4}t")
                    .fixedSize()
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mikrofon: \(label)")
    }

    private var label: String {
        device.isFallback ? "\(device.name) · Standardgerät" : device.name
    }
}
