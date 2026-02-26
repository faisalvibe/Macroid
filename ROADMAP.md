# ROADMAP.md — Macroid

## Phase 1 — Done ✓
- Native Mac (SwiftUI) + Android (Compose) apps
- UDP multicast discovery, HTTP sync protocol
- Sync loop prevention, clipboard history, retries
- Background foreground service (Android)
- CI/CD with GitHub Actions, auto-release

## Phase 2 — Done ✓ (v1.2.0)
- LocalSend-compatible protocol
- Direct IP connect fallback
- Image sync
- UI improvements (show peer IP, matching icons)
- Release workflow with DMG + APK

## Phase 3 — Potential Next Work

### Security
- [ ] Encrypt clipboard payloads (TLS or shared secret)
- [ ] Simple pairing flow — only accept from paired device

### Android Clipboard Access
- [ ] Handle API 29+ background clipboard restriction gracefully
- [ ] Consider accessibility service or input method workaround

### Multi-device
- [ ] Support multiple peers (list of discovered devices)
- [ ] Per-device sync toggle

### Quality
- [ ] Unit tests for sync logic (both platforms)
- [ ] Production signing for Android (release keystore)
- [ ] Play Store / Mac App Store distribution

### UX
- [ ] Connection status indicator (connected / searching / offline)
- [ ] Sync history with timestamps
- [ ] Notification on sync (optional, toggleable)
