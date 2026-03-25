// Ai4PoorsApp.swift
// Ai4Poors - Main app entry point
//
// System-wide AI layer for iOS. Settings hub, history viewer,
// and onboarding for keyboard, Safari extension, and screenshot pipeline.

import SwiftUI
import SwiftData
import UserNotifications
import CloudKit

@main
struct Ai4PoorsApp: App {
    @UIApplicationDelegateAdaptor(Ai4PoorsAppDelegate.self) var appDelegate
    @StateObject private var appState = Ai4PoorsAppState()
    @StateObject private var cloudKitReceiver = CloudKitReceiver.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([AnalysisRecord.self])

        // Use shared App Group container for SwiftData
        let config: ModelConfiguration
        if let containerURL = AppGroupConstants.sharedContainerURL {
            config = ModelConfiguration(
                "Ai4PoorsHistory",
                schema: schema,
                url: containerURL.appendingPathComponent("ai4poors_history.sqlite"),
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        }

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
                .onOpenURL(perform: handleDeepLink)
                .onAppear {
                    cloudKitReceiver.setup()
                }
                .overlay {
                    // PiP host view — invisible, must be in the view hierarchy
                    PiPHostView()
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "ai4poors" else { return }

        switch url.host {
        case "result":
            // ai4poors://result?id=<uuid>
            if let id = url.queryValue(for: "id") {
                appState.selectedResultID = id
                appState.selectedTab = .history
            }
        case "analyze":
            // ai4poors://analyze?text=<encoded>&action=<action>
            if let text = url.queryValue(for: "text"),
               let action = url.queryValue(for: "action") {
                appState.pendingAnalysis = PendingAnalysis(text: text, action: action)
                appState.selectedTab = .home
            }
        case "settings":
            appState.selectedTab = .settings
        case "history":
            appState.selectedTab = .history
        case "read":
            // ai4poors://read?url=<encoded_url>
            if let articleURL = url.queryValue(for: "url") {
                appState.pendingReaderURL = articleURL
                appState.selectedTab = .home
            }
        case "captures", "search", "photos":
            appState.selectedTab = .search
        case "voice":
            appState.selectedTab = .voice
        default:
            break
        }
    }
}

// MARK: - PiP Host View (bridges ClipboardMonitor's UIView into SwiftUI)

struct PiPHostView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        ClipboardMonitor.shared.hostView
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - URL Query Helpers

extension URL {
    func queryValue(for key: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == key })?
            .value
    }
}

// MARK: - Content View (Tab Navigation)

struct ContentView: View {
    @EnvironmentObject var appState: Ai4PoorsAppState

    var body: some View {
        Group {
            if !appState.isOnboardingCompleted {
                OnboardingView()
            } else {
                mainTabView
            }
        }
    }

    private var mainTabView: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(AppTab.home)

            VoiceView()
                .tabItem {
                    Label("Voice", systemImage: "waveform")
                }
                .tag(AppTab.voice)

            CaptureSearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(AppTab.search)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(AppTab.history)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .tint(.blue)
    }
}

// MARK: - App Delegate (Notification Setup)

class Ai4PoorsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        application.registerForRemoteNotifications()

        // Run capture maintenance in background
        Task.detached(priority: .utility) {
            await CaptureMaintenanceService.shared.runMaintenance()
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("[Ai4Poors] Registered for remote notifications")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Ai4Poors] Failed to register for remote notifications: \(error)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // CloudKit silent push — fetch changes
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
           notification.subscriptionID == "ai4poors-zone-changes" {
            Task { @MainActor in
                await CloudKitReceiver.shared.fetchChanges()
                completionHandler(.newData)
            }
        } else {
            completionHandler(.noData)
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error {
                print("[Ai4Poors] Notification permission error: \(error)")
            }
        }
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle notification tap — open result
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let result = response.notification.request.content.userInfo["result"] as? String {
            NotificationCenter.default.post(
                name: .ai4poorsShowResult,
                object: result
            )
        }
        completionHandler()
    }
}

// ai4poorsShowResult moved to Shared/Models.swift
