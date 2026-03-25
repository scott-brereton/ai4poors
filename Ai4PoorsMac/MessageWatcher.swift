// MessageWatcher.swift
// Ai4PoorsMac - Watches chat.db for new incoming messages
//
// Uses DispatchSource file monitoring on chat.db-wal for real-time detection,
// with a 10-second polling fallback. Collects messages per-sender within a
// configurable window, then analyzes the full burst together.

import Foundation
import Combine
import UserNotifications
import AppKit

// MARK: - Message Content Classification

enum MessageContentType {
    case text                    // Normal text, analyze as usual
    case textWithURLs            // Text containing URLs, analyze normally
    case urlOnly(String)         // Just a URL, note what it links to
    case attachmentOnly(String)  // Just attachment(s), description of what was sent
    case mixed                   // Text + attachments
}

// Pre-compiled regexes — avoid per-call compilation
private let tapbackRegex = try? NSRegularExpression(
    pattern: #"^(Loved|Liked|Disliked|Laughed at|Emphasized|Questioned)\s+(an?\s+\w+$|[\u{201c}"])"#,
    options: .caseInsensitive
)
private let urlOnlyRegex = try? NSRegularExpression(
    pattern: #"^https?://\S+$"#
)

@MainActor
final class MessageWatcher: ObservableObject {

    struct AnalyzedMessage: Identifiable {
        let id: Int64
        let sender: String
        let messageCount: Int
        let messagePreview: String
        let result: String
        let model: String
        let timestamp: Date
        let messageDate: Date
    }

    // MARK: - Published State

    @Published var isMonitoring = false
    @Published var isPaused = false
    @Published var recentResults: [AnalyzedMessage] = []
    @Published var isAnalyzing = false

    // MARK: - Internal State

    /// Persisted high-water mark. In-memory copy avoids UserDefaults read races.
    private var lastProcessedRowID: Int64 = 0 {
        didSet { UserDefaults.standard.set(Int(lastProcessedRowID), forKey: "lastProcessedRowID") }
    }

    /// Per-sender message buffer: collects messages during the summary window.
    private var pendingMessages: [String: [ChatMessage]] = [:]

    /// Per-sender flush timer: fires when the summary window expires.
    private var flushTimers: [String: Task<Void, Never>] = [:]

    /// Message ROWIDs we've already buffered, to prevent re-buffering on rapid DispatchSource fires.
    private var bufferedRowIDs: Set<Int64> = []

    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var pollingTimer: Timer?
    private var walFileDescriptor: Int32 = -1
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    /// User-configurable summary window in seconds.
    var summaryWindow: TimeInterval {
        AppGroupConstants.summaryWindowSeconds
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Restore persisted ROWID
        let persisted = UserDefaults.standard.integer(forKey: "lastProcessedRowID")
        lastProcessedRowID = persisted != 0 ? Int64(persisted) : ChatDBReader.currentMaxRowID()

        setupFileMonitor()
        setupPollingFallback()
        setupSleepWakeHandling()
        isMonitoring = true
        isPaused = false
        print("[Ai4PoorsMac] Monitoring started from ROWID \(lastProcessedRowID), window \(summaryWindow)s")
    }

