# Wyrm iOS 0.11.2 (36)

Build 36 corrects the production shell geometry reported from the iPhone build.

## Changes

- Moves full-screen safe-area ownership to the root `GeometryReader`, removing the doubled top inset that left parent pages visible above detail routes.
- Makes every pushed detail route cover the complete application canvas while preserving one-level back navigation and blur/spring transitions.
- Rebuilds the floating bottom navigation at the compact reference dimensions: 16-point horizontal inset, 56-point height and a 14-18 point visual bottom margin.
- Keeps the Wyrm rounded-rectangle silhouette, strengthens foreground contrast and separates glass, selection and label compositing layers.
- Uses native interactive Liquid Glass on iOS 26 with a restrained Wyrm paper tint and keeps the earlier material fallback for iOS 15-25.
- Presents the arena directory full-screen instead of as a system half-sheet.
- Adds dedicated Simulator screenshots for the Social root and full-screen Leaderboard route to the CI evidence bundle.

## Acceptance target

- Social root shows a compact readable floating navigation bar with an intentional bottom inset.
- Leaderboard begins directly below the status safe area and completely hides the Social parent page.
- Existing authentication, settings, native lobby and online arena smoke checks remain green.
