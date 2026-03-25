// HomeView.swift
// Ai4Poors - Control Centre: activity feed with service status

import SwiftUI
import SwiftData

// MARK: - Sort Options

enum ActivitySortOrder: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case channel = "By Channel"
}

struct HomeView: View {
    @EnvironmentObject var appState: Ai4PoorsAppState
    @Environment(\.modelContext) private var modelContext
    @StateObject private var clipboardMonitor = ClipboardMonitor.shared
    @Query(sort: \AnalysisRecord.timestamp, order: .reverse)
    private var allRecords: [AnalysisRecord]
    @Query(filter: #Predicate<AnalysisRecord> { !$0.isViewed },
           sort: \AnalysisRecord.timestamp, order: .reverse)
    private var unviewedRecords: [AnalysisRecord]
    @State private var showActionPicker = false
    @State private var showAPIKeyAlert = false
    @State private var preselectedAction: Ai4PoorsAction = .summarize
    @State private var preselectedInputMode: ActionPickerView.InputMode = .text
    @State private var showCopied = false
    @State private var selectedRecord: AnalysisRecord?
    @State private var showReaderSheet = false
    @State private var showDirectReader = false
    @State private var readerURL: String = ""
    @State private var readerPrefetchedMarkdown: String?
    @State private var readerPrefetchedTitle: String?
    @State private var sortOrder: ActivitySortOrder = .newest
    @State private var recordToDelete: AnalysisRecord?
    @State private var showCopyToast = false

    private let feedLimit = 15

