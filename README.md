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
**0.17.2 (build 58)** and targets **iOS 15 or newer**.

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
- Each Play action dials the selected arena once. Entry timeout or refusal
  returns to the native lobby without automatic retries or server failover.
  Socket diagnostics distinguish TCP, WebSocket upgrade, challenge,
  configuration and spawn phases without exposing nicknames or challenge contents.
- SDL3 window/input integration and Vulkan rendering through MoltenVK/Metal.
- Original landscape lobby and arena inside a portrait-owned iOS application.
- Live backend integration for profiles and avatars, notifications,
  leaderboards, connections, mutual direct conversations and voice-room
  control operations.
- Two-second arena directory updates, bounded on-demand game-port TCP latency
  measurements, four-digit arena codes, and direct handoff from Play into the
  original C lobby. The picker prioritizes recently joined and sampled active
  arenas, with an expandable full list and locally saved custom IPv4 addresses.
- Email-code voice verification plus separately presented official Wyrm rooms
  and player-created rooms.
- Native engine settings and on-screen controls connected through a narrow,
  thread-safe Swift/C bridge.
- Native SwiftUI Skin Studio with the original engine's full two-strip,
  256-segment preview geometry (128 beads per strip), atlas bead spacing, eye/accessory proportions,
  ten-point dual-stroke NTL tag rope, all 66 presets, 32 accessories, 164 tags
  and 22 arena floors. Editors replace the lower panel in place and selections
  persist through a bounded engine-thread mailbox.
- Skin Studio now supports 256-position code editing over the selected preset,
  the 42 original atlas beads as its palette, original preset eye variants,
  tightly packed one-row-per-skin browsing, and a tail-directed tag swing set by
  Chain and Swing controls. As on Android, building shows only the beads placed so far on an
  empty body; the pattern repeats in a match and when the editor is reopened. The preview respects Reduce Motion.
- Social pull-to-refresh updates sections in place without restarting account
  bootstrap. Transient optional-service failures no longer become a global
  disconnected toast; notification bodies support Markdown and read/delete
  actions are available on long press.
- NTL 9.68-compatible Team mode with Keychain-held Auth/Team credentials,
  four-second presence/roster/chat polling, live member arena handoff, selected
  tag publication and exact packet-S session-ID mapping back to rendered
  snakes. Team secrets are never written to diagnostics.
- Optimistic engine toggles that do not bounce back on stale polling frames,
  plus an absolute-position draggable iOS 26 Liquid Glass tab lens that follows
  the finger and springs only to the nearest tab.
- Settings rebuilt page for page from the Android app: Display, Controls,
  On-screen buttons, Arena UI, Modes, Bot, Food, Notifications, Privacy,
  Themes and Backup, all written live into the original engine. Play's
  Loadout opens Food, a tabbed Controls workspace and Modes directly.
- Android's Ready Room in SwiftUI above the rotated engine, themed with the
  app palette.
- A sideways layout editor over a bot-driven AI arena, for joystick, boost, zoom bar, buttons, minimap,
  leaderboard, stats, team and chat, with per-object size and opacity.
- Eight Android themes with an intensity control, pushed into the engine so
  the lobby and arena interface follow them. File-based backup and restore.
- Arrow steering offers the five drawn Wyrm arrows plus twenty image arrows in
  a visual picker, with size and brightness for all and colour for drawn ones.
- One in-game name everywhere: Play, the Ready Room, the arena and NTL Team.
- Wyrm's own themed keyboard in every text field (size and transparency behind
  its gear key; in the lobby it is drawn sideways and can be dragged by its
  knob). Fields and chat composers rise above it.
- Global chat and DMs share a Liquid Glass composer with an animated send
  arrow and grouped, animated message bubbles.
- Settings search: every setting's live control in the results, with an arrow
  that opens its page and blinks it twice.
- The slither.io Android Build-a-Slither colour wheel in Skin › Pattern: a
  brightness bezel and a hue pointer with glass-styled chrome, and the Android client's
  first two bead textures, drawn in the arena with their exact texture, tint
  and outline shadow. See [AIR-BUILD-A-SLITHER.md](AIR-BUILD-A-SLITHER.md).
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

- `Wyrm-0.17.2-build-58-unsigned.ipa` for user-side signing and installation.
- `Wyrm-0.17.2-build-58-simulator.app.zip` for Simulator/Appetize testing.
- SHA-256 checksums, simulator screenshots and runtime smoke-test logs.

The IPA is intentionally unsigned. App Store, TestFlight and distribution
signing material is never stored in this repository.

## Repository guide

For build/signing steps, source-reference rules and the current physical-device
arena investigation, read [the developer handoff](DEVELOPER-HANDOFF.md).

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
App Store acceptance claim. Build 49 still has intermittent short-lived arena
connections on the owner's iPhone; the cause is under investigation.
