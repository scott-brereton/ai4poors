// TriageFilter.swift
// Ai4Poors - Fast "worth keeping?" filter for screen captures
//
// Decides whether a captured frame contains meaningful content worth
// extracting and storing. Runs after OCR, before SQLite insert.

import Foundation

struct TriageResult {
    let shouldKeep: Bool
    let reason: String
    /// Content-zone text, already computed during triage. Nil if shouldKeep is false.
    let contentText: String?
}

enum TriageFilter {

    // MARK: - Configuration

    /// Minimum content-zone text length to consider "meaningful"
    static let minContentChars = 50

    /// Perceptual hash Hamming distance threshold.
    /// Below this = screen hasn't changed enough to store again.
    static let hashDistanceThreshold = 10

    /// Apps where captures are rarely useful
    static let blacklistedApps: Set<String> = [
        "com.apple.Preferences",
        "com.apple.calculator",
        "com.apple.camera",
        "com.apple.facetime",
        "com.apple.InCallService",
        "com.apple.springboard",   // home screen
        "com.apple.TelephonyUtilities",
    ]

    /// Text patterns that indicate system UI rather than app content
    static let systemUIPatterns: [String] = [
        "Control Cent",       // Control Center (may be truncated by OCR)
        "Slide to power off",
        "Emergency SOS",
        "App Switcher",
        "Focus On",           // Do Not Disturb
        "No Older Notifications",
        "Notification Center",
    ]

    // MARK: - Triage

    /// Evaluate whether this capture is worth storing.
    /// - Parameters:
    ///   - textBlocks: OCR results with positions
    ///   - sourceApp: Detected bundle ID (nil if detection failed)
    ///   - hash: Perceptual hash of current frame
    ///   - lastStoredHash: Hash of the last frame we actually stored (not just sampled)
    static func evaluate(
        textBlocks: [OCRTextBlock],
        sourceApp: String?,
        hash: UInt64,
        lastStoredHash: UInt64?
    ) -> TriageResult {

        // 1. Perceptual hash similarity to last *stored* capture
        if let lastHash = lastStoredHash {
            let dist = PerceptualHash.distance(hash, lastHash)
            if dist < hashDistanceThreshold {
                return TriageResult(shouldKeep: false, reason: "hash_similar(\(dist))", contentText: nil)
            }
        }

        // 2. System UI detection
        let fullText = textBlocks.map { $0.text }.joined(separator: " ")
        for pattern in systemUIPatterns {
            if fullText.localizedCaseInsensitiveContains(pattern) {
                return TriageResult(shouldKeep: false, reason: "system_ui(\(pattern))", contentText: nil)
            }
        }

        // 3. Content text density — filter out keyboard-dominated screens
        var contentChars = 0
        var keyboardChars = 0
        var totalChars = 0
        var contentParts: [String] = []

        for block in textBlocks {
            let len = block.text.count
            totalChars += len
            switch block.zone {
            case .content, .navBar:
                contentChars += len
                contentParts.append(block.text)
            case .keyboard:
                keyboardChars += len
            case .statusBar:
                break
            }
        }

        if contentChars < minContentChars {
            return TriageResult(shouldKeep: false, reason: "low_text(\(contentChars))", contentText: nil)
        }

        // 4. Keyboard dominance: if most text is in the keyboard zone, skip
        if totalChars > 0 && Double(keyboardChars) / Double(totalChars) > 0.7 {
            return TriageResult(shouldKeep: false, reason: "keyboard_dominant", contentText: nil)
        }

        let contentText = contentParts.joined(separator: "\n")
        return TriageResult(shouldKeep: true, reason: "pass(\(contentChars)_chars)", contentText: contentText)
    }
}
