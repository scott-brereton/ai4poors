// Project.swift
// Ai4Poors - Xcode Project Configuration Reference
//
// This file documents the Xcode project structure and build settings.
// Use this as a reference when setting up the .xcodeproj.
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │                      AI4POORS PROJECT TARGETS                       │
// ├─────────────────────────────────────────────────────────────────────┤
// │                                                                     │
// │  1. Ai4Poors (Main App)                                               │
// │     Bundle ID: com.example.ai4poors                                  │
// │     Platform: iOS 17.0+                                             │
// │     Frameworks: SwiftUI, SwiftData, ActivityKit, AppIntents         │
// │     Dependencies: WhisperKit (SPM)                                  │
// │     Entitlements: App Group, iCloud (CloudKit),                     │
// │       aps-environment, BackgroundModes (processing, audio,          │
// │       remote-notification), NSSupportsLiveActivities                │
// │     Sources: Ai4Poors/**, Shared/**                                   │
// │                                                                     │
// │  2. Ai4PoorsKeyboard (Keyboard Extension)                             │
// │     Bundle ID: com.example.ai4poors.keyboard                         │
// │     Platform: iOS 17.0+                                             │
// │     Frameworks: SwiftUI, UIKit                                      │
// │     Entitlements: App Group                                         │
// │     Sources: Ai4PoorsKeyboard/**, Shared/**                           │
// │     Memory Limit: ~70MB                                             │
// │                                                                     │
// │  3. Ai4PoorsSafari (Safari Web Extension)                             │
// │     Bundle ID: com.example.ai4poors.safari                           │
// │     Platform: iOS 17.0+                                             │
// │     Frameworks: SafariServices                                      │
// │     Entitlements: App Group                                         │
// │     Sources: Ai4PoorsSafari/**, Shared/**                             │
// │     Resources: Ai4PoorsSafari/Resources/**                            │
// │                                                                     │
// │  4. Ai4PoorsWidgets (Widget Extension)                                │
// │     Bundle ID: com.example.ai4poors.widgets                          │
// │     Platform: iOS 17.0+                                             │
// │     Frameworks: WidgetKit, SwiftUI, ActivityKit                     │
// │     Entitlements: App Group                                         │
// │     Sources: Ai4PoorsWidgets/**, Shared/**                            │
// │                                                                     │
// │  5. Ai4PoorsShareExtension (Share Extension)                          │
// │     Bundle ID: com.example.ai4poors.share                            │
// │     Platform: iOS 17.0+                                             │
// │     Frameworks: SwiftUI, UIKit, UniformTypeIdentifiers              │
// │     Entitlements: App Group                                         │
// │     Sources: Ai4PoorsShareExtension/**, Shared/**                     │
// │                                                                     │
// │  6. Ai4PoorsBroadcast (Screen Recording Extension)                    │
// │     Bundle ID: com.example.ai4poors.broadcast                        │
// │     Platform: iOS 17.0+                                             │
// │     Frameworks: ReplayKit                                           │
// │     Entitlements: App Group                                         │
// │     Sources: Ai4PoorsBroadcast/**, Shared/**                          │
// │                                                                     │
// │  7. Ai4PoorsMac (macOS Menu Bar App)                                  │
// │     Bundle ID: com.example.ai4poors.mac                              │
// │     Platform: macOS 14.0+                                           │
// │     Frameworks: SwiftUI, CloudKit, SQLite3                          │
// │     Entitlements: App Group, iCloud (CloudKit),                     │
// │       Full Disk Access                                              │
// │       (com.apple.security.files.user-selected.read-write)           │
// │     Sources: Ai4PoorsMac/**, Shared/**                                │
// │     Note: Reads ~/Library/Messages/chat.db for iMessage monitoring  │
// │                                                                     │
// ├─────────────────────────────────────────────────────────────────────┤
// │                      SHARED APP GROUP                               │
// │                                                                     │
// │  Group ID: group.com.example.ai4poors                                │
// │  iCloud Container: iCloud.com.example.ai4poors                       │
// │                                                                     │
// │  All 7 targets must include this App Group in their                 │
// │  entitlements to share:                                             │
// │    - API key (UserDefaults)                                         │
// │    - Settings/preferences (UserDefaults)                            │
// │    - Analysis history (SwiftData via shared container)              │
// │                                                                     │
// ├─────────────────────────────────────────────────────────────────────┤
// │                      BUILD SETTINGS                                 │
// │                                                                     │
// │  SWIFT_VERSION = 5.9                                                │
// │  IPHONEOS_DEPLOYMENT_TARGET = 17.0                                  │
// │  MACOSX_DEPLOYMENT_TARGET = 14.0                                    │
// │  PRODUCT_NAME = Ai4Poors                                              │
// │  DEVELOPMENT_TEAM = YOUR_TEAM_ID                                      │
// │  CODE_SIGN_STYLE = Automatic                                        │
// │  INFOPLIST_FILE = <target>/Info.plist                                │
// │  CODE_SIGN_ENTITLEMENTS = <target>/<target>.entitlements             │
// │                                                                     │
// └─────────────────────────────────────────────────────────────────────┘
//
// SETUP STEPS:
//
// 1. Open Xcode > New Project > App (iOS)
// 2. Set Product Name: "Ai4Poors", Bundle ID: "com.example.ai4poors"
// 3. Add targets:
//    - File > New > Target > Custom Keyboard Extension
//    - File > New > Target > Safari Web Extension
//    - File > New > Target > Widget Extension
//    - File > New > Target > Share Extension
//    - File > New > Target > Broadcast Upload Extension
//    - File > New > Target > macOS App (SwiftUI)
// 4. For each target:
//    - Add App Group capability: "group.com.example.ai4poors"
//    - Add Shared/ folder to target membership
// 5. For Ai4Poors (main app):
//    - Add iCloud capability with CloudKit (container: iCloud.com.example.ai4poors)
//    - Add Background Modes: processing, audio, remote-notification
//    - Enable NSSupportsLiveActivities in Info.plist
//    - Add WhisperKit package dependency via SPM
// 6. For Ai4PoorsKeyboard: Enable "RequestsOpenAccess" in Info.plist
// 7. For Ai4PoorsSafari: Add Resources folder to extension target
// 8. For Ai4PoorsMac: Add iCloud (CloudKit) and Full Disk Access entitlements
// 9. Build and run on device (extensions need real device for testing)
