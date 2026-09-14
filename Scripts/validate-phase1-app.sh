#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?usage: validate-phase1-app.sh /path/to/Wyrm.app}"
EXECUTABLE="$APP_PATH/Wyrm"

test -d "$APP_PATH"
test -x "$EXECUTABLE"
test -d "$APP_PATH/Frameworks/SDL3.framework"
test -f "$APP_PATH/EngineAssets/SHA256SUMS"
test -f "$APP_PATH/EngineAssets/tex_atlas_8k.png"
test -f "$APP_PATH/EngineAssets/shaders/bpv.spv"

echo "== bundled original Wyrm engine assets =="
(cd "$APP_PATH/EngineAssets" && shasum -a 256 -c SHA256SUMS)

echo "== executable architectures =="
lipo -info "$EXECUTABLE"

echo "== deployment target =="
xcrun vtool -show-build "$EXECUTABLE" | grep -E 'platform|minimum|sdk'

echo "== dynamic linkage =="
otool -L "$EXECUTABLE"
otool -L "$APP_PATH/Frameworks/SDL3.framework/SDL3"

echo "== custom UIKit SDL startup handshake =="
nm "$EXECUTABLE" | grep '_SDL_SetMainReady'

echo "== MoltenVK static symbols =="
nm "$EXECUTABLE" | grep -E '_vkCreateInstance|_vkCreateMetalSurfaceEXT|_vkQueuePresentKHR'

echo "== bundle metadata =="
plutil -p "$APP_PATH/Info.plist" | grep -E 'CFBundleIdentifier|CFBundleShortVersionString|CFBundleVersion|MinimumOSVersion'
