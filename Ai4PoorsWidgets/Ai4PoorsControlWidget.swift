// Ai4PoorsControlWidget.swift
// Ai4PoorsWidgets - Control Center Widget (iOS 18+)
//
// Adds a Ai4Poors button to Control Center that triggers
// the screenshot analysis pipeline.

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Control Center Toggle

@available(iOS 18.0, *)
struct Ai4PoorsControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.example.ai4poors.control"
        ) {
            ControlWidgetButton(action: Ai4PoorsCaptureIntent()) {
                Label("Ai4Poors", systemImage: "sparkle")
            }
        }
        .displayName("Ai4Poors")
        .description("Capture and analyze your screen with AI")
    }
}

// MARK: - Capture Intent (for Control Center)

@available(iOS 18.0, *)
struct Ai4PoorsCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture with Ai4Poors"
    static let description: IntentDescription = "Takes a screenshot and analyzes it with AI"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        // Signal the main app to begin screenshot analysis
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        defaults?.set(true, forKey: "pending_screenshot_capture")
        defaults?.set(Date().timeIntervalSince1970, forKey: "capture_timestamp")
        return .result()
    }
}

// MARK: - Widget Bundle

@main
struct Ai4PoorsWidgetBundle: WidgetBundle {
    var body: some Widget {
        Ai4PoorsLiveActivity()

        if #available(iOS 18.0, *) {
            Ai4PoorsControlWidget()
        }
    }
}
