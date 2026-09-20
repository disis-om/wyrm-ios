# Wyrm iOS 0.11.1 (35)

Build 35 recompiles the Build 34 Play/Social slice with Xcode 26 so the custom
navigation surface uses Apple's native interactive Liquid Glass on iOS 26.

- The tab bar and selected pill share a `GlassEffectContainer`.
- Both surfaces use interactive glass; the selected pill has a stable
  `glassEffectID` while it stretches and springs under the player's finger.
- iOS 15 through iOS 25 continue to use the carefully matched material fallback.
- The original C engine, service contracts and Build 34 product scope are
  unchanged.
