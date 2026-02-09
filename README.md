# Macroid

WiFi clipboard sync between Mac and Android. Dead simple.

Copy text on Mac → appears on Android. Copy on Android → appears on Mac. No cloud, no accounts, no internet. Just two devices on the same WiFi.

## Download

Grab the latest release from [GitHub Releases](../../releases):
- **Macroid-debug.apk** — Android (install directly)
- **Macroid.dmg** — macOS (drag to Applications)

## How it works

1. Both devices discover each other via **UDP multicast** (same protocol as [LocalSend](https://github.com/localsend/localsend))
2. Each device runs a tiny HTTP server on port `53317`
3. When your clipboard changes, it's instantly pushed to the other device
4. Origin-based deduplication prevents sync loops
5. Failed sends retry automatically with exponential backoff

## Features

- **Instant sync** — clipboard changes pushed in real-time over local WiFi
- **Clipboard history** — last 20 items, tap to restore
- **Background sync** — Android foreground service keeps sync alive
- **Auto-discovery** — UDP multicast with fallback subnet scan
- **Sync loop prevention** — origin fingerprint tracking prevents echo
- **Retry with backoff** — 3 attempts with exponential backoff on failure
- **Structured logging** — full debug logs via `android.util.Log` / `os.log`
- **Request validation** — 1MB size limit, origin checks, timestamp ordering
- **Light/dark mode** — follows system preference on both platforms

## UI

Simplenote-style. One screen. One text area. A status bar. History panel. Light/dark mode. Nothing else.

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
- **Release** — on push to main/claude branches or manual trigger, creates GitHub Release with APK + DMG

## Architecture

```
Mac (SwiftUI)                    Android (Compose)
┌──────────────┐                 ┌──────────────┐
│ ClipboardMon │◄── WiFi UDP ──►│ ClipboardMon │
│ SyncServer   │   Discovery     │ SyncServer   │
│ SyncClient   │◄── HTTP ──────►│ SyncClient   │
│ Discovery    │  /api/clipboard │ Discovery    │
│ SyncManager  │   + origin ID   │ MacroidApp   │
└──────────────┘                 └──────────────┘
```

**Discovery:** UDP multicast on `224.0.0.167:53317` (LocalSend compatible)
**Sync:** `POST /api/clipboard` with `{"text": "...", "timestamp": ..., "origin": "<fingerprint>"}`
**Health:** `GET /api/ping` returns `pong`

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
| HTTP Client | URLSession | OkHttp |
| Discovery | NWConnectionGroup (multicast) | MulticastSocket |
| Clipboard | NSPasteboard polling | ClipboardManager |
| Logging | os.log (Logger) | android.util.Log |
| Min target | macOS 13 | Android 8 (API 26) |

## License

MIT
