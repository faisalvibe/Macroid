# Macroid

WiFi clipboard sync between Mac and Android. Dead simple.

Copy text on Mac → appears on Android. Copy on Android → appears on Mac. No cloud, no accounts, no internet. Just two devices on the same WiFi.

## How it works

1. Both devices discover each other via **UDP multicast** (same protocol as [LocalSend](https://github.com/localsend/localsend))
2. Each device runs a tiny HTTP server on port `53317`
3. When your clipboard changes, it's instantly pushed to the other device
4. That's it

## UI

Simplenote-style. One screen. One text area. A status bar. Light/dark mode. Nothing else.

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

## Architecture

```
Mac (SwiftUI)                    Android (Compose)
┌──────────────┐                 ┌──────────────┐
│ ClipboardMon │◄── WiFi UDP ──►│ ClipboardMon │
│ SyncServer   │   Discovery     │ SyncServer   │
│ SyncClient   │◄── HTTP ──────►│ SyncClient   │
│ Discovery    │  /api/clipboard │ Discovery    │
└──────────────┘                 └──────────────┘
```

**Discovery:** UDP multicast on `224.0.0.167:53317` (LocalSend compatible)
**Sync:** `POST /api/clipboard` with `{"text": "...", "timestamp": ...}`
**Health:** `GET /api/ping` returns `pong`

## Tech Stack

| | Mac | Android |
|---|---|---|
| Language | Swift 5.9 | Kotlin |
| UI | SwiftUI | Jetpack Compose |
| HTTP Server | NWListener (Network.framework) | Ktor (Netty) |
| HTTP Client | URLSession | OkHttp |
| Discovery | NWConnectionGroup (multicast) | MulticastSocket |
| Clipboard | NSPasteboard polling | ClipboardManager |
| Min target | macOS 13 | Android 8 (API 26) |

## License

MIT
