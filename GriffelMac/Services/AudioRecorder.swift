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

    init(preferredDeviceUID: String? = nil) {
        self.preferredDeviceUID = preferredDeviceUID
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("griffel-\(UUID().uuidString).m4a")
    }

    func startRecording() {
        errorMessage = nil
        lastRecordingDuration = 0
        recordingURL = nil
        if let currentFileURL {
            try? FileManager.default.removeItem(at: currentFileURL)
        }

        let engine = AVAudioEngine()
        activeInputDevice = applyPreferredDeviceIfNeeded(to: engine)

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            errorMessage = "Kein Eingabegerät gefunden."
            return
        }

        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let fileURL = makeRecordingURL()
            let file = try AVAudioFile(forWriting: fileURL, settings: fileSettings)

            guard let converter = AVAudioConverter(from: inputFormat, to: file.processingFormat) else {
                errorMessage = "Aufnahmeformat wird nicht unterstützt."
                return
            }

            currentFileURL = fileURL
            audioFile = file
            self.converter = converter
            self.engine = engine

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

            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            teardownEngine()
            currentFileURL = nil
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        if let audioFile {
            lastRecordingDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        } else {
            lastRecordingDuration = 0
        }

        teardownEngine()
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
            try? FileManager.default.removeItem(at: currentFileURL)
            self.currentFileURL = nil
        }
    }

    private func teardownEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        // Releasing the file closes it and finalizes the m4a container.
        audioFile = nil
    }

    /// Points the engine at the preferred device and reports what it ended up
    /// on. The fallback is silent by design — a vanished device must not fail a
    /// recording — so the return value is the only place the difference shows.
    private func applyPreferredDeviceIfNeeded(to engine: AVAudioEngine) -> ActiveInputDevice? {
        let wantsSpecificDevice = !(preferredDeviceUID ?? "").isEmpty

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
                return ActiveInputDevice(name: device.name, isFallback: false)
            }
        }

        guard let fallback = AudioInputDeviceService.defaultInputDevice() else { return nil }
        return ActiveInputDevice(name: fallback.name, isFallback: wantsSpecificDevice)
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
