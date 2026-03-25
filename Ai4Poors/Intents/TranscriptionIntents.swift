// TranscriptionIntents.swift
// Ai4Poors - App Intents for voice-to-text triggered via Back Tap / Control Center
//
// Two configurable intents for Back Tap (double/triple) that read their mode
// from user settings, plus three direct-mode intents for Shortcuts flexibility.

#if os(iOS)
import AppIntents
import UIKit

// MARK: - Back Tap: Double Tap (reads mode from Settings)

struct DoubleTapVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Ai4Poors: Double Tap Voice"
    static let description: IntentDescription = "Starts voice transcription using your configured Double Tap mode"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let modeString = AppGroupConstants.voiceDoubleTapMode
        guard !modeString.isEmpty else { return .result() } // disabled
        AppGroupConstants.sharedDefaults?.set(
            modeString,
            forKey: "pending_transcription_mode"
        )
        return .result()
    }
}

// MARK: - Back Tap: Triple Tap (reads mode from Settings)

struct TripleTapVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Ai4Poors: Triple Tap Voice"
    static let description: IntentDescription = "Starts voice transcription using your configured Triple Tap mode"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let modeString = AppGroupConstants.voiceTripleTapMode
        guard !modeString.isEmpty else { return .result() } // disabled
        AppGroupConstants.sharedDefaults?.set(
            modeString,
            forKey: "pending_transcription_mode"
        )
        return .result()
    }
}

// MARK: - Direct Mode Intents (for Shortcuts / Control Center)

struct StartTranscriptionIntent: AppIntent {
    static let title: LocalizedStringResource = "Ai4Poors: Transcribe"
    static let description: IntentDescription = "Records speech and copies the transcription to clipboard"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AppGroupConstants.sharedDefaults?.set(
            TranscriptionMode.plain.rawValue,
            forKey: "pending_transcription_mode"
        )
        return .result()
    }
}

struct StartSmartTranscriptionIntent: AppIntent {
    static let title: LocalizedStringResource = "Ai4Poors: Smart Transcribe"
    static let description: IntentDescription = "Records speech, cleans it up with AI, and copies to clipboard"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AppGroupConstants.sharedDefaults?.set(
            TranscriptionMode.aiCleanup.rawValue,
            forKey: "pending_transcription_mode"
        )
        return .result()
    }
}

#endif
