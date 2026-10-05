#!/usr/bin/env python3
"""Source and asset contracts for the native SwiftUI Skin Studio."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
CATALOG = (ROOT / "SourcesShell/WyrmSkinCatalog.generated.swift").read_text()
STUDIO = (ROOT / "SourcesShell/WyrmSkinStudio.swift").read_text()
MAIN = (ROOT / "SourcesShell/WyrmDesignMain.swift").read_text()
MAILBOX = (ROOT / "SourcesOriginal/AppleSkinMailbox.c").read_text()
SWING = (ROOT / "SourcesShell/WyrmGravityTag.swift").read_text()

checks = {
    "catalog has all 66 original presets": CATALOG.count("        [") == 66,
    "catalog has all 164 original tags": len(re.findall(r"\.init\(id: \d+, width:", CATALOG)) == 164,
    "catalog has all 32 accessories": len(re.findall(r"\.init\(id: \d+, scale:", CATALOG)) == 32,
    # The original 22 plus Black and seven Wyrm floors (OM, 2026-10-01).
    "catalog has all 30 arena backgrounds": len(re.findall(r"\.init\(id: \d+, key:", CATALOG)) == 30,
    "Black is background 22": '.init(id: 22, key: "black"' in CATALOG,
    "pickers show Wyrm, Black, None first": "backgroundOrder: [Int] = [0, 22, 1," in CATALOG,
    "body preview crops the original atlas": "res/textures/tex_atlas_8k.png" in STUDIO and "Self.crop(atlas" in STUDIO,
    "tag preview crops the original tag atlas": "res/textures/wyrm_tags.png" in STUDIO and "Self.crop(tagAtlas" in STUDIO,
    "large images are downsampled off main": "DispatchQueue.global(qos: .userInitiated)" in STUDIO and "CGImageSourceCreateThumbnailAtIndex" in STUDIO,
    "preview stays fixed above inline content": "WyrmSkinPreview" in STUDIO and "ScrollView(showsIndicators: false)" in STUDIO,
    "preview uses native two-row 256-segment body": "let segmentsPerRow = 128" in STUDIO and "let totalSegments = segmentsPerRow * 2" in STUDIO,
    "preview uses native bead scale and spacing": "let step = 8 * (scale / 48)" in STUDIO and "let gap = scale * 0.16" in STUDIO,
    "preview omits the arena-only outer body shadow": "private(set) var shadow: CGImage?" not in STUDIO and "shadowContext.draw" not in STUDIO,
    "preview batches its 256 beads in an asynchronous canvas": "rendersAsynchronously: true" in STUDIO and "rotated.rotate(by: .degrees(180))" in STUDIO,
    "overview has no explanatory captions or asset status": "Original engine skins" not in STUDIO and "ORIGINAL TEXTURES READY" not in STUDIO,
    "preview has no technical caption": "NATIVE ATLAS PREVIEW" not in STUDIO,
    # Two ForEach over plain Ints in one lazy grid shared ids and recycled the
    # wrong cells while scrolling (OM, 2026-10-04): one identity per bead.
    "bead grid gives every bead its own identity": "private enum WyrmPatternBead: Hashable" in STUDIO and "ForEach(cells, id: \\.self)" in STUDIO and "ForEach(0..<WyrmBead.count, id: \\.self)" not in STUDIO and "ForEach(WyrmSkinCatalog.validGroups, id: \\.self)" not in STUDIO,
    # NTL 9.68's chooser rope (OM, 2026-10-05): pull .3 back, sway .14, default
    # path, bobble .15, one step per drawn frame; no device gravity.
    "tag swings like NTL's chooser without reading device gravity": "CMMotionManager" not in SWING and "0..<10" in SWING and "- 0.3 * u" in SWING and "0.14 * u * cos(Double(frame) / 23" in SWING and "let mb = 6.94" in SWING and "0.15 * d" in SWING and "TimelineView(.animation" in SWING,
    "skin code supports original 256 slots": "prefix(256)" in CATALOG and "/ 256 beads" in STUDIO,
    "building shows only placed beads; the engine wears the repeat": "customGroups[$0] : -1" in STUDIO and "if group < 0 { continue }" in STUDIO and "return (0..<256).map { source[$0 % source.count] }" in STUDIO,
    "partial code repeats after leaving pattern editor": "source[$0 % source.count]" in STUDIO and "editingPattern = false; apply()" in STUDIO,
    "preset strip draws no beads beyond its native 128-slot row": "let count = min(128, max(1," in STUDIO,
    "Build a Wyrm offers the 42 original beads and Wyrm's own in one grid": "WyrmSkinCatalog.validGroups.map(WyrmPatternBead.slither)" in STUDIO and "(0..<WyrmBead.count).map(WyrmPatternBead.wyrm)" in STUDIO and "allBeadsGrid" in STUDIO and 'WyrmSectionLabel("Wyrm beads")' not in STUDIO and "ForEach(0..<400" not in STUDIO and 'Colour studio' not in STUDIO and "queued.colors" in MAILBOX and "settings->skin_rgba" in MAILBOX,
    "picker sprites use shadowless high-resolution derivatives": "accessoryThumbnails" in STUDIO and "tagThumbnails" in STUDIO and "removingSoftShadow" in STUDIO,
    "long editors are constrained to the lower viewport": ".frame(maxHeight: .infinity)" in STUDIO and ".layoutPriority(1)" in STUDIO,
    "skin rows no longer push detail routes": "WyrmSkinRoot(open:" not in MAIN and "open(.presets)" not in MAIN,
    "selection crosses a bounded engine mailbox": "WyrmIOSQueueSkinSelection" in MAILBOX and "save_user_settings(settings)" in MAILBOX,
}

for relative in [
    "SharedEngine/app/res/textures/tex_atlas_8k.png",
    "SharedEngine/app/res/textures/wyrm_tags.png",
    "SharedEngine/app/res/textures/background_4k.png",
]:
    checks[f"bundled asset exists: {Path(relative).name}"] = (ROOT / relative).is_file()

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    raise SystemExit(f"{len(failed)} Skin Studio contract(s) failed")
print(f"Skin Studio contracts: {len(checks)}/{len(checks)} passed")
