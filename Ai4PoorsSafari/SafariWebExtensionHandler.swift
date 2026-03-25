// SafariWebExtensionHandler.swift
// Ai4PoorsSafari - Native backend for Safari Web Extension
//
// Receives messages from the content script (page content, user actions),
// calls OpenRouter, and returns AI results back to the content script.

import SafariServices
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    private let logger = Logger(subsystem: "com.example.ai4poors.safari", category: "extension")

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo as? [String: Any],
              let messageDict = userInfo[SFExtensionMessageKey] as? [String: Any] else {
            logger.error("Failed to parse extension message")
            sendResponse(context: context, result: "Error: Invalid message format")
            return
        }

        let action = messageDict["action"] as? String ?? "custom"
        let content = messageDict["content"] as? [String: Any] ?? [:]

        let title = content["title"] as? String ?? ""
        let text = content["text"] as? String ?? ""
        let url = content["url"] as? String ?? ""
        let customInstruction = content["customInstruction"] as? String
        let selectedText = content["selectedText"] as? String

        logger.info("Received action: \(action) for URL: \(url)")

        // Reader mode: use Crawl4AI instead of OpenRouter — skip content building
        if action == "read" {
            Task {
                do {
                    guard AppGroupConstants.isCrawl4AIConfigured else {
                        // Fallback: summarize via OpenRouter if no Crawl4AI key
                        let fallbackContent = self.buildContent(title: title, text: selectedText ?? text, url: url, isSelection: selectedText != nil)
                        let fallbackInstruction = "Summarize this article concisely. 3-5 key points as bullet points.\n\n(Reader mode unavailable — add a Crawl4AI key in Ai4Poors Settings for full article extraction.)"
                        let result = try await OpenRouterService.shared.analyzeText(
                            text: fallbackContent,
                            instruction: fallbackInstruction,
                            model: "google/gemini-3-flash-preview"
                        )
                        HistoryService.save(
                            channel: .safari, action: .summarize,
                            inputPreview: title.isEmpty ? url : title,
                            result: result, model: "google/gemini-3-flash-preview"
                        )
                        sendResponse(context: context, result: result)
                        return
                    }

                    let crawlResult = try await Crawl4AIClient.scrapeAndClean(url: url)
                    let markdown = crawlResult.articleBody ?? "No content extracted."

                    logger.info("Reader extraction complete, \(markdown.count) chars")

                    // Record domain as approved
                    Crawl4AIClient.recordApprovedDomain(from: url)

                    HistoryService.save(
                        channel: .reader, action: .read,
                        inputPreview: crawlResult.articleTitle ?? title,
                        result: markdown, model: "crawl4ai",
                        customInstruction: url
                    )

                    // Cache for instant handoff to the app via deep link
                    AppGroupConstants.cacheReaderResult(
                        url: url,
                        title: crawlResult.articleTitle ?? title,
                        markdown: markdown
                    )

                    sendResponse(context: context, result: markdown, isReader: true)

                } catch {
                    logger.error("Reader extraction failed: \(error.localizedDescription)")
                    sendResponse(context: context, result: "Error: \(error.localizedDescription)")
                }
            }
            return
        }

        let instruction = buildInstruction(
            action: action,
            customInstruction: customInstruction
        )

        let contentToAnalyze = buildContent(
            title: title,
            text: selectedText ?? text,
            url: url,
            isSelection: selectedText != nil
        )

        Task {
            do {
                let model = selectModel(for: action)
                let result = try await OpenRouterService.shared.analyzeText(
                    text: contentToAnalyze,
                    instruction: instruction,
                    model: model
                )

                logger.info("Analysis complete, \(result.count) chars")

                let cortexAction = Ai4PoorsAction(rawValue: action) ?? .custom
                HistoryService.save(
                    channel: .safari,
                    action: cortexAction,
                    inputPreview: title.isEmpty ? contentToAnalyze : title,
                    result: result,
                    model: model,
                    customInstruction: customInstruction
                )

                sendResponse(context: context, result: result)

            } catch {
                logger.error("Analysis failed: \(error.localizedDescription)")
                sendResponse(context: context, result: "Error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Instruction Building

    private func buildInstruction(action: String, customInstruction: String?) -> String {
        switch action {
        case "summarize":
            return "Summarize this article concisely. 3-5 key points as bullet points."
        case "translate":
            let lang = AppGroupConstants.preferredLanguage
            return "Translate this to \(lang). Only output the translation."
        case "explain":
            return "Explain this content simply. What is the key takeaway? Be clear and direct."
        case "extract":
            return "Extract key points, facts, dates, numbers, and action items. Format as a clean bulleted list."
        case "tldr":
            return "Give a one-sentence TL;DR of this content."
        case "qa":
            return customInstruction ?? "Answer the user's question based on this page content."
        case "custom":
            return customInstruction ?? "Analyze this content."
        default:
            return customInstruction ?? "Analyze this content."
        }
    }

    private func buildContent(title: String, text: String, url: String, isSelection: Bool) -> String {
        var parts: [String] = []

        if !title.isEmpty {
            parts.append("Title: \(title)")
        }
        if !url.isEmpty {
            parts.append("URL: \(url)")
        }
        if isSelection {
            parts.append("(User selected the following text)")
        }
        if !text.isEmpty {
            // Sanitize: remove excessive whitespace, null bytes
            let cleaned = text
                .replacingOccurrences(of: "\0", with: "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            // Truncate very long content to stay within token limits
            let maxChars = 6000
            let truncatedText = cleaned.count > maxChars
                ? String(cleaned.prefix(maxChars)) + "\n\n[Content truncated at \(maxChars) characters...]"
                : cleaned
            parts.append("\nContent:\n\(truncatedText)")
        }

        return parts.joined(separator: "\n")
    }

    private func selectModel(for action: String) -> String {
        let fastActions = ["summarize", "translate", "extract", "tldr"]
        if fastActions.contains(action) {
            return "google/gemini-3-flash-preview"
        }
        return AppGroupConstants.preferredModel
    }

    // MARK: - Response

    private func sendResponse(context: NSExtensionContext, result: String, isReader: Bool = false) {
        let response = NSExtensionItem()
        var payload: [String: Any] = ["result": result]
        if isReader {
            payload["isReader"] = true
        }
        response.userInfo = [
            SFExtensionMessageKey: payload
        ]
        context.completeRequest(returningItems: [response])
    }
}
