// SettingsView.swift
// Ai4Poors - App settings: API key, model preferences, channels

import SwiftUI

struct SettingsView: View {
    @State private var apiKey = AppGroupConstants.apiKey
    @State private var showAPIKey = false
    @State private var selectedModel = AppGroupConstants.preferredModel
    @State private var preferredLanguage = AppGroupConstants.preferredLanguage
    @State private var maxTokens = AppGroupConstants.maxTokens
    @State private var temperature = AppGroupConstants.temperature
    @State private var historyEnabled = AppGroupConstants.isHistoryEnabled
    @State private var streamingEnabled = AppGroupConstants.isStreamingEnabled
    @State private var hapticEnabled = AppGroupConstants.isHapticFeedbackEnabled
    @State private var toolUseEnabled = AppGroupConstants.isToolUseEnabled
    @State private var crawl4aiKey = AppGroupConstants.crawl4aiAPIKey
    @State private var showCrawl4AIKey = false
    @State private var showCrawl4AILog = false
    @StateObject private var clipboardMonitor = ClipboardMonitor.shared
    @State private var showResetAlert = false
    @State private var showAdvanced = false
    @StateObject private var photoScanner = PhotoScanner.shared

    var body: some View {
        NavigationStack {
            Form {
                apiKeySection
                crawl4aiKeySection
                modelSection
                preferencesSection
                backgroundSection
                photosSection
                channelSetupSection
                aboutSection
                dangerZone
            }
            .navigationTitle("Settings")
            .onChange(of: apiKey) { _, newValue in
                AppGroupConstants.apiKey = newValue
            }
            .onChange(of: selectedModel) { _, newValue in
                AppGroupConstants.preferredModel = newValue
            }
            .onChange(of: preferredLanguage) { _, newValue in
                AppGroupConstants.preferredLanguage = newValue
            }
            .onChange(of: maxTokens) { _, newValue in
                AppGroupConstants.maxTokens = newValue
            }
            .onChange(of: temperature) { _, newValue in
                AppGroupConstants.temperature = newValue
            }
            .onChange(of: historyEnabled) { _, newValue in
                AppGroupConstants.isHistoryEnabled = newValue
            }
            .onChange(of: streamingEnabled) { _, newValue in
                AppGroupConstants.isStreamingEnabled = newValue
            }
            .onChange(of: hapticEnabled) { _, newValue in
                AppGroupConstants.isHapticFeedbackEnabled = newValue
            }
            .onChange(of: toolUseEnabled) { _, newValue in
                AppGroupConstants.isToolUseEnabled = newValue
            }
            .onChange(of: crawl4aiKey) { _, newValue in
                AppGroupConstants.crawl4aiAPIKey = newValue
            }
        }
    }

    // MARK: - API Key

