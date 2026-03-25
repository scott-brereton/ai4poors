// TranscriptionHistoryView.swift
// Ai4Poors - Searchable voice transcription history with FTS5

#if os(iOS)
import SwiftUI
import AVFoundation

struct TranscriptionHistoryView: View {
    @State private var searchText = ""
    @State private var transcriptions: [TranscriptionRecord] = []
    @State private var selectedTranscription: TranscriptionRecord?
    @State private var filterMode: TranscriptionMode?

    private let store = TranscriptionStore.shared

    var body: some View {
        Group {
            if transcriptions.isEmpty && searchText.isEmpty {
                emptyState
            } else {
                transcriptionList
            }
        }
        .navigationTitle("Voice History")
        .searchable(text: $searchText, prompt: "Search transcriptions")
        .onChange(of: searchText) { _, _ in loadTranscriptions() }
        .onAppear { loadTranscriptions() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        filterMode = nil
                        loadTranscriptions()
                    } label: {
                        Label("All", systemImage: filterMode == nil ? "checkmark" : "")
                    }
                    ForEach(TranscriptionMode.allCases, id: \.rawValue) { mode in
                        Button {
                            filterMode = mode
                            loadTranscriptions()
                        } label: {
                            Label(mode.displayName, systemImage: filterMode == mode ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: filterMode != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(item: $selectedTranscription) { record in
            TranscriptionDetailView(record: record) {
                loadTranscriptions()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Transcriptions", systemImage: "waveform")
        } description: {
            Text("Voice transcriptions will appear here. Use Back Tap or Control Center to start recording.")
        }
    }

    // MARK: - Transcription List

    private var transcriptionList: some View {
        List {
            // Stats header
            if searchText.isEmpty {
                statsSection
            }

            // Transcription rows
            ForEach(transcriptions) { record in
                TranscriptionRowView(record: record)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTranscription = record
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(id: record.id)
                            loadTranscriptions()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            UIPasteboard.general.string = record.displayText
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .tint(.blue)
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section {
            HStack {
                Label("\(store.transcriptionCount()) transcriptions", systemImage: "waveform")
                    .font(.subheadline)
                Spacer()
                Text(formatTotalDuration(store.totalDuration()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data Loading

    private func loadTranscriptions() {
        if searchText.isEmpty {
            transcriptions = store.recentTranscriptions(limit: 100, mode: filterMode)
        } else {
            transcriptions = store.search(query: searchText)
        }
    }

    private func formatTotalDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m recorded"
        }
        return "\(minutes)m recorded"
    }
}

// MARK: - Row View

struct TranscriptionRowView: View {
    let record: TranscriptionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: record.mode.iconName)
                    .font(.caption)
                    .foregroundStyle(record.mode.color)

                Text(record.mode.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(record.mode.color)

                Spacer()

                Text(record.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(record.displayText)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Label(record.formattedDuration, systemImage: "clock")
                Label("\(record.wordCount) words", systemImage: "text.word.spacing")

                if record.audioFilePath != nil {
                    Image(systemName: "waveform.circle")
                        .foregroundStyle(.blue)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail View

struct TranscriptionDetailView: View {
    let record: TranscriptionRecord
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isPlayingAudio = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Image(systemName: record.mode.iconName)
                            .foregroundStyle(record.mode.color)
                        Text(record.mode.displayName)
                            .font(.headline)
                        Spacer()
                        Text(record.timestamp.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Duration & word count
                    HStack(spacing: 16) {
                        Label(record.formattedDuration, systemImage: "clock")
                        Label("\(record.wordCount) words", systemImage: "text.word.spacing")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Divider()

                    // Transcription text
                    if let cleaned = record.cleanedText {
                        HStack(spacing: Ai4PoorsDesign.Spacing.xs) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.purple)
                                .font(.caption)
                            Text("AI Cleaned")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.purple)
                        }
                        Text(cleaned)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(Ai4PoorsDesign.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.purple.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.medium))

                        DisclosureGroup {
                            Text(record.text)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } label: {
                            Text("Show Original")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(record.text)
                            .font(.body)
                            .textSelection(.enabled)
                    }

                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = record.displayText
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if record.audioFilePath != nil {
                            Button {
                                toggleAudioPlayback()
                            } label: {
                                Label(
                                    isPlayingAudio ? "Stop" : "Play",
                                    systemImage: isPlayingAudio ? "stop.fill" : "play.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 8)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Transcription", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete Transcription?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    TranscriptionStore.shared.delete(id: record.id)
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete this transcription and cannot be undone.")
            }
        }
    }

    private func toggleAudioPlayback() {
        // Audio playback placeholder — implemented when audio file management is finalized
        isPlayingAudio.toggle()
    }
}
#endif
