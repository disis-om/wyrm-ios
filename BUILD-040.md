# Build 040 — clean sessions, stable controls and native skin geometry

Version: 0.13.1 (40)  
Status: source contracts pass; Apple CI, Simulator runtime and physical-iPhone acceptance pending

## What changed

- Authentication retains the centered W-logo working stage while fresh alerts,
  leaderboards, conversations, voice state, arenas and connections are fetched.
  Home is presented only after the new account's service snapshot is installed.
- Service bootstrap now isolates endpoint failures, publishes one account's
  results together and uses a session revision guard so a cancelled login cannot
  overwrite the next account. Sign-out invalidates requests and removes all
  account-scoped arrays, tokens, arena choices and cached voice state.
- Sign-out is a full-screen blur/W transition with a shimmering “Signing you
  out…” line; the signed-out screen appears only after cleanup finishes.
- Native-engine toggles and hotkey switches hold their optimistic value while
  the C mailbox catches up, preventing the first tap from visibly reverting on
  a stale polling snapshot.
- The tab lens now follows absolute finger position and snaps to the nearest
  slot without velocity extrapolation. Both the bar and its capsule lens use
  interactive iOS 26 Liquid Glass inside one `GlassEffectContainer`, with the
  material fallback retained for iOS 15–25.
- Rebuilt the SwiftUI skin hero from the authoritative Android skin preview:
  two rows of ten constant-size atlas beads, 8/48 overlap spacing, 0.16 body
  gap, original eye and accessory ratios, and engine-order colour sampling.
- Replaced the decorative tag curve with the native NTL proportions: ten rope
  points, four snake-width segments, eight-width anchor, dual accent strokes
  and a tapered trim. The selected arena floor now fades into the exact paper
  colour at every preview edge.
- Increased atlas sampling resolution and generated crisp shadowless accessory
  and tag picker thumbnails. Game and hero-preview sprites retain their depth;
  catalogue tiles do not.

## Validation gates

- Arena lifecycle contracts: 13/13.
- Full-screen shell, glass, drag and optimistic-control contracts: 14/14.
- Skin Studio asset and geometry contracts: 18/18.
- Account session lifecycle contracts: 8/8.
- Apple CI must compile iPhoneOS and Simulator targets, package both artifacts,
  capture auth/session/Skin Studio screens, and pass existing lobby, offline-AI
  and live-online-arena smoke gates.

## Expected artifacts

- `Wyrm-0.13.1-build-40-unsigned.ipa`
- `Wyrm-0.13.1-build-40-simulator.app.zip`
- `SHA256SUMS`, screenshots and runtime logs
