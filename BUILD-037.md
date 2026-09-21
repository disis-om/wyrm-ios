# Build 37 — Slither arena lifecycle parity

Version: 0.12.0 (37)  
Phase: 6 — real arena lifecycle and failover  
Status: source and portable checks passed; Apple compile/runtime pending

## Added

- Slither `/ptc` WebSocket probing with three binary `p` round trips per cluster representative.
- Original 2667 ms first-probe readiness window and 7000 ms directory fallback.
- Active-server filtering, `activeCount > 20`, lowest-ping cluster selection, and `activeCount + 5` weighted choice.
- Native C → Swift refusal mailbox with a monotonic event sequence.
- Automatic alternate-arena selection after a refused or silent short-life session.
- Synthetic Simulator refusal-bridge smoke test and a 13-check lifecycle contract test.

## Fixed

- Removed the Apple generated engine's global 3333 ms re-entry cooldown. The value now remains the current connection-attempt timeout.
- Refused arenas are excluded for 120 seconds instead of being retried immediately.
- A remote close shortly after a successful spawn is classified as an arena refusal only when it is not a real death, client leave, or restart.

## Preserved

- `SharedEngine` and the Android source remain byte-identical and read-only.
- Existing challenge response, join packet, packet decoder, rendering, death packet, user leave, and restart paths remain intact.
- No backend contract, authentication flow, UI design, or signing secret changed.

## Verification

- Generated-source verification: 395 original files verified; 29 Apple platform selections adjusted.
- Lifecycle contract: 13/13 pass.
- Slither reference audit: 19 pass, 0 mismatch, 0 current fail; two items remain unproven until runtime evidence.
- Build 35's six arena drops remain recorded as historical evidence rather than being relabelled as fixed.

## Remaining proof

- GitHub macOS runner must compile iPhoneOS and Simulator products.
- Simulator must pass the native refusal-mailbox smoke test.
- An installed Build 37 must prove live arena admission, visible own snake, stable play, and real refusal failover on an iPhone.
