<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/WyrmIcon-1024.png" width="128" height="128" alt="Wyrm app icon">
</p>

<h1 align="center">Wyrm for iOS</h1>

<p align="center">
  The native iPhone client in the Wyrm ecosystem.<br>
  SwiftUI product surfaces over the original C game engine.
</p>

## Project status

Wyrm for iOS is under active development. The current source version is
**0.13.2 (build 41)** and targets **iOS 15 or newer**.

The repository contains the iOS application source and its automated Apple
build pipeline. It does not publish GitHub Releases; each accepted build is
compiled and tested by CI, then exposed as a workflow artifact.

## Current capabilities

- Full-screen cinematic username/password account creation and login, with
  live debounced username availability, keyboard-safe actions, password-match
  feedback, and no Google dependency or separate onboarding sequence.
- Account entry now keeps the W-logo working stage visible until fresh profile,
  alerts, social, arena and voice snapshots are installed atomically. Sign-out
  uses the same cinematic language and clears every account-scoped collection
  before another player can enter.
- Full-bleed Play, Alerts, Social, Skin and Settings product surfaces with a
  draggable glass navigation control and one-level-at-a-time route stacking.
- Original Wyrm C gameplay and network engine—not a Swift reimplementation.
- SDL3 window/input integration and Vulkan rendering through MoltenVK/Metal.
- Original landscape lobby and arena inside a portrait-owned iOS application.
- Live backend integration for profiles and avatars, notifications,
  leaderboards, connections, mutual direct conversations and voice-room
  control operations.
- One-second arena directory updates, real TCP latency measurements, four-digit
  arena codes, and direct handoff from Play into the original C lobby.
- Email-code voice verification plus separately presented official Wyrm rooms
  and player-created rooms.
- Native engine settings and on-screen controls connected through a narrow,
  thread-safe Swift/C bridge.
- Native SwiftUI Skin Studio with the original engine's full two-strip,
  256-segment preview geometry (128 beads per strip), atlas bead spacing, eye/accessory proportions,
  ten-point dual-stroke NTL tag rope, all 66 presets, 32 accessories, 164 tags
  and 22 arena floors. Editors replace the lower panel in place and selections
  persist through a bounded engine-thread mailbox.
- Optimistic engine toggles that do not bounce back on stale polling frames,
  plus an absolute-position draggable iOS 26 Liquid Glass tab lens that follows
  the finger and springs only to the nearest tab.
- Opt-in Developer Mode with bounded local logs and native iOS Share Sheet
  export for support diagnostics.

## Architecture

```text
SwiftUI product shell
        │
bounded Swift/C bridge
        │
original Wyrm C engine
        │
SDL3 · Vulkan · MoltenVK · Metal
```

UIKit owns the stable app container. Product screens remain portrait. When the
player enters the lobby or arena, only the native engine child surface is
rotated, so gameplay keeps its original landscape layout without changing the
application's iOS orientation contract.

## Building

Apple compilation runs on macOS through the repository's
`Compile original Android engine for Apple` workflow. The project is generated
from `original-engine.yml`; pinned SDL3 and MoltenVK packages are fetched and
verified during the job.

Successful build artifacts include:

- `Wyrm-0.13.2-build-41-unsigned.ipa` for user-side signing and installation.
- `Wyrm-0.13.2-build-41-simulator.app.zip` for Simulator/Appetize testing.
- SHA-256 checksums, simulator screenshots and runtime smoke-test logs.

The IPA is intentionally unsigned. App Store, TestFlight and distribution
signing material is never stored in this repository.

## Repository guide

| Path | Purpose |
|---|---|
| `SourcesShell/` | SwiftUI interface, account/services clients and diagnostics |
| `SourcesOriginal/` | UIKit container and Apple-specific native adapters |
| `SharedEngine/` | Verified native-engine source snapshot used by Apple builds |
| `Resources/` | App icon, fonts and packaged engine resources |
| `Scripts/` | Dependency verification and reproducible source preparation |
| `original-engine.yml` | XcodeGen project specification |
| `.github/workflows/` | Apple compile, package and simulator verification pipeline |

## Security and privacy

- Do not commit credentials, signing certificates, provisioning profiles,
  access tokens, private player data or local diagnostic exports.
- Authentication secrets are stored by the app in iOS Keychain.
- Developer diagnostics are local, expire after seven days, are size-bounded,
  and intentionally omit tokens, passwords and private message bodies.
- Android sources remain the read-only behavior reference for this iOS port.

## Current limitations

Physical-device acceptance, realtime voice audio, APNs, avatar upload and
Files-based backup/restore remain in development. Voice room
authority and verification are wired; the realtime media adapter is not. CI success
proves Apple compilation and Simulator behavior; it is not a physical-device or
App Store acceptance claim.
