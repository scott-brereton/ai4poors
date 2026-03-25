// HistoryView.swift
// Ai4Poors - Analysis history browser with search and filtering

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: Ai4PoorsAppState
    @Query(sort: \AnalysisRecord.timestamp, order: .reverse)
    private var records: [AnalysisRecord]

    @State private var searchText = ""
    @State private var selectedChannel: Ai4PoorsChannel?
    @State private var selectedRecord: AnalysisRecord?
    @State private var recordToDelete: AnalysisRecord?
    @State private var showCopyToast = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedIDs: Set<UUID> = []
    @State private var showClearAllAlert = false
    @State private var showBulkDeleteAlert = false

    var filteredRecords: [AnalysisRecord] {
        records.filter { record in
            let matchesChannel = selectedChannel == nil || record.channelEnum == selectedChannel
            let matchesSearch = searchText.isEmpty
                || record.result.localizedCaseInsensitiveContains(searchText)
                || record.inputPreview.localizedCaseInsensitiveContains(searchText)
                || (record.customInstruction?.localizedCaseInsensitiveContains(searchText) ?? false)
            return matchesChannel && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    emptyState
                } else if filteredRecords.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if filteredRecords.isEmpty, let channel = selectedChannel {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: channel.iconName,
                        description: Text("No analyses found for \(channel.displayName).")
                    )
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search history...")
            .environment(\.editMode, $editMode)
            .toolbar {
                if !records.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(editMode == .active ? "Done" : "Edit") {
                            withAnimation {
                                if editMode == .active {
                                    editMode = .inactive
                                    selectedIDs.removeAll()
                                } else {
                                    editMode = .active
                                }
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("All Channels") { selectedChannel = nil }
                            Divider()
                            ForEach(Ai4PoorsChannel.allCases, id: \.self) { channel in
                                Button {
                                    selectedChannel = channel
                                } label: {
                                    Label(channel.displayName, systemImage: channel.iconName)
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                showClearAllAlert = true
                            } label: {
                                Label("Clear All History", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: selectedChannel != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                    }
                }
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
            .toast(isShowing: $showCopyToast, message: "Copied to clipboard")
        }
        .onReceive(NotificationCenter.default.publisher(for: .cortexSaveRecord)) { notification in
            if let record = notification.object as? AnalysisRecord {
                modelContext.insert(record)
                try? modelContext.save()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh to pick up records saved by extensions in other processes
            try? modelContext.save()
        }
        .onChange(of: appState.selectedResultID) { _, newID in
            if let id = newID,
               let record = records.first(where: { $0.id.uuidString == id }) {
                selectedRecord = record
                appState.selectedResultID = nil
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No History", systemImage: "clock")
        } description: {
            Text("Your AI analysis results will appear here.")
        } actions: {
            Button {
                appState.selectedTab = .home
            } label: {
                Label("Analyze Something", systemImage: "sparkle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - History List

    private var historyList: some View {
        VStack(spacing: 0) {
            // Bulk delete bar when in edit mode with selections
            if editMode == .active && !selectedIDs.isEmpty {
                HStack {
                    Text("\(selectedIDs.count) selected")
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    Button("Select All") {
                        selectedIDs = Set(filteredRecords.map(\.id))
                    }
                    .font(.subheadline)

                    Button(role: .destructive) {
                        showBulkDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, Ai4PoorsDesign.Spacing.sm)
                .background(.ultraThinMaterial)
            }

            List(selection: $selectedIDs) {
                if let channel = selectedChannel {
                    Section {
                        HStack {
                            Image(systemName: channel.iconName)
                            Text("Showing: \(channel.displayName)")
                            Spacer()
                            Button("Clear Filter") { selectedChannel = nil }
                                .font(.caption)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                ForEach(filteredRecords) { record in
                    Button {
                        if editMode == .active {
                            toggleSelection(record.id)
                        } else {
                            selectedRecord = record
                        }
                    } label: {
                        HistoryRow(record: record)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            recordToDelete = record
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            UIPasteboard.general.string = record.result
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            showCopyToast = true
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .tint(.blue)
                    }
                }
            }
            .listStyle(.insetGrouped)
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
        .alert("Delete \(selectedIDs.count) Items?", isPresented: $showBulkDeleteAlert) {
            Button("Delete \(selectedIDs.count)", role: .destructive) {
                deleteSelectedRecords()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the selected analyses.")
        }
        .alert("Clear All History?", isPresented: $showClearAllAlert) {
            Button("Delete All", role: .destructive) {
                deleteAllRecords()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(records.count) analysis results.")
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func deleteSelectedRecords() {
        for record in records where selectedIDs.contains(record.id) {
            modelContext.delete(record)
        }
        try? modelContext.save()
        selectedIDs.removeAll()
        editMode = .inactive
    }

    private func deleteAllRecords() {
        for record in records {
            modelContext.delete(record)
        }
        try? modelContext.save()
        selectedIDs.removeAll()
        editMode = .inactive
    }

}

// MARK: - History Row

struct HistoryRow: View {
    let record: AnalysisRecord
    @State private var copied = false

    private var rowTitle: String {
        if record.actionEnum == .custom {
            return record.customInstruction.flatMap { String($0.prefix(40)) } ?? "\(record.channelEnum.displayName) Analysis"
        }
        return record.actionEnum.displayName
    }

    var body: some View {
        HStack(alignment: .top, spacing: Ai4PoorsDesign.Spacing.md) {
            // Screenshot thumbnail
            if let imageData = record.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.small))
                    .overlay(
                        RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.small)
                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                    Image(systemName: record.channelEnum.iconName)
                        .font(.system(size: Ai4PoorsDesign.IconSize.tiny))
                        .foregroundStyle(record.channelEnum.color)

                    Text(rowTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    Text(record.formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                MarkdownText(record.result, font: .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                    Text(AIModel.displayName(for: record.model))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Ai4PoorsDesign.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())

                    if record.imageData != nil {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

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
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copied ? "Copied" : "Copy result")
                }
            }
        }
        .padding(.vertical, Ai4PoorsDesign.Spacing.xs)
        .contentShape(Rectangle())
    }

}

// AnalysisRecord gets Identifiable via @Model (PersistentModel)
