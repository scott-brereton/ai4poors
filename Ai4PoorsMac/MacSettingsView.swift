// MacSettingsView.swift
// Ai4PoorsMac - Settings window
//
// API key input, model selection, Full Disk Access instructions.

import SwiftUI
import Contacts

struct MacSettingsView: View {
    @EnvironmentObject var watcher: MessageWatcher
    @EnvironmentObject var macState: MacAppState

    @State private var apiKey: String = AppGroupConstants.apiKey
    @State private var selectedModel: String = AppGroupConstants.preferredModel
    @State private var temperature: Double = AppGroupConstants.temperature
    @State private var maxTokens: Int = AppGroupConstants.maxTokens
    @State private var summaryWindow: Double = AppGroupConstants.summaryWindowSeconds
    @State private var monitoringEnabled: Bool = true
    @State private var contactsGranted: Bool = CNContactStore.authorizationStatus(for: .contacts) == .authorized

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 480, height: 400)
        .padding()
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("API Configuration") {
                SecureField("OpenRouter API Key", text: $apiKey)
                    .onChange(of: apiKey) { _, newValue in
                        AppGroupConstants.apiKey = newValue
                        macState.refreshStatus()
                    }

                Picker("Model", selection: $selectedModel) {
                    ForEach(AIModel.allModels) { model in
                        Text("\(model.displayName) (\(model.provider))")
                            .tag(model.id)
                    }
                }
                .onChange(of: selectedModel) { _, newValue in
                    AppGroupConstants.preferredModel = newValue
                }
            }

            Section("Analysis") {
                HStack {
                    Text("Temperature: \(temperature, specifier: "%.1f")")
                    Slider(value: $temperature, in: 0...1, step: 0.1)
                }
                .onChange(of: temperature) { _, newValue in
                    AppGroupConstants.temperature = newValue
                }

                Stepper("Max Tokens: \(maxTokens)", value: $maxTokens, in: 500...8000, step: 500)
                    .onChange(of: maxTokens) { _, newValue in
                        AppGroupConstants.maxTokens = newValue
                    }
            }

            Section("Monitoring") {
                Toggle("Enable message monitoring", isOn: $monitoringEnabled)
                    .onChange(of: monitoringEnabled) { _, newValue in
                        if newValue {
                            watcher.startMonitoring()
                        } else {
                            watcher.stopMonitoring()
                        }
                    }

                VStack(alignment: .leading) {
                    Text("Summary window: \(Int(summaryWindow))s")
                    Slider(value: $summaryWindow, in: 5...60, step: 5)
                }
                .onChange(of: summaryWindow) { _, newValue in
                    AppGroupConstants.summaryWindowSeconds = newValue
                }

                Text("When a message arrives, Ai4Poors waits this long for more messages from the same sender before analyzing. Longer windows catch full conversations; shorter windows give faster notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        Form {
            Section("Full Disk Access") {
                HStack {
                    Image(systemName: ChatDBReader.canAccessDatabase ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ChatDBReader.canAccessDatabase ? .green : .red)
                    Text(ChatDBReader.canAccessDatabase ? "Full Disk Access granted" : "Full Disk Access required")
                        .fontWeight(.medium)
                }

                if !ChatDBReader.canAccessDatabase {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ai4PoorsMac needs Full Disk Access to read your Messages database.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Text("How to grant access:")
                            .font(.callout)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: 4) {
                            instructionStep(1, "Open System Settings")
                            instructionStep(2, "Go to Privacy & Security > Full Disk Access")
                            instructionStep(3, "Click the + button")
                            instructionStep(4, "Find and select Ai4PoorsMac")
                            instructionStep(5, "Restart Ai4PoorsMac")
                        }

                        Button("Open Privacy & Security Settings") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section("Contacts") {
                HStack {
                    Image(systemName: contactsGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(contactsGranted ? .green : .red)
                    Text(contactsGranted ? "Contacts access granted" : "Contacts access needed")
                        .fontWeight(.medium)
                }

                if !contactsGranted {
                    Text("Allows Ai4PoorsMac to show sender names instead of phone numbers.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button("Grant Contacts Access") {
                        CNContactStore().requestAccess(for: .contacts) { granted, _ in
                            DispatchQueue.main.async { contactsGranted = granted }
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open Contacts Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")!
                        )
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
            }

            Section("iCloud") {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("iCloud sync enabled")
                }

                Text("Message analyses are synced to your iOS Ai4Poors app via CloudKit private database. Only accessible with your Apple ID.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func instructionStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .font(.callout)
        }
    }
}
