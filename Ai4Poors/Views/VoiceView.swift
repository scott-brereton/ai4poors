// VoiceView.swift
// Ai4Poors - Main voice tab: quick-start recording + recent transcriptions

#if os(iOS)
import SwiftUI

struct VoiceView: View {
    @StateObject private var transcriptionService = TranscriptionService.shared
    @StateObject private var audioService = AudioRecordingService.shared
    @State private var recentRecords: [TranscriptionRecord] = []
    @State private var selectedTranscriptionRecord: TranscriptionRecord?
    @State private var doubleTapMode = AppGroupConstants.voiceDoubleTapMode
    @State private var tripleTapMode = AppGroupConstants.voiceTripleTapMode

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 24) {
                    // Model status
                    modelStatusCard

                    // Quick action buttons
                    quickActions

                    // Back Tap configuration
                    backTapConfig

                    // Recent transcriptions
                    recentTranscriptions

                    Spacer()
                }
                .padding()
                .navigationTitle("Voice")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            TranscriptionHistoryView()
                        } label: {
                            Image(systemName: "clock")
                        }
                    }
                }

                // Recording overlay
                VStack {
                    Spacer()
                    TranscriptionOverlayView(
                        service: transcriptionService,
                        audioService: audioService
                    )
                    .padding(.bottom, 20)
                }
            }
        }
        .task {
            await transcriptionService.loadModelIfNeeded()
            loadRecent()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            checkPendingTranscription()
        }
        .onChange(of: transcriptionService.state) { _, newState in
            // Refresh recent list when a transcription completes
            if case .idle = newState { loadRecent() }
        }
    }

    // MARK: - Model Status

    private var modelStatusCard: some View {
        HStack(spacing: 12) {
            switch transcriptionService.modelState {
            case .notLoaded:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text("Model Not Loaded")
                        .font(.subheadline.weight(.medium))
                    Text("Tap a mode to download and load Whisper")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .downloading(let progress):
                ProgressView(value: progress)
                    .controlSize(.small)
                    .frame(width: 24)
                VStack(alignment: .leading) {
                    Text("Downloading Model...")
                        .font(.subheadline.weight(.medium))
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .loading:
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading) {
                    Text("Loading Model...")
                        .font(.subheadline.weight(.medium))
                    Text("This takes a few seconds the first time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text("Whisper Ready")
                        .font(.subheadline.weight(.medium))
                    Text("On-device | English")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading) {
                    Text("Model Error")
                        .font(.subheadline.weight(.medium))
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(Ai4PoorsDesign.Spacing.md)
        .cortexCard()
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: Ai4PoorsDesign.Spacing.sm) {
            modeCard(
                mode: .plain,
                icon: "waveform",
                title: "Transcribe",
                description: "Speech to text, copied to clipboard. Raw transcription, no cleanup.",
                color: .blue
            )
            modeCard(
                mode: .aiCleanup,
                icon: "wand.and.stars",
                title: "Smart Transcribe",
                description: "AI removes filler words (um, uh), fixes punctuation, and cleans up the text before copying.",
                color: .purple
            )
        }
    }

    private func modeCard(mode: TranscriptionMode, icon: String, title: String, description: String, color: Color) -> some View {
        Button {
            Task {
                await transcriptionService.startTranscription(mode: mode)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "mic.fill")
                    .font(.caption)
                    .foregroundStyle(color.opacity(0.5))
            }
            .padding(Ai4PoorsDesign.Spacing.md)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.medium))
        }
        .disabled(transcriptionService.state != .idle)
    }

    // MARK: - Back Tap Config

    private var backTapConfig: some View {
        VStack(spacing: Ai4PoorsDesign.Spacing.xs) {
            HStack {
                Text("Back Tap")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 0) {
                backTapRow(label: "Double Tap", selection: $doubleTapMode)
                Divider().padding(.leading, 16)
                backTapRow(label: "Triple Tap", selection: $tripleTapMode)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.medium))

            Text("Set Back Tap in Settings > Accessibility > Touch > Back Tap. Create a Shortcut with the matching \"Ai4Poors: Double/Triple Tap Voice\" action.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onChange(of: doubleTapMode) { _, newValue in
            AppGroupConstants.voiceDoubleTapMode = newValue
        }
        .onChange(of: tripleTapMode) { _, newValue in
            AppGroupConstants.voiceTripleTapMode = newValue
        }
    }

    private func backTapRow(label: String, selection: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Picker("", selection: selection) {
                Text("Off").tag("")
                ForEach(TranscriptionMode.allCases, id: \.rawValue) { mode in
                    Label(mode.displayName, systemImage: mode.iconName)
                        .tag(mode.rawValue)
                }
            }
            .tint(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Recent Transcriptions

    private var recentTranscriptions: some View {
        VStack(spacing: Ai4PoorsDesign.Spacing.sm) {
            HStack {
                Text("Recent")
                    .font(.headline)
                Spacer()
                if !recentRecords.isEmpty {
                    NavigationLink("See All") {
                        TranscriptionHistoryView()
                    }
                    .font(.subheadline)
                }
            }

            if recentRecords.isEmpty {
                ContentUnavailableView {
                    Label("No Transcriptions Yet", systemImage: "waveform")
                } description: {
                    Text("All speech is processed on-device using WhisperKit.")
                } actions: {
                    Button {
                        Task { await transcriptionService.startTranscription(mode: .plain) }
                    } label: {
                        Label("Start Recording", systemImage: "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(transcriptionService.state != .idle)
                }
            } else {
                ForEach(recentRecords) { record in
                    Button {
                        selectedTranscriptionRecord = record
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: record.mode.iconName)
                                .font(.caption)
                                .foregroundStyle(record.mode.color)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.displayText)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text("\(record.formattedDuration) - \(record.formattedDate)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                    .padding(.horizontal, Ai4PoorsDesign.Spacing.md)
                    .cortexCard()
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = record.displayText
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            TranscriptionStore.shared.delete(id: record.id)
                            loadRecent()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedTranscriptionRecord) { record in
            TranscriptionDetailView(record: record) {
                loadRecent()
            }
        }
    }

    private func loadRecent() {
        recentRecords = TranscriptionStore.shared.recentTranscriptions(limit: 5)
    }

    // MARK: - Pending Transcription (from App Intent)

    private func checkPendingTranscription() {
        guard let modeStr = AppGroupConstants.sharedDefaults?.string(forKey: "pending_transcription_mode"),
              let mode = TranscriptionMode(rawValue: modeStr) else { return }

        // Clear the pending flag
        AppGroupConstants.sharedDefaults?.removeObject(forKey: "pending_transcription_mode")

        // Start transcription
        Task {
            await transcriptionService.startTranscription(mode: mode)
        }
    }

}
#endif
