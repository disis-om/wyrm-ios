# Build 041 — full native skin body and independent glass lens

Version: 0.13.2 (41)  
Status: Apple CI and Simulator runtime accepted; physical-iPhone acceptance pending

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
- Session lifecycle contracts: 8/8.
- Arena lifecycle contracts: 13/13.
- Apple CI run `35603493751` compiled iPhoneOS and Simulator, captured the
  corrected Skin screen, packaged the IPA/Appetize ZIP and passed offline and
  online arena smoke.
- Visual proof confirms 128 beads per strip, no outer blurred body shadow, no
  technical preview/status labels, and a distinct raised glass selection lens.

## Expected artifacts

- `Wyrm-0.13.2-build-41-unsigned.ipa`
- `Wyrm-0.13.2-build-41-simulator.app.zip`
- `SHA256SUMS`, screenshots and runtime logs

## Artifact integrity

- IPA SHA-256: `2b6302662e0406521a3372917faeaeceb915a2e3456d3fb9e33f488b7969e291`
- Simulator ZIP SHA-256: `201cd07a76ca53ce8b7b0e0cb20dbcaefd3875560bbc5e51475c0d614bbae675`
