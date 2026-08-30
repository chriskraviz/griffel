import SwiftUI

/// The microphone choice, living in the popover's mode card — the one place it
/// is offered, so there is no second copy to keep in step.
/// `AudioInputDeviceService` is an observable singleton with a Core Audio
/// listener, so the list refreshes on plug and unplug without any redraw here.
struct InputDevicePicker: View {
    @Bindable var appState: AppState
    @State private var service = AudioInputDeviceService.shared

    /// A saved device that is not currently attached. Kept as an explicit
    /// option so selecting it back is possible and the picker never silently
    /// snaps to a different microphone than the one that is stored.
    private var missingSelectedUID: String? {
        guard let uid = appState.appSettings.preferredInputDeviceUID,
              !uid.isEmpty,
              !service.devices.contains(where: { $0.id == uid }) else {
            return nil
        }
        return uid
    }

    var body: some View {
        Picker("", selection: Binding(
            get: { appState.appSettings.preferredInputDeviceUID ?? "" },
            set: { appState.appSettings.preferredInputDeviceUID = $0.isEmpty ? nil : $0 }
        )) {
            Text("System-Standard").tag("")
            ForEach(service.devices) { device in
                Text(device.name).tag(device.id)
            }
            if let missingSelectedUID {
                Text("Nicht verbunden").tag(missingSelectedUID)
            }
        }
        .labelsHidden()
        .controlSize(.small)
    }
}
