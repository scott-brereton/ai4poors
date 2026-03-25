// AnalyzeScreenIntent.swift
// Ai4Poors - App Intents for Shortcuts integration (Screenshot Pipeline)

import AppIntents
import UIKit
import UserNotifications

// MARK: - Analyze Screenshot Intent

struct AnalyzeScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Analyze Screenshot with Ai4Poors"
    static let description: IntentDescription = "Analyzes a screenshot image using AI and returns the result"
    static let openAppWhenRun = false

    @Parameter(title: "Image")
    var imageFile: IntentFile

    @Parameter(title: "Instruction", default: "Look at this and tell me what matters.")
    var instruction: String

    @Parameter(title: "Model", default: "google/gemini-3-flash-preview")
    var model: String

    static var parameterSummary: some ParameterSummary {
        Summary("Analyze \(\.$imageFile) with \(\.$instruction)") {
            \.$model
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard AppGroupConstants.isAPIKeyConfigured else {
            return .result(value: "Error: No API key configured. Open Ai4Poors to set up your OpenRouter key.")
        }

        let imageData = imageFile.data
        guard let image = UIImage(data: imageData) else {
            return .result(value: "Error: Could not load image")
        }

        // Start Live Activity
        await Ai4PoorsActivityManager.shared.startAnalysis(
            source: "screenshot",
            instruction: "Screenshot Analysis"
        )

        do {
            let result: String
            var actionsData: Data?
            if AppGroupConstants.isToolUseEnabled {
                let toolResult = try await OpenRouterService.shared.analyzeImageWithTools(
                    image: image,
                    instruction: instruction,
                    model: model
                )
                result = toolResult.text
                actionsData = ToolAction.encode(toolResult.actions)
            } else {
                result = try await OpenRouterService.shared.analyzeImage(
                    image: image,
                    instruction: instruction,
                    model: model
                )
            }

            await Ai4PoorsActivityManager.shared.completeWithResult(result)

            // Save to history with screenshot image
            let thumbnailData = image.jpegData(compressionQuality: 0.5)
            HistoryService.save(
                channel: .screenshot,
                action: .custom,
                inputPreview: "[Screenshot]",
                result: result,
                model: model,
                customInstruction: instruction,
                imageData: thumbnailData,
                toolActionsData: actionsData
            )

            // Post local notification with result
            await postResultNotification(result: result)

            return .result(value: result)
        } catch {
            let errorMessage = error.localizedDescription
            await Ai4PoorsActivityManager.shared.completeWithError(errorMessage)
            return .result(value: "Error: \(errorMessage)")
        }
    }

    private func postResultNotification(result: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Ai4Poors Analysis"
        content.body = String(result.prefix(200))
        content.sound = .default
        content.userInfo = ["result": result]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Summarize Screen Intent

struct SummarizeScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize Screenshot"
    static let description: IntentDescription = "Takes a screenshot and returns an AI summary"
    static let openAppWhenRun = false

    @Parameter(title: "Image")
    var imageFile: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$imageFile)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard AppGroupConstants.isAPIKeyConfigured else {
            return .result(value: "Error: No API key configured.")
        }

        let imageData = imageFile.data
        guard let image = UIImage(data: imageData) else {
            return .result(value: "Error: Could not load image")
        }

        await Ai4PoorsActivityManager.shared.startAnalysis(
            source: "screenshot",
            instruction: "Summarize"
        )

        do {
            let result = try await OpenRouterService.shared.analyzeImage(
                image: image,
                instruction: "Summarize what you see on this screen in 2-3 bullet points. Be concise."
            )
            await Ai4PoorsActivityManager.shared.completeWithResult(result)

            HistoryService.save(
                channel: .screenshot,
                action: .summarize,
                inputPreview: "[Screenshot]",
                result: result,
                model: "google/gemini-3-flash-preview"
            )

            return .result(value: result)
        } catch {
            await Ai4PoorsActivityManager.shared.completeWithError(error.localizedDescription)
            return .result(value: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Translate Screen Intent

struct TranslateScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate Screenshot"
    static let description: IntentDescription = "Translates text visible in a screenshot"
    static let openAppWhenRun = false

    @Parameter(title: "Image")
    var imageFile: IntentFile

    @Parameter(title: "Target Language", default: "French")
    var targetLanguage: String

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$imageFile) to \(\.$targetLanguage)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard AppGroupConstants.isAPIKeyConfigured else {
            return .result(value: "Error: No API key configured.")
        }

        let imageData = imageFile.data
        guard let image = UIImage(data: imageData) else {
            return .result(value: "Error: Could not load image")
        }

        await Ai4PoorsActivityManager.shared.startAnalysis(
            source: "screenshot",
            instruction: "Translate"
        )

        do {
            let result = try await OpenRouterService.shared.analyzeImage(
                image: image,
                instruction: "Read the text visible on this screen and translate it to \(targetLanguage). Output only the translation."
            )
            await Ai4PoorsActivityManager.shared.completeWithResult(result)

            HistoryService.save(
                channel: .screenshot,
                action: .translate,
                inputPreview: "[Screenshot]",
                result: result,
                model: "google/gemini-3-flash-preview",
                customInstruction: "Translate to \(targetLanguage)"
            )

            return .result(value: result)
        } catch {
            await Ai4PoorsActivityManager.shared.completeWithError(error.localizedDescription)
            return .result(value: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Analyze Message Intent (for Shortcuts message automation)

struct AnalyzeMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Analyze Message with Ai4Poors"
    static let description: IntentDescription = "Analyzes an incoming message using AI and posts a notification with the result"
    static let openAppWhenRun = false

    @Parameter(title: "Message Text")
    var messageText: String

    @Parameter(title: "Sender", default: "Someone")
    var sender: String

    static var parameterSummary: some ParameterSummary {
        Summary("Analyze message from \(\.$sender): \(\.$messageText)")
    }

    private func intentLog(_ message: String) {
        guard let url = AppGroupConstants.sharedContainerURL?.appendingPathComponent("message_intent_debug.log") else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8) ?? Data())
            handle.closeFile()
        } else {
            try? entry.data(using: .utf8)?.write(to: url)
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        intentLog("Intent triggered — sender: \"\(sender)\" messageText (\(messageText.count) chars): \(String(messageText.prefix(200)))")

        // Skip short messages
        guard messageText.count >= 30 else {
            intentLog("Skipped: message too short (\(messageText.count) chars)")
            return .result(value: "Skipped: message too short")
        }

        guard AppGroupConstants.isAPIKeyConfigured else {
            intentLog("Skipped: no API key")
            return .result(value: "Error: No API key configured. Open Ai4Poors to set up your OpenRouter key.")
        }

        // Debounce: skip if we analyzed a message from this sender within 30 seconds
        let debounceKey = "ai4poors_last_message_\(sender)"
        if let lastAnalysis = AppGroupConstants.sharedDefaults?.object(forKey: debounceKey) as? Date,
           Date().timeIntervalSince(lastAnalysis) < 30 {
            intentLog("Skipped: debounced (\(sender)), last analysis \(Date().timeIntervalSince(lastAnalysis))s ago")
            return .result(value: "Skipped: debounced (\(sender))")
        }
        AppGroupConstants.sharedDefaults?.set(Date(), forKey: debounceKey)

        let instruction = "You received this message from \(sender). In 1-2 sentences: what are they saying/asking? If action needed, note it."

        do {
            intentLog("Sending to API...")
            let result = try await OpenRouterService.shared.analyzeText(
                text: messageText,
                instruction: instruction,
                model: "google/gemini-3-flash-preview"
            )
            intentLog("API response: \(result)")

            // Post local notification
            let content = UNMutableNotificationContent()
            content.title = "Ai4Poors: \(sender)"
            content.body = String(result.prefix(200))
            content.sound = .default
            content.categoryIdentifier = "ai4poors_message"
            content.userInfo = ["result": result, "sender": sender]

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)

            // Save to history
            HistoryService.save(
                channel: .share,
                action: .custom,
                inputPreview: "[\(sender)] \(String(messageText.prefix(150)))",
                result: result,
                model: "google/gemini-3-flash-preview",
                customInstruction: instruction
            )

            return .result(value: result)
        } catch {
            intentLog("ERROR: \(error.localizedDescription)")
            return .result(value: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Analyze Text Intent (for text-based Shortcuts)

struct AnalyzeTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Analyze Text with Ai4Poors"
    static let description: IntentDescription = "Sends text to AI for analysis"
    static let openAppWhenRun = false

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Instruction", default: "Analyze this text.")
    var instruction: String

    static var parameterSummary: some ParameterSummary {
        Summary("Analyze \(\.$text) with \(\.$instruction)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard AppGroupConstants.isAPIKeyConfigured else {
            return .result(value: "Error: No API key configured.")
        }

        do {
            let result = try await OpenRouterService.shared.analyzeText(
                text: text,
                instruction: instruction
            )
            return .result(value: result)
        } catch {
            return .result(value: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Shortcuts Provider

struct Ai4PoorsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AnalyzeScreenIntent(),
            phrases: [
                "Analyze screen with \(.applicationName)",
                "What's on my screen \(.applicationName)",
                "Read my screen with \(.applicationName)"
            ],
            shortTitle: "Analyze Screen",
            systemImageName: "camera.viewfinder"
        )

        AppShortcut(
            intent: SummarizeScreenIntent(),
            phrases: [
                "Summarize screen with \(.applicationName)",
                "Quick summary \(.applicationName)"
            ],
            shortTitle: "Summarize Screen",
            systemImageName: "doc.text.magnifyingglass"
        )

        AppShortcut(
            intent: AnalyzeTextIntent(),
            phrases: [
                "Analyze text with \(.applicationName)",
                "Ask \(.applicationName) about this"
            ],
            shortTitle: "Analyze Text",
            systemImageName: "text.cursor"
        )

        AppShortcut(
            intent: AnalyzeMessageIntent(),
            phrases: [
                "Analyze message with \(.applicationName)",
                "Read message with \(.applicationName)",
                "What does this message say \(.applicationName)"
            ],
            shortTitle: "Analyze Message",
            systemImageName: "message"
        )

        AppShortcut(
            intent: StartTranscriptionIntent(),
            phrases: [
                "Transcribe with \(.applicationName)",
                "Voice to text with \(.applicationName)",
                "Start recording \(.applicationName)"
            ],
            shortTitle: "Voice Transcription",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: StartSmartTranscriptionIntent(),
            phrases: [
                "Smart transcribe with \(.applicationName)",
                "Clean transcription \(.applicationName)"
            ],
            shortTitle: "Smart Transcription",
            systemImageName: "wand.and.stars"
        )

    }
}
