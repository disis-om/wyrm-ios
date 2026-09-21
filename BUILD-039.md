# Build 039 — native atlas Skin Studio

Version: 0.13.0 (39)  
Status: source and portable contracts pending Apple CI; physical iPhone acceptance remains open

## What changed

- Replaced the placeholder Skin tab and its pushed detail pages with one
  seamless Skin Studio. The preview stays fixed while Default skins, Pattern,
  Accessory, Tag and Arena background replace only the lower content panel.
- The SwiftUI preview loads pixels directly from the bundled original engine
  resources: `tex_atlas_8k.png`, `wyrm_tags.png` and every arena background.
  It does not embed or expose the native engine render surface.
- Generated a reviewable Swift catalog from the authoritative C tables: all 66
  presets, 42 atlas colour groups, 32 accessories, 164 tags and 22 backgrounds.
- Added real accessory placement, animated tag rope/art, custom bead-pattern
  editing, tag motion controls and exact background previews.
- Downsamples atlas/background images off the main thread, crops once, keeps
  stable grid identity and uses lazy grids to avoid launch hangs and scroll
  churn.
- Added a bounded Swift-to-C skin mailbox. Selections are applied and saved on
  the engine thread; SwiftUI never mutates engine state directly.

## Validation plan

- Regenerate the catalog and verify its counts against the engine source.
- Run arena lifecycle, full-screen shell and Skin Studio source/asset contracts.
- Compile iPhoneOS and iPhone Simulator targets in Apple CI.
- Launch the overview and Tags editor in Simulator, require all texture-cache
  counts in logs, and capture both screens for visual inspection.
- Continue the existing rotated lobby, offline AI and live online-arena smoke
  gates to protect the gameplay baseline.

## Expected artifacts

- `Wyrm-0.13.0-build-39-unsigned.ipa`
- `Wyrm-0.13.0-build-39-simulator.app.zip`
- `SHA256SUMS`, screenshots and runtime logs
