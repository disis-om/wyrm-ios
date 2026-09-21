#!/usr/bin/env python3
"""Source and asset contracts for the native SwiftUI Skin Studio."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
CATALOG = (ROOT / "SourcesShell/WyrmSkinCatalog.generated.swift").read_text()
STUDIO = (ROOT / "SourcesShell/WyrmSkinStudio.swift").read_text()
MAIN = (ROOT / "SourcesShell/WyrmDesignMain.swift").read_text()
MAILBOX = (ROOT / "SourcesOriginal/AppleSkinMailbox.c").read_text()

checks = {
    "catalog has all 66 original presets": CATALOG.count("        [") == 66,
    "catalog has all 164 original tags": len(re.findall(r"\.init\(id: \d+, width:", CATALOG)) == 164,
    "catalog has all 32 accessories": len(re.findall(r"\.init\(id: \d+, scale:", CATALOG)) == 32,
    "catalog has all 22 arena backgrounds": len(re.findall(r"\.init\(id: \d+, key:", CATALOG)) == 22,
    "body preview crops the original atlas": "res/textures/tex_atlas_8k.png" in STUDIO and "Self.crop(atlas" in STUDIO,
    "tag preview crops the original tag atlas": "res/textures/wyrm_tags.png" in STUDIO and "Self.crop(tagAtlas" in STUDIO,
    "large images are downsampled off main": "DispatchQueue.global(qos: .userInitiated)" in STUDIO and "CGImageSourceCreateThumbnailAtIndex" in STUDIO,
    "preview stays fixed above inline content": "WyrmSkinPreview" in STUDIO and "ScrollView(showsIndicators: false)" in STUDIO,
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
