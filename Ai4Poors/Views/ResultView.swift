// ResultView.swift
// Ai4Poors - Result-first display with conversational follow-up

import SwiftUI

struct ResultView: View {
    let record: AnalysisRecord

    var toolActions: [ToolAction] {
        ToolAction.decode(from: record.toolActionsData)
    }

    private var navigationTitle: String {
        // Message channel: extract sender name from inputPreview "[SenderName] ..."
        if record.channelEnum == .message {
            let preview = record.inputPreview
            if preview.hasPrefix("["),
               let closeBracket = preview.firstIndex(of: "]") {
                let name = String(preview[preview.index(after: preview.startIndex)..<closeBracket])
                if !name.isEmpty { return name }
            }
        }

        // Other custom actions: use instruction as title
        if record.actionEnum == .custom,
           let instruction = record.customInstruction, !instruction.isEmpty {
            let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(40)) + (trimmed.count > 40 ? "…" : "")
        }

        return record.actionEnum.displayName
    }
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var followUpText = ""
    @State private var followUps: [(question: String, answer: String)] = []
    @State private var isFollowingUp = false
    @State private var showFullScreenImage = false
    @State private var savedToPhotos = false
    @State private var actionConfirmation: String?
    @State private var showContext = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Compact metadata strip
                    metadataSection

                    // Screenshot shown prominently when present
                    if let imageData = record.imageData,
                       let uiImage = UIImage(data: imageData) {
                        screenshotSection(uiImage)
                    }

                    // Result FIRST — the reason the user tapped
                    MarkdownText(record.result)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Inline tool action pills
                    if !toolActions.isEmpty {
                        actionPills
                    }

                    // Collapsible context (text inputs only — screenshot shown above)
                    if hasTextContext {
                        DisclosureGroup("Input & Context", isExpanded: $showContext) {
                            VStack(alignment: .leading, spacing: 12) {
                                if !record.inputPreview.isEmpty && record.inputPreview != "[Screenshot]" {
                                    inputSection
                                }

                                if let instruction = record.customInstruction, !instruction.isEmpty {
                                    instructionSection(instruction)
                                }
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    // Follow-up conversation history
                    ForEach(Array(followUps.enumerated()), id: \.offset) { _, pair in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: Ai4PoorsDesign.Spacing.xs) {
                                Image(systemName: "person.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                Text(pair.question)
                                    .font(.subheadline.weight(.medium))
                            }
                            Divider()
                            MarkdownText(pair.answer)
                                .textSelection(.enabled)
                        }
                        .padding(Ai4PoorsDesign.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.medium))
                    }


                    // Thinking indicator while follow-up is processing
                    if isFollowingUp {
                        HStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(Ai4PoorsDesign.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.medium))
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                followUpBar
                    .background(.ultraThinMaterial)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task { await OpenRouterService.shared.clearConversation() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            let textToCopy = followUps.last?.answer ?? record.result
                            UIPasteboard.general.string = textToCopy
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(copied ? .green : .blue)
                        }

                        ShareLink(item: followUps.last?.answer ?? record.result)
                    }
                }
            }
        }
    }

    private var hasContextContent: Bool {
        record.imageData != nil
            || (!record.inputPreview.isEmpty && record.inputPreview != "[Screenshot]")
            || (record.customInstruction != nil && !record.customInstruction!.isEmpty)
    }

    private var hasTextContext: Bool {
        (!record.inputPreview.isEmpty && record.inputPreview != "[Screenshot]")
            || (record.customInstruction != nil && !record.customInstruction!.isEmpty)
    }

    // MARK: - Compact Metadata

    private var metadataSection: some View {
        HStack(spacing: 6) {
            Image(systemName: record.channelEnum.iconName)
                .font(.system(size: 14))
                .foregroundStyle(record.channelEnum.color)

            Text("via \(record.channelEnum.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(record.formattedDate)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(AIModel.displayName(for: record.model))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
    }

    // MARK: - Sections

    private func screenshotSection(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Screenshot")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    savedToPhotos = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedToPhotos = false }
                } label: {
                    Label(savedToPhotos ? "Saved" : "Save", systemImage: savedToPhotos ? "checkmark" : "square.and.arrow.down")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Button {
                showFullScreenImage = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.medium)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(Ai4PoorsDesign.Spacing.xs)
                            .background(.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.small))
                            .padding(Ai4PoorsDesign.Spacing.xs)
                    }
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showFullScreenImage) {
                FullScreenImageView(image: image)
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: Ai4PoorsDesign.Spacing.xs) {
            Text("Input")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(record.inputPreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(Ai4PoorsDesign.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [record.channelEnum.color.opacity(0.06), record.channelEnum.color.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.medium))
        }
    }

    private func instructionSection(_ instruction: String) -> some View {
        VStack(alignment: .leading, spacing: Ai4PoorsDesign.Spacing.xs) {
            Text("Instruction")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(instruction)
                .font(.subheadline)
                .italic()
                .padding(Ai4PoorsDesign.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.medium))
        }
    }

    // MARK: - Action Pills (inline)

    private var actionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(toolActions) { action in
                    Button {
                        executeAction(action)
                    } label: {
                        Label(action.label, systemImage: action.systemImage)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func executeAction(_ action: ToolAction) {
        switch action.type {
        case .copy(let text):
            UIPasteboard.general.string = text
            withAnimation {
                actionConfirmation = "Copied to clipboard"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { actionConfirmation = nil }
            }
        case .openURL(let url):
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Sticky Follow-up Bar

    private var followUpBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                TextField(
                    record.imageData != nil ? "Ask about this screenshot..." : "Ask a follow-up...",
                    text: $followUpText
                )
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

                Button {
                    sendFollowUp()
                } label: {
                    if isFollowingUp {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 36, height: 36)
                    }
                }
                .disabled(followUpText.trimmingCharacters(in: .whitespaces).isEmpty || isFollowingUp)
                .accessibilityLabel("Send follow-up")
            }
            .padding(.horizontal)
            .padding(.vertical, Ai4PoorsDesign.Spacing.sm)
        }
    }

    // MARK: - Follow-up

    private func sendFollowUp() {
        guard !followUpText.isEmpty else { return }

        isFollowingUp = true
        let question = followUpText
        followUpText = ""
        let priorResult = record.result

        Task {
            do {
                // Seed conversation history if empty
                await OpenRouterService.shared.seedHistoryIfEmpty(
                    instruction: record.customInstruction ?? "Analyze this content.",
                    result: priorResult
                )

                let result: String
                if let imageData = record.imageData,
                   let image = UIImage(data: imageData) {
                    result = try await OpenRouterService.shared.analyzeImageFollowUp(
                        image: image,
                        question: question
                    )
                } else {
                    // Build context from all follow-ups
                    var context = "The user previously asked about some content and got this result:\n\(priorResult)"
                    for pair in followUps {
                        context += "\n\nUser follow-up: \(pair.question)\nResponse: \(pair.answer)"
                    }
                    context += "\n\nNow they have a follow-up question. Answer it based on the context above."

                    result = try await OpenRouterService.shared.analyzeText(
                        text: question,
                        instruction: context
                    )
                }
                await MainActor.run {
                    followUps.append((question: question, answer: result))
                    isFollowingUp = false
                }
            } catch {
                await MainActor.run {
                    followUps.append((question: question, answer: "Error: \(error.localizedDescription)"))
                    isFollowingUp = false
                }
            }
        }
    }
}

// MARK: - Full Screen Image Viewer

struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var savedToPhotos = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { value in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation { scale = 1.0; lastScale = 1.0; offset = .zero }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1.0 {
                                    offset = value.translation
                                }
                            }
                            .onEnded { _ in
                                if scale <= 1.0 {
                                    withAnimation { offset = .zero }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            if scale > 1.0 {
                                scale = 1.0; lastScale = 1.0; offset = .zero
                            } else {
                                scale = 2.5; lastScale = 2.5
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .background(.black)
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        savedToPhotos = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedToPhotos = false }
                    } label: {
                        Image(systemName: savedToPhotos ? "checkmark.circle.fill" : "square.and.arrow.down")
                            .font(.title3)
                            .foregroundStyle(savedToPhotos ? .green : .white.opacity(0.8))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
