// Ai4PoorsActivity.swift
// Ai4Poors - Shared Live Activity attributes and manager
//
// Used by both the main app (to start/update activities) and
// the widget extension (to render them).

#if os(iOS)
import ActivityKit
import SwiftUI

// MARK: - Activity Attributes

struct Ai4PoorsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String           // "analyzing", "streaming", "result", "error"
        var instruction: String     // "Summarize", "Translate", etc.
        var preview: String         // First ~120 chars of result
        var fullResult: String      // Complete result (for expanded view)
        var progress: Double        // 0.0-1.0 for indeterminate animation
    }

    var source: String              // "keyboard", "safari", "screenshot"
    var timestamp: Date
    var actionIcon: String          // SF Symbol name
}

// MARK: - Activity Manager

@MainActor
final class Ai4PoorsActivityManager {
    static let shared = Ai4PoorsActivityManager()
    private var currentActivity: Activity<Ai4PoorsActivityAttributes>?

    private init() {}

    var isActive: Bool {
        currentActivity != nil
    }

    func startAnalysis(source: String, instruction: String, actionIcon: String = "sparkle") {
        // End any existing activity
        endCurrentActivity()

        let attributes = Ai4PoorsActivityAttributes(
            source: source,
            timestamp: Date(),
            actionIcon: actionIcon
        )

        let initialState = Ai4PoorsActivityAttributes.ContentState(
            phase: "analyzing",
            instruction: instruction,
            preview: "",
            fullResult: "",
            progress: 0.0
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("[Ai4Poors] Failed to start Live Activity: \(error)")
        }
    }

    func updateStreaming(preview: String) {
        guard let activity = currentActivity else { return }

        let updatedState = Ai4PoorsActivityAttributes.ContentState(
            phase: "streaming",
            instruction: activity.content.state.instruction,
            preview: String(preview.suffix(120)),
            fullResult: preview,
            progress: 0.5
        )

        Task {
            await activity.update(.init(state: updatedState, staleDate: nil))
        }
    }

    func completeWithResult(_ result: String) {
        guard let activity = currentActivity else { return }

        let preview = result.count > 120
            ? String(result.prefix(117)) + "..."
            : result

        let updatedState = Ai4PoorsActivityAttributes.ContentState(
            phase: "result",
            instruction: activity.content.state.instruction,
            preview: preview,
            fullResult: result,
            progress: 1.0
        )

        Task {
            await activity.update(.init(state: updatedState, staleDate: nil))

            // Auto-dismiss after 30 seconds
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await activity.end(
                .init(state: updatedState, staleDate: nil),
                dismissalPolicy: .after(.now + 60)
            )
            currentActivity = nil
        }
    }

    func completeWithError(_ message: String) {
        guard let activity = currentActivity else { return }

        let updatedState = Ai4PoorsActivityAttributes.ContentState(
            phase: "error",
            instruction: activity.content.state.instruction,
            preview: message,
            fullResult: "",
            progress: 0.0
        )

        Task {
            await activity.update(.init(state: updatedState, staleDate: nil))

            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await activity.end(
                .init(state: updatedState, staleDate: nil),
                dismissalPolicy: .after(.now + 30)
            )
            currentActivity = nil
        }
    }

    func endCurrentActivity() {
        guard let activity = currentActivity else { return }
        let finalState = activity.content.state
        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        currentActivity = nil
    }
}
#endif
