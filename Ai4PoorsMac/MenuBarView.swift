// MenuBarView.swift
// Ai4PoorsMac - Menu bar popover UI
//
// Shows recent analyzed messages, status, and controls.

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var watcher: MessageWatcher
    @EnvironmentObject var macState: MacAppState
    @Environment(\.openSettings) private var openSettings

    private func showSettings() {
        // LSUIElement apps must activate before presenting windows
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain")
                    .font(.title2)
                Text("Ai4Poors")
                    .font(.headline)
                Spacer()
                statusBadge
            }
            .padding(.bottom, 4)

            Divider()

            // Status / Onboarding prompts
            if macState.status == .noAPIKey {
                warningRow(
                    icon: "key.fill",
                    message: "No API key configured",
                    action: "Open Settings"
                ) {
                    showSettings()
                }
            } else if macState.status == .noFullDiskAccess {
                warningRow(
                    icon: "lock.shield",
                    message: "Full Disk Access required",
                    action: "Open Settings"
                ) {
                    showSettings()
                }
            }

            // Controls
            HStack {
                Button(action: {
                    if watcher.isMonitoring {
                        watcher.togglePause()
                    } else {
                        watcher.startMonitoring()
                    }
                }) {
                    Label(
                        watcher.isPaused ? "Resume" : (watcher.isMonitoring ? "Pause" : "Start"),
                        systemImage: watcher.isPaused ? "play.fill" : (watcher.isMonitoring ? "pause.fill" : "play.fill")
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(watcher.isPaused ? .orange : .blue)

                if watcher.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
            }

            Divider()

            // Recent results
            if watcher.recentResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "message")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No messages analyzed yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if watcher.isMonitoring && !watcher.isPaused {
                        Text("Monitoring for new messages...")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(watcher.recentResults) { msg in
                            MessageResultRow(message: msg)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Footer
            Button("Quit Ai4Poors Mac") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .padding()
        .frame(width: 360)
        .onAppear {
            macState.refreshStatus()
        }
    }

    // MARK: - Components

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch macState.status {
        case .monitoring:
            return watcher.isPaused ? .orange : .green
        case .noFullDiskAccess: return .orange
        case .noAPIKey: return .red
        case .paused: return .orange
        }
    }

    private var statusText: String {
        if watcher.isPaused { return "Paused" }
        switch macState.status {
        case .monitoring: return watcher.isMonitoring ? "Monitoring" : "Idle"
        case .noFullDiskAccess: return "No Access"
        case .noAPIKey: return "No API Key"
        case .paused: return "Paused"
        }
    }

    private func warningRow(icon: String, message: String, action: String, onTap: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
            Spacer()
            Button(action, action: onTap)
                .font(.caption)
                .buttonStyle(.borderless)
        }
        .padding(8)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Message Result Row

struct MessageResultRow: View {
    let message: MessageWatcher.AnalyzedMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.sender)
                    .font(.caption)
                    .fontWeight(.semibold)
                if message.messageCount > 1 {
                    Text("\(message.messageCount) msgs")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.7), in: Capsule())
                }
                Spacer()
                Text(message.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(message.messagePreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(message.result)
                .font(.caption)
                .lineLimit(3)
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }
}
