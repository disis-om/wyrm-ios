# Phase 1 dependency lock

| Dependency | Version | Official asset | SHA-256 | Use |
|---|---:|---|---|---|
| SDL3 | 3.4.16 | `SDL3-3.4.16.dmg` from `libsdl-org/SDL` release `release-3.4.16` | `675660a9e457239af615f9e41f788612168d1639b9d2eda2957e8dace26687fd` | Dynamic XCFramework, embedded in app |
| MoltenVK | 1.4.2 | `MoltenVK-all.tar` from `KhronosGroup/MoltenVK` release `v1.4.2` | `562a15a29bc358446a56a4091c5f7e08f604184187c1d34f712148b61ef17276` | Static XCFramework plus Vulkan headers |

`Scripts/fetch-ios-dependencies.sh` downloads only these pinned assets, verifies their hashes, and prepares `Vendor/` on the macOS build runner. Generated vendor binaries are not source authority.

