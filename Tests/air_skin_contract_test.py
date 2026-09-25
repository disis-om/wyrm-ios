#!/usr/bin/env python3
"""Contracts for the Android (AIR) Build-a-Slither colour wheel and beads.

Runs after Scripts/prepare-original-engine.py, so the prepared engine tree
is checked as well as the sources that produce it.
"""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
PICKER = (ROOT / "SourcesShell/WyrmAirSkinPicker.swift").read_text()
STUDIO = (ROOT / "SourcesShell/WyrmSkinStudio.swift").read_text()
ENTRY = (ROOT / "SourcesShell/WyrmDesignEntry.swift").read_text()
PREPARE = (ROOT / "Scripts/prepare-original-engine.py").read_text()
PORT = (ROOT / "Scripts/air_skin_textures.py").read_text()
SPEC = (ROOT / "original-engine.yml").read_text()
MAIN = (ROOT / "SourcesOriginal/Main.m").read_text()
AIR_ATLAS = ROOT / "Resources/AirSkin/tex_atlas_8k.png"
WHEEL = ROOT / "Resources/AirSkin/air_colour_wheel.png"
PREPARED_REDRAW = ROOT / "build-original-source/app/src/game/redraw.c"
PREPARED_ATLAS = ROOT / "build-original-source/app/res/textures/tex_atlas_8k.png"
PREPARED_CALLBACK = ROOT / "build-original-source/app/src/network/callback.c"

