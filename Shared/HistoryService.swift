// HistoryService.swift
// Ai4Poors - Shared history persistence for all channels
//
// Writes AnalysisRecord to the shared SwiftData store.
// Works from any process: main app, keyboard, safari, share extension, or intents.

import Foundation
import SwiftData

enum HistoryService {

    /// Save an analysis record to the shared SwiftData store.
    /// Safe to call from any target/process — uses the App Group container.
    static func save(
        channel: Ai4PoorsChannel,
        action: Ai4PoorsAction,
        inputPreview: String,
        result: String,
        model: String,
        customInstruction: String? = nil,
        imageData: Data? = nil,
        toolActionsData: Data? = nil,
        isViewed: Bool = false
    ) {
        guard AppGroupConstants.isHistoryEnabled else { return }
        guard let containerURL = AppGroupConstants.sharedContainerURL else {
            print("[Ai4Poors] No shared container URL — cannot save history")
            return
        }

        do {
            let schema = Schema([AnalysisRecord.self])
            let config = ModelConfiguration(
                "Ai4PoorsHistory",
                schema: schema,
                url: containerURL.appendingPathComponent("ai4poors_history.sqlite"),
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            let record = AnalysisRecord(
                channel: channel,
                action: action,
                inputPreview: inputPreview,
                result: result,
                model: model,
                customInstruction: customInstruction,
                imageData: imageData,
                toolActionsData: toolActionsData,
                isViewed: isViewed
            )
            context.insert(record)
            try context.save()
        } catch {
            print("[Ai4Poors] Failed to save history record: \(error)")
        }
    }
}
