// Ai4PoorsKeyboardView.swift
// Ai4PoorsKeyboard - Compact AI toolbar keyboard

import SwiftUI

// MARK: - View Model

class Ai4PoorsKeyboardViewModel: ObservableObject {
    @Published var phase: KeyboardPhase = .actions
    @Published var streamingResult: String = ""
    @Published var contextPreview: String = "No text detected"

    enum KeyboardPhase: Equatable {
        case actions
        case loading(String)
        case result(String)
        case message(String)

        static func == (lhs: KeyboardPhase, rhs: KeyboardPhase) -> Bool {
            switch (lhs, rhs) {
            case (.actions, .actions): return true
            case (.loading(let a), .loading(let b)): return a == b
            case (.result(let a), .result(let b)): return a == b
            case (.message(let a), .message(let b)): return a == b
            default: return false
            }
        }
    }
}

// MARK: - Main Keyboard Content

struct Ai4PoorsKeyboardContent: View {
    @ObservedObject var viewModel: Ai4PoorsKeyboardViewModel

    let onReply: () -> Void
    let onSummarize: () -> Void
    let onTranslate: () -> Void
    let onImprove: () -> Void
    let onCustom: (String) -> Void
    let onSwitchKeyboard: () -> Void
    let onInsert: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.phase {
            case .actions:
                actionsView

            case .loading(let message):
                loadingView(message)

            case .result(let text):
                resultView(text)

            case .message(let text):
                messageView(text)
            }

            bottomBar
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Actions View

    private var actionsView: some View {
        VStack(spacing: 6) {
            // Context indicator
            HStack(spacing: 4) {
                Image(systemName: viewModel.contextPreview == "No text detected" ? "exclamationmark.circle" : "text.viewfinder")
                    .font(.system(size: 9))
                Text(viewModel.contextPreview == "No text detected"
                     ? "Type text above, then use an action"
                     : viewModel.contextPreview)
                    .font(.system(size: 10))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(viewModel.contextPreview == "No text detected" ? .orange : .secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)

            // Row 1: Primary actions
            HStack(spacing: 5) {
                KBChip(icon: "arrowshape.turn.up.left.fill", label: "Reply", action: onReply)
                KBChip(icon: "doc.text.magnifyingglass", label: "Summarize", action: onSummarize)
                KBChip(icon: "globe", label: "Translate", action: onTranslate)
                KBChip(icon: "wand.and.stars", label: "Improve", action: onImprove)
            }
            .padding(.horizontal, 6)

            // Row 2: Secondary actions
            HStack(spacing: 5) {
                KBChip(icon: "lightbulb.fill", label: "Explain") {
                    onCustom("Explain this content simply. What is the key takeaway?")
                }
                KBChip(icon: "list.bullet", label: "Key Points") {
                    onCustom("Extract key points, facts, dates, and action items as a list.")
                }
                KBChip(icon: "text.justify.left", label: "TL;DR") {
                    onCustom("Give a one-sentence TL;DR of this content.")
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Loading View

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    viewModel.phase = .actions
                    viewModel.streamingResult = ""
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            if !viewModel.streamingResult.isEmpty {
                ScrollView {
                    Text(viewModel.streamingResult)
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(maxHeight: 100)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Result View

    private func resultView(_ text: String) -> some View {
        VStack(spacing: 4) {
            ScrollView {
                MarkdownText(text, font: .system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 100)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 6)
            .padding(.top, 6)

            HStack(spacing: 8) {
                Button {
                    onInsert(text)
                    viewModel.phase = .actions
                    viewModel.streamingResult = ""
                } label: {
                    Label("Insert", systemImage: "text.insert")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)

                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Spacer()

                Button {
                    viewModel.phase = .actions
                    viewModel.streamingResult = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
        }
    }

    // MARK: - Message View

    private func messageView(_ text: String) -> some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button("OK") {
                viewModel.phase = .actions
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.bordered)
            .controlSize(.mini)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button(action: onSwitchKeyboard) {
                Image(systemName: "globe")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 4)

            Spacer()

            HStack(spacing: 3) {
                Image(systemName: "sparkle")
                    .font(.system(size: 7))
                Text("Ai4Poors")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.tertiary)

            Spacer()

            Button {
                viewModel.phase = .actions
                viewModel.streamingResult = ""
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
            }
            .padding(.trailing, 4)
        }
        .padding(.vertical, 4)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Compact Action Chip

struct KBChip: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