pinned = re.search(r'AIR_ATLAS_SHA256 = "([0-9a-f]{64})"', PREPARE)
checks = {
    # Colour model: a transcription, not an imitation.
    "wheel pointer uses AIR's radii and limit": "pointerLimit = 128.0 - 24.0 + 3.0" in PICKER and "bezelPointerRadius = 151.0" in PICKER and "let inner = 16.0, outer = 24.0, rad = 128.0" in PICKER,
    "hue channels use Mod.closestMod with AS3 remainder": "static func closestMod" in PICKER and "truncatingRemainder(dividingBy: period)" in PICKER,
    "bezel lightens to 1 and darkens to -0.5": "1.1 * (1 - amount)" in PICKER and "max(-0.5, -amount * 0.5)" in PICKER,
    "bezel shading rounds like Math.round": "(v + 0.5).rounded(.down)" in PICKER,
    "body tint applies nsk_min2c lift": "if mid + hi < 255" in PICKER and "1 + (255 - (mid + hi)) / 2" in PICKER,
    "AIR texture named in the alpha byte": "0xFE00_0000" in PICKER and "0xFD00_0000" in PICKER,
    "arena gets the nearest non-dead colour group": "static func nearestGroup" in PICKER and "WyrmSkinCatalog.validGroups" in PICKER and "0.30, dg = (c.1 - g) * 0.59, db = (c.2 - b) * 0.11" in PICKER,
    "palette matches engine cg_colors row count": PICKER.count("(0.") + PICKER.count("(0, ") + PICKER.count("(1, 1, 1)") >= 42,
    # Liquid Glass chrome with an iOS 15 fallback.
    "Liquid Glass on iOS 26 with material fallback": "if #available(iOS 26.0, *)" in PICKER and "glassEffect(glass, in: shape)" in PICKER and ".ultraThinMaterial" in PICKER and "#if compiler(>=6.2)" in PICKER,
    "bezel is tinted with the unshaded colour": "bezel(tint: Color(airRGB: pure)" in PICKER,
    # Build 56 device report: live glass on moving parts flickered.
    "moving knobs and bezel carry no live glass": "airGlass" not in PICKER[PICKER.index("private func bezel("):PICKER.index("private func dragChanged(")],
    "one wheel-wide drag that beats the scroll view": PICKER.count(".highPriorityGesture(DragGesture(minimumDistance: 0)") == 1 and ".contentShape(Rectangle())" in PICKER,
    "pointer grabbed on the knob moves by the drag": "drag = .pointer(x: pointerX, y: pointerY)" in PICKER and "originX + Double(value.translation.width / unit)" in PICKER,
    "drag stays local; storage is written on lift": "private func dragEnded()" in PICKER and "storedRGB = Int(rgb)" in PICKER and "@AppStorage(" not in PICKER,
    "toggle button is glass": "struct WyrmAirWheelToggle" in PICKER and ".airGlass(Circle())" in PICKER,
    # Studio wiring.
    "pattern toggle swaps the bead grid for the wheel": "WyrmAirWheelToggle(showingWheel: showingWheel)" in STUDIO and "if showingWheel {" in STUDIO and "airWheelPanel" in STUDIO,
    "exactly AIR's first two beads are offered": "ForEach(0..<2, id: \\.self) { kind in" in PICKER and "beads: textures.airBeads" in STUDIO,
    "wheel bead keeps exact RGB and a nearest group": "WyrmAirSkin.nearestGroup(rgb)" in STUDIO and "WyrmAirSkin.marker(kind: kind) | rgb" in STUDIO,
    "wheel state persists": all(k in STUDIO for k in ("air-pointer-x", "air-pointer-y", "air-bezel", "air-rgb")),
    "studio crops the AIR atlas cells": "x: Double(2 + kind) / 7, y: 6.0 / 9" in STUDIO and "width: 102.0 / 64 / 7, height: 102.0 / 64 / 9" in STUDIO,
    "preview tints AIR beads with the body tint": "WyrmAirSkin.bodyTint(rgba)" in STUDIO,
    "preview draws ksmc in AIR order": "stride(from: 8, through: 0, by: -1)" in STUDIO and "for n in 1...4 { airShadow(totalSegments - n" in STUDIO and "airShadow(codeIndex - 4" in STUDIO,
    "wheel has a smoke entry": '--smoke-skin-wheel' in STUDIO and '--smoke-skin-wheel' in ENTRY,
    # Assets.
    "port keeps the calibrated Flash circle": "FLASH_CIRCLE_BIAS = 0.2" in PORT,
    "AIR atlas is committed and matches its pin": AIR_ATLAS.is_file() and pinned is not None and hashlib.sha256(AIR_ATLAS.read_bytes()).hexdigest() == pinned.group(1),
    "colour wheel image is committed and bundled": WHEEL.is_file() and "Resources/AirSkin/air_colour_wheel.png" in SPEC,
    "app bundles the prepared res tree": "- path: build-original-source/app/res" in SPEC and "- path: SharedEngine/app/res" not in SPEC,
    "installed assets refresh on a new revision": 'assetRevision = @"56-air-skin"' in MAIN and "removeItemAtURL:assets" in MAIN and "user.dat" in MAIN,
}

if PREPARED_ATLAS.is_file():
    checks["prepared atlas is the AIR atlas"] = PREPARED_ATLAS.read_bytes() == AIR_ATLAS.read_bytes()
if PREPARED_REDRAW.is_file():
    redraw = PREPARED_REDRAW.read_text()
    checks["engine helpers appear once"] = redraw.count("static int apple_air_kind(uint32_t rgba)") == 1 and redraw.count("static vec4s apple_air_tint(") == 1
    checks["engine draws AIR bead UV and tint"] = "? apple_air_bead_uv(apple_air_kind(built))" in redraw and "? apple_air_tint(built, a)" in redraw
    checks["engine stamps ksmc head, tail and interleaved"] = redraw.count("apple_air_shadow(env, p, apple_air_half") == 3
    checks["Wyrm tail shadow skips AIR beads"] = "!(apple_air_any && apple_air_kind_at(env, o, (int)j) >= 0)" in redraw

if PREPARED_CALLBACK.is_file():
    callback = PREPARED_CALLBACK.read_text()
    checks["arena skin bytes logged without nickname, capped"] = 'SDL_Log("Wyrm arena skin id=%d len=%d bytes=%s", id, skl, hex);' in callback and "apple_skin_logged < 24" in callback

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    raise SystemExit(f"{len(failed)} AIR skin contract(s) failed")
print(f"AIR skin contracts: {len(checks)}/{len(checks)} passed")
