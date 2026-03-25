// TranscriptionService.swift
// Ai4Poors - Orchestrates recording, transcription, and post-processing
//
// Coordinates AudioRecordingService, WhisperKit model loading,
// clipboard copy, and history persistence.

#if os(iOS) && canImport(WhisperKit)
import Foundation
import UIKit
import WhisperKit

@MainActor
final class TranscriptionService: ObservableObject {

    static let shared = TranscriptionService()

    // MARK: - Published State

    @Published var state: TranscriptionState = .idle
    @Published var currentMode: TranscriptionMode = .plain
    @Published var lastTranscription: String?
    @Published var modelState: ModelState = .notLoaded
    @Published var modelDownloadProgress: Double = 0

    enum TranscriptionState: Equatable {
        case idle
        case recording
        case processing
        case result(String)
        case error(String)
    }

    enum ModelState: Equatable {
        case notLoaded
        case downloading(Double)
        case loading
        case ready
        case error(String)
    }

    // MARK: - Private

    private var whisperPipe: WhisperKit?
    private let audioService = AudioRecordingService.shared
    private let store = TranscriptionStore.shared

    private init() {}

    // MARK: - Model Management

    func loadModelIfNeeded() async {
        guard whisperPipe == nil else {
            modelState = .ready
            return
        }

        modelState = .loading

        do {
            // Omit model to let WhisperKit auto-select the best model for this device
            let config = WhisperKitConfig(
                verbose: false,
                prewarm: true
            )
            let pipe = try await WhisperKit(config)
            whisperPipe = pipe
            modelState = .ready
            print("[TranscriptionService] WhisperKit model loaded: \(pipe.modelVariant.description)")
        } catch {
            modelState = .error(error.localizedDescription)
            print("[TranscriptionService] Model load failed: \(error)")
        }
    }

    var isModelReady: Bool {
        whisperPipe != nil
    }

    // MARK: - Transcription Flow

    func startTranscription(mode: TranscriptionMode) async {
        currentMode = mode
        state = .recording

        // Start recording immediately, then load model while user speaks
        do {
            try audioService.startRecording()
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
            return
        }

        // Load model in parallel — will be ready by the time user stops talking
        await loadModelIfNeeded()
    }

    func stopAndTranscribe() async {
        guard audioService.isRecording else { return }

        let result = audioService.stopRecording()
        state = .processing

        guard !result.samples.isEmpty else {
            state = .error("No audio recorded")
            return
        }

        // Ensure model is loaded
        if whisperPipe == nil {
            await loadModelIfNeeded()
        }

        guard let pipe = whisperPipe else {
            state = .error("Whisper model not available")
            return
        }

        do {
            let options = DecodingOptions(
                language: "en",
                temperature: 0.0,
                skipSpecialTokens: true,
                noSpeechThreshold: 0.6
            )

            let transcriptionResult = try await pipe.transcribe(
                audioArray: result.samples,
                decodeOptions: options
            )

            let rawText = transcriptionResult.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

            guard !rawText.isEmpty else {
                state = .error("No speech detected")
                return
            }

            // Process based on mode
            var finalText = rawText
            var cleanedText: String? = nil

            switch currentMode {
            case .plain:
                UIPasteboard.general.string = rawText

            case .aiCleanup:
                if let cleaned = await cleanupWithAI(rawText) {
                    cleanedText = cleaned
                    finalText = cleaned
                    UIPasteboard.general.string = cleaned
                } else {
                    UIPasteboard.general.string = rawText
                }
            }

            lastTranscription = finalText
            state = .result(finalText)

            // Save audio file off the main thread
            let capturedSamples = result.samples
            let audioPath: String? = await Task.detached(priority: .utility) {
                await self.audioService.saveAudioToFile(samples: capturedSamples)?.lastPathComponent
            }.value

            // Save to history
            let record = TranscriptionRecord(
                text: rawText,
                mode: currentMode,
                cleanedText: cleanedText,
                duration: result.duration,
                audioFilePath: audioPath,
                languageDetected: "en"
            )
            store.insert(record)

            // Haptic feedback
            if AppGroupConstants.isHapticFeedbackEnabled {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }

            // Auto-dismiss after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if case .result = state {
                state = .idle
            }

        } catch {
            state = .error("Transcription failed: \(error.localizedDescription)")
        }
    }

    func cancel() {
        if audioService.isRecording {
            _ = audioService.stopRecording()
        }
        state = .idle
    }

    // MARK: - AI Cleanup

    private func cleanupWithAI(_ text: String) async -> String? {
        guard AppGroupConstants.isAPIKeyConfigured else { return nil }

        let instruction = """
        Clean up this voice transcription. Fix punctuation, capitalize properly, \
        remove filler words (um, uh, like, you know), fix obvious speech-to-text errors, \
        and improve sentence structure. Maintain the original meaning and tone. \
        Output only the cleaned text, nothing else.
        """

        do {
            return try await OpenRouterService.shared.analyzeText(
                text: text,
                instruction: instruction,
                model: "google/gemini-3-flash-preview"
            )
        } catch {
            print("[TranscriptionService] AI cleanup failed: \(error)")
            return nil
        }
    }

}
#endif
