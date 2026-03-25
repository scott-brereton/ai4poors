// TranscriptionRecord.swift
// Ai4Poors - Data model for voice transcriptions

import Foundation

// MARK: - Transcription Mode

enum TranscriptionMode: String, Codable, CaseIterable {
    case plain = "plain"
    case aiCleanup = "ai_cleanup"

    var displayName: String {
        switch self {
        case .plain: return "Transcribe"
        case .aiCleanup: return "Smart Transcribe"
        }
    }

    var iconName: String {
        switch self {
        case .plain: return "waveform"
        case .aiCleanup: return "wand.and.stars"
        }
    }

    var tintColor: String {
        switch self {
        case .plain: return "blue"
        case .aiCleanup: return "purple"
        }
    }
}

// MARK: - Transcription Record

struct TranscriptionRecord: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let text: String
    let mode: TranscriptionMode
    let cleanedText: String?
    let duration: TimeInterval
    let audioFilePath: String?
    let foregroundApp: String?
    let languageDetected: String
    let wordCount: Int

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        text: String,
        mode: TranscriptionMode,
        cleanedText: String? = nil,
        duration: TimeInterval,
        audioFilePath: String? = nil,
        foregroundApp: String? = nil,
        languageDetected: String = "en",
        wordCount: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.mode = mode
        self.cleanedText = cleanedText
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.foregroundApp = foregroundApp
        self.languageDetected = languageDetected
        self.wordCount = wordCount ?? text.split(separator: " ").count
    }

    var displayText: String {
        cleanedText ?? text
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
