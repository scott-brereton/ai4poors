// KeyboardViewController.swift
// Ai4PoorsKeyboard - Custom keyboard extension
//
// An AI toolbar that sits above the regular keyboard.
// Reads text from any app's text field via textDocumentProxy,
// sends it to OpenRouter for AI analysis, and inserts results directly.

import UIKit
import SwiftUI

class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<Ai4PoorsKeyboardContent>?
    private let viewModel = Ai4PoorsKeyboardViewModel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupAi4PoorsToolbar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateContextPreview()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateContextPreview()
    }

    // MARK: - Setup

    private func setupAi4PoorsToolbar() {
        let content = Ai4PoorsKeyboardContent(
            viewModel: viewModel,
            onReply: { [weak self] in self?.handleAction(.reply) },
            onSummarize: { [weak self] in self?.handleAction(.summarize) },
            onTranslate: { [weak self] in self?.handleAction(.translate) },
            onImprove: { [weak self] in self?.handleAction(.improve) },
            onCustom: { [weak self] instruction in self?.handleCustom(instruction) },
            onSwitchKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            onInsert: { [weak self] text in self?.insertResult(text) }
        )

        let host = UIHostingController(rootView: content)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear

        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.heightAnchor.constraint(equalToConstant: 200)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    // MARK: - Context Reading

    func readContext() -> (before: String, after: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        return (before, after)
    }

    func readFullDocument() async -> String {
        let originalBefore = textDocumentProxy.documentContextBeforeInput ?? ""
        let originalAfter = textDocumentProxy.documentContextAfterInput ?? ""

        var allBefore = originalBefore
        var previousContext = originalBefore

        // Walk cursor backward to collect text beyond the ~300 char limit
        while !previousContext.isEmpty {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -previousContext.count)
            try? await Task.sleep(nanoseconds: 50_000_000)

            let newContext = textDocumentProxy.documentContextBeforeInput ?? ""
            if newContext.isEmpty || newContext == previousContext { break }
            allBefore = newContext + allBefore
            previousContext = newContext
        }

        // Return cursor to original position
        let totalMoved = allBefore.count - originalBefore.count
        if totalMoved > 0 {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: totalMoved)
        }

        return allBefore + originalAfter
    }

    private func updateContextPreview() {
        let context = readContext()
        let fullText = context.before + context.after
        let preview = fullText.trimmingCharacters(in: .whitespacesAndNewlines)

        DispatchQueue.main.async {
            if preview.isEmpty {
                self.viewModel.contextPreview = "No text detected"
            } else {
                let trimmed = String(preview.prefix(80))
                self.viewModel.contextPreview = trimmed + (preview.count > 80 ? "..." : "")
            }
        }
    }

    // MARK: - AI Actions

    private static let maxContentLength = 10_000

    private func handleAction(_ action: Ai4PoorsAction) {
        Task { @MainActor in
            guard AppGroupConstants.isAPIKeyConfigured else {
                viewModel.phase = .message("No API key. Open the Ai4Poors app to configure.")
                return
            }

            let context = readContext()
            let fullText = context.before + context.after

            guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                viewModel.phase = .message("No text detected in this field")
                return
            }

            // Truncate excessively long content to stay within memory limits
            let truncatedText: String
            if fullText.count > Self.maxContentLength {
                truncatedText = String(fullText.prefix(Self.maxContentLength))
            } else {
                truncatedText = fullText
            }
            let instruction = action.defaultInstruction
            viewModel.phase = .loading(action.displayName + "...")
            viewModel.streamingResult = ""

            triggerHaptic(.light)

            do {
                if AppGroupConstants.isStreamingEnabled {
                    let result = try await OpenRouterService.shared.analyzeTextStreaming(
                        text: truncatedText,
                        instruction: instruction
                    ) { [weak self] chunk in
                        DispatchQueue.main.async {
                            self?.viewModel.streamingResult += chunk
                        }
                    }
                    viewModel.phase = .result(result)
                    HistoryService.save(channel: .keyboard, action: action, inputPreview: truncatedText, result: result, model: OpenRouterService.routeModel(for: instruction))
                } else {
                    let result = try await OpenRouterService.shared.analyzeText(
                        text: truncatedText,
                        instruction: instruction
                    )
                    viewModel.phase = .result(result)
                    HistoryService.save(channel: .keyboard, action: action, inputPreview: truncatedText, result: result, model: OpenRouterService.routeModel(for: instruction))
                }
                triggerHaptic(.success)
            } catch {
                viewModel.phase = .message("Error: \(error.localizedDescription)")
                triggerHaptic(.error)
            }
        }
    }

    private func handleCustom(_ instruction: String) {
        Task { @MainActor in
            let context = readContext()
            let fullText = context.before + context.after

            viewModel.phase = .loading("Thinking...")
            viewModel.streamingResult = ""

            triggerHaptic(.light)

            do {
                let textToAnalyze = fullText.isEmpty ? "(No surrounding text)" : fullText

                if AppGroupConstants.isStreamingEnabled {
                    let result = try await OpenRouterService.shared.analyzeTextStreaming(
                        text: textToAnalyze,
                        instruction: instruction
                    ) { [weak self] chunk in
                        DispatchQueue.main.async {
                            self?.viewModel.streamingResult += chunk
                        }
                    }
                    viewModel.phase = .result(result)
                    HistoryService.save(channel: .keyboard, action: .custom, inputPreview: textToAnalyze, result: result, model: OpenRouterService.routeModel(for: instruction), customInstruction: instruction)
                } else {
                    let result = try await OpenRouterService.shared.analyzeText(
                        text: textToAnalyze,
                        instruction: instruction
                    )
                    viewModel.phase = .result(result)
                    HistoryService.save(channel: .keyboard, action: .custom, inputPreview: textToAnalyze, result: result, model: OpenRouterService.routeModel(for: instruction), customInstruction: instruction)
                }
                triggerHaptic(.success)
            } catch {
                viewModel.phase = .message("Error: \(error.localizedDescription)")
                triggerHaptic(.error)
            }
        }
    }

    // MARK: - Text Insertion

    private func insertResult(_ text: String) {
        textDocumentProxy.insertText(text)
        triggerHaptic(.medium)
    }

    func selectAllAndReplace(with text: String) {
        if let after = textDocumentProxy.documentContextAfterInput {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: after.count)
        }
        while let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty {
            for _ in 0..<before.count {
                textDocumentProxy.deleteBackward()
            }
        }
        textDocumentProxy.insertText(text)
    }

    // MARK: - Haptics

    private enum HapticType {
        case light, medium, success, error
    }

    private func triggerHaptic(_ type: HapticType) {
        guard AppGroupConstants.isHapticFeedbackEnabled else { return }
        switch type {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
