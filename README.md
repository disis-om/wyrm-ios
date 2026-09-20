# Wyrm iOS

Official iPhone port of Wyrm, built from the existing native C game engine rather
than reimplementing gameplay in Swift.

**Current build:** 0.6.0 (27)

**Minimum target:** iOS 15.0, iPhone first

**Current milestone:** the original SDL3/Vulkan engine runs through MoltenVK in
the iOS Simulator, joins a live arena, spawns the player's real snake and draws
the original HUD, minimap and leaderboard. A SwiftUI product shell now mirrors
the Android Compose Play, Notifications, Social, Skin and Settings structure.

## What is working

- UIKit-owned root container with a SwiftUI product layer above the SDL surface.
- Original C gameplay, renderer, network, mobile controls, ImGui and Thermite
  sources compiled for Apple ARM64 and Simulator.
- Vulkan rendering through MoltenVK/Metal using the original atlas and shaders.
- Portrait iOS process with the original landscape lobby/arena rotated inside a
  stable child container.
- Live arena admission, own-snake spawn, frame progression, minimap,
  leaderboard and stats in automated Simulator smoke tests.
- Android-style Paper UI: Play, Notifications, Social, Skin placeholder and the
  complete Settings hierarchy.
- Home actions and every non-skin engine setting cross a bounded Swift/C mailbox
  and are applied by the engine thread.
- Unsigned iPhone IPA for AltStore and Simulator app ZIP for Appetize.

## Still intentionally incomplete

- Physical-iPhone launch, input, performance and lifecycle acceptance.
- Skin Studio wiring. Its tab is present, but the editor is deliberately not
  connected yet.
- Account, Social, notifications, voice and other backend-dependent services.
  Their screens show honest offline/empty states instead of fabricated data.
- TestFlight/App Store signing, privacy/compliance work and distribution.
- Permanent neutral shared-engine ownership. `SharedEngine` is currently a
  hash-verified transport snapshot; Android remains the read-only authority.

## Runtime shape

```text
SwiftUI: Play · Notifications · Social · Skin · Settings
                          |
               bounded Swift/C mailboxes
                          |
Original Wyrm C engine: world · protocol · settings · renderer
                          |
                         SDL3
                          |
                 Vulkan -> MoltenVK -> Metal
```

UIKit owns the container. SwiftUI covers the engine on product screens and is
removed for Lobby/Playing. The iOS process stays portrait; only the engine child
is transformed to show the original landscape game correctly.

See [ARCHITECTURE.md](ARCHITECTURE.md) for ownership and threading details.

## Build and test

The source is edited on Windows, but Apple compilation happens on a macOS 15
runner. The project is generated from `original-engine.yml`; pinned SDL3 and
MoltenVK binaries are fetched and verified during CI.

The `Compile original Android engine for Apple` workflow produces:

- `Wyrm-0.6.0-build-27-simulator.app.zip` — upload to Appetize.
- `Wyrm-0.6.0-build-27-unsigned.ipa` — sign/install with AltStore.
- Play, Settings, Lobby, offline-AI and live-online screenshots and logs.
- `SHA256SUMS` and the build-specific README.

Full commands and evidence gates are in
[BUILDING-AND-TESTING.md](BUILDING-AND-TESTING.md).

## Repository map

| Path | Purpose |
|---|---|
| `SourcesShell/` | SwiftUI Android-parity shell and Swift/C declarations |
| `SourcesOriginal/` | UIKit host and narrow Apple engine adapters |
| `SharedEngine/` | Hash-locked native source transport snapshot; do not edit gameplay here |
| `Scripts/prepare-original-engine.py` | Verifies all snapshot hashes and creates a disposable Apple compile tree |
| `Scripts/fetch-ios-dependencies.sh` | Fetches and verifies SDL3/MoltenVK |
| `original-engine.yml` | XcodeGen specification for the current app |
| `.github/workflows/original-engine.yml` | Compile, package and Simulator proof pipeline |
| `phase0/` | Safety baseline, protected behavior and dependency review |
| `phase1/` | Initial SDL3/MoltenVK foundation evidence |
| `phase2/` | Per-build changelogs, current status and engine-port evidence |
| `dist/` | Downloaded CI artifacts; generated, not source authority |

## Source and safety rules

- `../Wyrm Android` is the product/engine authority and is read-only unless OM
  explicitly authorizes a cross-platform refactor.
- The engine snapshot is verified against `SharedEngine/SHA256.json` before
  every Apple preparation step. Apple-only selections are applied only to the
  disposable `build-original-source` tree.
- Never commit signing identities, provisioning profiles, API keys, session
  secrets or player-private data.
- A successful compile is not a physical-device result. Build, signing,
  install, launch, first frame, gameplay and owner acceptance are reported as
  separate gates.

## Documentation index

- [Official phase plan](Wyrm-iOS-PLAN.md)
- [Current Phase 2 status](phase2/STATUS.md)
- [Current Build 27 notes](phase2/BUILD-027-NOTES.md)
- [Protected behavior](phase0/PROTECTED-BEHAVIOR.md)
- [Dependencies and licences](phase0/DEPENDENCIES-AND-LICENSES.md)
