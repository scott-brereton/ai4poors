// Models.swift
// Ai4Poors - Shared data models across all targets

import Foundation
import SwiftData

// MARK: - Analysis Channel

enum Ai4PoorsChannel: String, Codable, CaseIterable {
    case keyboard = "keyboard"
    case safari = "safari"
    case screenshot = "screenshot"
    case share = "share"
    case clipboard = "clipboard"
    case message = "message"
    case reader = "reader"

    var displayName: String {
        switch self {
        case .keyboard: return "Keyboard"
        case .safari: return "Safari"
        case .screenshot: return "Screenshot"
        case .share: return "Share Extension"
        case .clipboard: return "Clipboard"
        case .message: return "Messages"
        case .reader: return "Reader"
        }
    }

    var iconName: String {
        switch self {
        case .keyboard: return "keyboard"
        case .safari: return "safari"
        case .screenshot: return "camera.viewfinder"
        case .share: return "square.and.arrow.up"
        case .clipboard: return "doc.on.clipboard"
        case .message: return "message"
        case .reader: return "book"
        }
    }
}

// MARK: - Analysis Action

enum Ai4PoorsAction: String, Codable, CaseIterable {
    case reply
    case summarize
    case translate
    case explain
    case extract
    case tldr
    case improve
    case read
    case custom

    var displayName: String {
        switch self {
        case .reply: return "Reply"
        case .summarize: return "Summarize"
        case .translate: return "Translate"
        case .explain: return "Explain"
        case .extract: return "Key Points"
        case .tldr: return "TL;DR"
        case .improve: return "Improve"
        case .read: return "Read Article"
        case .custom: return "Custom"
        }
    }

    var iconName: String {
        switch self {
        case .reply: return "arrowshape.turn.up.left"
        case .summarize: return "doc.text.magnifyingglass"
        case .translate: return "globe"
        case .explain: return "lightbulb"
        case .extract: return "list.bullet"
        case .tldr: return "text.justify.left"
        case .improve: return "wand.and.stars"
        case .read: return "book.pages"
        case .custom: return "text.cursor"
        }
    }

    var defaultInstruction: String {
        switch self {
        case .reply: return "Draft a concise, professional reply to this message. Match the tone."
        case .summarize: return "Summarize this text in 2-3 bullet points. Be concise."
        case .translate: return "Translate this to \(AppGroupConstants.preferredLanguage). Only output the translation."
        case .explain: return "Explain this content simply. What is the key takeaway? If it's an error, explain the fix."
        case .extract: return "Extract key points, facts, dates, and action items as a list."
        case .tldr: return "Give a one-sentence TL;DR of this content."
        case .improve: return "Improve this text. Fix grammar, clarify meaning, improve flow. Keep the same tone and intent. Output only the improved text."
        case .read: return "Extract and display article content."
        case .custom: return "Analyze this content."
        }
    }
}

// MARK: - Supported Languages
enum SupportedLanguages {
    static let all = ["English", "French", "Spanish", "German", "Japanese", "Chinese", "Arabic", "Portuguese", "Korean", "Italian", "Russian", "Hindi"]
}

// MARK: - Analysis Result (SwiftData)

@Model
final class AnalysisRecord {
    var id: UUID
    var timestamp: Date
    var channel: String
    var action: String
    var inputPreview: String
    var result: String
    var model: String
    var customInstruction: String?
    @Attribute(.externalStorage) var imageData: Data?
    var toolActionsData: Data?
    var isViewed: Bool = true

    init(
        channel: Ai4PoorsChannel,
        action: Ai4PoorsAction,
        inputPreview: String,
        result: String,
        model: String,
        customInstruction: String? = nil,
        imageData: Data? = nil,
        toolActionsData: Data? = nil,
        isViewed: Bool = true
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.channel = channel.rawValue
        self.action = action.rawValue
        self.inputPreview = String(inputPreview.prefix(200))
        self.result = result
        self.model = model
        self.customInstruction = customInstruction
        self.imageData = imageData
        self.toolActionsData = toolActionsData
        self.isViewed = isViewed
    }

    var channelEnum: Ai4PoorsChannel {
        Ai4PoorsChannel(rawValue: channel) ?? .keyboard
    }

