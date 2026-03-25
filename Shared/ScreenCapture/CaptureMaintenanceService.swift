// CaptureMaintenanceService.swift
// Ai4Poors - Periodic maintenance for the screen capture database
//
// Runs in the main app (not the extension) to:
// - Deduplicate similar captures from the same app
// - Batch-process unsummarized captures via LLM
// - Prune old thumbnails and records

import Foundation

actor CaptureMaintenanceService {

    static let shared = CaptureMaintenanceService()

    private let store = CaptureStore.shared
    private var isRunning = false

    // MARK: - Run All Maintenance

    /// Run all maintenance tasks. Call from main app on launch or periodically.
    func runMaintenance() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        debugLog("[Maintenance] Starting maintenance pass")

        let dedupCount = deduplicateCaptures()
        debugLog("[Maintenance] Dedup removed \(dedupCount) records")

        let pruneCount = pruneOldRecords(olderThanDays: 90)
        debugLog("[Maintenance] Pruned \(pruneCount) old records")

        cleanOrphanedThumbnails()
        debugLog("[Maintenance] Cleaned orphaned thumbnails")

        debugLog("[Maintenance] Complete")
    }

    // MARK: - Deduplication

    /// Find and remove duplicate captures using text similarity.
    /// Compares captures from the same app within a 30-minute window.
    /// If Jaccard similarity > 0.8, keeps the one with more text.
    func deduplicateCaptures() -> Int {
        let pairs = store.findDuplicateCandidates(windowMinutes: 30)
        var removedCount = 0

        for (a, b) in pairs {
            let similarity = jaccardSimilarity(a.rawOCRText, b.rawOCRText)
            if similarity > 0.8 {
                // Keep the one with more content
                let toRemove = a.rawOCRText.count >= b.rawOCRText.count ? b : a
                store.delete(id: toRemove.id)
                deleteThumbnail(path: toRemove.thumbnailPath)
                removedCount += 1
            }
        }

        return removedCount
    }

    // MARK: - LLM Batch Summarization

    /// Get captures that need LLM summarization.
    /// The caller should send these to OpenRouterService and call updateSummary.
    func capturesNeedingSummary(limit: Int = 10) -> [CaptureRecord] {
        return store.recordsNeedingSummary(limit: limit)
    }

    /// Update a capture's summary after LLM processing.
    func updateSummary(id: String, summary: String) {
        store.updateSummary(id: id, summary: summary)
    }

    // MARK: - Pruning

    /// Delete records older than N days.
    func pruneOldRecords(olderThanDays days: Int) -> Int {
        return store.deleteOlderThan(days: days)
    }

    /// Remove thumbnail files that no longer have corresponding database records.
    func cleanOrphanedThumbnails() {
        guard let containerURL = AppGroupConstants.sharedContainerURL else { return }
        let thumbDir = containerURL.appendingPathComponent("capture_thumbnails")

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: thumbDir,
            includingPropertiesForKeys: nil
        ) else { return }

        // Get all IDs currently in the database (lightweight, no OCR text loaded)
        let validIDs = store.allCaptureIDs()

        for file in files {
            let id = file.deletingPathExtension().lastPathComponent
            if !validIDs.contains(id) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Text Similarity

    /// Jaccard similarity between two texts (based on word sets).
    /// 0.0 = completely different, 1.0 = identical word sets.
    private func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(separator: " ").map { String($0) })
        let wordsB = Set(b.lowercased().split(separator: " ").map { String($0) })

        guard !wordsA.isEmpty || !wordsB.isEmpty else { return 1.0 }

        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count

        return Double(intersection) / Double(union)
    }

    // MARK: - Helpers

    private func deleteThumbnail(path: String?) {
        guard let path = path else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
