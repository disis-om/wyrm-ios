# Build 041 — full native skin body and independent glass lens

Version: 0.13.2 (41)  
Status: source contracts pass; Apple CI, Simulator runtime and physical-iPhone acceptance pending

## What changed

- Replaced the incorrect 20-bead Skin hero with the engine-authoritative
  `MAX_SKIN_CODE_LEN` body: two rows of 128 beads, 256 total.
- Preserved the native row direction, reversed group lookup, 8/48 overlap and
  0.16-row gap. The arena-only blurred body shadow is deliberately omitted;
  the original shading baked into every bead texture remains intact.
- Moved the 256 atlas draws into one asynchronous SwiftUI `Canvas` instead of
  constructing hundreds of independently invalidated image views. Only the
  selected NTL tag subtree runs on the animation timeline.
- Removed the Skin overview subtitles, texture-loaded status and technical
  “Native atlas preview” label.
- Split the bottom bar and moving tab lens into independent iOS 26
  `GlassEffectContainer` layers. This prevents overlapping glass shapes from
  being merged into one surface, and removes the opaque ink tint that hid the
  lens refraction. Both layers remain interactive, with the iOS 15–25 material
  fallback unchanged.

## Validation gates

- Skin Studio source and asset contracts: 22/22.
- Full-screen shell, Liquid Glass, drag and control contracts: 15/15.
- Existing session and arena lifecycle suites must remain green.
- Apple CI must compile iPhoneOS and Simulator, capture the corrected Skin
  screen, package the IPA/Appetize ZIP and pass offline and online arena smoke.

## Expected artifacts

- `Wyrm-0.13.2-build-41-unsigned.ipa`
- `Wyrm-0.13.2-build-41-simulator.app.zip`
- `SHA256SUMS`, screenshots and runtime logs
