import AVFoundation
import CoreAudio
import Observation

/// Records microphone input to a 16 kHz mono AAC m4a temp file.
/// Built on AVAudioEngine so a specific input device can be selected;
/// a nil or vanished `preferredDeviceUID` falls back to the system default.
@Observable
final class AudioRecorder {
    var isRecording = false
    var recordingURL: URL?
    var errorMessage: String?
    var audioLevel: Float = 0
    var lastRecordingDuration: TimeInterval = 0
    /// The input actually in use for the current recording — not the stored
    /// preference. Nil until `startRecording()` has resolved it.
    private(set) var activeInputDevice: ActiveInputDevice?

    /// Called on the main queue with each converted 16 kHz mono chunk while
    /// recording — feeds live transcription without touching the m4a path.
    var onConvertedBuffer: (([Float]) -> Void)?
    /// Called on the main queue with the throttled level (same cadence as
    /// `audioLevel`) — feeds silence detection.
    var onLevelSample: ((Float) -> Void)?

    private let preferredDeviceUID: String?
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var currentFileURL: URL?
    /// The device the engine was asked to open, set when the preference
    /// resolved to an attached device. Kept so the outcome can be verified
    /// after `start()` and re-applied when a configuration change forces a
    /// rebuild — the property write alone is not proof the pin took.
    private var requestedDeviceID: AudioDeviceID?
    private var configChangeObserver: (any NSObjectProtocol)?

    init(preferredDeviceUID: String? = nil) {
        self.preferredDeviceUID = preferredDeviceUID
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("griffel-\(UUID().uuidString).m4a")
    }

    private static let fileSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    func startRecording() {
        errorMessage = nil
        lastRecordingDuration = 0
        recordingURL = nil
        if let currentFileURL {
            try? FileManager.default.removeItem(at: currentFileURL)
        }

        do {
            let fileURL = makeRecordingURL()
            let file = try AVAudioFile(forWriting: fileURL, settings: Self.fileSettings)
            currentFileURL = fileURL
            audioFile = file

            guard startEngine(writingTo: file) else {
                teardownEngine()
                audioFile = nil
                try? FileManager.default.removeItem(at: fileURL)
                currentFileURL = nil
                return
            }
            isRecording = true
        } catch {
            teardownEngine()
            audioFile = nil
            currentFileURL = nil
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        // Idempotent: a failed mid-recording restart can stop the recording
        // before the workflow's own stop call arrives, and the second call
        // must not wipe the finished recording's URL.
        guard isRecording || currentFileURL != nil else { return }

        if let audioFile {
            lastRecordingDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        } else {
            lastRecordingDuration = 0
        }

        teardownEngine()
        // Releasing the file closes it and finalizes the m4a container.
        audioFile = nil
        isRecording = false
        recordingURL = currentFileURL
        currentFileURL = nil
        audioLevel = 0
    }

    func discardRecording() {
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
        }

        if let currentFileURL {
            teardownEngine()
            audioFile = nil
            try? FileManager.default.removeItem(at: currentFileURL)
            self.currentFileURL = nil
        }
    }

