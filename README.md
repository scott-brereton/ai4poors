# Ai4Poors

<p align="center">
  <img src="assets/hero.png" alt="Ai4Poors — your cracked iPhone is smarter than you think" width="600"/>
</p>

<p align="center">
  <em>Apple Intelligence requires an iPhone 15 Pro or later. This app requires an iPhone. Any iPhone.</em>
</p>

<p align="center">
  <a href="#features">Features</a> · <a href="#how-it-works">How it works</a> · <a href="#installation">Installation</a> · <a href="#cost">Cost</a> · <a href="#architecture">Architecture</a> · <a href="#license">License</a>
</p>

---

## What is this

Apple Intelligence requires an iPhone 15 Pro. That's a thousand-dollar entrance fee to summarize a webpage. We thought that was stupid, so we built this instead.

Ai4Poors is an open-source iOS app that works on any iPhone running iOS 17+. The one in your pocket with the cracked screen and the battery that dies at 40%? That one works. It ships four extension targets (keyboard, Safari, share sheet, and screen broadcast) plus in-app clipboard monitoring and Live Activity on the Lock Screen — so you get AI practically everywhere.

It also transcribes speech on-device (nothing leaves your phone), searches your photo library by description ("the blurry one of my cat on the fridge"), and has a macOS companion that reads your iMessage conversations and syncs analysis back to your phone.