    var actionEnum: Ai4PoorsAction {
        Ai4PoorsAction(rawValue: action) ?? .custom
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - API Response Models

struct ChatCompletionResponse: Codable {
    let id: String?
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable {
        let index: Int
        let message: ResponseMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Codable {
        let role: String
        let content: String?
        let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Codable {
        let id: String
        let type: String
        let function: ToolFunction

        struct ToolFunction: Codable {
            let name: String
            let arguments: String
        }
    }

    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

struct StreamChunkResponse: Codable {
    let choices: [StreamChoice]

    struct StreamChoice: Codable {
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Codable {
        let content: String?
        let role: String?
    }
}

// MARK: - Model Info

struct AIModel: Identifiable {
    let id: String
    let displayName: String
    let provider: String
    let costPer1kTokens: Double
    let supportsVision: Bool
    let isDefault: Bool

    static let allModels: [AIModel] = [
        AIModel(
            id: "anthropic/claude-sonnet-4.6",
            displayName: "Claude Sonnet 4.6",
            provider: "Anthropic",
            costPer1kTokens: 0.015,
            supportsVision: true,
            isDefault: true
        ),
        AIModel(
            id: "google/gemini-3-flash-preview",
            displayName: "Gemini 3 Flash",
            provider: "Google",
            costPer1kTokens: 0.002,
            supportsVision: true,
            isDefault: false
        ),
        AIModel(
            id: "openai/gpt-5.4-mini",
            displayName: "GPT-5.4 Mini",
            provider: "OpenAI",
            costPer1kTokens: 0.003,
            supportsVision: true,
            isDefault: false
        ),
        AIModel(
            id: "anthropic/claude-haiku-4.5",
            displayName: "Claude Haiku 4.5",
            provider: "Anthropic",
            costPer1kTokens: 0.001,
            supportsVision: true,
            isDefault: false
        ),
        AIModel(
            id: "google/gemini-3.1-flash-lite-preview",
            displayName: "Gemini 3.1 Flash Lite",
            provider: "Google",
            costPer1kTokens: 0.001,
            supportsVision: true,
            isDefault: false
        ),
        AIModel(
            id: "openai/gpt-5.4",
            displayName: "GPT-5.4",
            provider: "OpenAI",
            costPer1kTokens: 0.030,
            supportsVision: true,
            isDefault: false
        ),
    ]

    static func model(for id: String) -> AIModel? {
        allModels.first { $0.id == id }
    }

    static func displayName(for id: String) -> String {
        if id == "crawl4ai" { return "Crawl4AI" }
        return model(for: id)?.displayName ?? id
    }
}

// MARK: - Page Content (Safari Extension)

struct PageContent: Codable {
    let type: String
    let title: String
    let text: String
    let url: String
    let meta: String?
    let customInstruction: String?
}

// MARK: - Notification Names

extension Notification.Name {
    static let ai4poorsShowResult = Notification.Name("ai4poorsShowResult")
    static let cortexSaveRecord = Notification.Name("cortexSaveRecord")
}

// MARK: - Ai4Poors Errors

enum Ai4PoorsError: LocalizedError {
    case imageEncodingFailed
    case networkError(underlying: Error)
    case apiError(code: Int, message: String)
    case noAPIKey
    case rateLimited
    case invalidResponse
    case extensionMemoryLimit
    case contentTooLong(charCount: Int)
    case modelUnavailable(model: String)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "Failed to encode image for upload"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .noAPIKey:
            return "No API key configured. Open Ai4Poors to set up your OpenRouter key."
        case .rateLimited:
            return "Rate limited. Please wait a moment and try again."
        case .invalidResponse:
            return "Invalid response from API"
        case .extensionMemoryLimit:
            return "Memory limit reached. Try a shorter text."
        case .contentTooLong(let charCount):
            return "Content too long (\(charCount) characters). Try selecting a smaller portion."
        case .modelUnavailable(let model):
            return "Model '\(model)' is unavailable. Falling back to default."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noAPIKey:
            return "Open the Ai4Poors app and enter your OpenRouter API key in Settings."
        case .rateLimited:
            return "Wait 10-30 seconds and try again. Consider switching to a cheaper model."
        case .networkError:
            return "Check your internet connection and try again."
        case .extensionMemoryLimit:
            return "The keyboard extension has limited memory. Try analyzing shorter text."
        case .contentTooLong:
            return "Select a portion of the text instead of analyzing the full document."
        case .apiError(let code, _):
            if code == 401 { return "Your API key may be invalid. Check it in Ai4Poors Settings." }
            if code == 402 { return "Your OpenRouter account may have insufficient credits." }
            return nil
        default:
            return nil
        }
    }
}