    /// Builds a fresh engine on the preferred device, wires the processing
    /// tap and starts it. Afterwards it verifies that the engine is really
    /// open on the requested device: macOS runs an untouched engine on a
    /// hidden default-device aggregate, and with a Bluetooth device (AirPods)
    /// as system default that aggregate is known to accept the device
    /// property with noErr and keep capturing from the default anyway. One
    /// rebuild from scratch gets a stale aggregate out of the way; after that
    /// the fallback is accepted and labelled honestly instead of claiming the
    /// picked microphone.
    private func startEngine(writingTo file: AVAudioFile) -> Bool {
        for attempt in 0..<2 {
            teardownEngine()

            let engine = AVAudioEngine()
            activeInputDevice = applyPreferredDeviceIfNeeded(to: engine)

            let inputFormat = engine.inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                errorMessage = "Kein Eingabegerät gefunden."
                return false
            }

            guard let converter = AVAudioConverter(from: inputFormat, to: file.processingFormat) else {
                errorMessage = "Aufnahmeformat wird nicht unterstützt."
                return false
            }

            self.converter = converter
            self.engine = engine
            installProcessingTap(on: engine, inputFormat: inputFormat, converter: converter, file: file)

            engine.prepare()
            do {
                try engine.start()
            } catch {
                errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
                return false
            }

            if let requestedDeviceID,
               attempt == 0,
               let actual = currentInputDeviceID(of: engine),
               actual != requestedDeviceID {
                continue
            }

            activeInputDevice = verifiedActiveDevice(of: engine)
            observeConfigurationChanges(of: engine, file: file)
            return true
        }
        return false
    }

    private func installProcessingTap(
        on engine: AVAudioEngine,
        inputFormat: AVAudioFormat,
        converter: AVAudioConverter,
        file: AVAudioFile
    ) {
        let ratio = file.processingFormat.sampleRate / inputFormat.sampleRate
        var lastLevelUpdate = Date.distantPast

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let level = Self.normalizedLevel(for: buffer)
            let now = Date()
            if now.timeIntervalSince(lastLevelUpdate) >= 0.05 {
                lastLevelUpdate = now
                DispatchQueue.main.async {
                    if self.isRecording {
                        self.audioLevel = level
                        self.onLevelSample?(level)
                    }
                }
            }

            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let outBuffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: capacity
            ) else {
                return
            }

            var didProvideInput = false
            var conversionError: NSError?
            converter.convert(to: outBuffer, error: &conversionError) { _, status in
                if didProvideInput {
                    status.pointee = .noDataNow
                    return nil
                }
                didProvideInput = true
                status.pointee = .haveData
                return buffer
            }

            if conversionError == nil, outBuffer.frameLength > 0 {
                try? file.write(from: outBuffer)

                if self.onConvertedBuffer != nil, let channelData = outBuffer.floatChannelData {
                    let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outBuffer.frameLength)))
                    DispatchQueue.main.async {
                        if self.isRecording {
                            self.onConvertedBuffer?(samples)
                        }
                    }
                }
            }
        }
    }

    /// A Core Audio configuration change stops the engine mid-recording; the
    /// classic trigger is a Bluetooth device joining or leaving, which makes
    /// the system rebuild the hidden default-device aggregate. Restarting on
    /// a fresh engine re-applies the device pin and keeps appending to the
    /// same file — without this the recording goes silent and a pinned
    /// device quietly reverts to the system default.
    private func observeConfigurationChanges(of engine: AVAudioEngine, file: AVAudioFile) {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self, weak engine] _ in
            // The engine identity check drops a notification that was already
            // in flight when its engine got replaced — restarting on it would
            // write into a file that is finalized or gone.
            guard let self, let engine, self.engine === engine, self.isRecording else { return }
            if !self.startEngine(writingTo: file) {
                self.stopRecording()
            }
        }
    }

    private func teardownEngine() {
        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
        }
        configChangeObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        requestedDeviceID = nil
    }

    /// Points the engine at the preferred device and reports what it ended up
    /// on. The fallback is silent by design — a vanished device must not fail a
    /// recording — so the return value is the only place the difference shows.
    private func applyPreferredDeviceIfNeeded(to engine: AVAudioEngine) -> ActiveInputDevice? {
        let wantsSpecificDevice = !(preferredDeviceUID ?? "").isEmpty
        requestedDeviceID = nil

        if let preferredDeviceUID,
           !preferredDeviceUID.isEmpty,
           let device = AudioInputDeviceService.inputDevice(forUID: preferredDeviceUID),
           let audioUnit = engine.inputNode.audioUnit {
            var deviceID = device.deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status == noErr {
                requestedDeviceID = device.deviceID
                return ActiveInputDevice(name: device.name, isFallback: false)
            }
        }

        guard let fallback = AudioInputDeviceService.defaultInputDevice() else { return nil }
        return ActiveInputDevice(name: fallback.name, isFallback: wantsSpecificDevice)
    }

    /// The device the engine's input unit is actually open on right now — the
    /// read-back side of `kAudioOutputUnitProperty_CurrentDevice`. Nil when
    /// the unit cannot be asked, which counts as "unverifiable", not as a
    /// mismatch.
    private func currentInputDeviceID(of engine: AVAudioEngine) -> AudioDeviceID? {
        guard let audioUnit = engine.inputNode.audioUnit else { return nil }
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            &size
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    /// The label refined by what the engine actually opened. When the pin did
    /// not take, the honest answer is the device that is really recording — a
    /// confident wrong name here is exactly the bug this label exists to
    /// avoid.
    private func verifiedActiveDevice(of engine: AVAudioEngine) -> ActiveInputDevice? {
        guard let requestedDeviceID,
              let actual = currentInputDeviceID(of: engine),
              actual != requestedDeviceID else {
            return activeInputDevice
        }
        if let device = AudioInputDeviceService.listInputDevices().first(where: { $0.deviceID == actual }) {
            return ActiveInputDevice(name: device.name, isFallback: true)
        }
        guard let fallback = AudioInputDeviceService.defaultInputDevice() else { return activeInputDevice }
        return ActiveInputDevice(name: fallback.name, isFallback: true)
    }

    private static func normalizedLevel(for buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else {
            return 0
        }

        let samples = channelData[0]
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            let sample = samples[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(buffer.frameLength))
        let decibels = 20 * log10(max(rms, .leastNonzeroMagnitude))
        return max(0, min(1, (decibels + 50) / 50))
    }
}