Everything runs through [OpenRouter](https://openrouter.ai). You pick the model, you pay per-token. No subscription. No company deciding you need to buy new hardware first.

## Features

### Six ways in

| Channel | What It Does |
|---------|-------------|
| **Keyboard** | AI toolbar in any text field. Reply, summarize, translate, improve, or ask whatever you want. Works in every app. |
| **Safari Extension** | Reads the full page DOM. Summarize articles, pull out key points, explain jargon, translate. |
| **Screen Capture** | Records your screen via ReplayKit, OCRs every frame, deduplicates with perceptual hashing, and indexes it all with FTS5. Searchable history of everything you've looked at. |
| **Share Extension** | Share text, URLs, or images from any app straight into analysis. |
| **Clipboard Monitor** | Sits in the background. When the clipboard changes, it runs analysis automatically. |
| **Live Activity** | Progress bar on Dynamic Island and the Lock Screen while analysis is running. |

### Voice transcription

Speech-to-text that runs on your phone's Neural Engine via WhisperKit. No audio goes anywhere.

- **Plain Transcribe** -- raw speech-to-text
- **Smart Transcribe** -- cleans up the transcript so it reads like actual sentences
- **Voice Command** -- treats what you said as an instruction and acts on it

### Photo search

Type "photos of my dog at the beach" instead of scrolling through 14,000 pictures. Gemini 3 Flash indexes your library with vision analysis. Simple queries hit a local string match first so they come back instantly.

### macOS companion

A menu bar app that reads your iMessage conversations straight from `chat.db`, runs them through AI, and syncs the results to your phone over CloudKit. You need macOS 14+ and Full Disk Access (so it can read the Messages database).

### Models

Six models, ranging from "practically free" to "I guess I'm not eating out this week":

| Model | Good For | Cost per 1K Tokens |
|-------|----------|-------------------|
| Claude Sonnet 4.6 | Deep analysis, complex reasoning (default) | $0.015 |
| Gemini 3 Flash | Fast summaries, photo indexing | $0.002 |
| GPT-5.4 Mini | Quick lightweight tasks | $0.003 |
| Claude Haiku 4.5 | Fast responses on a budget | $0.001 |
| Gemini 3.1 Flash Lite | Cheapest option | $0.001 |
| GPT-5.4 | Maximum capability | $0.030 |

## How it works

You sign up at [OpenRouter](https://openrouter.ai), load $5 of credits, paste your API key into the app, and pick a model. That's it. OpenRouter is a single gateway to Claude, Gemini, and GPT models, so you only need one account.

All the extensions (keyboard, Safari, share sheet, etc.) share state through an iOS App Group container. Your API key, preferences, and analysis history are available everywhere. Credentials for custom API skills go in the Keychain.

Screen captures live in a local SQLite database with FTS5 full-text search. Voice transcription runs on the Neural Engine through WhisperKit, fully offline.

The macOS companion syncs over CloudKit with a private database tied to your Apple ID. Nobody else can see it.

## Installation

### Requirements

- Xcode 16+ (Swift 5.9)
- iOS 17.0+ device (yes, your old one works)
- macOS 14.0+ for the companion app
- An Apple Developer account (free works for personal use, but extensions need a paid account for distribution)
- An [OpenRouter](https://openrouter.ai) account and API key

### Step 1: Clone and configure

```bash
git clone https://github.com/scott-brereton/ai4poors.git
cd ai4poors
```

Open `Ai4Poors.xcodeproj` in Xcode.

### Step 2: Set your identity

The project ships with placeholder bundle IDs (`com.example.ai4poors`). You need to replace these with your own Apple Developer account info. Two ways:

**Option A: Edit `project.yml` and regenerate (recommended if you have [xcodegen](https://github.com/yonaskolb/XcodeGen))**

1. Open `project.yml`
2. Change `bundleIdPrefix: com.example` to your own prefix (e.g., `com.yourname`)
3. Change `DEVELOPMENT_TEAM: YOUR_TEAM_ID` to your Apple Team ID
4. Run `xcodegen generate`

**Option B: Edit directly in Xcode**

1. Select the project in the navigator
2. For each target, go to **Signing & Capabilities**
3. Select your Development Team
4. Update the Bundle Identifier to use your own prefix

You must update the bundle identifier in **all seven targets**:

| Target | Default Bundle ID |
|--------|------------------|
| Ai4Poors | `com.example.ai4poors` |
| Ai4PoorsKeyboard | `com.example.ai4poors.keyboard` |
| Ai4PoorsSafari | `com.example.ai4poors.safari` |
| Ai4PoorsWidgets | `com.example.ai4poors.widgets` |
| Ai4PoorsShareExtension | `com.example.ai4poors.share` |
| Ai4PoorsBroadcast | `com.example.ai4poors.broadcast` |
| Ai4PoorsMac | `com.example.ai4poors.mac` |

Also update the App Group identifier in each target's entitlements file to match (e.g., `group.com.yourname.ai4poors`), and update the `suiteName` in `Shared/AppGroupConstants.swift`.

#### Additional identifiers to update

Beyond the bundle IDs above, the following hardcoded `com.example.ai4poors` references will cause runtime failures if not updated to match your own prefix:

| File | Value | What breaks |
|------|-------|-------------|
| `Ai4Poors/Info.plist` | `com.example.ai4poors.background-processing` | BGTaskScheduler won't fire |
| `Ai4Poors/Views/CaptureSearchView.swift:496` | `com.example.ai4poors.broadcast` | Screen capture won't find the extension |
| `Shared/KeychainService.swift` | `com.example.ai4poors.skills` | Keychain reads/writes fail |
| `Ai4PoorsWidgets/Ai4PoorsControlWidget.swift` | `com.example.ai4poors.control` | Control widget won't register |
| `Ai4PoorsMac/CloudKitSyncService.swift` | `iCloud.com.example.ai4poors` | CloudKit sync fails |
| `Ai4Poors/CloudKitReceiver.swift` | `iCloud.com.example.ai4poors` | CloudKit sync fails |
| Entitlements files (main app + Mac) | `iCloud.com.example.ai4poors` | iCloud container mismatch |

> **Note:** `DEVELOPMENT_TEAM` is set at the project level (not per-target), so changing it in `project.yml` or the project-level build settings is sufficient — you don't need to set it on each target individually.

> **Note:** The Ai4PoorsMac entitlements file declares an App Group, but App Groups are unused on macOS in this project. You don't need to update that entry.

### Step 3: Resolve dependencies

```bash
xcodebuild -resolvePackageDependencies -project Ai4Poors.xcodeproj
```

Or let Xcode do it automatically when you first open the project.

### Step 4: Build and run

1. Connect your iPhone
2. Select the **Ai4Poors** scheme and your device
3. Build and run (Cmd+R)

Extensions need a real device. The simulator can't run keyboard extensions, Safari extensions, or screen capture.

### Step 5: Enable extensions

iOS doesn't enable extensions automatically (thanks, Apple). You have to flip them on yourself:

- **Keyboard**: Settings > General > Keyboard > Keyboards > Add New Keyboard > Ai4Poors. Then tap Ai4Poors and enable "Allow Full Access."
- **Safari Extension**: Settings > Safari > Extensions > Ai4Poors > toggle on, set to "All Websites."
- **Share Extension**: Appears automatically in the share sheet.
- **Screen Capture**: Start from the app's home screen.

### Step 6: Enter your API key

Open the app, go to Settings, paste your OpenRouter API key.

If you want the article reader (pulls clean text from URLs), also add a Crawl4AI API key.

### macOS companion setup

1. Open `Ai4Poors.xcodeproj`, select the **Ai4PoorsMac** scheme
2. Build and run on your Mac
3. Grant Full Disk Access: System Settings > Privacy & Security > Full Disk Access > enable Ai4PoorsMac
4. Enter your OpenRouter API key in the menu bar popover
5. Sign into the same Apple ID on both your Mac and iPhone for CloudKit sync

## Project structure

```
├── Ai4Poors/                     # Main iOS app
│   ├── Views/                  # SwiftUI views (Home, Settings, History, etc.)
│   ├── State/                  # Observable app state
│   └── Intents/                # Siri Shortcuts
├── Ai4PoorsKeyboard/             # Custom keyboard extension
├── Ai4PoorsSafari/               # Safari web extension
│   └── Resources/              # JS content scripts, manifest
├── Ai4PoorsBroadcast/            # Screen recording (ReplayKit)
├── Ai4PoorsShareExtension/       # Share sheet extension
├── Ai4PoorsWidgets/              # Dynamic Island, Lock Screen, Control Center
├── Ai4PoorsMac/                  # macOS menu bar companion
└── Shared/                     # Code shared across all targets
    ├── OpenRouterService.swift # API layer
    ├── AppGroupConstants.swift # Settings & constants
    ├── ScreenCapture/          # OCR, FTS5, dedup pipeline
    └── VoiceTranscription/     # WhisperKit integration
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Ai4Poors                                    │
│                                                                      │
│  KEYBOARD ─┐                                                        │
│  SAFARI ───┤                                                        │
│  SCREEN ───┤── CORE ──── OpenRouter API ──── Claude / Gemini / GPT  │
│  SHARE ────┤     │                                                   │
│  CLIPBOARD ┤     ├── SwiftData (shared via App Group)               │
│  LIVE ACT ─┘     ├── WhisperKit (on-device voice)                   │
│                   └── Photo Scanner (AI vision)                      │
│                                                                      │
│                          CloudKit                                    │
│                            │                                         │
│                     macOS Companion                                  │
│                   (iMessage watcher)                                 │
└─────────────────────────────────────────────────────────────────────┘
```

## Cost

About $4-5/month if you use it ~24 times a day and let the app pick cheap models for quick stuff (Gemini Flash) and expensive ones for hard questions (Claude Sonnet). Use it less, pay less. Use only the cheapest model, pay almost nothing.

The app tracks your token usage and estimated spend in Settings so you don't get surprised.

You pay OpenRouter directly. There's no middleman and no subscription.

## Troubleshooting

**Keyboard doesn't show up**: You probably forgot to add it. Settings > General > Keyboard > Keyboards > Add New Keyboard > Ai4Poors. Then tap it and toggle "Allow Full Access."

**Safari extension does nothing**: Settings > Safari > Extensions > Ai4Poors AI. Toggle it on and set permission to "All Websites."

**Build blows up with SPM errors**: Run `xcodebuild -resolvePackageDependencies -project Ai4Poors.xcodeproj` and try again.

**Extensions can't find the API key**: Your App Group identifier has to match exactly across all seven targets and in `AppGroupConstants.swift`. If even one is off, the extensions can't read shared settings.

**macOS companion won't sync**: Both devices need the same Apple ID. Also check that the iCloud container identifier in the entitlements files matches.

## Development tools

If you use [Claude Code](https://claude.ai/claude-code) (or any AI coding assistant), these two tools will save you a lot of pain with this project:

**[XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP)** — MCP server that lets Claude build, run, test, and debug the app on simulators and devices directly from the terminal. With 7 targets and a bunch of extensions, being able to say "build and run on the simulator" instead of switching to Xcode is worth the 2-minute setup.

**[xcodegen](https://github.com/yonaskolb/XcodeGen)** — The Xcode project is generated from `project.yml`. Install it (`brew install xcodegen`) so you can add targets or change build settings in the YAML file and run `xcodegen generate` instead of hand-editing the pbxproj. Editing pbxproj files by hand will eventually ruin your day.

## Contributing

PRs welcome. If you add a new extension or input channel, wire it through the existing App Group so it can read the API key and shared settings.

## License

MIT
