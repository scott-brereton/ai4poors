// TranscriptionOverlayView.swift
// Ai4Poors - Floating overlay for voice recording and transcription status

#if os(iOS)
import SwiftUI

struct TranscriptionOverlayView: View {
    @ObservedObject var service: TranscriptionService
    @ObservedObject var audioService: AudioRecordingService

    var body: some View {
        Group {
            switch service.state {
            case .idle:
                EmptyView()
            case .recording:
                recordingOverlay
            case .processing:
                processingOverlay
            case .result(let text):
                resultOverlay(text: text)
            case .error(let message):
                errorOverlay(message: message)
            }
        }
        .animation(.spring(duration: 0.3), value: service.state)
    }

    // MARK: - Recording Overlay

    private var recordingOverlay: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                // Pulsing red dot
                Circle()
                    .fill(service.currentMode.color)
                    .frame(width: 12, height: 12)
                    .modifier(PulseModifier())

                Text(service.currentMode.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(formatDuration(audioService.recordingDuration))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Audio level meter
            AudioLevelView(level: audioService.audioLevel)
                .frame(height: 32)

            // Stop button
            Button {
                Task {
                    await service.stopAndTranscribe()
                }
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Ai4PoorsDesign.Spacing.sm)
                .background(service.currentMode.color)
                .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.medium))
            }
        }
        .padding(Ai4PoorsDesign.Spacing.lg)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.overlay))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        .padding(.horizontal, Ai4PoorsDesign.Spacing.xl)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        HStack(spacing: Ai4PoorsDesign.Spacing.md) {
            ProgressView()
                .controlSize(.small)
            Text("Transcribing...")
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(Ai4PoorsDesign.Spacing.lg)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.overlay))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        .padding(.horizontal, Ai4PoorsDesign.Spacing.xl)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Result Overlay

    private func resultOverlay(text: String) -> some View {
        VStack(alignment: .leading, spacing: Ai4PoorsDesign.Spacing.sm) {
            HStack(spacing: Ai4PoorsDesign.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Copied to Clipboard")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    service.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss")
            }

            Text(String(text.prefix(100)) + (text.count > 100 ? "..." : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(Ai4PoorsDesign.Spacing.lg)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.overlay))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        .padding(.horizontal, Ai4PoorsDesign.Spacing.xl)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
            // Auto-dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                service.cancel()
            }
        }
    }

    // MARK: - Error Overlay

    private func errorOverlay(message: String) -> some View {
        HStack(spacing: Ai4PoorsDesign.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer()
            Button {
                service.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss error")
        }
        .padding(Ai4PoorsDesign.Spacing.lg)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.overlay))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        .padding(.horizontal, Ai4PoorsDesign.Spacing.xl)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Audio Level Visualizer

struct AudioLevelView: View {
    let level: Float
    private let barCount = 20

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let normalizedLevel = normalizeLevel(level)
                    let barThreshold = Float(index) / Float(barCount)
                    let isActive = normalizedLevel > barThreshold

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(for: index, active: isActive))
                        .frame(width: (geometry.size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount))
                        .scaleEffect(y: isActive ? 1.0 : 0.3, anchor: .bottom)
                        .animation(.easeOut(duration: 0.08), value: isActive)
                }
            }
        }
    }

    private func normalizeLevel(_ db: Float) -> Float {
        // Map -60dB..0dB to 0..1
        let clamped = max(-60, min(0, db))
        return (clamped + 60) / 60
    }

    private func barColor(for index: Int, active: Bool) -> Color {
        guard active else { return Color.gray.opacity(0.2) }
        let ratio = Float(index) / Float(barCount)
        if ratio < 0.6 { return .green }
        if ratio < 0.8 { return .yellow }
        return .red
    }
}

// MARK: - Pulse Animation Modifier

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
#endif
