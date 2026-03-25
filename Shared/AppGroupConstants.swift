// AppGroupConstants.swift
// Ai4Poors - Shared constants for App Group communication
//
// All extensions and the main app share the same App Group
// for settings, API keys, and history storage.

import Foundation

enum AppGroupConstants {
    static let suiteName = "group.com.example.ai4poors"

    // MARK: - UserDefaults Keys

    enum Keys {
        static let apiKey = "openrouter_api_key"
        static let preferredModel = "preferred_model"
        static let preferredLanguage = "preferred_language"
        static let historyEnabled = "history_enabled"
        static let streamingEnabled = "streaming_enabled"
        static let hapticFeedbackEnabled = "haptic_feedback_enabled"
        static let maxTokens = "max_tokens"
        static let temperature = "temperature"
        static let lastUsedChannel = "last_used_channel"
        static let totalCallCount = "total_call_count"
        static let onboardingCompleted = "onboarding_completed"
        static let keyboardEnabled = "keyboard_enabled"
        static let safariExtensionEnabled = "safari_extension_enabled"
        static let screenshotPipelineEnabled = "screenshot_pipeline_enabled"
        static let toolUseEnabled = "tool_use_enabled"
        static let clipboardMonitorEnabled = "clipboard_monitor_enabled"
        static let screenCaptureEnabled = "screen_capture_enabled"
        static let captureSampleInterval = "capture_sample_interval"
        static let summaryWindowSeconds = "summary_window_seconds"
        static let crawl4aiAPIKey = "crawl4ai_api_key"
        static let approvedReaderDomains = "approved_reader_domains"
        static let voiceDoubleTapMode = "voice_double_tap_mode"
        static let voiceTripleTapMode = "voice_triple_tap_mode"
    }

    // MARK: - Defaults

    enum Defaults {
        static let maxTokens = 2000
        static let temperature: Double = 0.3
        static let preferredModel = "anthropic/claude-sonnet-4.6"
        static let preferredLanguage = "French"
        static let historyEnabled = true
        static let streamingEnabled = true
        static let hapticFeedbackEnabled = true
        static let summaryWindowSeconds: Double = 15
    }

    // MARK: - Shared UserDefaults

    #if os(macOS)
    static var sharedDefaults: UserDefaults? {
        UserDefaults.standard
    }
    #else
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
    #endif

    // MARK: - Shared Container URL (for SwiftData / file storage)

