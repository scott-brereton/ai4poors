// OCRPipeline.swift
// Ai4Poors - Vision framework OCR text extraction
//
// Runs VNRecognizeTextRequest on a CGImage, returns position-aware text blocks.
// Vision OCR runs inference out-of-process, keeping extension memory low.

import Vision
import CoreGraphics

enum OCRPipeline {

    /// Extract text blocks from a screen capture image.
    /// Returns text with bounding box positions for zone classification.
    static func extractText(from image: CGImage) -> [OCRTextBlock] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            debugLog("[OCR] Failed: \(error.localizedDescription)")
            return []
        }

        guard let observations = request.results else { return [] }

        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRTextBlock(
                text: candidate.string,
                boundingBox: observation.boundingBox,
                confidence: candidate.confidence
            )
        }
    }

    /// Convenience: get all text concatenated (content zone only, filtering keyboard/status bar).
    static func extractContentText(from image: CGImage) -> String {
        let blocks = extractText(from: image)
        let contentBlocks = blocks.filter { block in
            block.zone == .content || block.zone == .navBar
        }
        let texts: [String] = contentBlocks.map { $0.text }
        return texts.joined(separator: "\n")
    }

    /// Get full raw text from all zones.
    static func extractAllText(from image: CGImage) -> String {
        let blocks = extractText(from: image)
        let texts: [String] = blocks.map { $0.text }
        return texts.joined(separator: "\n")
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
