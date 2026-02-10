# Macroid

WiFi clipboard sync between Mac and Android. Dead simple.

Copy text on Mac → appears on Android. Copy on Android → appears on Mac. No cloud, no accounts, no internet. Just two devices on the same WiFi.

## Download

Grab the latest release from [GitHub Releases](../../releases):
- **Macroid-debug.apk** — Android (install directly)
- **Macroid.dmg** — macOS (drag to Applications)

## How it works

1. Both devices discover each other via **UDP multicast** (same protocol as [LocalSend](https://github.com/localsend/localsend))
2. Each device runs a tiny HTTP server on port `53317` (with fallback to `53318`/`53319`)
3. Tap **Paste** to send your clipboard to the other device, or type directly in the editor
4. Received text and images appear instantly — tap images to copy them
5. Failed sends retry automatically with exponential backoff

## Features

- **Manual send** — tap Paste to send clipboard content (text or images), no auto-sync surprises
- **Clipboard history** — last 20 items, tap to restore
- **Image sync** — send and receive images between devices
- **Auto-discovery** — UDP multicast with fallback subnet scan and port fallback
- **In-app debug logs** — dedicated Logs tab for troubleshooting connection issues
- **Retry with backoff** — 3 attempts with exponential backoff on failure
- **Request validation** — 1MB text limit, 10MB image limit, origin checks
- **Light/dark mode** — follows system preference on both platforms
- **LocalSend compatible** — uses the same discovery protocol as [LocalSend](https://github.com/localsend/localsend)

## UI

One screen. Three tabs: **Editor**, **History**, **Logs**. A **Paste** button to send clipboard. A status bar showing connection state. Light/dark mode.

## Build

### Android

```bash
cd android
./gradlew assembleDebug
# APK at: app/build/outputs/apk/debug/app-debug.apk
```

Requires: JDK 17+, Android SDK 34

### macOS

Open `mac/Macroid/Macroid.xcodeproj` in Xcode, hit Build (Cmd+B).

Or from terminal:
```bash
cd mac/Macroid
xcodebuild -scheme Macroid -configuration Release
```

Requires: Xcode 15+, macOS 13+

## CI/CD

GitHub Actions builds both platforms automatically:
- **Build Android APK** — on every push to `main` or `claude/*`
- **Build macOS App** — on every push to `main` or `claude/*`
- **Release** — on tag push (`v*`) or manual trigger, creates GitHub Release with APK + DMG

## Architecture

```
Mac (SwiftUI)                    Android (Compose)
┌──────────────┐                 ┌──────────────┐
│ SyncServer   │◄── WiFi UDP ──►│ SyncServer   │
│ SyncClient   │   Discovery     │ SyncClient   │
│ Discovery    │◄── HTTP ──────►│ Discovery    │
│ SyncManager  │  /api/clipboard │ MacroidApp   │
│ AppLog       │   + origin ID   │ AppLog       │
└──────────────┘                 └──────────────┘
```

**Discovery:** UDP multicast on `224.0.0.167:53317` (LocalSend compatible)
**Sync:** `POST /api/clipboard` with `{"text": "...", "timestamp": ..., "origin": "<fingerprint>"}`
**Images:** `POST /api/clipboard/image` with base64-encoded image data
**Health:** `GET /api/ping` returns `pong`
**Device Info:** `GET /api/localsend/v2/info` returns device metadata

## Sync Protocol

Each device generates a unique fingerprint at startup. Every clipboard update includes:
- `text` — the clipboard content
- `timestamp` — milliseconds since epoch (for ordering)
- `origin` — the sender's fingerprint (for loop prevention)

The receiver ignores updates where `origin` matches its own fingerprint, preventing infinite sync loops.

## Tech Stack

| | Mac | Android |
|---|---|---|
| Language | Swift 5.9 | Kotlin |
| UI | SwiftUI | Jetpack Compose |
| HTTP Server | NWListener (Network.framework) | Ktor (Netty) |
| HTTP Client | NWConnection (Network.framework) | OkHttp |
| Discovery | NWConnectionGroup (multicast) | MulticastSocket |
| Clipboard | NSPasteboard (manual send) | ClipboardManager (manual send) |
| Logging | AppLog + os.log | AppLog + android.util.Log |
| Min target | macOS 13 | Android 8 (API 26) |

## License

MIT
