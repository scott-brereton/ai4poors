// CaptureRecord.swift
// Ai4Poors - Data model for screen capture records

import Foundation
import CoreGraphics

struct CaptureRecord: Identifiable {
    let id: String
    let timestamp: Date
    let sourceApp: String?
    let sourceAppName: String?
    let rawOCRText: String
    var summary: String?
    let thumbnailPath: String?
    let perceptualHash: UInt64

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        sourceApp: String? = nil,
        sourceAppName: String? = nil,
        rawOCRText: String,
        summary: String? = nil,
        thumbnailPath: String? = nil,
        perceptualHash: UInt64
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceApp = sourceApp
        self.sourceAppName = sourceAppName
        self.rawOCRText = rawOCRText
        self.summary = summary
        self.thumbnailPath = thumbnailPath
        self.perceptualHash = perceptualHash
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var formattedDate: String {
        Self.relativeDateFormatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var textPreview: String {
        String(rawOCRText.prefix(200))
    }
}

// MARK: - OCR Text Block (position-aware text from Vision)

struct OCRTextBlock {
    let text: String
    /// Normalized bounding box (0-1). Origin at bottom-left per Vision conventions.
    let boundingBox: CGRect
    let confidence: Float

    /// Vertical zone classification based on bounding box position.
    var zone: ScreenZone {
        let midY = boundingBox.midY
        if midY > 0.92 { return .statusBar }
        if midY < 0.35 { return .keyboard }
        if midY > 0.85 { return .navBar }
        return .content
    }
}

enum ScreenZone {
    case statusBar  // top ~8%
    case navBar     // top ~15% (below status bar)
    case content    // middle ~50%
    case keyboard   // bottom ~35%
}
