#!/usr/bin/env python3
"""Packs the NTL VANCED arrow skins into one atlas for the Apple build.

Source: ../NTL VANCED/sc/*.webp (the owner's own mod folder; not part of this
repository). Output: Resources/ArrowSkins.png, committed, so CI never needs the
mod folder. Every cell is 256 x 256 with the art pointing to the RIGHT (+x):
art that NTL marks `left: true` is turned 180 degrees here, once, instead of on
every frame. The order below is the index the engine and SwiftUI both use —
append only, never reorder, or a saved choice would point at another arrow.

Run from the repository root:  python Scripts/generate-arrow-skins.py
"""

from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "NTL VANCED" / "sc"
OUTPUT = ROOT / "Resources" / "ArrowSkins.png"
CELL = 256
BOX = 232
COLUMNS = 5

# (file, points left in the source art) — same table as NTL_CU.SKINS, minus
# the code-drawn "Vanced arrow" and the custom-image slot.
SKINS = [
    ("blue3d.webp", True), ("1blue3d.webp", True), ("red3d.webp", True),
    ("yellow3d.webp", True), ("redarrow.webp", True), ("wing3d.webp", True),
    ("arrow1.webp", True), ("arrow2.webp", True), ("arrow3.webp", True),
    ("neonice.webp", False), ("neonmag.webp", False), ("volt.webp", False),
    ("inferno.webp", False), ("aqua.webp", False), ("heat.webp", False),
    ("jade.webp", False), ("chrome.webp", False), ("twinvolt.webp", False),
    ("sunset.webp", False), ("streak.webp", False),
]


def main() -> None:
    rows = (len(SKINS) + COLUMNS - 1) // COLUMNS
    atlas = Image.new("RGBA", (COLUMNS * CELL, rows * CELL), (0, 0, 0, 0))
    for index, (name, left) in enumerate(SKINS):
        art = Image.open(SOURCE / name).convert("RGBA")
        if left:
            art = art.rotate(180)
        bounds = art.getbbox()
        if bounds:
            art = art.crop(bounds)
        scale = min(BOX / art.width, BOX / art.height)
        art = art.resize((max(1, round(art.width * scale)), max(1, round(art.height * scale))), Image.LANCZOS)
        x = (index % COLUMNS) * CELL + (CELL - art.width) // 2
        y = (index // COLUMNS) * CELL + (CELL - art.height) // 2
        atlas.alpha_composite(art, (x, y))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUTPUT, optimize=True)
    print(f"{OUTPUT.relative_to(ROOT)}: {len(SKINS)} arrows, {atlas.width}x{atlas.height}")


if __name__ == "__main__":
    main()
