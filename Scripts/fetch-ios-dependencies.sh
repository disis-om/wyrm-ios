#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
WORK_DIR="$(mktemp -d)"
SDL_MOUNT="$WORK_DIR/sdl-volume"

SDL_VERSION="3.4.16"
SDL_ARCHIVE="SDL3-${SDL_VERSION}.dmg"
SDL_URL="https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VERSION}/${SDL_ARCHIVE}"
SDL_SHA256="675660a9e457239af615f9e41f788612168d1639b9d2eda2957e8dace26687fd"

MOLTENVK_VERSION="1.4.2"
MOLTENVK_ARCHIVE="MoltenVK-all.tar"
MOLTENVK_URL="https://github.com/KhronosGroup/MoltenVK/releases/download/v${MOLTENVK_VERSION}/${MOLTENVK_ARCHIVE}"
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

curl --fail --location --retry 3 --output "$WORK_DIR/$SDL_ARCHIVE" "$SDL_URL"
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

curl --fail --location --retry 3 --output "$WORK_DIR/$MOLTENVK_ARCHIVE" "$MOLTENVK_URL"
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

