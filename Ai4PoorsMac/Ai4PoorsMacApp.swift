// Ai4PoorsMacApp.swift
// Ai4PoorsMac - Menu bar companion app for iMessage analysis
//
// Reads chat.db, analyzes new messages via OpenRouter,
// and syncs results to iOS via CloudKit.

import SwiftUI
import UserNotifications

@main
struct Ai4PoorsMacApp: App {
    @StateObject private var messageWatcher = MessageWatcher()
    @StateObject private var macState = MacAppState()

    init() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { _, error in
            if let error {
                print("[Ai4PoorsMac] Notification permission error: \(error)")
            }
        }
        ChatDBReader.requestContactsAccess()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(messageWatcher)
                .environmentObject(macState)
                .onAppear {
                    // Ensure monitoring is running whenever panel opens
                    autoStartIfNeeded()
                }
        } label: {
            Image(systemName: macState.statusIcon)
                .onAppear {
                    // This fires once at app launch when the menu bar icon is created
                    autoStartIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView()
                .environmentObject(messageWatcher)
                .environmentObject(macState)
        }
    }

    private func autoStartIfNeeded() {
        macState.refreshStatus()
        if macState.status == .monitoring && !messageWatcher.isMonitoring {
            messageWatcher.startMonitoring()
        }
    }
}

// MARK: - Mac App State

@MainActor
final class MacAppState: ObservableObject {
    @Published var statusIcon: String = "brain"

    enum Status {
        case monitoring, noFullDiskAccess, noAPIKey, paused
    }

    @Published var status: Status = .monitoring {
        didSet { updateIcon() }
    }

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        if !AppGroupConstants.isAPIKeyConfigured {
            status = .noAPIKey
        } else if !ChatDBReader.canAccessDatabase {
            status = .noFullDiskAccess
        } else {
            status = .monitoring
        }
    }

    private func updateIcon() {
        switch status {
        case .monitoring: statusIcon = "brain"
        case .noFullDiskAccess: statusIcon = "exclamationmark.brain"
        case .noAPIKey: statusIcon = "brain"
        case .paused: statusIcon = "brain"
        }
    }
}
