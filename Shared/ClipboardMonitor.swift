// ClipboardMonitor.swift
// Ai4Poors - Background clipboard monitoring via Picture-in-Picture
//
// Uses AVPictureInPictureController with AVSampleBufferDisplayLayer to keep
// the app in a semi-foreground state where UIPasteboard reads succeed.
// Polls changeCount, analyzes via AI, saves to history, posts notification.

#if canImport(UIKit)
import UIKit
import AVKit
import AVFoundation
import UserNotifications
import os.log

private let log = Logger(subsystem: "com.example.ai4poors", category: "ClipboardMonitor")

/// Writes to both os_log and a file in the App Group container for easy retrieval.
private func clipLog(_ message: String) {
    log.info("\(message)")
    guard let url = AppGroupConstants.sharedContainerURL?.appendingPathComponent("clipboard_debug.log") else { return }
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let entry = "[\(timestamp)] \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(entry.data(using: .utf8) ?? Data())
        handle.closeFile()
    } else {
        try? entry.data(using: .utf8)?.write(to: url)
    }
}

@MainActor
final class ClipboardMonitor: NSObject, ObservableObject {
    static let shared = ClipboardMonitor()

    @Published private(set) var isMonitoring = false
    private var lastChangeCount: Int = 0
    private var isProcessing = false

    // MARK: - PiP Infrastructure

    private let bufferDisplayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var pipPossibleObservation: NSKeyValueObservation?
    private var renderTimer: Timer?
    private var clipboardTimer: Timer?

