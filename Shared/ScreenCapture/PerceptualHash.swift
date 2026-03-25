// PerceptualHash.swift
// Ai4Poors - Difference hash (dHash) for screen change detection
//
// Resizes to 9x8 grayscale, compares adjacent horizontal pixels.
// Produces a 64-bit hash. Hamming distance indicates visual similarity.

import CoreImage
import CoreGraphics

enum PerceptualHash {

    /// Compute dHash from a CVPixelBuffer using the provided CIContext.
    /// The CIContext should be reused across calls for performance.
    static func compute(from pixelBuffer: CVPixelBuffer, context: CIContext) -> UInt64 {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return computeFromCIImage(ciImage, context: context)
    }

    /// Compute dHash from a CGImage using the provided CIContext.
    static func compute(from cgImage: CGImage, context: CIContext) -> UInt64 {
        let ciImage = CIImage(cgImage: cgImage)
        return computeFromCIImage(ciImage, context: context)
    }

    /// Hamming distance between two hashes (number of differing bits).
    /// Lower = more similar. 0 = identical. 64 = maximally different.
    static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        return (a ^ b).nonzeroBitCount
    }

    // MARK: - Internal

    /// Reuse a single color space across all hash computations.
    private static let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

    private static func computeFromCIImage(_ ciImage: CIImage, context: CIContext) -> UInt64 {
        let width = 9
        let height = 8

        // Scale down to 9x8
        let scaleX = CGFloat(width) / ciImage.extent.width
        let scaleY = CGFloat(height) / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Render to RGBA8 buffer
        var rgbaPixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            scaled,
            toBitmap: &rgbaPixels,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: rgbColorSpace
        )

        // Convert to grayscale luminance
        var gray = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Int(rgbaPixels[i * 4])
            let g = Int(rgbaPixels[i * 4 + 1])
            let b = Int(rgbaPixels[i * 4 + 2])
            gray[i] = UInt8((r * 299 + g * 587 + b * 114) / 1000)
        }

        // dHash: for each row, compare adjacent pixels horizontally
        // If left pixel > right pixel, bit = 1
        var hash: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 {
                let idx = y * width + x
                if gray[idx] > gray[idx + 1] {
                    hash |= 1 << UInt64(y * 8 + x)
                }
            }
        }

        return hash
    }
}
