# REQUIREMENTS.md — Macroid

## Core Features (Implemented)

- [x] **Instant clipboard sync** — real-time push over local WiFi on clipboard change
- [x] **UDP multicast discovery** — auto-discovers peer on same network (LocalSend-compatible, `224.0.0.167:53317`)
- [x] **Fallback subnet scan** — if multicast fails, scans subnet for peer
- [x] **Direct IP connect** — manual IP entry as fallback
- [x] **HTTP sync protocol** — `POST /api/clipboard` with `text`, `timestamp`, `origin`
- [x] **Sync loop prevention** — origin fingerprint tracking prevents echo loops
- [x] **Clipboard history** — last 20 items, tap/click to restore
- [x] **Background sync (Android)** — foreground service keeps sync alive when app is backgrounded
- [x] **Retry with backoff** — 3 attempts with exponential backoff on failed sends
- [x] **Keepalive / health check** — `GET /api/ping` endpoint
- [x] **Light/dark mode** — follows system preference on both platforms
- [x] **Structured logging** — `os.log` (Mac), `android.util.Log` (Android)
- [x] **Request validation** — 1MB size limit, origin checks, timestamp ordering
- [x] **Image sync** — clipboard image sync support (added in v1.2.0)
- [x] **Show peer IP** — displays connected device IP in UI
- [x] **Matching icons** — consistent icon across Mac and Android
- [x] **CI/CD** — GitHub Actions builds APK + DMG, auto-release on tag

## Known Gaps / Open Issues

- [ ] No encryption — clipboard data sent in plain text over local network
- [ ] No pairing/authentication — any device on the same WiFi can push clipboard data
- [ ] Android clipboard read restricted on API 29+ (background reads require accessibility service or foreground focus)
- [ ] No multi-device support — protocol assumes one Mac ↔ one Android
- [ ] Release signing uses debug keystore — not suitable for Play Store distribution
- [ ] No tests (unit or integration) on either platform

## Current Version

- Android: `versionCode = 3`, `versionName = "1.2.0"`
- Mac: tracks same versioning
