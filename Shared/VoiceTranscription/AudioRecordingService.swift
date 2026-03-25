// AudioRecordingService.swift
// Ai4Poors - AVAudioEngine-based recording for voice transcription
//
// Records 16kHz mono Float32 PCM (WhisperKit's required format).

#if os(iOS)
import AVFoundation
import UIKit

@MainActor
final class AudioRecordingService: ObservableObject {

    static let shared = AudioRecordingService()

    @Published var isRecording = false
    @Published var audioLevel: Float = 0
    @Published var recordingDuration: TimeInterval = 0

    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private var recordingStartTime: Date?
    private var displayTimer: Timer?

    private init() {}

    // MARK: - Configure Audio Session

    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
        )
        try session.setActive(true)
    }

    // MARK: - Start Recording

    func startRecording() throws {
        audioBuffer.removeAll()
        recordingStartTime = Date()

        try configureAudioSession()

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // WhisperKit needs 16kHz mono Float32
        let targetSampleRate: Double = 16000
        let channelCount: AVAudioChannelCount = 1

        guard let convertFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw Ai4PoorsError.invalidResponse
        }

        let converter = AVAudioConverter(from: recordingFormat, to: convertFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Calculate RMS for level metering
            let rms = self.calculateRMS(buffer: buffer)

            Task { @MainActor in
                self.audioLevel = rms
            }

            // Convert to 16kHz mono
            if let converter = converter {
                let frameCount = AVAudioFrameCount(
                    Double(buffer.frameLength) * targetSampleRate / recordingFormat.sampleRate
                )
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: convertFormat,
                    frameCapacity: frameCount
                ) else { return }

                var error: NSError?
                var hasProvided = false
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    if hasProvided {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    hasProvided = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

                if error == nil, let channelData = convertedBuffer.floatChannelData {
                    let samples = Array(UnsafeBufferPointer(
                        start: channelData[0],
                        count: Int(convertedBuffer.frameLength)
                    ))
                    Task { @MainActor in
                        self.audioBuffer.append(contentsOf: samples)
                    }
                }
            }
        }

        try audioEngine.start()
        isRecording = true

        // Display timer for duration updates
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    // MARK: - Stop Recording

    func stopRecording() -> (samples: [Float], duration: TimeInterval) {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        displayTimer?.invalidate()
        displayTimer = nil

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let samples = audioBuffer

        isRecording = false
        audioLevel = 0
        recordingDuration = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return (samples: samples, duration: duration)
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return -100 }
        let channelDataValue = channelData[0]
        let count = Int(buffer.frameLength)
        guard count > 0 else { return -100 }

        var sum: Float = 0
        for i in 0..<count {
            let sample = channelDataValue[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        // Convert to dB
        let db = 20 * log10(max(rms, 1e-10))
        return db
    }

    // MARK: - Audio File Save

    func saveAudioToFile(samples: [Float], sampleRate: Double = 16000) -> URL? {
        guard let containerURL = AppGroupConstants.sharedContainerURL else { return nil }

        let audioDir = containerURL.appendingPathComponent("VoiceTranscriptions/audio")
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let fileName = "\(UUID().uuidString).m4a"
        let fileURL = audioDir.appendingPathComponent(fileName)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { ptr in
                channelData[0].update(from: ptr.baseAddress!, count: samples.count)
            }
        }

        // Write as AAC M4A
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000
        ]

        do {
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: outputSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try audioFile.write(from: buffer)
            return fileURL
        } catch {
            print("[AudioRecording] Failed to save audio: \(error)")
            return nil
        }
    }
}
#endif
