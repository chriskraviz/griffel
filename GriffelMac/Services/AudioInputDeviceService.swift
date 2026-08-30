import CoreAudio
import Foundation
import Observation

struct AudioInputDevice: Identifiable, Hashable {
    /// Device UID — stable across reboots and re-plugs, used for persistence.
    let id: String
    let deviceID: AudioDeviceID
    let name: String
}

/// The device the microphone is actually open on for one recording. Resolved
/// when recording starts, because the answer can differ from the setting: a
/// device picked in the settings and then unplugged falls back to the system
/// default, and saying so is the difference between a helpful label and a
/// wrong one.
struct ActiveInputDevice: Equatable {
    let name: String
    /// True when a specific device was picked in the settings but was not
    /// available, so this is the system default standing in for it.
    let isFallback: Bool
}

/// Enumerates input-capable Core Audio devices and tracks plug/unplug events.
@Observable
@MainActor
final class AudioInputDeviceService {
    static let shared = AudioInputDeviceService()

    private(set) var devices: [AudioInputDevice] = []

    private init() {
        refreshDevices()
        installDeviceListListener()
    }

    func refreshDevices() {
        devices = Self.listInputDevices()
    }

    // MARK: - Core Audio (nonisolated: callable from the recorder off the main actor)

    nonisolated static func inputDevice(forUID uid: String) -> AudioInputDevice? {
        listInputDevices().first { $0.id == uid }
    }

    /// The system default input — what CoreAudio hands an untouched
    /// `AVAudioEngine`, and therefore what a failed device pick falls back to.
    nonisolated static func defaultInputDevice() -> AudioInputDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID
        ) == noErr, deviceID != 0 else {
            return nil
        }

        return listInputDevices().first { $0.deviceID == deviceID }
    }

    nonisolated static func listInputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard hasInputStreams(deviceID),
                  let uid = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceNameCFString) else {
                return nil
            }
            return AudioInputDevice(id: uid, deviceID: deviceID, name: name)
        }
    }

    private nonisolated static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private nonisolated static func stringProperty(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString? = nil
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private func installDeviceListListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refreshDevices()
            }
        }
    }
}
