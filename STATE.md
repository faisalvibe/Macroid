# STATE.md — Macroid

## Current Status

**Stable. Feature-complete for personal use.**

Version 1.2.0 is the latest. Both Mac and Android apps are built and released via CI/CD.

---

## What's Done

- Full Mac (SwiftUI) + Android (Compose) clipboard sync apps
- UDP multicast discovery (LocalSend-compatible protocol)
- HTTP sync with loop prevention, retries, history
- Android foreground service for background sync
- Image sync support
- Direct IP connect fallback
- CI/CD: GitHub Actions builds APK + DMG, auto-releases on git tag
- GSD files set up (2026-02-26)

## What's In Progress

Nothing currently in progress.

## What's Next

See `ROADMAP.md` Phase 3 for potential improvements. Top candidates:
1. Encryption / pairing for security
2. Handle Android API 29+ clipboard restriction
3. Add tests

## Last Action

2026-02-26 — GSD setup: created PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md.