    #if os(macOS)
    static var sharedContainerURL: URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let cortexDir = appSupport?.appendingPathComponent("Ai4PoorsMac", isDirectory: true)
        if let dir = cortexDir, !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return cortexDir
    }
    #else
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }
    #endif

    // MARK: - Convenience Accessors

    #if os(macOS)
    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: Keys.apiKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.apiKey) }
    }
    #else
    static var apiKey: String {
        get { sharedDefaults?.string(forKey: Keys.apiKey) ?? "" }
        set { sharedDefaults?.set(newValue, forKey: Keys.apiKey) }
    }
    #endif

    static var isAPIKeyConfigured: Bool {
        !apiKey.isEmpty
    }

    static var preferredModel: String {
        get { sharedDefaults?.string(forKey: Keys.preferredModel) ?? Defaults.preferredModel }
        set { sharedDefaults?.set(newValue, forKey: Keys.preferredModel) }
    }

    static var preferredLanguage: String {
        get { sharedDefaults?.string(forKey: Keys.preferredLanguage) ?? Defaults.preferredLanguage }
        set { sharedDefaults?.set(newValue, forKey: Keys.preferredLanguage) }
    }

    static var maxTokens: Int {
        get {
            let val = sharedDefaults?.integer(forKey: Keys.maxTokens) ?? 0
            return val > 0 ? val : Defaults.maxTokens
        }
        set { sharedDefaults?.set(newValue, forKey: Keys.maxTokens) }
    }

    static var temperature: Double {
        get {
            guard sharedDefaults?.object(forKey: Keys.temperature) != nil else { return Defaults.temperature }
            return sharedDefaults?.double(forKey: Keys.temperature) ?? Defaults.temperature
        }
        set { sharedDefaults?.set(newValue, forKey: Keys.temperature) }
    }

    static var isHistoryEnabled: Bool {
        get { sharedDefaults?.object(forKey: Keys.historyEnabled) != nil ? sharedDefaults!.bool(forKey: Keys.historyEnabled) : Defaults.historyEnabled }
        set { sharedDefaults?.set(newValue, forKey: Keys.historyEnabled) }
    }

    static var isStreamingEnabled: Bool {
        get { sharedDefaults?.object(forKey: Keys.streamingEnabled) != nil ? sharedDefaults!.bool(forKey: Keys.streamingEnabled) : Defaults.streamingEnabled }
        set { sharedDefaults?.set(newValue, forKey: Keys.streamingEnabled) }
    }

    static var isHapticFeedbackEnabled: Bool {
        get { sharedDefaults?.object(forKey: Keys.hapticFeedbackEnabled) != nil ? sharedDefaults!.bool(forKey: Keys.hapticFeedbackEnabled) : Defaults.hapticFeedbackEnabled }
        set { sharedDefaults?.set(newValue, forKey: Keys.hapticFeedbackEnabled) }
    }

    static var isToolUseEnabled: Bool {
        get { sharedDefaults?.object(forKey: Keys.toolUseEnabled) != nil ? sharedDefaults!.bool(forKey: Keys.toolUseEnabled) : false }
        set { sharedDefaults?.set(newValue, forKey: Keys.toolUseEnabled) }
    }

    static var isClipboardMonitorEnabled: Bool {
        get { sharedDefaults?.object(forKey: Keys.clipboardMonitorEnabled) != nil ? sharedDefaults!.bool(forKey: Keys.clipboardMonitorEnabled) : false }
        set { sharedDefaults?.set(newValue, forKey: Keys.clipboardMonitorEnabled) }
    }

    static var isScreenCaptureEnabled: Bool {
        get { sharedDefaults?.object(forKey: Keys.screenCaptureEnabled) != nil ? sharedDefaults!.bool(forKey: Keys.screenCaptureEnabled) : false }
        set { sharedDefaults?.set(newValue, forKey: Keys.screenCaptureEnabled) }
    }

    /// Capture sample interval in seconds (default 10)
    static var captureSampleInterval: Double {
        get {
            let val = sharedDefaults?.double(forKey: Keys.captureSampleInterval) ?? 0
            return val > 0 ? val : 10.0
        }
        set { sharedDefaults?.set(newValue, forKey: Keys.captureSampleInterval) }
    }

    static var summaryWindowSeconds: Double {
        get {
            guard sharedDefaults?.object(forKey: Keys.summaryWindowSeconds) != nil else { return Defaults.summaryWindowSeconds }
            return sharedDefaults?.double(forKey: Keys.summaryWindowSeconds) ?? Defaults.summaryWindowSeconds
        }
        set { sharedDefaults?.set(newValue, forKey: Keys.summaryWindowSeconds) }
    }

    static var isOnboardingCompleted: Bool {
        get { sharedDefaults?.bool(forKey: Keys.onboardingCompleted) ?? false }
        set { sharedDefaults?.set(newValue, forKey: Keys.onboardingCompleted) }
    }

    static func incrementCallCount() {
        let current = sharedDefaults?.integer(forKey: Keys.totalCallCount) ?? 0
        sharedDefaults?.set(current + 1, forKey: Keys.totalCallCount)
    }

    static var totalCallCount: Int {
        sharedDefaults?.integer(forKey: Keys.totalCallCount) ?? 0
    }

    // MARK: - Token Usage Tracking

    static func addTokenUsage(prompt: Int, completion: Int) {
        let currentPrompt = sharedDefaults?.integer(forKey: "total_prompt_tokens") ?? 0
        let currentCompletion = sharedDefaults?.integer(forKey: "total_completion_tokens") ?? 0
        sharedDefaults?.set(currentPrompt + prompt, forKey: "total_prompt_tokens")
        sharedDefaults?.set(currentCompletion + completion, forKey: "total_completion_tokens")
    }

    static var totalPromptTokens: Int {
        sharedDefaults?.integer(forKey: "total_prompt_tokens") ?? 0
    }

    static var totalCompletionTokens: Int {
        sharedDefaults?.integer(forKey: "total_completion_tokens") ?? 0
    }

    static var totalTokens: Int {
        totalPromptTokens + totalCompletionTokens
    }

    static var estimatedCost: Double {
        // Rough average across models: ~$0.005 per 1k tokens
        Double(totalTokens) / 1000.0 * 0.005
    }

    // MARK: - Voice Back Tap

    /// Returns the TranscriptionMode for double-tap, or nil if disabled.
    static var voiceDoubleTapMode: String {
        get { sharedDefaults?.string(forKey: Keys.voiceDoubleTapMode) ?? "" }
        set { sharedDefaults?.set(newValue, forKey: Keys.voiceDoubleTapMode) }
    }

    /// Returns the TranscriptionMode for triple-tap, or nil if disabled.
    static var voiceTripleTapMode: String {
        get { sharedDefaults?.string(forKey: Keys.voiceTripleTapMode) ?? "plain" }
        set { sharedDefaults?.set(newValue, forKey: Keys.voiceTripleTapMode) }
    }

    // MARK: - Crawl4AI

    #if os(macOS)
    static var crawl4aiAPIKey: String {
        get { UserDefaults.standard.string(forKey: Keys.crawl4aiAPIKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.crawl4aiAPIKey) }
    }
    #else
    static var crawl4aiAPIKey: String {
        get { sharedDefaults?.string(forKey: Keys.crawl4aiAPIKey) ?? "" }
        set { sharedDefaults?.set(newValue, forKey: Keys.crawl4aiAPIKey) }
    }
    #endif

    static var isCrawl4AIConfigured: Bool {
        !crawl4aiAPIKey.isEmpty
    }

    // MARK: - Approved Reader Domains

    static var approvedReaderDomains: Set<String> {
        get {
            let array = sharedDefaults?.stringArray(forKey: Keys.approvedReaderDomains) ?? []
            return Set(array)
        }
        set {
            sharedDefaults?.set(Array(newValue), forKey: Keys.approvedReaderDomains)
        }
    }

    static func addApprovedReaderDomain(_ domain: String) {
        var domains = approvedReaderDomains
        domains.insert(domain.lowercased())
        approvedReaderDomains = domains
    }

    static func isApprovedReaderDomain(_ domain: String) -> Bool {
        approvedReaderDomains.contains(domain.lowercased())
    }

    // MARK: - Last Reader Result Cache (cross-process handoff)

    /// Stash the last reader result so the app can pick it up instantly via deep link.
    static func cacheReaderResult(url: String, title: String, markdown: String) {
        sharedDefaults?.set(url, forKey: "reader_cache_url")
        sharedDefaults?.set(title, forKey: "reader_cache_title")
        sharedDefaults?.set(markdown, forKey: "reader_cache_markdown")
    }

    /// Retrieve the cached reader result if the URL matches.
    static func cachedReaderResult(for url: String) -> (title: String, markdown: String)? {
        guard sharedDefaults?.string(forKey: "reader_cache_url") == url,
              let title = sharedDefaults?.string(forKey: "reader_cache_title"),
              let markdown = sharedDefaults?.string(forKey: "reader_cache_markdown"),
              !markdown.isEmpty else { return nil }
        return (title, markdown)
    }
}
