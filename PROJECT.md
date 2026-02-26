# PROJECT.md — Macroid

## What It Is

WiFi clipboard sync between Mac and Android. Copy on one device, it appears on the other. No cloud, no accounts, no internet — just two devices on the same WiFi.

## Tech Stack

| | Mac | Android |
|---|---|---|
| Language | Swift 5.9 | Kotlin |
| UI | SwiftUI | Jetpack Compose |
| HTTP Server | NWListener (Network.framework) | Ktor (Netty) |
| HTTP Client | URLSession | OkHttp |
| Discovery | NWConnectionGroup (UDP multicast) | MulticastSocket |
| Clipboard | NSPasteboard polling | ClipboardManager |
| Logging | os.log (Logger) | android.util.Log |
| Min target | macOS 13 | Android 8 (API 26) |

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

- **Discovery:** UDP multicast on `224.0.0.167:53317` (LocalSend-compatible)
- **Sync:** `POST /api/clipboard` — `{"text": "...", "timestamp": ..., "origin": "<fingerprint>"}`
- **Health:** `GET /api/ping` returns `pong`
- **Loop prevention:** each device has a unique fingerprint; ignores messages from itself
- **Retry:** 3 attempts with exponential backoff on failed sends

## Folder Structure

```
Macroid/
├── mac/Macroid/Macroid/        # SwiftUI app source
│   ├── MacroidApp.swift
│   ├── ContentView.swift
│   ├── ClipboardMonitor.swift
│   ├── SyncServer.swift
│   ├── SyncClient.swift
│   ├── SyncManager.swift
│   └── Discovery.swift
├── android/app/src/main/java/com/macroid/
│   ├── MainActivity.kt
│   ├── clipboard/ClipboardMonitor.kt
│   ├── network/{Discovery, SyncServer, SyncClient, DeviceInfo}.kt
│   ├── service/SyncForegroundService.kt
│   └── ui/{MacroidApp, MainScreen, Theme}.kt
└── .github/workflows/         # CI/CD
    ├── build-android.yml
    ├── build-mac.yml
    └── release.yml
```

## Build Commands

### Android
```bash
cd android && ./gradlew assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
```
Requires: JDK 17+, Android SDK 34

### macOS
```bash
open mac/Macroid/Macroid.xcodeproj  # then Cmd+B
```
Requires: Xcode 15+, macOS 13+

## CI/CD

- **Build Android / Build macOS** — triggered on push to `main` or `claude/*`
- **Release** — triggered on tag `v*` or manual, creates GitHub Release with APK + DMG