    private var feedRecords: [AnalysisRecord] {
        let sorted: [AnalysisRecord]
        switch sortOrder {
        case .newest:
            sorted = allRecords
        case .oldest:
            sorted = allRecords.reversed()
        case .channel:
            sorted = allRecords.sorted { a, b in
                if a.channel == b.channel {
                    return a.timestamp > b.timestamp
                }
                return a.channel < b.channel
            }
        }
        return Array(sorted.prefix(feedLimit))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Unread circles row
                    if !unviewedRecords.isEmpty {
                        UnreadCirclesRow(
                            records: unviewedRecords,
                            onTap: { records in
                                withAnimation(.easeOut(duration: 0.25)) {
                                    for record in records {
                                        record.isViewed = true
                                    }
                                    try? modelContext.save()
                                }
                                selectedRecord = records.first
                            },
                            onMarkAllRead: {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    for record in unviewedRecords {
                                        record.isViewed = true
                                    }
                                    try? modelContext.save()
                                }
                            }
                        )
                        .padding(.top, Ai4PoorsDesign.Spacing.sm)
                        .padding(.bottom, Ai4PoorsDesign.Spacing.md)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    // Active analysis card — only when there's something to show
                    if appState.isAnalyzing || appState.currentResult != nil || appState.currentError != nil {
                        activeAnalysisCard
                            .padding(.horizontal)
                            .padding(.top, Ai4PoorsDesign.Spacing.sm)
                            .padding(.bottom, Ai4PoorsDesign.Spacing.md)
                    }

                    // Service status strip
                    serviceStatusStrip
                        .padding(.horizontal)
                        .padding(.top, appState.isAnalyzing || appState.currentResult != nil || appState.currentError != nil ? 0 : Ai4PoorsDesign.Spacing.sm)

                    // Activity feed
                    activityFeedSection
                        .padding(.top, Ai4PoorsDesign.Spacing.md)

                    // Compact quick actions
                    quickActionsRow
                        .padding(.horizontal)
                        .padding(.top, Ai4PoorsDesign.Spacing.lg)
                        .padding(.bottom, Ai4PoorsDesign.Spacing.xl)
                }
            }
            .navigationTitle("Ai4Poors")
            .sheet(isPresented: $showActionPicker) {
                preselectedInputMode = .text
            } content: {
                ActionPickerView(initialAction: preselectedAction, initialInputMode: preselectedInputMode)
            }
            .sheet(item: $selectedRecord) { record in
                if record.channelEnum == .reader || record.actionEnum == .read {
                    ArticleReaderView(
                        url: record.customInstruction ?? "",
                        prefetchedMarkdown: record.result,
                        prefetchedTitle: record.inputPreview
                    )
                } else {
                    ResultView(record: record)
                }
            }
            .sheet(isPresented: $showReaderSheet) {
                ReadURLSheet(initialURL: readerURL)
            }
            .sheet(isPresented: $showDirectReader) {
                ArticleReaderView(
                    url: readerURL,
                    prefetchedMarkdown: readerPrefetchedMarkdown,
                    prefetchedTitle: readerPrefetchedTitle
                )
            }
            .alert("API Key Required", isPresented: $showAPIKeyAlert) {
                Button("Open Settings") {
                    appState.selectedTab = .settings
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Configure your OpenRouter API key in Settings to start using Ai4Poors.")
            }
            .alert("Delete Analysis?", isPresented: Binding(
                get: { recordToDelete != nil },
                set: { if !$0 { recordToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let record = recordToDelete {
                        modelContext.delete(record)
                        try? modelContext.save()
                    }
                    recordToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    recordToDelete = nil
                }
            } message: {
                Text("This will permanently delete this analysis result.")
            }
            .toast(isShowing: $showCopyToast, message: "Copied to clipboard")
            .onChange(of: appState.pendingAnalysis?.text) { _, newValue in
                if let pending = appState.pendingAnalysis {
                    let action = Ai4PoorsAction(rawValue: pending.action) ?? .summarize
                    appState.analyzeText(pending.text, action: action, channel: .share)
                    appState.pendingAnalysis = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ai4poorsShowResult)) { notification in
                if let result = notification.object as? String {
                    appState.currentResult = result
                    appState.selectedTab = .home
                }
            }
            .onChange(of: appState.pendingReaderURL) { _, newURL in
                if let url = newURL, !url.isEmpty {
                    readerURL = url
                    if let cached = AppGroupConstants.cachedReaderResult(for: url) {
                        readerPrefetchedMarkdown = cached.markdown
                        readerPrefetchedTitle = cached.title
                    } else {
                        readerPrefetchedMarkdown = nil
                        readerPrefetchedTitle = nil
                    }
                    showDirectReader = true
                    appState.pendingReaderURL = nil
                }
            }
        }
    }

    // MARK: - Service Status Strip

    private var serviceStatusStrip: some View {
        HStack(spacing: Ai4PoorsDesign.Spacing.md) {
            // Clipboard monitor status
            Button {
                appState.selectedTab = .settings
            } label: {
                HStack(spacing: Ai4PoorsDesign.Spacing.xs) {
                    Circle()
                        .fill(clipboardMonitor.isMonitoring ? .green : Color(.systemGray4))
                        .frame(width: 7, height: 7)
                    Text(clipboardMonitor.isMonitoring ? "Monitor Active" : "Monitor Off")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Ai4PoorsDesign.Spacing.sm)
                .padding(.vertical, Ai4PoorsDesign.Spacing.xs + 1)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // API status
            HStack(spacing: Ai4PoorsDesign.Spacing.xs) {
                Circle()
                    .fill(AppGroupConstants.isAPIKeyConfigured ? .green : .orange)
                    .frame(width: 7, height: 7)
                Text(AppGroupConstants.isAPIKeyConfigured ? AIModel.displayName(for: AppGroupConstants.preferredModel) : "No API Key")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Ai4PoorsDesign.Spacing.sm)
            .padding(.vertical, Ai4PoorsDesign.Spacing.xs + 1)
            .background(Color(.systemGray6))
            .clipShape(Capsule())

            Spacer()

            // Last activity
            if let latest = allRecords.first {
                Text(latest.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Active Analysis Card (conditional)

    private var statusCardPhase: String {
        if appState.isAnalyzing { return "analyzing" }
        if appState.currentResult != nil { return "result" }
        if appState.currentError != nil { return "error" }
        return "ready"
    }

    private var activeAnalysisCard: some View {
        VStack(spacing: Ai4PoorsDesign.Spacing.md) {
            if appState.isAnalyzing {
                analyzingCard
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    ))
            } else if let result = appState.currentResult {
                resultCard(result)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    ))
            } else if let error = appState.currentError {
                errorCard(error)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: statusCardPhase)
    }

    private var analyzingCard: some View {
        VStack(spacing: Ai4PoorsDesign.Spacing.sm) {
            HStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Analyzing...")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }

            if !appState.streamingText.isEmpty {
                Text(appState.streamingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Ai4PoorsDesign.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.large)
                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
        )
        .accessibilityLabel("Analyzing your content")
    }

    private func resultCard(_ result: String) -> some View {
        VStack(spacing: Ai4PoorsDesign.Spacing.sm) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
                Text("Result")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    appState.clearResult()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            MarkdownText(result, font: .subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            HStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                Button {
                    UIPasteboard.general.string = result
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCopied = false
                        }
                    }
                } label: {
                    Label(
                        showCopied ? "Copied!" : "Copy",
                        systemImage: showCopied ? "checkmark" : "doc.on.doc"
                    )
                    .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.bordered)
                .tint(showCopied ? .green : nil)
                .controlSize(.small)

                Button {
                    shareResult(result)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(Ai4PoorsDesign.Spacing.md)
        .frame(maxWidth: .infinity)
        .cortexCard(elevated: true)
    }

    private func errorCard(_ error: String) -> some View {
        VStack(spacing: Ai4PoorsDesign.Spacing.sm) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 14))
                Text("Error")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    appState.clearResult()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                Button("Dismiss") {
                    appState.clearResult()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    appState.clearResult()
                    showActionPicker = true
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(Ai4PoorsDesign.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.large)
                .stroke(Color.red.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Activity Feed

    private var activityFeedSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity")
                    .font(.headline)

                if !allRecords.isEmpty {
                    Text("\(allRecords.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                Spacer()

                if !allRecords.isEmpty {
                    Menu {
                        ForEach(ActivitySortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                if sortOrder == order {
                                    Label(order.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(order.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 11))
                            Text(sortOrder.rawValue)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                    }

                    Button {
                        appState.selectedTab = .history
                    } label: {
                        Text("See All")
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, Ai4PoorsDesign.Spacing.sm)

            // Feed
            if allRecords.isEmpty {
                emptyFeedView
                    .padding(.horizontal)
            } else {
                LazyVStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                    ForEach(feedRecords) { record in
                        ActivityCard(
                            record: record,
                            onTap: {
                                if !record.isViewed {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        record.isViewed = true
                                        try? modelContext.save()
                                    }
                                }
                                selectedRecord = record
                            },
                            onDelete: { recordToDelete = record },
                            onCopy: {
                                UIPasteboard.general.string = record.result
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                                showCopyToast = true
                            }
                        )
                        .padding(.horizontal)
                    }
                }
            }
        }
    }

    private var emptyFeedView: some View {
        VStack(spacing: Ai4PoorsDesign.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No activity yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Results from Safari, clipboard, keyboard, and other channels will appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button {
                checkAPIKeyAndAct {
                    preselectedAction = .summarize
                    showActionPicker = true
                }
            } label: {
                Label("Start an Analysis", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(Ai4PoorsDesign.Spacing.xl)
        .frame(maxWidth: .infinity)
        .cortexCard()
    }

    // MARK: - Compact Quick Actions Row

    private var quickActionsRow: some View {
        VStack(alignment: .leading, spacing: Ai4PoorsDesign.Spacing.sm) {
            Text("New Analysis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                    CompactActionPill(icon: "doc.text.magnifyingglass", label: "Summarize") {
                        checkAPIKeyAndAct {
                            preselectedAction = .summarize
                            showActionPicker = true
                        }
                    }
                    CompactActionPill(icon: "globe", label: "Translate") {
                        checkAPIKeyAndAct {
                            preselectedAction = .translate
                            showActionPicker = true
                        }
                    }
                    CompactActionPill(icon: "lightbulb", label: "Explain") {
                        checkAPIKeyAndAct {
                            preselectedAction = .explain
                            showActionPicker = true
                        }
                    }
                    CompactActionPill(icon: "list.bullet", label: "Key Points") {
                        checkAPIKeyAndAct {
                            preselectedAction = .extract
                            showActionPicker = true
                        }
                    }
                    CompactActionPill(icon: "wand.and.stars", label: "Improve") {
                        checkAPIKeyAndAct {
                            preselectedAction = .improve
                            showActionPicker = true
                        }
                    }
                    CompactActionPill(icon: "camera.viewfinder", label: "Screenshot") {
                        checkAPIKeyAndAct {
                            preselectedAction = .summarize
                            preselectedInputMode = .image
                            showActionPicker = true
                        }
                    }
                    CompactActionPill(icon: "arrowshape.turn.up.left", label: "Reply") {
                        checkAPIKeyAndAct {
                            preselectedAction = .reply
                            showActionPicker = true
                        }
                    }
                    CompactActionPill(icon: "text.cursor", label: "Custom") {
                        checkAPIKeyAndAct {
                            preselectedAction = .custom
                            showActionPicker = true
                        }
                    }
                    if AppGroupConstants.isCrawl4AIConfigured {
                        CompactActionPill(icon: "book.pages", label: "Read URL") {
                            if let clip = UIPasteboard.general.string,
                               let url = URL(string: clip.trimmingCharacters(in: .whitespacesAndNewlines)),
                               let scheme = url.scheme, ["http", "https"].contains(scheme) {
                                readerURL = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            } else {
                                readerURL = ""
                            }
                            showReaderSheet = true
                        }
                    }
                }
            }
            .opacity(appState.isAnalyzing ? 0.5 : 1.0)
            .allowsHitTesting(!appState.isAnalyzing)
        }
    }

    // MARK: - Helpers

    private func checkAPIKeyAndAct(_ action: @escaping () -> Void) {
        if AppGroupConstants.isAPIKeyConfigured {
            action()
        } else {
            showAPIKeyAlert = true
        }
    }

    private func shareResult(_ text: String) {
        let ac = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            root.present(ac, animated: true)
        }
    }
}

// MARK: - Activity Card

struct ActivityCard: View {
    let record: AnalysisRecord
    let onTap: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void

    @State private var copied = false

    private var cardTitle: String {
        if record.actionEnum == .read || record.channelEnum == .reader {
            if let urlStr = record.customInstruction,
               let url = URL(string: urlStr),
               let host = url.host {
                return host.replacingOccurrences(of: "www.", with: "")
            }
            return "Article"
        }

        // Message channel: extract sender name from "[SenderName] ..."
        if record.channelEnum == .message {
            let preview = record.inputPreview
            if preview.hasPrefix("["),
               let closeBracket = preview.firstIndex(of: "]") {
                let name = String(preview[preview.index(after: preview.startIndex)..<closeBracket])
                if !name.isEmpty { return name }
            }
        }

        // Use inputPreview as the title when it's meaningful content
        let preview = record.inputPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty && preview != "[Screenshot]" {
            return String(preview.prefix(60))
        }
        // Fall back to custom instruction if available
        if record.actionEnum == .custom,
           let instruction = record.customInstruction,
           !instruction.isEmpty {
            return String(instruction.prefix(40))
        }
        return record.actionEnum.displayName
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Ai4PoorsDesign.Spacing.md) {
                // Screenshot thumbnail
                if let imageData = record.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.small))
                        .overlay(
                            RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.small)
                                .stroke(Color(.systemGray4), lineWidth: 0.5)
                        )
                }

                VStack(alignment: .leading, spacing: Ai4PoorsDesign.Spacing.xs) {
                    // Top line: channel + action + timestamp
                    HStack(spacing: Ai4PoorsDesign.Spacing.xs) {
                        Image(systemName: record.channelEnum.iconName)
                            .font(.system(size: 11))
                            .foregroundStyle(record.channelEnum.color)

                        Text("\(record.channelEnum.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)

                        Text(record.actionEnum.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(record.formattedDate)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // Title
                    Text(cardTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // Result preview
                    MarkdownText(record.result, font: .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    // Bottom: model badge + copy
                    HStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                        Text(AIModel.displayName(for: record.model))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Ai4PoorsDesign.Spacing.xs + 2)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())

                        Spacer()

                        Button {
                            UIPasteboard.general.string = record.result
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                                .font(.system(size: Ai4PoorsDesign.IconSize.tiny))
                                .foregroundStyle(copied ? .green : .blue)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Ai4PoorsDesign.Spacing.md)
            .cortexCard()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onCopy()
            } label: {
                Label("Copy Result", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Unread Circles Row

/// Groups unread records for display: message-channel records are merged
/// by sender (1:1) or group name, non-message records stay individual.
struct UnreadGroup: Identifiable {
    let id: String           // grouping key
    let label: String        // display name
    let records: [AnalysisRecord]

    var latestRecord: AnalysisRecord { records.first! }
    var count: Int { records.count }
    var channel: Ai4PoorsChannel { latestRecord.channelEnum }
}

struct UnreadCirclesRow: View {
    let records: [AnalysisRecord]
    let onTap: ([AnalysisRecord]) -> Void
    let onMarkAllRead: () -> Void

    /// Extracts the `[Name]` prefix from a message-channel inputPreview.
    private static func messageSenderName(from record: AnalysisRecord) -> String? {
        guard record.channelEnum == .message else { return nil }
        let preview = record.inputPreview
        guard preview.hasPrefix("["),
              let closeBracket = preview.firstIndex(of: "]") else { return nil }
        let name = String(preview[preview.index(after: preview.startIndex)..<closeBracket])
        return name.isEmpty ? nil : name
    }

    /// Groups message records by sender/group name, keeps others individual.
    /// Input records are newest-first from @Query, so records[0] within each
    /// group is always the most recent.
    static func buildGroups(from records: [AnalysisRecord]) -> [UnreadGroup] {
        var nonMessageGroups: [UnreadGroup] = []
        var messageGroups: [String: [AnalysisRecord]] = [:]
        var messageGroupOrder: [String] = []

        for record in records {
            if let senderName = messageSenderName(from: record) {
                if messageGroups[senderName] == nil {
                    messageGroupOrder.append(senderName)
                }
                messageGroups[senderName, default: []].append(record)
            } else {
                nonMessageGroups.append(UnreadGroup(
                    id: record.id.uuidString,
                    label: record.channelEnum.displayName,
                    records: [record]
                ))
            }
        }

        var result = nonMessageGroups
        for name in messageGroupOrder {
            if let grouped = messageGroups[name] {
                result.append(UnreadGroup(
                    id: "msg:\(name)",
                    label: name,
                    records: grouped
                ))
            }
        }

        result.sort { $0.latestRecord.timestamp > $1.latestRecord.timestamp }
        return result
    }

    var body: some View {
        let groups = Self.buildGroups(from: records)

        VStack(alignment: .leading, spacing: Ai4PoorsDesign.Spacing.sm) {
            HStack {
                Text("New")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(records.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .clipShape(Capsule())

                Spacer()

                Button("Mark All Read") {
                    onMarkAllRead()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Ai4PoorsDesign.Spacing.lg) {
                    ForEach(groups) { group in
                        UnreadCircle(group: group) {
                            onTap(group.records)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, Ai4PoorsDesign.Spacing.xs)
            }
        }
    }
}

struct UnreadCircle: View {
    let group: UnreadGroup
    let onTap: () -> Void

    private var circleInitial: String {
        String(group.label.prefix(1)).uppercased()
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Ai4PoorsDesign.Spacing.xs) {
                ZStack {
                    Circle()
                        .fill(group.channel.color.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Circle()
                        .stroke(group.channel.color.opacity(0.3), lineWidth: 2)
                        .frame(width: 56, height: 56)

                    if group.channel == .message {
                        Text(circleInitial)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(group.channel.color)
                    } else {
                        Image(systemName: group.channel.iconName)
                            .font(.system(size: 22))
                            .foregroundStyle(group.channel.color)
                    }

                    // Count badge (replaces dot when > 1)
                    if group.count > 1 {
                        Text("\(group.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.blue)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color(UIColor.systemBackground), lineWidth: 2)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(0)
                    } else {
                        // Single unread dot
                        Circle()
                            .fill(.blue)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color(UIColor.systemBackground), lineWidth: 2)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(2)
                    }
                }
                .frame(width: 56, height: 56)

                Text(group.label)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(QuickActionButtonStyle())
    }
}

// MARK: - Compact Action Pill

struct CompactActionPill: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Ai4PoorsDesign.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, Ai4PoorsDesign.Spacing.md)
            .padding(.vertical, Ai4PoorsDesign.Spacing.sm)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
        }
        .buttonStyle(QuickActionButtonStyle())
        .accessibilityLabel(label)
    }
}

struct QuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Read URL Sheet

struct ReadURLSheet: View {
    let initialURL: String
    @Environment(\.dismiss) private var dismiss
    @State private var urlText: String = ""
    @State private var showReader = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "book.pages")
                    .font(.largeTitle)
                    .foregroundStyle(.brown)

                Text("Read Article")
                    .font(.title2.weight(.semibold))

                Text("Enter a URL to extract and read the article content.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("https://example.com/article", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .padding(.horizontal)

                Button {
                    showReader = true
                } label: {
                    Label("Read", systemImage: "book.pages")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brown)
                .controlSize(.large)
                .padding(.horizontal)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding(.top, 40)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                urlText = initialURL
            }
            .sheet(isPresented: $showReader) {
                dismiss()
            } content: {
                ArticleReaderView(url: urlText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}
