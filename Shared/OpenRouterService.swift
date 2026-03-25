// OpenRouterService.swift
// Ai4Poors - Unified API layer for all channels
//
// Handles text analysis, streaming, and vision (image) analysis
// via OpenRouter. Shared across keyboard, Safari, screenshot, and share extensions.

import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

private let cortexLog = Logger(subsystem: "com.example.ai4poors", category: "ToolUse")

actor OpenRouterService {

    static let shared = OpenRouterService()
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let session: URLSession

    // Conversation history for follow-up questions (limited to last 6 messages)
    private var conversationHistory: [[String: Any]] = []
    private let maxHistoryMessages = 6

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    func clearConversation() {
        conversationHistory = []
    }

    func seedHistoryIfEmpty(instruction: String, result: String) {
        guard conversationHistory.isEmpty else { return }
        appendToHistory(role: "user", content: instruction)
        appendToHistory(role: "assistant", content: result)
    }

    private func appendToHistory(role: String, content: String) {
        conversationHistory.append(["role": role, "content": content])
        // Keep history bounded
        if conversationHistory.count > maxHistoryMessages {
            conversationHistory = Array(conversationHistory.suffix(maxHistoryMessages))
        }
    }

    // MARK: - API Key

    private var apiKey: String {
        AppGroupConstants.apiKey
    }

    // MARK: - Message Triage (cheap gate before full summarization)

    struct TriageResult: Decodable {
        let analyze: Bool
    }

    /// Fast, cheap LLM call that decides if a message burst warrants full summarization.
    /// Returns true if the messages contain questions, requests, or complex content.
    func triageMessages(text: String) async throws -> Bool {
        guard !apiKey.isEmpty else { throw Ai4PoorsError.noAPIKey }

        let prompt = """
        You are a message triage filter. Given incoming text message(s), decide if they warrant a detailed summary notification.

        Return {"analyze": true} if the messages contain ANY of:
        - A question or request that needs attention
        - Complex or detailed content that benefits from summarization
        - Important information, plans, logistics, or updates
        - Multiple topics or a conversation worth catching up on
        - Time-sensitive content (invitations, deadlines, meeting times)

        Return {"analyze": false} if the messages are ONLY:
        - Simple acknowledgments (ok, sounds good, cool, got it, thanks, np, bet, yep, nah)
        - Short reactions (lol, haha, nice, wow, omg, 😂, 💀)
        - Single emoji or very brief responses that are self-explanatory
        - Simple yes/no answers with no additional context
        - Trivial one-liners that don't need rephrasing to understand

        Respond with ONLY a JSON object.
        """

        let body: [String: Any] = [
            "model": "google/gemini-3-flash-preview",
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ] as [[String: Any]],
            "max_tokens": 20,
            "temperature": 0.0,
            "response_format": ["type": "json_object"] as [String: String]
        ]

        let data = try await performRequest(body: body)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        AppGroupConstants.incrementCallCount()

        guard let content = response.choices.first?.message.content,
              let jsonData = content.data(using: .utf8),
              let result = try? JSONDecoder().decode(TriageResult.self, from: jsonData) else {
            // If triage parsing fails, default to analyzing (don't miss important messages)
            return true
        }

        return result.analyze
    }

    // MARK: - Text Analysis (Keyboard, Safari — cheap & fast)

    func analyzeText(
        text: String,
        instruction: String,
        model: String? = nil,
        maxTokens: Int? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw Ai4PoorsError.noAPIKey }

        let selectedModel = model ?? Self.routeModel(for: instruction)
        let messages = Self.buildMessages(text: text, instruction: instruction)

        var body = Self.buildRequestBody(
            model: selectedModel,
            messages: messages,
            stream: false
        )
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }

        let data = try await performRequest(body: body)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        AppGroupConstants.incrementCallCount()

        guard let message = response.choices.first?.message,
              let content = message.content else {
            throw Ai4PoorsError.invalidResponse
        }
        return content
    }

    // MARK: - Raw Text Transform (no default system prompt, custom max_tokens)

    /// Sends text through a model with a custom system prompt and no routing/prompt overrides.
    /// Used for tasks like article cleaning where the full text must be preserved.
    func transformText(
        text: String,
        systemPrompt: String,
        model: String,
        maxTokens: Int
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw Ai4PoorsError.noAPIKey }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ] as [[String: Any]],
            "max_tokens": maxTokens,
            "temperature": 0.0
        ]

        let data = try await performRequest(body: body)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        AppGroupConstants.incrementCallCount()

        guard let message = response.choices.first?.message,
              let content = message.content else {
            throw Ai4PoorsError.invalidResponse
        }
        return content
    }

    // MARK: - Streaming Text Analysis (Keyboard — for longer outputs)

    func analyzeTextStreaming(
        text: String,
        instruction: String,
        model: String? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw Ai4PoorsError.noAPIKey }

        let selectedModel = model ?? Self.routeModel(for: instruction)
        let messages = Self.buildMessages(text: text, instruction: instruction)

        let body = Self.buildRequestBody(
            model: selectedModel,
            messages: messages,
            stream: true
        )

        let request = buildURLRequest(body: body)
        let (stream, response) = try await session.bytes(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorData = try await stream.lines.reduce(into: "") { $0 += $1 }
            throw Ai4PoorsError.apiError(code: httpResponse.statusCode, message: errorData)
        }

        var fullResult = ""

        for try await line in stream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]" else { break }

            if let data = payload.data(using: .utf8),
               let chunk = try? JSONDecoder().decode(StreamChunkResponse.self, from: data),
               let content = chunk.choices.first?.delta.content {
                fullResult += content
                onChunk(content)
            }
        }

        AppGroupConstants.incrementCallCount()
        return fullResult
    }

    // MARK: - Text Analysis with Tools + Web Search

    func analyzeTextWithTools(
        text: String,
        instruction: String,
        model: String? = nil
    ) async throws -> ToolAnalysisResult {
        guard !apiKey.isEmpty else { throw Ai4PoorsError.noAPIKey }

        let selectedModel = model ?? Self.routeModel(for: instruction)
        let toolDefs = await ToolRegistry.shared.allDefinitions()

        let body: [String: Any] = [
            "model": selectedModel,
            "messages": [
                ["role": "system", "content": instruction],
                ["role": "user", "content": text]
            ] as [[String: Any]],
            "max_tokens": max(AppGroupConstants.maxTokens, 4096),
            "temperature": 0.5,
            "tools": toolDefs,
            "plugins": [
                ["id": "web"]
            ]
        ]

        let data = try await performRequest(body: body)

        let rawResponse = String(data: data, encoding: .utf8) ?? "nil"
        Self.writeDebugLog("=== analyzeTextWithTools RAW RESPONSE ===\n\(rawResponse)\n")

        let response: ChatCompletionResponse
        do {
            response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            Self.writeDebugLog("=== analyzeTextWithTools DECODE ERROR ===\n\(error)\nRaw: \(rawResponse.prefix(500))\n")
            throw Ai4PoorsError.invalidResponse
        }

        AppGroupConstants.incrementCallCount()

        guard let message = response.choices.first?.message else {
            Self.writeDebugLog("=== analyzeTextWithTools NO MESSAGE ===\nChoices count: \(response.choices.count)\n")
            throw Ai4PoorsError.invalidResponse
        }

        // If the model returned tool calls, execute them and do a final round-trip
        if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            var toolResults: [String] = []
            var assistantMessage: [String: Any] = [
                "role": "assistant",
                "tool_calls": toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": call.type,
                        "function": [
                            "name": call.function.name,
                            "arguments": call.function.arguments
                        ] as [String: Any]
                    ] as [String: Any]
                }
            ]
            if let content = message.content {
                assistantMessage["content"] = content
            }

            var toolMessages: [[String: Any]] = [
                ["role": "system", "content": instruction],
                ["role": "user", "content": text],
                assistantMessage
            ]

            for call in toolCalls {
                let args = parseToolArguments(call.function.arguments)
                let result = await ToolRegistry.shared.execute(name: call.function.name, arguments: args)
                toolResults.append(result)
                toolMessages.append([
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": result
                ])
            }

            Self.writeDebugLog("=== analyzeTextWithTools TOOL EXECUTION ===\nTool calls: \(toolCalls.count)\nResults: \(toolResults)\n")

            let finalBody: [String: Any] = [
                "model": selectedModel,
                "messages": toolMessages,
                "max_tokens": max(AppGroupConstants.maxTokens, 4096),
                "temperature": 0.5
            ]

            let finalData = try await performRequest(body: finalBody)
            let finalRaw = String(data: finalData, encoding: .utf8) ?? "nil"
            Self.writeDebugLog("=== analyzeTextWithTools FINAL RESPONSE ===\n\(finalRaw.prefix(1000))\n")

            let finalResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: finalData)

            AppGroupConstants.incrementCallCount()

            // Use final response content if available, otherwise use the first response's content
            let finalContent = finalResponse.choices.first?.message.content
                ?? message.content
                ?? ""

            let actions = await ToolRegistry.shared.parseActions(from: toolCalls, results: toolResults)
            Self.writeDebugLog("=== analyzeTextWithTools COMPLETE ===\nContent: \(finalContent.prefix(200))\nActions: \(actions.count)\n")
            return ToolAnalysisResult(text: finalContent, actions: actions)
        }

        // No tool calls — return the first pass result directly
        return ToolAnalysisResult(text: message.content ?? "", actions: [])
    }

    struct ToolAnalysisResult: Sendable {
        let text: String
        let actions: [ToolAction]
    }

    // MARK: - Vision Analysis (Screenshot pipeline — more expensive)

    #if canImport(UIKit)
    func analyzeImage(
        image: UIImage,
        instruction: String,
        model: String? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw Ai4PoorsError.noAPIKey }

        guard let imageData = Self.optimizeImageForUpload(image) else {
            throw Ai4PoorsError.imageEncodingFailed
        }
        let base64 = imageData.base64EncodedString()
        let selectedModel = model ?? "google/gemini-3-flash-preview"

        let systemPrompt = """
        Today's date is \(Self.todayString).

        You are the user's smart, observant friend. They just showed you their phone screen. Your job:

        1. **IDENTIFY** what matters — skip "This is a screenshot of..." and name the actual thing (a deal, an error, a conversation, a receipt, a product, a meme, code, an article...)
        2. **REACT** like a real person — Is the deal good? Is the error fixable? Is the product worth it? What's the read on the conversation? Flag anything sketchy on a receipt.
        3. **SURFACE** what they might miss — the fine print, the red flag, the hidden cost, the better alternative, the missing context.

        Be direct. Be opinionated where it helps. 2-4 sentences unless it genuinely needs more. Start with the insight, not the description.

        CRITICAL RULES FOR SCREENSHOT ANALYSIS:
        You are analyzing a screenshot taken on an iPhone. You MUST completely ignore and NEVER mention any of the following iOS system elements:
        - Status bar (time, wifi/cellular signal, battery, carrier name)
        - Navigation bars, tab bars, toolbars, home indicator
        - System notifications, banners, or overlays (including "Back Tap Detected", Do Not Disturb, AirDrop, etc.)
        - Keyboard, autocorrect suggestions, dictation UI
        - System alerts or permission dialogs that are overlaid
        - Control Center, Notification Center
        - Any Ai4Poors UI elements (floating button, panel)

        Focus EXCLUSIVELY on the primary app or website content visible in the screenshot. Analyze only the visible content underneath any overlays and do not mention the overlays.
        """

        let body: [String: Any] = [
            "model": selectedModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    [
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                    ] as [String: Any],
                    [
                        "type": "text",
                        "text": instruction
                    ] as [String: Any]
                ] as [[String: Any]]]
            ] as [[String: Any]],
            "max_tokens": max(AppGroupConstants.maxTokens, 4096),
            "temperature": 0.5
        ]

        let data = try await performRequest(body: body)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        AppGroupConstants.incrementCallCount()

        guard let message = response.choices.first?.message,
              let content = message.content else {
            throw Ai4PoorsError.invalidResponse
        }

        // Store conversation for follow-ups
        appendToHistory(role: "user", content: instruction)
        appendToHistory(role: "assistant", content: content)

        return content
    }

    /// Follow-up question using stored conversation history (no image re-upload)
    func analyzeImageFollowUp(
        image: UIImage,
        question: String,
        model: String? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw Ai4PoorsError.noAPIKey }

        guard let imageData = Self.optimizeImageForUpload(image) else {
            throw Ai4PoorsError.imageEncodingFailed
        }
        let base64 = imageData.base64EncodedString()
        let selectedModel = model ?? "google/gemini-3-flash-preview"

        let systemPrompt = """
        Today's date is \(Self.todayString).

        You are the user's smart, observant friend continuing a conversation about their phone screen. \
        They already showed you the screen and you discussed it. Now they have a follow-up question. \
        Be direct and helpful. Reference what you discussed before when relevant.

        CRITICAL RULES FOR SCREENSHOT ANALYSIS:
        Completely ignore iOS system elements (status bar, nav bars, overlays, keyboard, Control Center, Ai4Poors UI). \
        Focus exclusively on the app/website content.
        """

        // Build messages: system + image + conversation history + new question
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": [
                [
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                ] as [String: Any],
                [
                    "type": "text",
                    "text": "Here's the screenshot we're discussing."
                ] as [String: Any]
            ] as [[String: Any]]]
        ]

        // Append stored conversation history
        messages.append(contentsOf: conversationHistory)

        // Append new follow-up question
        messages.append(["role": "user", "content": question])

        let body: [String: Any] = [
            "model": selectedModel,
            "messages": messages,
            "max_tokens": AppGroupConstants.maxTokens,
            "temperature": 0.5
        ]

        let data = try await performRequest(body: body)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        AppGroupConstants.incrementCallCount()

        guard let message = response.choices.first?.message,
              let content = message.content else {
            throw Ai4PoorsError.invalidResponse
        }

        // Update history with follow-up
        appendToHistory(role: "user", content: question)
        appendToHistory(role: "assistant", content: content)

        return content
    }

    // MARK: - Vision Analysis with Tool Use

    func analyzeImageWithTools(
        image: UIImage,
        instruction: String,
        model: String? = nil
    ) async throws -> ToolAnalysisResult {
        guard !apiKey.isEmpty else { throw Ai4PoorsError.noAPIKey }

        guard let imageData = Self.optimizeImageForUpload(image) else {
            throw Ai4PoorsError.imageEncodingFailed
        }
        let base64 = imageData.base64EncodedString()
        let selectedModel = model ?? "google/gemini-3-flash-preview"

        // ── Pass 1: Extract context from the screenshot (vision, no web) ──

        let extractionPrompt = """
        Look at this screenshot and extract:
        1. A brief summary of what's on screen (1-2 sentences)
        2. All key entities: people, companies, places, products, events, dates, numbers
        3. Two or three specific web search queries that would find the most relevant, current context for what's shown (be very specific — include names, dates, places)

        Format your response exactly like this:
        SUMMARY: ...
        ENTITIES: ...
        SEARCH: query one
        SEARCH: query two
        SEARCH: query three
        """

        let pass1Body: [String: Any] = [
            "model": selectedModel,
            "messages": [
                ["role": "system", "content": "Today's date is \(Self.todayString). You extract structured information from screenshots. Be precise and specific. Ignore iOS system UI elements."],
                ["role": "user", "content": [
                    [
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                    ] as [String: Any],
                    [
                        "type": "text",
                        "text": extractionPrompt
                    ] as [String: Any]
                ] as [[String: Any]]]
            ] as [[String: Any]],
            "max_tokens": 512,
            "temperature": 0.1
        ]

        Self.writeDebugLog("=== PASS 1: EXTRACTION ===\nModel: \(selectedModel)\n")

        let pass1Data = try await performRequest(body: pass1Body)
        let pass1Response = try JSONDecoder().decode(ChatCompletionResponse.self, from: pass1Data)

        AppGroupConstants.incrementCallCount()

        let extraction = pass1Response.choices.first?.message.content ?? ""
        Self.writeDebugLog("=== PASS 1 RESULT ===\n\(extraction)\n")

        // ── Pass 2: Grounded analysis with web search + tools ──

        let analysisPrompt = """
        Today's date is \(Self.todayString).

        You are the user's smart, curious friend. They showed you their phone screen. You have access to real-time web search results that have been found for you — use them to give substantive, well-informed analysis.

        YOUR APPROACH:
        1. **Lead with the insight** — no "This is a screenshot of..." Start with what matters.
        2. **Go deep** — Use the web search results to add real substance:
           - What's the bigger picture? What are the implications?
           - What do the numbers actually mean? Put them in context with current data.
           - What should the user know that isn't on screen?
           - What are different perspectives or interpretations?
           Write as much as the topic genuinely warrants. A breaking news story deserves several paragraphs of context. A simple meme deserves a line. Match your depth to the content.
        3. **Treat the content as real and current** — if it has today's date or recent dates, it IS current. Do not speculate that it might be fictional or a simulation. Analyze it at face value.
        4. **Give your take** — Be opinionated where it helps. A smart friend doesn't just inform, they advise.
        5. **Use tools when there's something actionable:**
           - copy_text: Phone numbers, codes, addresses, prices, key quotes, reference numbers
           - open_url: Source articles, Maps links, product pages, relevant resources
           Only call tools when there's genuinely useful extractable text or a link worth opening.

        CRITICAL: Ignore iOS system elements (status bar, nav bars, overlays, keyboard, Ai4Poors UI). Focus on the content.
        """

        let toolDefs = await ToolRegistry.shared.allDefinitions()

        // Build pass 2 user message: the image + the extracted context as searchable text
        let pass2UserContent: [[String: Any]] = [
            [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
            ] as [String: Any],
            [
                "type": "text",
                "text": """
                The user wants to know: \(instruction)

                Here is what's on this screen:
                \(extraction)
                """
            ] as [String: Any]
        ]

        let pass2Body: [String: Any] = [
            "model": selectedModel,
            "messages": [
                ["role": "system", "content": analysisPrompt],
                ["role": "user", "content": pass2UserContent]
            ] as [[String: Any]],
            "max_tokens": max(AppGroupConstants.maxTokens, 4096),
            "temperature": 0.5,
            "tools": toolDefs,
            "plugins": [
                ["id": "web"]
            ]
        ]

        Self.writeDebugLog("=== PASS 2: GROUNDED ANALYSIS ===\nExtraction fed to web plugin:\n\(extraction)\n")

        let data = try await performRequest(body: pass2Body)

        let responseStr = String(data: data, encoding: .utf8) ?? "nil"
        Self.writeDebugLog("=== PASS 2 RESPONSE ===\n\(responseStr)\n")

        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        AppGroupConstants.incrementCallCount()

        guard let message = response.choices.first?.message else {
            throw Ai4PoorsError.invalidResponse
        }

        // If the model returned tool calls, execute them and do a final round-trip
        if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            var toolResults: [String] = []
            var assistantMessage: [String: Any] = [
                "role": "assistant",
                "tool_calls": toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": call.type,
                        "function": [
                            "name": call.function.name,
                            "arguments": call.function.arguments
                        ] as [String: Any]
                    ] as [String: Any]
                }
            ]
            if let content = message.content {
                assistantMessage["content"] = content
            }

            var toolMessages: [[String: Any]] = [
                ["role": "system", "content": analysisPrompt],
                ["role": "user", "content": pass2UserContent],
                assistantMessage
            ]

            for call in toolCalls {
                let args = parseToolArguments(call.function.arguments)
                let result = await ToolRegistry.shared.execute(name: call.function.name, arguments: args)
                toolResults.append(result)
                toolMessages.append([
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": result
                ])
            }

            let finalBody: [String: Any] = [
                "model": selectedModel,
                "messages": toolMessages,
                "max_tokens": max(AppGroupConstants.maxTokens, 4096),
                "temperature": 0.5
            ]

            let finalData = try await performRequest(body: finalBody)
            let finalResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: finalData)

            AppGroupConstants.incrementCallCount()

            guard let finalMessage = finalResponse.choices.first?.message,
                  let finalContent = finalMessage.content else {
                throw Ai4PoorsError.invalidResponse
            }

            let actions = await ToolRegistry.shared.parseActions(from: toolCalls, results: toolResults)

            Self.writeDebugLog("=== FINAL (with tools) ===\n\(finalContent)\nActions: \(actions.count)\n")

            appendToHistory(role: "user", content: instruction)
            appendToHistory(role: "assistant", content: finalContent)

            return ToolAnalysisResult(text: finalContent, actions: actions)
        }

        // No tool calls — return the grounded analysis as-is
        let content = message.content ?? ""

        Self.writeDebugLog("=== FINAL (no tools) ===\n\(content)\n")

        appendToHistory(role: "user", content: instruction)
        appendToHistory(role: "assistant", content: content)

        return ToolAnalysisResult(text: content, actions: [])
    }

    #endif

    private func parseToolArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    // MARK: - Debug Logging

    static func writeDebugLog(_ message: String) {
        guard let url = AppGroupConstants.sharedContainerURL?.appendingPathComponent("tool_debug.log") else { return }
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

    // MARK: - Model Routing

    static func routeModel(for instruction: String) -> String {
        let lower = instruction.lowercased()

        let fastTasks = ["summarize", "translate", "extract", "list", "tldr", "key points"]
        if fastTasks.contains(where: { lower.contains($0) }) {
            return "google/gemini-3-flash-preview"
        }

        return AppGroupConstants.preferredModel
    }

    // MARK: - Message Building

    private static func buildMessages(text: String, instruction: String) -> [[String: Any]] {
        let system = systemPrompt(for: instruction)
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": "Content:\n\(text)\n\nInstruction: \(instruction)"]
        ]
    }

    private static func buildRequestBody(
        model: String,
        messages: [[String: Any]],
        stream: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": AppGroupConstants.maxTokens,
            "temperature": AppGroupConstants.temperature
        ]
        if stream {
            body["stream"] = true
        }
        return body
    }

    // MARK: - Date Helper

    static var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - System Prompts

    static func systemPrompt(for instruction: String) -> String {
        let lower = instruction.lowercased()

        if lower.contains("translate") {
            return "You are a translator. Output only the translation, no commentary."
        }
        if lower.contains("summarize") || lower.contains("tldr") {
            return "You are a summarizer. Be concise. Use bullet points for multiple points."
        }
        if lower.contains("reply") || lower.contains("draft") {
            return "You are a writing assistant. Draft a reply that matches the tone and context. Keep it natural and concise."
        }
        if lower.contains("explain") || lower.contains("error") {
            return "You are a technical explainer. If it's an error, explain the cause and fix. Be clear and actionable."
        }
        if lower.contains("extract") || lower.contains("key points") {
            return "You are a data extractor. Pull out dates, names, numbers, action items. Format as a clean list."
        }
        if lower.contains("improve") {
            return "You are an editor. Improve this text — fix grammar, clarify meaning, improve flow. Keep the same tone and intent. Output only the improved text."
        }

        return "Today's date is \(todayString). You are Ai4Poors, the user's sharp AI assistant. Be direct, lead with the insight, and skip obvious observations."
    }

    // MARK: - Network

    private func buildURLRequest(body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Ai4Poors iOS", forHTTPHeaderField: "X-Title")
        request.setValue("https://github.com/example/ai4poors", forHTTPHeaderField: "HTTP-Referer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func performRequest(body: [String: Any], maxRetries: Int = 3) async throws -> Data {
        let request = buildURLRequest(body: body)
        var lastError: Error?

        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }

            do {
                let (data, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200...299:
                        return data
                    case 429:
                        if attempt == maxRetries { throw Ai4PoorsError.rateLimited }
                        lastError = Ai4PoorsError.rateLimited
                        continue
                    case 500...599:
                        if attempt == maxRetries {
                            let message = String(data: data, encoding: .utf8) ?? "Server error"
                            throw Ai4PoorsError.apiError(code: httpResponse.statusCode, message: message)
                        }
                        lastError = Ai4PoorsError.apiError(code: httpResponse.statusCode, message: "Server error")
                        continue
                    default:
                        let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                        throw Ai4PoorsError.apiError(code: httpResponse.statusCode, message: message)
                    }
                }

                return data
            } catch let error as Ai4PoorsError {
                throw error
            } catch {
                if attempt == maxRetries { throw Ai4PoorsError.networkError(underlying: error) }
                lastError = error
                continue
            }
        }

        throw lastError ?? Ai4PoorsError.invalidResponse
    }

    // MARK: - Image Optimization

    #if canImport(UIKit)
    private static func optimizeImageForUpload(_ image: UIImage) -> Data? {
        let maxDim: CGFloat = 1280
        let scale = min(maxDim / image.size.width, maxDim / image.size.height, 1.0)

        if scale < 1.0 {
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            return resized.jpegData(compressionQuality: 0.7)
        }

        return image.jpegData(compressionQuality: 0.7)
    }
    #endif
}
