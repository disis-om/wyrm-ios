# Build 038 — full-screen paper and stable glass controls

Version: 0.12.1 (38)  
Status: Apple CI validation required

## What changed

- Replaced layered translucent page backgrounds with one full-bleed warm-paper canvas across the root tabs, safe areas, and every pushed detail route.
- Removed the footer reservation beneath the root content. The tab bar is now a true floating overlay and scrollable content continues behind it, with trailing scroll clearance so the final row remains reachable.
- Tightened the root page header spacing while preserving notch-safe layout.
- Kept the iOS 26 tab bar and selection lens inside one `GlassEffectContainer`; both glass surfaces remain interactive and the selection lens now receives direct horizontal drags over tab buttons.
- Fixed sliders and toggles losing touch during engine refreshes. Setting rows now retain stable SwiftUI identity, and slider values defer external snapshot updates while the user is dragging.
- Applied the stable-control fix to the current design shell and the retained parity/legacy shells.

## Engine baseline preserved

- Build 37 established the original Android-derived C engine lifecycle baseline: real arena probe, server selection, 120-second taint, native refusal bridge, and automatic failover.
- This build changes shell layout and control identity only; it does not rewrite or replace the native gameplay engine.

## Validation

- `Tests/ui_shell_contract_test.py` guards the full-screen canvas, floating navigation, grouped interactive glass, draggable lens, and stable setting-control identity.
- `Tests/arena_lifecycle_contract_test.py` continues to guard the engine lifecycle and protocol timing path.
- GitHub Actions compiles device and Simulator targets, captures SwiftUI screens, then performs rotated lobby, AI arena, and real online arena smoke tests.

## Artifacts

- `Wyrm-0.12.1-build-38-unsigned.ipa` — unsigned device package for AltStore signing.
- `Wyrm-0.12.1-build-38-simulator.app.zip` — Simulator/Appetize package.
- `SHA256SUMS` — artifact integrity hashes.
