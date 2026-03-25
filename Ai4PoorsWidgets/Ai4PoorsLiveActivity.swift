// Ai4PoorsLiveActivity.swift
// Ai4PoorsWidgets - Dynamic Island and Lock Screen Live Activity
//
// Shows AI analysis progress and results in Dynamic Island
// and on the Lock Screen, from any channel.

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Widget

struct Ai4PoorsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Ai4PoorsActivityAttributes.self) { context in
            // Lock Screen / StandBy banner
            lockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.75))

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text(channelLabel(context.attributes.source))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.instruction)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if context.state.phase == "analyzing" || context.state.phase == "streaming" {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.blue)
                                Text(context.state.phase == "streaming" ? "Generating..." : "Analyzing...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            if !context.state.preview.isEmpty {
                                Text(context.state.preview)
                                    .font(.system(size: 12))
                                    .lineLimit(2)
                                    .foregroundStyle(.primary.opacity(0.8))
                            }
                        } else if context.state.phase == "result" {
                            Text(context.state.preview)
                                .font(.system(size: 12))
                                .lineLimit(3)
                                .foregroundStyle(.primary)
                        } else if context.state.phase == "error" {
                            Label(context.state.preview, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }

            } compactLeading: {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.blue)

            } compactTrailing: {
                compactTrailingView(phase: context.state.phase)

            } minimal: {
                Image(systemName: statusIcon(for: context.state.phase))
                    .font(.system(size: 11))
                    .foregroundStyle(statusColor(for: context.state.phase))
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<Ai4PoorsActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(context.state.instruction)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text(channelLabel(context.attributes.source))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }

                if context.state.phase == "analyzing" || context.state.phase == "streaming" {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.blue)
                        Text(context.state.preview.isEmpty ? "Working..." : context.state.preview)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else if context.state.phase == "result" {
                    Text(context.state.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                } else if context.state.phase == "error" {
                    Label(context.state.preview, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }

            if context.state.phase == "result" {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func compactTrailingView(phase: String) -> some View {
        switch phase {
        case "analyzing", "streaming":
            ProgressView()
                .controlSize(.small)
                .tint(.blue)
        case "result":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case "error":
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        default:
            Image(systemName: "sparkle")
                .font(.system(size: 12))
                .foregroundStyle(.blue)
        }
    }

    private func statusIcon(for phase: String) -> String {
        switch phase {
        case "analyzing", "streaming": return "sparkle"
        case "result": return "checkmark.circle.fill"
        case "error": return "exclamationmark.triangle.fill"
        default: return "sparkle"
        }
    }

    private func statusColor(for phase: String) -> Color {
        switch phase {
        case "result": return .green
        case "error": return .red
        default: return .blue
        }
    }

    private func channelLabel(_ source: String) -> String {
        switch source {
        case "keyboard": return "Keyboard"
        case "safari": return "Safari"
        case "screenshot": return "Screenshot"
        case "share": return "Share"
        default: return source.capitalized
        }
    }
}
