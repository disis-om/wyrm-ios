# Build 042 — NTL Team mode and interoperable tags

Version: 0.14.0 (42)  
Status: source and local contracts accepted; Apple CI/runtime evidence pending

## What changed

- Inspected the read-only NTL 9.68 mod and matched its Team request contract:
  Auth/Team ID, nickname, score, position, bot/SOS/food, arena, `sid`, message,
  rank, client detail, selected `tg`, version and device fields.
- Added an iOS Team client with the original four-second cadence and two-second
  request timeout. Auth and Team ID require at least 16 characters and live in
  this-device-only Keychain storage; diagnostics contain neither secret.
- Replaced the Team placeholder with connect, status, live roster, arena jump,
  chat and disconnect surfaces while keeping the established full-screen Wyrm
  paper design.
- Carried selected tags as the exact NTL tag number (`tg`) and added the
  packet-`S` identity transform used by NTL 9.68:
  `((session & 63) << 10) | (arenaID & 1023)`.
- Every native snake now retains both its renderer arena ID and NTL session ID.
  Team/API and tag-socket records resolve the session ID back to the correct
  arena snake before changing renderer tag state.
- Matched the NTL rope's ten-point, 60 Hz/four-catch-up spring and 5/4/3/2 px
  layered stroke contract in the native renderer and SwiftUI preview.
- Team tag updates remain active when the player hides the HUD.

## Compatibility boundaries

- Bundled/public NTL tags are published using their original NTL IDs. Wyrm
  does not claim a private tag or transmit a private tag password.
- Team service responses are treated as untrusted data, parsed into bounded
  native rows, and never block the engine thread.
- `ntl 9.68` and Wyrm Android were inspection-only references; neither tree was
  modified.

## Validation gates

- Verified the 395-file native source manifest and regenerated the disposable
  Apple compile tree.
- NTL Team/rope source contracts pass.
- Skin Studio contracts: 22/22.
- Full-screen shell/control contracts: 15/15.
- Session lifecycle contracts: 8/8.
- Arena lifecycle contracts: 13/13.
- Apple iPhoneOS/Simulator compile, Team screenshot and online arena smoke are
  run by CI before artifact delivery.

## Expected artifacts

- `Wyrm-0.14.0-build-42-unsigned.ipa`
- `Wyrm-0.14.0-build-42-simulator.app.zip`
- `SHA256SUMS`, Team/Skin screenshots and runtime logs

## Remaining acceptance

An authenticated two-client NTL session needs the owner's real Auth and Team
ID and is intentionally not run in CI. CI proves compile and unauthenticated
UI/runtime behavior; physical-iPhone and cross-client visibility remain owner
acceptance gates.
