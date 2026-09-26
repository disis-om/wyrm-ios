<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/WyrmIcon-1024.png" width="128" height="128" alt="Wyrm app icon">
</p>

<h1 align="center">Wyrm for iOS</h1>

<p align="center">
  The native iPhone client in the Wyrm ecosystem.<br>
  SwiftUI product surfaces over the original C game engine.
</p>

## Status

- Version **0.17.9 (build 65)**, iOS **15 or newer**, iPhone first.
- Every build is compiled and smoke-tested by the Apple CI workflow and
  published as a workflow artifact. There are no GitHub Releases.
- The IPA is unsigned. Players sign and install it themselves (for example
  with AltStore). TestFlight and App Store distribution are not set up.

## Features

- Username/password sign-up and login with live username availability.
  Signing out clears every account-scoped cache.
- Play, Alerts, Social, Skin and Settings tabs with a draggable Liquid Glass
  tab bar.
- The original Wyrm C gameplay and network engine, not a Swift rewrite.
  The lobby and arena run in landscape inside a portrait app.
- One arena connection per Play. A refused or failed entry returns to the
  lobby with no automatic retry or server switch. Play can never stay stuck
  on "Entering".
- Arena picker with the live directory, four-digit arena codes, recent and
  saved custom IPv4 arenas. Latency probes run only while the picker is open,
  and each arena is dialled at most once a minute.
- Skin Studio: 66 presets, the 42 atlas beads, the slither.io Android colour
  wheel, 32 accessories, 164 tags and 22 arena floors, with a 256-bead preview
  drawn from the engine's own atlas.
- NTL 9.68-compatible Team mode (presence, roster, chat, tags). Team
  credentials stay in the iOS Keychain.
- Settings rebuilt from the Android app: display, controls, on-screen
  buttons, arena UI, modes, bot, food, notifications, privacy, themes and
  backup. Changes go straight into the engine. Settings search included.
- Layout editor over a bot-driven practice arena, eight themes, twenty-five
  arrow skins, file-based backup and restore.
- Wyrm's own keyboard, global chat and direct messages.
- Leaderboards, profiles, avatars, follows, notifications and voice-room
  control through the Wyrm backend.
- Opt-in Developer Mode with bounded local diagnostics and share-sheet export.

## Architecture

```text
SwiftUI product shell
        │
bounded Swift/C bridge (mailboxes and snapshots)
        │
original Wyrm C engine
        │
SDL3 · Vulkan · MoltenVK · Metal
```

UIKit owns the app container. Product screens are portrait. During the lobby
and the match only the engine surface is rotated, so the original landscape
renderer runs unchanged while iOS stays portrait.

## Building

Apple compilation runs on macOS in the `Compile original Android engine for
Apple` workflow:

1. Fetch SDL3 3.4.16 and MoltenVK 1.4.2 (SHA-256 pinned).
2. Verify and prepare the engine snapshot (`Scripts/prepare-original-engine.py`).
3. Run the source contract tests in `Tests/`.
4. Generate the Xcode project from `original-engine.yml`.
5. Build for iPhone and Simulator with code signing off.
6. Run Simulator smoke tests (UI, settings, skin, team, AI and online arena).

Artifacts: `Wyrm-<version>-build-<n>-unsigned.ipa`, the Simulator `.app.zip`,
SHA-256 checksums, screenshots and logs.

## Repository layout

| Path | Contents |
|---|---|
| `SourcesShell/` | SwiftUI interface, account and service clients, diagnostics |
| `SourcesOriginal/` | UIKit container and the Swift/C boundary |
| `SharedEngine/` | Hash-verified snapshot of the Wyrm C engine |
| `Resources/` | App icon, fonts, arrow skins, privacy policy text |
| `Scripts/` | Dependency fetch, engine preparation, reference checks |
| `Tests/` | Source contract tests run before compilation |
| `original-engine.yml` | XcodeGen spec, bundle ID, version and build number |
| `.github/workflows/` | Build, package and Simulator test pipeline |

## Not done yet

- Realtime voice audio, push notifications (APNs), voice-room creation and
  moderation.
- TestFlight and App Store distribution.
- CI proves compilation and Simulator behaviour only, not physical-device
  behaviour.

## Security and privacy

- No signing certificates, provisioning profiles, keys, tokens or player data
  are stored in this repository.
- Account and Team credentials live in the iOS Keychain.
- Diagnostics are local, size-bounded, expire after seven days, and never
  contain tokens, passwords or private message text.

## License

The engine snapshot is GPL-3.0; see `SharedEngine/LICENSE` and
`SharedEngine/NOTICE`. Slither.io names, artwork and trademarks belong to
their owners. Wyrm is independent and not affiliated with the game's developer.