    /// Invisible host view — must be added to the window's view hierarchy.
    let hostView: UIView = {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 30))
        v.alpha = 0
        return v
    }()

    /// Content rendered into the PiP window.
    private let statusLabel: UILabel = {
        let l = UILabel(frame: CGRect(x: 0, y: 0, width: 120, height: 30))
        l.backgroundColor = .black
        l.textColor = .white
        l.font = .systemFont(ofSize: 9, weight: .medium)
        l.textAlignment = .center
        l.text = "Ai4Poors Monitoring"
        return l
    }()

    // MARK: - Init

    override private init() {
        super.init()
        bufferDisplayLayer.frame = hostView.bounds
        bufferDisplayLayer.videoGravity = .resizeAspect
        hostView.layer.addSublayer(bufferDisplayLayer)
        lastChangeCount = UIPasteboard.general.changeCount
    }

    // MARK: - Start / Stop

    /// Must be called from a user-initiated action (button tap).
    func start() {
        guard !isMonitoring else { return }

        // Audio session required for PiP to work
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            clipLog("ERROR: Audio session setup failed: \(error.localizedDescription)")
            return
        }

        // Render an initial frame
        renderFrame()

        lastChangeCount = UIPasteboard.general.changeCount

        // Create PiP controller lazily (must be after view is in hierarchy)
        if pipController == nil {
            guard AVPictureInPictureController.isPictureInPictureSupported() else {
                clipLog("ERROR: PiP not supported on this device")
                return
            }
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: bufferDisplayLayer,
                playbackDelegate: self
            )
            let controller = AVPictureInPictureController(contentSource: source)
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            pipController = controller
        }

        guard let pip = pipController else { return }

        clipLog("PiP possible: \(pip.isPictureInPicturePossible)")
        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
            beginMonitoring()
        } else {
            // Wait for PiP to become possible
            pipPossibleObservation = pip.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] controller, change in
                guard change.newValue == true else { return }
                DispatchQueue.main.async {
                    controller.startPictureInPicture()
                    self?.beginMonitoring()
                    self?.pipPossibleObservation = nil
                }
            }
        }
    }

    private func beginMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Re-render PiP content every second
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renderFrame() }
        }

        // Poll clipboard every 1.5 seconds
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkClipboard() }
        }

        clipLog("Clipboard monitor started (PiP)")
    }

    func stop() {
        pipController?.stopPictureInPicture()
        renderTimer?.invalidate()
        renderTimer = nil
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        isMonitoring = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        clipLog("Clipboard monitor stopped")
    }

    // MARK: - PiP Rendering

    private func renderFrame() {
        if bufferDisplayLayer.status == .failed {
            bufferDisplayLayer.flush()
        }
        guard let sampleBuffer = makeSampleBuffer(from: statusLabel) else { return }
        bufferDisplayLayer.enqueue(sampleBuffer)
    }

    private func makeSampleBuffer(from view: UIView) -> CMSampleBuffer? {
        let scale = UIScreen.main.scale
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)

        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                   kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: scale, y: -scale)
        view.layer.render(in: context)

        var formatDesc: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &formatDesc)
        guard let fmt = formatDesc else { return nil }

        let now = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 60)
        let timing = CMSampleTimingInfo(duration: CMTime(seconds: 1, preferredTimescale: 60), presentationTimeStamp: now, decodeTimeStamp: now)
        return try? CMSampleBuffer(imageBuffer: buffer, formatDescription: fmt, sampleTiming: timing)
    }

    // MARK: - Clipboard Polling

    private func checkClipboard() {
        let currentCount = UIPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        guard !isProcessing else { return }
        lastChangeCount = currentCount

        clipLog("Clipboard changed (changeCount: \(currentCount))")

        if let text = UIPasteboard.general.string {
            if text.count > 10 {
                clipLog("Clipboard text (\(text.count) chars): \(String(text.prefix(120)))")

                // Check if this is a URL from an approved reader domain
                if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                   let scheme = url.scheme, ["http", "https"].contains(scheme),
                   let host = url.host,
                   url.pathComponents.count > 1,
                   AppGroupConstants.isCrawl4AIConfigured {
                    let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                    if AppGroupConstants.isApprovedReaderDomain(domain) {
                        clipLog("Approved reader domain detected: \(domain)")
                        statusLabel.text = "Reading article..."
                        readArticle(url: text.trimmingCharacters(in: .whitespacesAndNewlines))
                        return
                    }
                }

                statusLabel.text = "Analyzing..."
                analyzeText(text)
            } else {
                clipLog("Clipboard text too short (\(text.count) chars), skipping: \(text)")
            }
        } else if let image = UIPasteboard.general.image {
            clipLog("Clipboard image: \(Int(image.size.width))x\(Int(image.size.height))")
            statusLabel.text = "Analyzing image..."
            analyzeImage(image)
        } else {
            clipLog("Clipboard changed but no readable text or image (nil from UIPasteboard)")
        }
    }

    private func analyzeText(_ text: String) {
        isProcessing = true
        Task {
            defer {
                isProcessing = false
                statusLabel.text = "Ai4Poors Monitoring"
            }

            guard AppGroupConstants.isAPIKeyConfigured else {
                clipLog("WARN: Skipping clipboard analysis — no API key")
                return
            }

            let todayDate = OpenRouterService.todayString
            let instruction = """
            Today's date is \(todayDate).

            The user just copied this text to their clipboard. You are their smart, observant assistant with access to web search and tools. Your job:

            1. **IDENTIFY** what this is — a name, a quote, an address, a code snippet, a URL, a product, a book title, an error message, a conversation snippet, etc.
            2. **REACT** with useful context — if it's a book, what's it about and is it good? If it's an error, what causes it? If it's a product/price, is it a good deal? If it's a person, who are they? If it's an address, what's there?
            3. **USE TOOLS** to give the user actionable next steps:
               - open_url: Link to the relevant page (Goodreads for books, Google Maps for addresses, Amazon for products, Wikipedia for people/topics, GitHub for code/repos, etc.)
               - copy_text: Extract key info worth copying (ISBN, phone number, address, price, etc.)
               Always provide at least one open_url tool call with the most useful link.

            Be direct and helpful. 2-3 sentences. Start with the insight, not "This is a..."
            """

            do {
                clipLog("Sending to API with tools — input: \(String(text.prefix(80)))...")
                let toolResult = try await OpenRouterService.shared.analyzeTextWithTools(
                    text: text, instruction: instruction, model: "google/gemini-3-flash-preview"
                )
                clipLog("API response: \(toolResult.text)")
                clipLog("Tool actions: \(toolResult.actions.count)")
                for action in toolResult.actions {
                    clipLog("  Action: \(action.label) — \(action.type)")
                }

                let actionsData = ToolAction.encode(toolResult.actions)
                HistoryService.save(
                    channel: .clipboard, action: .custom,
                    inputPreview: String(text.prefix(200)), result: toolResult.text,
                    model: "google/gemini-3-flash-preview", customInstruction: instruction,
                    toolActionsData: actionsData
                )
                await postNotification(body: toolResult.text)
                NotificationCenter.default.post(name: .ai4poorsShowResult, object: toolResult.text)
            } catch {
                clipLog("ERROR: Clipboard text analysis failed: \(error.localizedDescription)")
            }
        }
    }

    private func readArticle(url: String) {
        isProcessing = true
        Task {
            defer {
                isProcessing = false
                statusLabel.text = "Ai4Poors Monitoring"
            }

            do {
                clipLog("Reading article via Crawl4AI: \(url)")
                let result = try await Crawl4AIClient.scrapeAndClean(url: url)
                let title = result.articleTitle ?? URL(string: url)?.host ?? "Article"
                let body = result.articleBody ?? result.markdown ?? ""

                clipLog("Reader result: \(title) (\(body.count) chars)")

                Crawl4AIClient.recordApprovedDomain(from: url)

                HistoryService.save(
                    channel: .reader, action: .read,
                    inputPreview: title, result: body,
                    model: "crawl4ai", customInstruction: url
                )

                let preview = String(body.prefix(200)).replacingOccurrences(of: "\n", with: " ")
                await postNotification(body: "\(title)\n\n\(preview)")
            } catch {
                clipLog("ERROR: Reader extraction failed: \(error.localizedDescription)")
            }
        }
    }

    private func analyzeImage(_ image: UIImage) {
        isProcessing = true
        Task {
            defer {
                isProcessing = false
                statusLabel.text = "Ai4Poors Monitoring"
            }

            guard AppGroupConstants.isAPIKeyConfigured else { return }

            let instruction = "Describe what's in this image in one sentence."

            do {
                clipLog("Sending image to API — \(Int(image.size.width))x\(Int(image.size.height))")
                let result = try await OpenRouterService.shared.analyzeImage(image: image, instruction: instruction)
                clipLog("Image API response: \(result)")

                let thumbnailData = image.jpegData(compressionQuality: 0.5)
                HistoryService.save(
                    channel: .clipboard, action: .custom,
                    inputPreview: "[Clipboard Image]", result: result,
                    model: "google/gemini-3-flash-preview", customInstruction: instruction,
                    imageData: thumbnailData
                )
                await postNotification(body: result)
                NotificationCenter.default.post(name: .ai4poorsShowResult, object: result)
            } catch {
                clipLog("ERROR: Clipboard image analysis failed: \(error.localizedDescription)")
            }
        }
    }

    private func postNotification(body: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Ai4Poors: Clipboard"
        content.body = String(body.prefix(200))
        content.sound = .default
        content.categoryIdentifier = "ai4poors_clipboard"
        content.userInfo = ["result": body]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension ClipboardMonitor: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            clipLog("ERROR: PiP failed to start: \(error.localizedDescription)")
            isMonitoring = false
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        Task { @MainActor in stop() }
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension ClipboardMonitor: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController, setPlaying playing: Bool
    ) {
        // play/pause in PiP overlay toggles monitoring
        Task { @MainActor in
            if playing {
                beginMonitoring()
            } else {
                clipboardTimer?.invalidate()
                clipboardTimer = nil
            }
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController
    ) -> CMTimeRange {
        // Use .zero start to avoid iOS 16.1+ CPU bug with .negativeInfinity
        CMTimeRange(start: .zero, duration: CMTime(value: 86400, timescale: 1))
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ controller: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
#endif
