# Wyrm iOS

The official iOS port of Wyrm. Phase 1 proved a UIKit + SwiftUI shell, SDL3 initialization, and a Vulkan clear frame presented through MoltenVK to a UIKit-owned `CAMetalLayer` in the Appetize simulator. Phase 2 is in progress: the original atlas and shaders are bundled, verified and prepared for GPU upload, but the real Wyrm snake is not rendered yet.

The iOS project is generated from `project.yml`. Third-party Apple binaries are downloaded only on macOS through `Scripts/fetch-ios-dependencies.sh` and are verified against `DEPENDENCIES.lock.md`.

The GitHub Actions artifact is intentionally unsigned. AltStore applies the user's Apple ID signature and provisioning when installing it on a personal iPhone.
