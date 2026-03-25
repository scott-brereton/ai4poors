// Ai4PoorsState.swift
// Ai4Poors - App-wide state management

import SwiftUI
import Combine

// MARK: - App Tabs

enum AppTab: Hashable {
    case home
    case voice
    case search
    case history
    case settings
}

// MARK: - Pending Analysis

struct PendingAnalysis {
    let text: String
    let action: String
}

// MARK: - App State

@MainActor
final class Ai4PoorsAppState: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var selectedResultID: String?
    @Published var pendingAnalysis: PendingAnalysis?
    @Published var isAnalyzing = false
    @Published var currentResult: String?
    @Published var currentError: String?
    @Published var streamingText: String = ""
    @Published var isOnboardingCompleted: Bool = AppGroupConstants.isOnboardingCompleted
    @Published var pendingReaderURL: String?

    func completeOnboarding(apiKey: String) {
        AppGroupConstants.apiKey = apiKey
        AppGroupConstants.isOnboardingCompleted = true
        isOnboardingCompleted = true
    }

    // Analysis from screenshot pipeline
    func analyzeScreenshot(image: UIImage, action: Ai4PoorsAction, customInstruction: String? = nil) {
        isAnalyzing = true
        currentResult = nil
        currentError = nil
        streamingText = ""

        let instruction = customInstruction ?? action.defaultInstruction

        // Start Live Activity
        Ai4PoorsActivityManager.shared.startAnalysis(
            source: "screenshot",
            instruction: action.displayName,
            actionIcon: action.iconName
        )

        Task {
            do {
                let result = try await OpenRouterService.shared.analyzeImage(
                    image: image,
                    instruction: instruction
                )
                currentResult = result
                isAnalyzing = false

                Ai4PoorsActivityManager.shared.completeWithResult(result)

                // Save to history
                if AppGroupConstants.isHistoryEnabled {
                    saveToHistory(
                        channel: .screenshot,
                        action: action,
                        input: "[Screenshot]",
                        result: result,
                        customInstruction: customInstruction
                    )
                }
            } catch {
                currentError = error.localizedDescription
                isAnalyzing = false
                Ai4PoorsActivityManager.shared.completeWithError(error.localizedDescription)
            }
        }
    }

    // Text analysis (from share extension or direct)
    func analyzeText(_ text: String, action: Ai4PoorsAction, channel: Ai4PoorsChannel = .share, customInstruction: String? = nil) {
        isAnalyzing = true
        currentResult = nil
        currentError = nil
        streamingText = ""

        let instruction = customInstruction ?? action.defaultInstruction

        Ai4PoorsActivityManager.shared.startAnalysis(
            source: channel.rawValue,
            instruction: action.displayName,
            actionIcon: action.iconName
        )

        Task {
            do {
                if AppGroupConstants.isStreamingEnabled {
                    let result = try await OpenRouterService.shared.analyzeTextStreaming(
                        text: text,
                        instruction: instruction
                    ) { [weak self] chunk in
                        DispatchQueue.main.async {
                            self?.streamingText += chunk
                            Ai4PoorsActivityManager.shared.updateStreaming(
                                preview: self?.streamingText ?? ""
                            )
                        }
                    }
                    currentResult = result
                } else {
                    let result = try await OpenRouterService.shared.analyzeText(
                        text: text,
                        instruction: instruction
                    )
                    currentResult = result
                }

                isAnalyzing = false
                Ai4PoorsActivityManager.shared.completeWithResult(currentResult ?? "")

                if AppGroupConstants.isHistoryEnabled {
                    saveToHistory(
                        channel: channel,
                        action: action,
                        input: text,
                        result: currentResult ?? "",
                        customInstruction: customInstruction
                    )
                }
            } catch {
                currentError = error.localizedDescription
                isAnalyzing = false
                Ai4PoorsActivityManager.shared.completeWithError(error.localizedDescription)
            }
        }
    }

    private func saveToHistory(
        channel: Ai4PoorsChannel,
        action: Ai4PoorsAction,
        input: String,
        result: String,
        customInstruction: String?
    ) {
        let model = OpenRouterService.routeModel(for: customInstruction ?? action.defaultInstruction)
        let record = AnalysisRecord(
            channel: channel,
            action: action,
            inputPreview: input,
            result: result,
            model: model,
            customInstruction: customInstruction
        )
        // Persist via notification to ModelContext holder
        NotificationCenter.default.post(
            name: .ai4poorsSaveRecord,
            object: record
        )
    }

    func clearResult() {
        currentResult = nil
        currentError = nil
        streamingText = ""
        isAnalyzing = false
    }
}

// ai4poorsSaveRecord moved to Shared/Models.swift