    private var apiKeySection: some View {
        Section {
            HStack {
                if showAPIKey {
                    TextField("sk-or-v1-...", text: $apiKey)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField("sk-or-v1-...", text: $apiKey)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Button {
                    showAPIKey.toggle()
                } label: {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showAPIKey ? "Hide API key" : "Show API key")
            }

            if apiKey.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Required. Get a key at openrouter.ai")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("API key configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("OpenRouter API Key")
        } footer: {
            Text("OpenRouter is a unified API gateway that gives Ai4Poors access to AI models from Anthropic, Google, and OpenAI through a single key. Your key is stored locally and shared with Ai4Poors extensions via App Group. It never leaves your device except to authenticate API requests.")
        }
    }

    // MARK: - Crawl4AI Key

    private var crawl4aiKeySection: some View {
        Section {
            HStack {
                if showCrawl4AIKey {
                    TextField("your-api-key", text: $crawl4aiKey)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField("your-api-key", text: $crawl4aiKey)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Button {
                    showCrawl4AIKey.toggle()
                } label: {
                    Image(systemName: showCrawl4AIKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showCrawl4AIKey ? "Hide API key" : "Show API key")
            }

            if crawl4aiKey.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Optional — enables Reader mode for articles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Reader mode enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                Crawl4AIDebugLogView()
            } label: {
                Label("Debug Log", systemImage: "doc.text.magnifyingglass")
            }
        } header: {
            Text("Crawl4AI (Reader)")
        } footer: {
            Text("Crawl4AI extracts clean article text from any URL. Powers the Reader action in Safari and in-app article reading. Your key is stored locally and never leaves your device except to authenticate requests.")
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        Section {
            Picker("Default Model", selection: $selectedModel) {
                ForEach(AIModel.allModels) { model in
                    Text("\(model.displayName) — $\(String(format: "%.3f", model.costPer1kTokens))/1k")
                        .tag(model.id)
                }
            }

            Picker("Translation Language", selection: $preferredLanguage) {
                ForEach(SupportedLanguages.all, id: \.self) {
                    Text($0).tag($0)
                }
            }
        } header: {
            Text("AI Model")
        } footer: {
            Text("Ai4Poors auto-routes for cost efficiency: quick tasks like summaries and translations use Gemini Flash (~$0.002/1k tokens), while complex tasks like replies, custom queries, and follow-ups use your selected default model. Vision tasks (photo indexing, screenshot analysis) use Gemini 3 Flash.")
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        Section {
            Toggle("Stream Responses", isOn: $streamingEnabled)
            Toggle("Save History", isOn: $historyEnabled)
            Toggle("Haptic Feedback", isOn: $hapticEnabled)

            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                Stepper("Max Tokens: \(maxTokens)", value: $maxTokens, in: 500...4000, step: 500)
                    .accessibilityValue("\(maxTokens) tokens")

                VStack(alignment: .leading) {
                    Text("Temperature: \(String(format: "%.1f", temperature))")
                        .font(.subheadline)
                    Slider(value: $temperature, in: 0...1, step: 0.1)
                        .accessibilityValue("\(String(format: "%.1f", temperature))")
                        .accessibilityLabel("Temperature")
                }

                Toggle("Smart Actions (Tool Use)", isOn: $toolUseEnabled)
            }
        } header: {
            Text("Preferences")
        } footer: {
            if showAdvanced {
                VStack(alignment: .leading, spacing: 4) {
                    if toolUseEnabled {
                        Text("Smart Actions lets the AI suggest copyable text, URLs, and other structured actions. Uses ~2x tokens.")
                    }
                    Text("Max Tokens controls response length. Temperature controls creativity (lower = focused, higher = varied).")
                }
            } else {
                Text("Streaming shows AI responses word-by-word as they generate.")
            }
        }
    }

    // MARK: - Clipboard Monitor

    private var backgroundSection: some View {
        Section {
            if clipboardMonitor.isMonitoring {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Clipboard Monitor Active")
                        .font(.subheadline)
                    Spacer()
                    Button("Stop") {
                        clipboardMonitor.stop()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
            } else {
                Button {
                    clipboardMonitor.start()
                } label: {
                    Label("Start Clipboard Monitor", systemImage: "pip")
                }
            }

            NavigationLink {
                ClipboardSetupGuide()
            } label: {
                Label("Setup Guide", systemImage: "questionmark.circle")
            }
        } header: {
            Text("Clipboard Monitor")
        } footer: {
            if clipboardMonitor.isMonitoring {
                Text("Ai4Poors is monitoring your clipboard via Picture-in-Picture. Copy text or images in any app — Ai4Poors will analyze and notify you instantly. Minimize the PiP window by swiping it to the screen edge.")
            } else {
                Text("Uses Picture-in-Picture to keep Ai4Poors alive in the background. Copy anything in any app and get an instant AI analysis notification.")
            }
        }
    }

    // MARK: - Photos

    private var photosSection: some View {
        Section {
            HStack {
                Text("Indexed Photos")
                Spacer()
                Text("\(photoScanner.indexedCount)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if photoScanner.isScanning {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning...")
                            .font(.subheadline)
                        Spacer()
                        Button("Stop") {
                            photoScanner.stopScan()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    }
                    ProgressView(
                        value: Double(photoScanner.scannedCount),
                        total: Double(max(photoScanner.totalToScan, 1))
                    )
                    Text("Indexed \(photoScanner.scannedCount)/\(photoScanner.totalToScan) photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task {
                        let granted = await photoScanner.requestPermission()
                        if granted {
                            photoScanner.startScan()
                        }
                    }
                } label: {
                    Label("Scan Photos", systemImage: "photo.badge.magnifyingglass")
                }
            }

            if let error = photoScanner.currentError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("Scan your recent photos to enable natural language search. Each photo is analyzed by AI and indexed locally. Processing is rate-limited to avoid API overuse.")
        }
    }

    // MARK: - Channel Setup

    private var channelSetupSection: some View {
        Section {
            NavigationLink {
                KeyboardSetupGuide()
            } label: {
                Label("Keyboard Setup", systemImage: "keyboard")
            }

            NavigationLink {
                SafariSetupGuide()
            } label: {
                Label("Safari Extension Setup", systemImage: "safari")
            }

            NavigationLink {
                ScreenshotSetupGuide()
            } label: {
                Label("Screenshot Pipeline Setup", systemImage: "camera.viewfinder")
            }

            NavigationLink {
                MessagesSetupGuide()
            } label: {
                Label("Messages Setup", systemImage: "message")
            }

            NavigationLink {
                VoiceSetupGuide()
            } label: {
                Label("Voice-to-Text Setup", systemImage: "waveform")
            }
        } header: {
            Text("Channel Setup Guides")
        } footer: {
            Text("Step-by-step guides for enabling each Ai4Poors extension on your device. Most extensions need to be turned on once in iOS Settings before they'll work.")
        }
    }

    // MARK: - About & Usage Stats

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Total Analyses")
                Spacer()
                Text("\(AppGroupConstants.totalCallCount)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack {
                Text("Total Tokens Used")
                Spacer()
                Text(formatTokenCount(AppGroupConstants.totalTokens))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack {
                Text("Prompt / Completion")
                Spacer()
                Text("\(formatTokenCount(AppGroupConstants.totalPromptTokens)) / \(formatTokenCount(AppGroupConstants.totalCompletionTokens))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack {
                Text("Estimated Cost")
                Spacer()
                Text("$\(String(format: "%.2f", AppGroupConstants.estimatedCost))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } header: {
            Text("Usage & Stats")
        } footer: {
            Text("Token usage and cost are tracked across all Ai4Poors channels and extensions. Estimated cost is calculated from each model's per-token pricing.")
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        Section {
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label("Reset All Settings", systemImage: "arrow.counterclockwise")
            }
            .alert("Reset All Settings?", isPresented: $showResetAlert) {
                Button("Reset", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear your API key, preferences, and history. This cannot be undone.")
            }
        } header: {
            Text("Reset")
        }
    }

    private func resetAll() {
        apiKey = ""
        selectedModel = AppGroupConstants.Defaults.preferredModel
        preferredLanguage = AppGroupConstants.Defaults.preferredLanguage
        maxTokens = AppGroupConstants.Defaults.maxTokens
        temperature = AppGroupConstants.Defaults.temperature
        historyEnabled = AppGroupConstants.Defaults.historyEnabled
        streamingEnabled = AppGroupConstants.Defaults.streamingEnabled
        hapticEnabled = AppGroupConstants.Defaults.hapticFeedbackEnabled
        toolUseEnabled = false
        crawl4aiKey = ""

        ClipboardMonitor.shared.stop()

        AppGroupConstants.apiKey = ""
        AppGroupConstants.crawl4aiAPIKey = ""
        AppGroupConstants.approvedReaderDomains = []
        AppGroupConstants.isOnboardingCompleted = false
    }
}

// MARK: - Setup Guides

struct KeyboardSetupGuide: View {
    var body: some View {
        List {
            Section {
                SetupStep(number: 1, text: "Open Settings app")
                SetupStep(number: 2, text: "Go to General > Keyboard > Keyboards")
                SetupStep(number: 3, text: "Tap \"Add New Keyboard...\"")
                SetupStep(number: 4, text: "Select \"Ai4Poors AI\" from the list")
                SetupStep(number: 5, text: "Tap \"Ai4Poors AI\" again and enable \"Allow Full Access\"")
                SetupStep(number: 6, text: "Full Access is required for AI features (network requests)")
            } header: {
                Text("Enable Ai4Poors Keyboard")
            }

            Section {
                SetupStep(number: 1, text: "Open any app with a text field (Mail, Notes, Messages)")
                SetupStep(number: 2, text: "Tap the globe icon (🌐) on your keyboard")
                SetupStep(number: 3, text: "Select \"Ai4Poors AI\"")
                SetupStep(number: 4, text: "Use the action buttons or type a custom instruction")
                SetupStep(number: 5, text: "Tap \"Insert\" to place the AI result in the text field")
            } header: {
                Text("Using the Keyboard")
            }
        }
        .navigationTitle("Keyboard Setup")
    }
}

struct SafariSetupGuide: View {
    var body: some View {
        List {
            Section {
                SetupStep(number: 1, text: "Open Settings app")
                SetupStep(number: 2, text: "Scroll down to Safari")
                SetupStep(number: 3, text: "Tap Extensions")
                SetupStep(number: 4, text: "Find and enable \"Ai4Poors AI\"")
                SetupStep(number: 5, text: "Set permission to \"Allow\" for all websites (or specific ones)")
            } header: {
                Text("Enable Safari Extension")
            }

            Section {
                SetupStep(number: 1, text: "Open Safari and navigate to any page")
                SetupStep(number: 2, text: "Tap the floating ✦ button in the bottom-right")
                SetupStep(number: 3, text: "Choose an action or type a custom question")
                SetupStep(number: 4, text: "Results appear inline — tap Copy to use them")
            } header: {
                Text("Using the Extension")
            }
        }
        .navigationTitle("Safari Setup")
    }
}

struct ScreenshotSetupGuide: View {
    var body: some View {
        List {
            Section {
                SetupStep(number: 1, text: "Open the Shortcuts app")
                SetupStep(number: 2, text: "Create a new shortcut")
                SetupStep(number: 3, text: "Add \"Take Screenshot\" action")
                SetupStep(number: 4, text: "Add \"Analyze with Ai4Poors\" action")
                SetupStep(number: 5, text: "Save the shortcut")
            } header: {
                Text("Create Screenshot Shortcut")
            }

            Section {
                Text("Assign your shortcut to any of these triggers:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SetupStep(number: 1, text: "AssistiveTouch (Settings > Accessibility > Touch)")
                SetupStep(number: 2, text: "Back Tap (Settings > Accessibility > Touch > Back Tap)")
                SetupStep(number: 3, text: "Action Button (iPhone 15 Pro+)")
                SetupStep(number: 4, text: "Control Center Widget (iOS 18+)")
            } header: {
                Text("Trigger Options")
            }
        }
        .navigationTitle("Screenshot Setup")
    }
}

struct ClipboardSetupGuide: View {
    var body: some View {
        List {
            Section {
                SetupStep(number: 1, text: "Open the Settings app on your iPhone")
                SetupStep(number: 2, text: "Scroll down and tap \"Ai4Poors\"")
                SetupStep(number: 3, text: "Tap \"Paste from Other Apps\"")
                SetupStep(number: 4, text: "Select \"Allow\"")
            } header: {
                Text("Allow Paste (Recommended)")
            } footer: {
                Text("This lets Ai4Poors read your clipboard silently without showing a permission prompt every time you copy something. Without this, iOS will ask \"Allow Paste?\" each time.")
            }

            Section {
                SetupStep(number: 1, text: "Open Ai4Poors and go to Settings")
                SetupStep(number: 2, text: "Tap \"Start Clipboard Monitor\" — a small PiP window appears")
                SetupStep(number: 3, text: "Swipe the PiP window to the edge of the screen to minimize it")
                SetupStep(number: 4, text: "Switch to any app and copy text or an image")
                SetupStep(number: 5, text: "You'll get a notification with the AI analysis within seconds")
            } header: {
                Text("Using the Clipboard Monitor")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Text over 10 characters is analyzed", systemImage: "doc.text")
                        .font(.subheadline)
                    Label("Copied images are described by AI", systemImage: "photo")
                        .font(.subheadline)
                    Label("Results appear as notifications and save to History", systemImage: "bell.badge")
                        .font(.subheadline)
                    Label("Tap a notification to see the full result in Ai4Poors", systemImage: "hand.tap")
                        .font(.subheadline)
                }
            } header: {
                Text("What Gets Analyzed")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The clipboard monitor uses Picture-in-Picture to keep Ai4Poors alive when you switch apps. This is the same technology used by video apps — iOS keeps the app running so it can monitor your clipboard in real time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("If PiP stops (e.g., you close the PiP window), monitoring stops. Just re-enable it from Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("How It Works")
            }
        }
        .navigationTitle("Clipboard Setup")
    }
}

struct MessagesSetupGuide: View {
    @State private var showLegacyShortcuts = false

    var body: some View {
        List {
            // MARK: - How it works overview
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "desktopcomputer")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ai4PoorsMac")
                                .font(.subheadline.weight(.semibold))
                            Text("Menu bar app on your Mac")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    flowArrow("iMessage arrives on Mac")
                    flowArrow("Ai4PoorsMac detects it in chat.db")
                    flowArrow("AI analyzes the message via OpenRouter")
                    flowArrow("Result syncs to this iPhone via iCloud")

                    HStack(spacing: 12) {
                        Image(systemName: "iphone")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ai4Poors iOS")
                                .font(.subheadline.weight(.semibold))
                            Text("Receives analysis in History")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("How It Works")
            } footer: {
                Text("Ai4PoorsMac reads your Messages database directly on your Mac — no Shortcuts, no automations, no fragile triggers. Results sync via CloudKit private database (your iCloud account only, no servers).")
            }

            // MARK: - Mac setup
            Section {
                SetupStep(number: 1, text: "Build and run the Ai4PoorsMac scheme in Xcode on your Mac")
                SetupStep(number: 2, text: "Ai4PoorsMac appears as a brain icon in your menu bar")
                SetupStep(number: 3, text: "Click the icon and open Settings")
                SetupStep(number: 4, text: "Enter your OpenRouter API key")
                SetupStep(number: 5, text: "Grant Full Disk Access: System Settings > Privacy & Security > Full Disk Access > add Ai4PoorsMac")
                SetupStep(number: 6, text: "Restart Ai4PoorsMac — the status dot turns green when monitoring")
            } header: {
                Text("Set Up Ai4PoorsMac")
            } footer: {
                Text("Full Disk Access lets Ai4PoorsMac read ~/Library/Messages/chat.db. Your API key is stored locally on the Mac — it is not synced to iCloud or shared with the iOS app.")
            }

            // MARK: - iOS side
            Section {
                SetupStep(number: 1, text: "Make sure you're signed into the same Apple ID on both devices")
                SetupStep(number: 2, text: "Open Ai4Poors on your iPhone — that's it")
                Text("Ai4Poors iOS automatically subscribes to CloudKit changes. When Ai4PoorsMac pushes a new analysis, your iPhone receives a silent push notification, fetches the record, and saves it to History.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("iOS Setup")
            }

            // MARK: - What you'll see
            Section {
                Label("Notification with sender name and AI summary", systemImage: "bell.badge")
                    .font(.subheadline)
                Label("Analysis appears in History tab under \"Messages\" channel", systemImage: "clock")
                    .font(.subheadline)
                Label("Same sender debounced for 30 seconds (no spam)", systemImage: "timer")
                    .font(.subheadline)
                Label("Works for all incoming iMessages — not just contacts", systemImage: "message")
                    .font(.subheadline)
            } header: {
                Text("What to Expect")
            }

            // MARK: - Security
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("CloudKit private database — only your Apple ID can access it", systemImage: "lock.shield")
                        .font(.subheadline)
                    Label("No intermediate server — Mac pushes directly to iCloud", systemImage: "arrow.right.circle")
                        .font(.subheadline)
                    Label("Message text is sent to OpenRouter for analysis (same as all Ai4Poors features)", systemImage: "network")
                        .font(.subheadline)
                    Label("API key stays on each device — never synced", systemImage: "key")
                        .font(.subheadline)
                }
            } header: {
                Text("Privacy & Security")
            }

            // MARK: - Legacy Shortcuts method
            Section {
                Button {
                    withAnimation { showLegacyShortcuts.toggle() }
                } label: {
                    HStack {
                        Label("Shortcuts Automation (Legacy)", systemImage: "arrow.triangle.branch")
                        Spacer()
                        Image(systemName: showLegacyShortcuts ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)

                if showLegacyShortcuts {
                    Text("If you don't have a Mac or prefer the on-device approach, you can still use the original Shortcuts automation. It's more fragile but works without a Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    NavigationLink("Shortcuts Setup Guide") {
                        LegacyMessageShortcutsGuide()
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Alternative Method")
            }
        }
        .navigationTitle("Messages Setup")
    }

    private func flowArrow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 36)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct LegacyMessageShortcutsGuide: View {
    var body: some View {
        List {
            Section {
                SetupStep(number: 1, text: "Open the Shortcuts app")
                SetupStep(number: 2, text: "Tap Automation at the bottom")
                SetupStep(number: 3, text: "Tap + to create a new automation")
                SetupStep(number: 4, text: "Select \"Message\" as the trigger")
                SetupStep(number: 5, text: "Choose sender: Anyone (or specific contacts)")
                SetupStep(number: 6, text: "Under \"Message Contains\", type a single space character")
                SetupStep(number: 7, text: "Set to \"Run Immediately\" and turn off \"Notify When Run\"")
            } header: {
                Text("Create the Automation")
            }

            Section {
                SetupStep(number: 1, text: "Add \"Receive messages as input\" (search \"Shortcut Input\")")
                SetupStep(number: 2, text: "Add \"Get Text from Input\"")
                SetupStep(number: 3, text: "Add \"Find Contacts\" with filter: Phone is Sender (optional)")
                SetupStep(number: 4, text: "Add \"Analyze Message with Ai4Poors\"")
                SetupStep(number: 5, text: "Connect the Text and Contacts variables to the Ai4Poors action")
                SetupStep(number: 6, text: "Save")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Receive messages as input")
                    Text("  > Get text from Shortcut Input")
                    Text("  > Find Contacts where Phone is Sender")
                    Text("  > Analyze message from [Contacts] : [Text]")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            } header: {
                Text("Actions")
            }

            Section {
                Text("Messages under 30 characters are skipped. Same sender is debounced for 30 seconds. iOS may briefly show a \"Running\" banner — this cannot be fully suppressed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notes")
            }
        }
        .navigationTitle("Shortcuts Setup")
    }
}

struct Crawl4AIDebugLogView: View {
    @State private var logText = ""
    @State private var copied = false

    var body: some View {
        ScrollView {
            Text(logText)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Crawl4AI Log")
        .onAppear { logText = Crawl4AIClient.readDebugLog() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = logText
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }

                    Button {
                        Crawl4AIClient.clearDebugLog()
                        logText = "(cleared)"
                    } label: {
                        Image(systemName: "trash")
                    }

                    Button {
                        logText = Crawl4AIClient.readDebugLog()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

struct SetupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.blue)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
        }
    }
}
