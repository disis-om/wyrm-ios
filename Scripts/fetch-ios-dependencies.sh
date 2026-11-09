#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
WORK_DIR="$(mktemp -d)"
SDL_MOUNT="$WORK_DIR/sdl-volume"

SDL_VERSION="3.4.16"
SDL_ARCHIVE="SDL3-${SDL_VERSION}.dmg"
SDL_URL="https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VERSION}/${SDL_ARCHIVE}"
SDL_ASSET_API="https://api.github.com/repos/libsdl-org/SDL/releases/assets/541452150"
SDL_SHA256="675660a9e457239af615f9e41f788612168d1639b9d2eda2957e8dace26687fd"

MOLTENVK_VERSION="1.4.2"
MOLTENVK_ARCHIVE="MoltenVK-all.tar"
MOLTENVK_URL="https://github.com/KhronosGroup/MoltenVK/releases/download/v${MOLTENVK_VERSION}/${MOLTENVK_ARCHIVE}"
MOLTENVK_ASSET_API="https://api.github.com/repos/KhronosGroup/MoltenVK/releases/assets/488518329"
MOLTENVK_SHA256="562a15a29bc358446a56a4091c5f7e08f604184187c1d34f712148b61ef17276"

mounted=0
cleanup() {
  if [[ "$mounted" == "1" ]]; then
    hdiutil detach "$SDL_MOUNT" -quiet || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$VENDOR_DIR" "$SDL_MOUNT"

# The browser download endpoint can return persistent HTTP 504 while the
# public release-asset API still serves the exact pinned bytes. Both paths
# must pass the same SHA-256 check below; no credentials are required.
download_release() {
  if curl --fail --location --retry 3 --connect-timeout 30 --output "$3" "$1"; then
    return 0
  fi
  curl --fail --location --retry 3 --connect-timeout 30 \
    --header 'Accept: application/octet-stream' --output "$3" "$2"
}

download_release "$SDL_URL" "$SDL_ASSET_API" "$WORK_DIR/$SDL_ARCHIVE"
echo "$SDL_SHA256  $WORK_DIR/$SDL_ARCHIVE" | shasum -a 256 --check
hdiutil attach "$WORK_DIR/$SDL_ARCHIVE" -nobrowse -readonly -mountpoint "$SDL_MOUNT" -quiet
mounted=1
SDL_XCFRAMEWORK="$(find "$SDL_MOUNT" -name SDL3.xcframework -type d -print -quit)"
if [[ -z "$SDL_XCFRAMEWORK" ]]; then
  echo "SDL3.xcframework was not present in the pinned release image" >&2
  exit 1
fi
rm -rf "$VENDOR_DIR/SDL3.xcframework"
ditto "$SDL_XCFRAMEWORK" "$VENDOR_DIR/SDL3.xcframework"
hdiutil detach "$SDL_MOUNT" -quiet
mounted=0

download_release "$MOLTENVK_URL" "$MOLTENVK_ASSET_API" "$WORK_DIR/$MOLTENVK_ARCHIVE"
echo "$MOLTENVK_SHA256  $WORK_DIR/$MOLTENVK_ARCHIVE" | shasum -a 256 --check
mkdir -p "$WORK_DIR/moltenvk"
tar -xf "$WORK_DIR/$MOLTENVK_ARCHIVE" -C "$WORK_DIR/moltenvk"
rm -rf "$VENDOR_DIR/MoltenVK.xcframework" "$VENDOR_DIR/MoltenVK"
ditto "$WORK_DIR/moltenvk/MoltenVK/MoltenVK/static/MoltenVK.xcframework" "$VENDOR_DIR/MoltenVK.xcframework"
ditto "$WORK_DIR/moltenvk/MoltenVK/MoltenVK/include" "$VENDOR_DIR/MoltenVK/include"

test -f "$VENDOR_DIR/SDL3.xcframework/Info.plist"
test -f "$VENDOR_DIR/MoltenVK.xcframework/Info.plist"
test -f "$VENDOR_DIR/MoltenVK/include/vulkan/vulkan.h"
echo "Prepared SDL3 $SDL_VERSION and MoltenVK $MOLTENVK_VERSION"

