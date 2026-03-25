// BackgroundKeepAlive.swift
// Ai4Poors - Silent audio playback to keep app alive in background
//
// Plays a programmatically generated silent WAV on infinite loop.
// TestFlight only — not for App Store submission.

#if os(iOS)
import AVFoundation

final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()

    private var audioPlayer: AVAudioPlayer?
    private(set) var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("[Ai4Poors] Failed to configure audio session: \(error)")
            return
        }

        guard let silentData = generateSilentWAV() else {
            print("[Ai4Poors] Failed to generate silent WAV")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(data: silentData)
            audioPlayer?.numberOfLoops = -1 // infinite loop
            audioPlayer?.volume = 0
            audioPlayer?.play()
            isRunning = true
            print("[Ai4Poors] Background keep-alive started")
        } catch {
            print("[Ai4Poors] Failed to start audio player: \(error)")
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[Ai4Poors] Background keep-alive stopped")
    }

    // Generate a 1-second silent WAV file in memory (8kHz, mono, 16-bit PCM)
    private func generateSilentWAV() -> Data? {
        let sampleRate: UInt32 = 8000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples = sampleRate // 1 second
        let dataSize = numSamples * UInt32(numChannels) * UInt32(bitsPerSample / 8)

        var wav = Data()

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(uint32LE: 36 + dataSize)
        wav.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(uint32LE: 16) // chunk size
        wav.append(uint16LE: 1)  // PCM format
        wav.append(uint16LE: numChannels)
        wav.append(uint32LE: sampleRate)
        wav.append(uint32LE: sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)) // byte rate
        wav.append(uint16LE: numChannels * (bitsPerSample / 8)) // block align
        wav.append(uint16LE: bitsPerSample)

        // data chunk (all zeros = silence)
        wav.append(contentsOf: "data".utf8)
        wav.append(uint32LE: dataSize)
        wav.append(Data(count: Int(dataSize)))

        return wav
    }
}

// MARK: - Data Helpers for WAV Generation

private extension Data {
    mutating func append(uint16LE value: UInt16) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 2))
    }

    mutating func append(uint32LE value: UInt32) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: 4))
    }
}
#endif
