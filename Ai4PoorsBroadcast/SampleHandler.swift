// SampleHandler.swift
// Ai4PoorsBroadcast - ReplayKit Broadcast Upload Extension
//
// Receives screen frames from the system, samples every ~10 seconds,
// runs the capture pipeline: hash → app detect → OCR → triage → store.
//
// Memory budget: 50MB. Key constraints:
// - Only hold one frame at a time
// - CIContext and CaptureStore are long-lived singletons
// - Vision OCR runs out-of-process (doesn't count against our memory)
// - Release pixel buffers immediately after extracting needed data

import ReplayKit
import CoreImage
import ImageIO

class SampleHandler: RPBroadcastSampleHandler {

    // MARK: - Configuration

    /// Minimum interval between frame samples
    private let sampleInterval: CFAbsoluteTime = 10.0

    /// Perceptual hash distance threshold for "screen changed"
    /// (checked against the PREVIOUS SAMPLE, not the last stored capture)
    private let sampleHashThreshold = 5

    /// Thumbnail width in pixels
    private let thumbnailWidth: CGFloat = 320

    // MARK: - State

    private var lastSampleTime: CFAbsoluteTime = 0
    private var lastSampleHash: UInt64 = 0
    private var lastStoredHash: UInt64?

    /// Atomic flag — prevents stacking frames while one is being processed.
    /// Accessed from the ReplayKit callback queue and the processing queue.
    private let processingLock = NSLock()
    private var _isProcessing = false
    private var isProcessing: Bool {
        get { processingLock.lock(); defer { processingLock.unlock() }; return _isProcessing }
        set { processingLock.lock(); defer { processingLock.unlock() }; _isProcessing = newValue }
    }

    /// Reusable CIContext — expensive to create, cheap to reuse
    private lazy var ciContext: CIContext = {
        CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
    }()

    private let processingQueue = DispatchQueue(
        label: "com.ai4poors.broadcast.processing",
        qos: .utility
    )

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    // MARK: - Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        debugLog("[Broadcast] Started")

        // Load last stored hash from database
        lastStoredHash = CaptureStore.shared.lastStoredHash()

        debugLog("[Broadcast] Last stored hash: \(lastStoredHash.map(String.init) ?? "none")")
    }

    override func broadcastPaused() {
        debugLog("[Broadcast] Paused")
    }

    override func broadcastResumed() {
        debugLog("[Broadcast] Resumed")
    }

    override func broadcastFinished() {
        debugLog("[Broadcast] Finished")
    }

    // MARK: - Frame Processing

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        // Only process video frames
        guard sampleBufferType == .video else { return }

        // Rate limit: only sample every N seconds
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSampleTime >= sampleInterval else { return }

        // Don't stack up processing
        guard !isProcessing else { return }
        isProcessing = true
        lastSampleTime = now

        // Extract pixel buffer (zero-copy reference to the frame)
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessing = false
            return
        }

        // Phase 1: Compute perceptual hash directly from pixel buffer (fast, ~5ms)
        let hash = PerceptualHash.compute(from: pixelBuffer, context: ciContext)

        // Skip if screen hasn't changed since last sample
        if PerceptualHash.distance(hash, lastSampleHash) < sampleHashThreshold {
            lastSampleHash = hash
            isProcessing = false
            return
        }
        lastSampleHash = hash

        // Phase 2: Screen changed — create CGImage for OCR + thumbnail
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            isProcessing = false
            return
        }

        // Process the rest on a background queue (CGImage is self-contained)
        let capturedHash = hash
        processingQueue.async { [weak self] in
            self?.processFrame(image: cgImage, hash: capturedHash, timestamp: Date())
            self?.isProcessing = false
        }
    }

    // MARK: - Pipeline

    private func processFrame(image: CGImage, hash: UInt64, timestamp: Date) {
        // Step 1: Detect foreground app
        let appInfo = ForegroundAppDetector.currentApp()
        let sourceApp = appInfo?.bundleID
        let sourceAppName = appInfo?.name

        // Step 2: Check app blacklist (before expensive OCR)
        if let app = sourceApp, TriageFilter.blacklistedApps.contains(app) {
            debugLog("[Broadcast] Skipped blacklisted app: \(app)")
            return
        }

        // Step 3: Run Vision OCR
        let textBlocks = OCRPipeline.extractText(from: image)

        // Step 4: Triage — is this worth keeping?
        // Triage computes content text internally; reuse it to avoid re-filtering.
        let triage = TriageFilter.evaluate(
            textBlocks: textBlocks,
            sourceApp: sourceApp,
            hash: hash,
            lastStoredHash: lastStoredHash
        )

        guard triage.shouldKeep, let ocrText = triage.contentText, !ocrText.isEmpty else {
            debugLog("[Broadcast] Skipped: \(triage.reason)")
            return
        }

        // Step 6: Generate thumbnail
        let recordID = UUID().uuidString
        let thumbnailPath = saveThumbnail(image: image, id: recordID)

        // Step 7: Store in database
        let record = CaptureRecord(
            id: recordID,
            timestamp: timestamp,
            sourceApp: sourceApp,
            sourceAppName: sourceAppName,
            rawOCRText: ocrText,
            thumbnailPath: thumbnailPath,
            perceptualHash: hash
        )

        CaptureStore.shared.insert(record)
        lastStoredHash = hash

        debugLog("[Broadcast] Stored capture: \(sourceAppName ?? sourceApp ?? "unknown") (\(ocrText.count) chars)")
    }

    // MARK: - Thumbnail

    private func saveThumbnail(image: CGImage, id: String) -> String? {
        guard let containerURL = AppGroupConstants.sharedContainerURL else { return nil }

        let thumbDir = containerURL.appendingPathComponent("capture_thumbnails")
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)

        let thumbURL = thumbDir.appendingPathComponent("\(id).jpg")

        // Scale down
        let scale = thumbnailWidth / CGFloat(image.width)
        let thumbW = Int(thumbnailWidth)
        let thumbH = Int(CGFloat(image.height) * scale)

        guard let context = CGContext(
            data: nil,
            width: thumbW,
            height: thumbH,
            bitsPerComponent: 8,
            bytesPerRow: thumbW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: thumbW, height: thumbH))

        guard let thumbImage = context.makeImage() else { return nil }

        // Write JPEG via ImageIO
        guard let dest = CGImageDestinationCreateWithURL(
            thumbURL as CFURL,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.6]
        CGImageDestinationAddImage(dest, thumbImage, options as CFDictionary)
        CGImageDestinationFinalize(dest)

        return thumbURL.path
    }

    // MARK: - Debug

    private func debugLog(_ message: String) {
        #if DEBUG
        print(message)

        // Write to shared container for debugging from main app (DEBUG only)
        guard let containerURL = AppGroupConstants.sharedContainerURL else { return }
        let logURL = containerURL.appendingPathComponent("broadcast_log.txt")
        let entry = "[\(Self.isoFormatter.string(from: Date()))] \(message)\n"
        if let data = entry.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
        #endif
    }
}