    func stopMonitoring() {
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
        pollingTimer?.invalidate()
        pollingTimer = nil
        if walFileDescriptor >= 0 {
            close(walFileDescriptor)
            walFileDescriptor = -1
        }
        removeSleepWakeHandling()
        // Cancel all pending flush timers
        for (_, task) in flushTimers { task.cancel() }
        flushTimers.removeAll()
        pendingMessages.removeAll()
        isMonitoring = false
        print("[Ai4PoorsMac] Monitoring stopped")
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            print("[Ai4PoorsMac] Monitoring paused")
        } else {
            print("[Ai4PoorsMac] Monitoring resumed")
            checkForNewMessages(source: "resume")
        }
    }

    // MARK: - File Monitoring

    private func setupFileMonitor() {
        let walPath = FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Messages/chat.db-wal"

        walFileDescriptor = open(walPath, O_EVTONLY)
        guard walFileDescriptor >= 0 else {
            print("[Ai4PoorsMac] Cannot open WAL file for monitoring — relying on polling")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: walFileDescriptor,
            eventMask: [.write, .extend],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.checkForNewMessages(source: "file-monitor")
            }
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.walFileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        source.resume()
        fileMonitorSource = source
    }

    private func setupPollingFallback() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForNewMessages(source: "polling")
            }
        }
    }

    // MARK: - Sleep / Wake Handling

    private func setupSleepWakeHandling() {
        let ws = NSWorkspace.shared.notificationCenter

        wakeObserver = ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWake()
            }
        }

        sleepObserver = ws.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSleep()
            }
        }
    }

    private func removeSleepWakeHandling() {
        let ws = NSWorkspace.shared.notificationCenter
        if let obs = wakeObserver { ws.removeObserver(obs); wakeObserver = nil }
        if let obs = sleepObserver { ws.removeObserver(obs); sleepObserver = nil }
    }

    private func handleSleep() {
        guard isMonitoring else { return }
        print("[Ai4PoorsMac] System going to sleep")

        // Pause to prevent processing during sleep transition
        isPaused = true

        // Roll back persisted ROWID to before any un-analyzed pending messages
        // so they'll be re-fetched and re-processed on wake
        let allPendingIDs = pendingMessages.values.flatMap { $0 }.map(\.id)
        if let minID = allPendingIDs.min() {
            let safeID = minID - 1
            UserDefaults.standard.set(Int(safeID), forKey: "lastProcessedRowID")
            print("[Ai4PoorsMac] Rolled back persisted ROWID to \(safeID) (\(allPendingIDs.count) pending message(s) preserved)")
        }

        // Clear in-memory buffers — they'll be re-fetched on wake
        for (_, task) in flushTimers { task.cancel() }
        flushTimers.removeAll()
        pendingMessages.removeAll()
        bufferedRowIDs.removeAll()
    }

    private func handleWake() {
        guard isMonitoring else { return }
        print("[Ai4PoorsMac] System woke from sleep")

        // Restore persisted ROWID (may have been rolled back in handleSleep)
        let persisted = UserDefaults.standard.integer(forKey: "lastProcessedRowID")
        if persisted != 0 {
            lastProcessedRowID = Int64(persisted)
        }

        // Re-setup file monitor with fresh file descriptor
        fileMonitorSource?.cancel()
        if walFileDescriptor >= 0 {
            close(walFileDescriptor)
            walFileDescriptor = -1
        }
        setupFileMonitor()

        // Resume and immediately check for messages that arrived during sleep
        isPaused = false
        checkForNewMessages(source: "wake")
    }

    // MARK: - Message Collection

    private func checkForNewMessages(source: String = "direct") {
        guard !isPaused else { return }
        guard ChatDBReader.canAccessDatabase else { return }

        let newMessages = ChatDBReader.fetchNewMessages(after: lastProcessedRowID)
        guard !newMessages.isEmpty else { return }

        print("[Ai4PoorsMac] Found \(newMessages.count) new message(s) via \(source)")

        if let maxID = newMessages.map(\.id).max() {
            lastProcessedRowID = maxID
        }

        // Filter out non-analyzable messages before buffering
        let analyzable = newMessages.filter { Self.isAnalyzable($0) }
        guard !analyzable.isEmpty else { return }

        // Buffer messages per conversation, skipping any we've already seen.
        // Group chats: group by chatID so multiple senders are analyzed together.
        // 1-on-1: group by senderID as before.
        for msg in analyzable {
            guard !bufferedRowIDs.contains(msg.id) else { continue }
            bufferedRowIDs.insert(msg.id)
            let key = conversationKey(for: msg)
            pendingMessages[key, default: []].append(msg)
            scheduleFlush(for: key)
        }

        // Keep bufferedRowIDs bounded
        if bufferedRowIDs.count > 500 {
            bufferedRowIDs = Set(bufferedRowIDs.sorted().suffix(200))
        }
    }

    /// Returns a grouping key: chatID for group chats, senderID for 1-on-1.
    private func conversationKey(for msg: ChatMessage) -> String {
        if let chat = msg.chat, chat.isGroup {
            return "group:\(chat.chatID)"
        }
        return msg.senderID
    }

    // MARK: - Message Filtering

    /// Returns true if the message contains analyzable content.
    private static func isAnalyzable(_ message: ChatMessage) -> Bool {
        // Always keep messages with attachments (we want to note "they sent an image")
        if !message.attachments.isEmpty { return true }

        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty or whitespace-only
        if text.isEmpty { return false }

        // Only Unicode replacement character(s) (U+FFFC)
        if text.allSatisfy({ $0 == "\u{FFFC}" }) { return false }

        // Only a blob: or data: URI with no human-readable content
        if text.hasPrefix("blob:") || text.hasPrefix("data:") { return false }

        // iMessage tapback system messages (e.g., "Loved an image", "Liked an image")
        if let regex = tapbackRegex,
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return false
        }

        // Keep messages that contain a real URL
        if text.contains("http://") || text.contains("https://") { return true }

        return true
    }

    /// Starts (or restarts) the flush timer for a conversation.
    /// Each new message resets the clock — the window slides until messages stop.
    private func scheduleFlush(for key: String) {
        flushTimers[key]?.cancel()

        let window = summaryWindow
        flushTimers[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled else { return }
            await self?.flushConversation(key)
        }
    }

    /// Flush: take all buffered messages for this conversation and analyze them together.
    private func flushConversation(_ key: String) {
        guard let messages = pendingMessages.removeValue(forKey: key),
              !messages.isEmpty else { return }
        flushTimers.removeValue(forKey: key)

        Task {
            await analyzeBurst(conversationKey: key, messages: messages)
        }
    }

    // MARK: - Analysis

    // MARK: - Content Classification

    /// Classifies a single message based on its text and attachments.
    private func classifyMessage(_ message: ChatMessage) -> MessageContentType {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachments = !message.attachments.isEmpty
        let hasMeaningfulText = !text.isEmpty
            && !text.allSatisfy({ $0 == "\u{FFFC}" })
            && !text.hasPrefix("blob:")
            && !text.hasPrefix("data:")

        // Has attachments but no meaningful text → describe all attachments
        if hasAttachments && !hasMeaningfulText {
            return .attachmentOnly(describeAttachments(message.attachments))
        }

        // Has attachments AND meaningful text
        if hasAttachments && hasMeaningfulText {
            return .mixed
        }

        // Text only: check if it's just a URL
        if let regex = urlOnlyRegex,
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return .urlOnly(text)
        }

        // Text contains URLs mixed with other content
        if text.contains("http://") || text.contains("https://") {
            return .textWithURLs
        }

        return .text
    }

    /// Builds a human-readable description of attachments.
    private func describeAttachments(_ attachments: [MessageAttachment]) -> String {
        let images = attachments.filter { $0.mimeType.hasPrefix("image/") }.count
        let videos = attachments.filter { $0.mimeType.hasPrefix("video/") }.count
        let others = attachments.filter { !$0.mimeType.hasPrefix("image/") && !$0.mimeType.hasPrefix("video/") }

        var parts: [String] = []
        if images > 0 { parts.append(images == 1 ? "an image" : "\(images) images") }
        if videos > 0 { parts.append(videos == 1 ? "a video" : "\(videos) videos") }
        for file in others { parts.append(file.filename) }
        return parts.joined(separator: " and ")
    }

    /// Builds a human-readable description for a single message based on its classification.
    private func describeMessage(_ message: ChatMessage) -> String {
        switch classifyMessage(message) {
        case .text, .textWithURLs:
            return message.text
        case .urlOnly(let url):
            return "[Sent a link: \(url)]"
        case .attachmentOnly(let description):
            return "[Sent \(description)]"
        case .mixed:
            let attachDesc = describeAttachments(message.attachments)
            return "\(message.text)\n[Also sent \(attachDesc)]"
        }
    }

    /// Returns true if any message in the burst has non-text content (attachments, URLs only, etc.).
    private func burstHasNonTextContent(_ messages: [ChatMessage]) -> Bool {
        for msg in messages {
            switch classifyMessage(msg) {
            case .text, .textWithURLs:
                continue
            default:
                return true
            }
        }
        return false
    }

    private func analyzeBurst(conversationKey key: String, messages: [ChatMessage]) async {
        // Log detection delay — helps diagnose sleep/wake timing issues
        if let oldestDate = messages.map(\.date).min() {
            let delaySec = Int(Date().timeIntervalSince(oldestDate))
            if delaySec > 60 {
                print("[Ai4PoorsMac] Detection delay: \(delaySec)s (\(delaySec / 60)m) for \(messages.count) message(s) — oldest from \(oldestDate)")
            }
        }

        // Determine if this is a group chat
        let isGroup = messages.first?.chat?.isGroup ?? false
        let groupName = messages.first?.chat?.groupName

        // Resolve sender names
        let uniqueSenderIDs = Set(messages.map(\.senderID))
        let senderNames: [String: String] = uniqueSenderIDs.reduce(into: [:]) { dict, id in
            dict[id] = ChatDBReader.contactName(for: id) ?? id
        }

        // Display name for notifications: group name or sender name
        let displayName: String
        if isGroup {
            displayName = groupName ?? senderNames.values.sorted().joined(separator: ", ")
        } else {
            displayName = senderNames.values.first ?? key
        }

        // Build the text with content-aware descriptions.
        // For group chats, prefix each message with the sender name.
        let combinedText: String
        let preview: String

        if messages.count == 1 {
            let desc = describeMessage(messages[0])
            if isGroup {
                let name = senderNames[messages[0].senderID] ?? messages[0].senderID
                combinedText = "\(name): \(desc)"
            } else {
                combinedText = desc
            }
            preview = String(combinedText.prefix(100))
        } else {
            combinedText = messages.map { msg in
                let desc = describeMessage(msg)
                if isGroup {
                    let name = senderNames[msg.senderID] ?? msg.senderID
                    return "\(name): \(desc)"
                }
                return desc
            }.joined(separator: "\n")
            preview = "\(messages.count) messages: " + String(combinedText.prefix(80))
        }

        // Triage: ask a fast model if this burst warrants full analysis
        let shouldAnalyze: Bool
        do {
            shouldAnalyze = try await OpenRouterService.shared.triageMessages(text: combinedText)
        } catch {
            // If triage fails, analyze anyway — don't miss important messages
            shouldAnalyze = true
            print("[Ai4PoorsMac] Triage failed, defaulting to analyze: \(error)")
        }

        guard shouldAnalyze else {
            print("[Ai4PoorsMac] Triage: skipping trivial message(s) from \(displayName)")
            return
        }

        // Past triage — this burst is worth analyzing
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Build instruction
        let instruction: String
        let hasNonText = burstHasNonTextContent(messages)
        let today = OpenRouterService.todayString

        if isGroup {
            let participantList = senderNames.values.sorted().joined(separator: ", ")
            if messages.count == 1 {
                let name = senderNames[messages[0].senderID] ?? messages[0].senderID
                let groupLabel = groupName.map { "in your '\($0)' group chat" } ?? "in a group chat"
                instruction = "\(name) just texted \(groupLabel). Today is \(today). What's the gist? Be natural — like you're telling a friend. One or two sentences, no bullet points, no labels."
            } else {
                let groupLabel = groupName.map { "your '\($0)' group chat" } ?? "a group chat"
                instruction = "There are \(messages.count) new messages in \(groupLabel) from \(participantList). Today is \(today). What are they talking about? Summarize the conversation naturally — like you're telling a friend what the group chat is saying. A couple sentences max, no bullet points, no labels.\(hasNonText ? " Some messages are images or links you can't see — just note what was sent." : "")"
            }
        } else if messages.count == 1 {
            let classification = classifyMessage(messages[0])
            switch classification {
            case .text, .textWithURLs:
                instruction = "\(displayName) just texted you. Today is \(today). What's the gist? Be natural — like you're telling a friend what the text says. One or two sentences, no bullet points, no labels."
            case .urlOnly:
                instruction = "\(displayName) just sent you a link. Today is \(today). Briefly note what the URL suggests it links to. One sentence, no bullet points, no labels."
            case .attachmentOnly:
                instruction = "\(displayName) just sent you something. Today is \(today). Briefly note what they sent. One sentence, no bullet points, no labels."
            case .mixed:
                instruction = "\(displayName) just texted you with an attachment. Today is \(today). What's the gist? Note both the text and the attachment. Be natural — one or two sentences, no bullet points, no labels."
            }
        } else {
            instruction = "\(displayName) just sent you \(messages.count) texts in a row. Today is \(today). What are they saying? Give the overall gist naturally — like you're telling a friend. A couple sentences max, no bullet points, no labels.\(hasNonText ? " Some messages are images or links you can't see — just note what was sent." : "")"
        }

        do {
            let result = try await OpenRouterService.shared.analyzeText(
                text: combinedText,
                instruction: instruction
            )

            let model = OpenRouterService.routeModel(for: instruction)
            let lastMessage = messages.last!
            let primarySenderID = uniqueSenderIDs.first ?? key

            let analyzed = AnalyzedMessage(
                id: lastMessage.id,
                sender: displayName,
                messageCount: messages.count,
                messagePreview: preview,
                result: result,
                model: model,
                timestamp: Date(),
                messageDate: lastMessage.date
            )

            recentResults.insert(analyzed, at: 0)
            if recentResults.count > 50 {
                recentResults = Array(recentResults.prefix(50))
            }

            HistoryService.save(
                channel: .message,
                action: .custom,
                inputPreview: "[\(displayName)] \(preview)",
                result: result,
                model: model,
                customInstruction: instruction
            )

            await postNotification(
                sender: displayName,
                messageCount: messages.count,
                result: result
            )

            await CloudKitSyncService.shared.pushAnalysis(
                id: UUID(),
                messageDate: lastMessage.date,
                sender: displayName,
                senderID: primarySenderID,
                messagePreview: String(combinedText.prefix(200)),
                result: result,
                model: model
            )

            print("[Ai4PoorsMac] Analyzed \(messages.count) message(s) from \(displayName)")
        } catch {
            print("[Ai4PoorsMac] Analysis failed for \(displayName): \(error)")
        }
    }

    private func postNotification(sender: String, messageCount: Int, result: String) async {
        let content = UNMutableNotificationContent()
        content.title = messageCount > 1
            ? "\(sender) (\(messageCount) messages)"
            : "Message from \(sender)"
        content.body = result
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
