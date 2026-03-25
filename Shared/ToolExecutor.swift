// ToolExecutor.swift
// Ai4Poors - Tool protocol, registry, and built-in tools for screenshot analysis

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Tool Protocol

protocol Ai4PoorsTool: Sendable {
    var name: String { get }
    var definition: [String: Any] { get }
    func execute(arguments: [String: Any]) async -> String
}

// MARK: - Tool Action (returned to UI for rendering action pills)

struct ToolAction: Identifiable, Codable, Sendable {
    let id: UUID
    let label: String
    let systemImage: String
    let type: ActionType

    enum ActionType: Codable, Sendable {
        case copy(String)
        case openURL(URL)
    }

    init(label: String, systemImage: String, type: ActionType) {
        self.id = UUID()
        self.label = label
        self.systemImage = systemImage
        self.type = type
    }

    static func encode(_ actions: [ToolAction]) -> Data? {
        try? JSONEncoder().encode(actions)
    }

    static func decode(from data: Data?) -> [ToolAction] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([ToolAction].self, from: data)) ?? []
    }
}

// MARK: - Tool Registry

actor ToolRegistry {
    static let shared = ToolRegistry()

    private var tools: [String: any Ai4PoorsTool] = [:]

    private init() {
        let copyTool = CopyTextTool()
        let openTool = OpenURLTool()
        tools[copyTool.name] = copyTool
        tools[openTool.name] = openTool
    }

    func register(_ tool: any Ai4PoorsTool) {
        tools[tool.name] = tool
    }

    func allDefinitions() -> [[String: Any]] {
        tools.values.map { $0.definition }
    }

    func execute(name: String, arguments: [String: Any]) async -> String {
        guard let tool = tools[name] else {
            return "Error: Unknown tool '\(name)'"
        }
        return await tool.execute(arguments: arguments)
    }

    /// Parse tool call results into ToolActions for the UI
    func parseActions(from toolCalls: [ChatCompletionResponse.ToolCall], results: [String]) -> [ToolAction] {
        var actions: [ToolAction] = []

        for (call, result) in zip(toolCalls, results) {
            guard let args = parseArguments(call.function.arguments) else { continue }

            switch call.function.name {
            case "copy_text":
                if let text = args["text"] as? String {
                    let label = args["label"] as? String ?? String(text.prefix(30))
                    actions.append(ToolAction(
                        label: "Copy \"\(label)\"",
                        systemImage: "doc.on.clipboard",
                        type: .copy(text)
                    ))
                }
            case "open_url":
                if let urlString = args["url"] as? String, let url = URL(string: urlString) {
                    let label = args["label"] as? String ?? url.host ?? "link"
                    actions.append(ToolAction(
                        label: "Open \(label)",
                        systemImage: "arrow.up.right.square",
                        type: .openURL(url)
                    ))
                }
            default:
                break
            }
        }

        return actions
    }

    private func parseArguments(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
}

// MARK: - Copy Text Tool

struct CopyTextTool: Ai4PoorsTool, Sendable {
    let name = "copy_text"

    var definition: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": "Extract and prepare specific text for the user to copy (phone number, address, code snippet, email, tracking number, etc). Use this when you spot text the user will likely want to grab.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "text": [
                            "type": "string",
                            "description": "The exact text to copy"
                        ] as [String: Any],
                        "label": [
                            "type": "string",
                            "description": "Short label describing what this text is (e.g. 'phone number', 'tracking code')"
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["text"]
                ] as [String: Any]
            ] as [String: Any]
        ]
    }

    func execute(arguments: [String: Any]) async -> String {
        guard let text = arguments["text"] as? String else {
            return "Error: No text provided"
        }
        let label = arguments["label"] as? String ?? "text"
        return "Ready to copy \(label): \(text)"
    }
}

// MARK: - Open URL Tool

struct OpenURLTool: Ai4PoorsTool, Sendable {
    let name = "open_url"

    var definition: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": "Construct a URL for the user to open — Maps directions, App Store link, website, search query, etc. Use this when an action requires navigating somewhere.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "url": [
                            "type": "string",
                            "description": "The full URL to open"
                        ] as [String: Any],
                        "label": [
                            "type": "string",
                            "description": "Short label for the button (e.g. 'Open in Maps', 'View on Amazon')"
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["url"]
                ] as [String: Any]
            ] as [String: Any]
        ]
    }

    func execute(arguments: [String: Any]) async -> String {
        guard let urlString = arguments["url"] as? String else {
            return "Error: No URL provided"
        }
        guard URL(string: urlString) != nil else {
            return "Error: Invalid URL"
        }
        let label = arguments["label"] as? String ?? "link"
        return "Ready to open \(label): \(urlString)"
    }
}
