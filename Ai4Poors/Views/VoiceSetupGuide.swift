// VoiceSetupGuide.swift
// Ai4Poors - Setup guide for voice-to-text feature

#if os(iOS)
import SwiftUI

struct VoiceSetupGuide: View {
    var body: some View {
        List {
            // MARK: - Overview
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Speak anywhere, paste everywhere", systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                    Text("Ai4Poors uses on-device Whisper AI to transcribe your voice into text, copy it to your clipboard, and save it to searchable history. All processing happens on your iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Voice-to-Text")
            }

            // MARK: - Modes
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcribe")
                            .font(.subheadline.weight(.medium))
                        Text("Raw speech-to-text, copied to clipboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.purple)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Transcribe")
                            .font(.subheadline.weight(.medium))
                        Text("AI cleans up filler words, fixes punctuation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            } header: {
                Text("Two Modes")
            }

            // MARK: - Back Tap Setup
            Section {
                SetupStep(number: 1, text: "In Ai4Poors, go to the Voice tab and pick which mode you want for Double Tap and Triple Tap (or leave either as Off)")
                SetupStep(number: 2, text: "Open the Shortcuts app and create a new shortcut")
                SetupStep(number: 3, text: "Search for \"Ai4Poors\" and add \"Ai4Poors: Double Tap Voice\" or \"Ai4Poors: Triple Tap Voice\"")
                SetupStep(number: 4, text: "Name it and save")
                SetupStep(number: 5, text: "Go to Settings > Accessibility > Touch > Back Tap")
                SetupStep(number: 6, text: "Assign your shortcut to the matching tap (Double or Triple)")
            } header: {
                Text("Back Tap Setup")
            } footer: {
                Text("You can use either tap or both — just skip the ones you already have assigned to something else (like Screenshot).")
            }

            // MARK: - Control Center
            Section {
                SetupStep(number: 1, text: "Create a shortcut with \"Ai4Poors: Transcribe\" or \"Ai4Poors: Smart Transcribe\"")
                SetupStep(number: 2, text: "Open Control Center (swipe down from top-right)")
                SetupStep(number: 3, text: "Long-press to edit, tap + to add a control")
                SetupStep(number: 4, text: "Search for your shortcut and add it")
            } header: {
                Text("Control Center Button (iOS 18+)")
            } footer: {
                Text("One-tap from Control Center for voice transcription.")
            }

            // MARK: - First Use
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("First launch downloads the Whisper model (~600 MB)", systemImage: "arrow.down.circle")
                        .font(.subheadline)
                    Label("Model stays in memory for instant transcription", systemImage: "memorychip")
                        .font(.subheadline)
                    Label("Recording starts immediately, even during model load", systemImage: "bolt")
                        .font(.subheadline)
                    Label("Tap Stop when you're done speaking", systemImage: "stop.circle")
                        .font(.subheadline)
                    Label("Result is automatically copied to clipboard", systemImage: "doc.on.clipboard")
                        .font(.subheadline)
                }
            } header: {
                Text("How It Works")
            }

            // MARK: - Privacy
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Whisper runs 100% on-device via Apple Neural Engine", systemImage: "lock.shield")
                        .font(.subheadline)
                    Label("Audio is never sent to a server", systemImage: "iphone")
                        .font(.subheadline)
                    Label("Smart Transcription sends text (not audio) to OpenRouter for cleanup", systemImage: "network")
                        .font(.subheadline)
                    Label("Audio recordings stored locally, auto-pruned at 500 files", systemImage: "folder")
                        .font(.subheadline)
                }
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Voice Setup")
    }
}
#endif
