<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/WyrmIcon-1024.png" width="128" height="128" alt="Wyrm app icon">
</p>

<h1 align="center">Wyrm for iOS</h1>

<p align="center">
  The native iPhone client in the Wyrm ecosystem.<br>
  SwiftUI product surfaces over the original C game engine.
</p>

## Status

- Current release: **1.0.0 (build 107)**, stable. iOS **15 or newer**, iPhone
  first.
- Every build is compiled and smoke-tested by the Apple CI workflow. Chosen
  builds are published as releases of this repository. Betas are titled
  "beta" and announced only through `update/beta.json`; stable builds use
  `update/latest.json`.
- The IPA is unsigned. Players sign and install it themselves with AltStore,
  SideStore, KSign or ESign. TestFlight and App Store distribution are not set
  up.

## Features

- Username/password sign-up and login with live username availability.
  Every setting lives in the account, one copy per platform plus a shared copy
  (skin, look, background, name and play options follow you between iPhone
  and Android). Settings are saved on log out and restored during the log-in
  animation; logging out clears the phone.
- Play, Trails, Social, Skin and Settings tabs. Alerts opens from the bell on
  Play. On iOS 26 the tab bar, switches, sliders, segmented controls and
  buttons are the system's own Liquid Glass; earlier iOS versions get a
  draggable glass-style tab bar.
- The original Wyrm C gameplay and network engine, not a Swift rewrite. The
  lobby and arena run in landscape (or upright, if chosen) inside a portrait
  app.
- One arena connection per Play. A refused or failed entry returns to the
  lobby with no automatic retry or server switch. Play can never stay stuck
  on "Entering".
- Arena picker with the live directory, a lowest-ping pick, four-digit arena
  codes, recent and saved custom IPv4 arenas. Latency probes run only while the
  picker is open, and each arena is dialled at most once a minute.
- Skin Studio: 66 presets, the atlas beads and Wyrm's own beads, the
  slither.io colour wheel, accessories, Wyrm looks (hair, ears, glasses), 241
  tags and 30 arena floors. Tags show to everyone in the arena: only the tag's
  number travels in the skin block, and each player draws the chain, swing and
  size with their own settings.
- Modes: Wyrm, assist and Near Original (slither's own HUD and controls);
  Texture, Solid, Flat and Skinless snake rendering, and Spine.
- NTL 9.68-compatible Team mode: presence, an in-arena roster and team chat
  window. Several teams can be saved; only the selected one runs. Team
  credentials stay in the iOS Keychain.
- Settings rebuilt from the Android app: display, controls, on-screen buttons
  (including Auto restart and Eyes back), arena UI, modes, bot, food,
  performance, notifications, privacy, themes and updates. Changes go straight
  into the engine. Settings search included.
- Layout editor over a bot-driven practice arena, eight themes, drawn and
  image arrows.
- Trails: photo, text and canvas posts with a story-style editor, looks,
  stickers and replies.
- Wyrm's own keyboard (sideways too), global chat and direct messages.
- Leaderboards with search, profiles, avatars, follows, notifications and
  voice-room control through the Wyrm backend.
- Help & feedback: crash and arena-drop reports (sent only with your consent),
  reports to Wyrm with replies, a FAQ and an app tour.
- Stable and beta update channels. Settings › Updates shows an "Update now"
  card when a newer build is out and hands the IPA to AltStore, SideStore,
  KSign or ESign. Beta builds are offered only with "Beta updates" on.
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
