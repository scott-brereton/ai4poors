// OnboardingView.swift
// Ai4Poors - First-launch setup wizard

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: Ai4PoorsAppState
    @State private var currentPage = 0
    @State private var apiKey = ""
    @State private var showAPIKeyField = false

    private let totalPages = 8

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                keyboardPage.tag(1)
                safariPage.tag(2)
                screenshotPage.tag(3)
                voicePage.tag(4)
                photoSearchPage.tag(5)
                shareExtensionPage.tag(6)
                apiKeyPage.tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Bottom controls
            VStack(spacing: 16) {
                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { page in
                        Circle()
                            .fill(page == currentPage ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(currentPage + 1) of \(totalPages)")

                // Navigation buttons
                HStack {
                    if currentPage > 0 {
                        Button("Back") {
                            withAnimation { currentPage -= 1 }
                        }
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if currentPage < totalPages - 1 {
                        Button {
                            withAnimation { currentPage += 1 }
                        } label: {
                            Text("Next")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            completeOnboarding()
                        } label: {
                            Text("Get Started")
                                .fontWeight(.semibold)
                                .frame(minWidth: 120)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.isEmpty)
                        .accessibilityHint(apiKey.isEmpty ? "Enter your API key above to continue" : "")
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        OnboardingPage(
            icon: "sparkle",
            iconColor: .blue,
            title: "Welcome to Ai4Poors",
            subtitle: "A system-wide AI layer for iOS",
            description: "Ai4Poors gives you AI superpowers in every app — through your keyboard, Safari, screenshots, voice, photo search, and more. No app-switching required."
        )
    }

    private var keyboardPage: some View {
        OnboardingPage(
            icon: "keyboard",
            iconColor: .blue,
            title: "AI Keyboard",
            subtitle: "In-App AI",
            description: "An AI toolbar that works in any text field. Reply to emails, summarize messages, translate text — all without leaving the app you're in.\n\nEnable it in Settings > General > Keyboard > Keyboards > Add New > Ai4Poors AI"
        )
    }

    private var safariPage: some View {
        OnboardingPage(
            icon: "safari",
            iconColor: .cyan,
            title: "Safari Extension",
            subtitle: "Web Analysis",
            description: "Analyze any web page with a single tap. Summarize articles, extract key points, translate content, or ask custom questions — all inline in Safari.\n\nEnable it in Settings > Safari > Extensions > Ai4Poors AI"
        )
    }

    private var screenshotPage: some View {
        OnboardingPage(
            icon: "camera.viewfinder",
            iconColor: .indigo,
            title: "Screenshot Pipeline",
            subtitle: "Visual Analysis",
            description: "For everything else — Settings screens, error dialogs, photos, any app. Trigger a capture via Back Tap, Action Button, or AssistiveTouch. AI analyzes the screenshot instantly."
        )
    }

    private var voicePage: some View {
        OnboardingPage(
            icon: "waveform",
            iconColor: .blue,
            title: "Voice Transcription",
            subtitle: "On-Device Speech-to-Text",
            description: "Record speech and get instant transcription — entirely on your device using WhisperKit. No audio is ever sent to a server.\n\nTwo modes: plain transcription and AI-cleaned text (removes filler words, fixes punctuation)."
        )
    }

    private var photoSearchPage: some View {
        OnboardingPage(
            icon: "photo.on.rectangle.angled",
            iconColor: .teal,
            title: "Photo Search",
            subtitle: "AI-Powered Photo Library",
            description: "Scan your photo library with AI vision to build a searchable index. Then find any photo by describing what's in it — people, places, objects, or text.\n\nIndexing runs in Settings and stays on-device. Search uses natural language."
        )
    }

    private var shareExtensionPage: some View {
        OnboardingPage(
            icon: "square.and.arrow.up",
            iconColor: .orange,
            title: "Share Extension",
            subtitle: "AI From Any App",
            description: "Select text, a URL, or an image in any app, tap Share, and choose Ai4Poors. Pick an analysis action and get results saved to your history — no app-switching required."
        )
    }

    private var apiKeyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)

            Text("API Key Setup")
                .font(.title.weight(.bold))

            Text("Ai4Poors uses OpenRouter to access AI models.\nYou need an API key to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                HStack {
                    if showAPIKeyField {
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
                        showAPIKeyField.toggle()
                    } label: {
                        Image(systemName: showAPIKeyField ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(showAPIKeyField ? "Hide API key" : "Show API key")
                }
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 32)

                Link("Get your key at openrouter.ai/keys", destination: URL(string: "https://openrouter.ai/keys")!)
                    .font(.caption)

                if !apiKey.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Key entered")
                            .font(.caption)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Completion

    private func completeOnboarding() {
        appState.completeOnboarding(apiKey: apiKey)
    }
}

// MARK: - Onboarding Page Template

struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 6) {
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .textCase(.uppercase)
                    .tracking(1)

                Text(title)
                    .font(.title.weight(.bold))
            }

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}
