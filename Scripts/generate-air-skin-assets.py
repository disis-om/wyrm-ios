#!/usr/bin/env python3
"""Build the Android (AIR) Build-a-Slither assets for Wyrm iOS.

Writes, deterministically:
  Resources/AirSkin/tex_atlas_8k.png   original engine atlas + three AIR cells
  Resources/AirSkin/air_colour_wheel.png  the AIR hue/saturation disc, 768 px

Atlas cells (448 px = one bead cell, the AIR 64 px bitmaps at 7x):
  (2/7, 6/9)  1 cell      nsk 0  `kmc_ts[9][0]`   plain bead
  (3/7, 6/9)  1 cell      nsk 1  `kmc_ts[29][0]`  dark core, light rim
  (4/7, 6/9)  102/64 cell `ksmc_t` outline + drop shadow under each bead

Optional check against the untouched AIR client (never committed):
  generate-air-skin-assets.py --verify <ffdec image export dir> <Main.as>
compares this port with the baked sheet pixels the shipped app draws.

Run with Python 3 + numpy + Pillow on the owner's machine; CI only verifies
the committed PNG hashes (see prepare-original-engine.py).
"""
import hashlib
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import air_skin_textures as air  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SOURCE_ATLAS = ROOT / "SharedEngine/app/res/textures/tex_atlas_8k.png"
OUT = ROOT / "Resources/AirSkin"
CELL = 448
SCALE = CELL / (2 * air.BEAD_RADIUS)  # 7
CELLS = {
    "bead0": (2 * CELL, 6 * CELL),
    "bead1": (3 * CELL, 6 * CELL),
    "shadow": (4 * CELL, 6 * CELL),
}


def paste(atlas, image, origin):
    x, y = origin
    h, w = image.shape[:2]
    region = atlas[y:y + h, x:x + w]
    if region[..., 3].max() != 0:
        raise SystemExit(f"atlas cell at {origin} is not empty")
    atlas[y:y + h, x:x + w] = image


def build():
    atlas = np.array(Image.open(SOURCE_ATLAS).convert("RGBA"))
    if atlas.shape[:2] != (9 * CELL, 7 * CELL):
        raise SystemExit(f"unexpected atlas size {atlas.shape}")
    paste(atlas, air.bead(0, SCALE), CELLS["bead0"])
    paste(atlas, air.bead(1, SCALE), CELLS["bead1"])
    paste(atlas, air.shadow(SCALE), CELLS["shadow"])
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(OUT / "tex_atlas_8k.png", optimize=True)
    Image.fromarray(air.wheel(3.0), "RGBA").save(OUT / "air_colour_wheel.png", optimize=True)
    for name in ("tex_atlas_8k.png", "air_colour_wheel.png"):
        digest = hashlib.sha256((OUT / name).read_bytes()).hexdigest()
        print(f"{name} {digest}")


def verify(export_dir, main_as):
    """Compare the port with the baked AIR sheets (2048 px level)."""
    text = Path(main_as).read_text(encoding="utf-8")
    start = text.index("internal function finishTextures")
    table = re.search(r"_loc2_ = new <Number>\[([^\]]*)\]", text[start:]).group(1)
    values = [float(v) for v in table.split(",")]
    rects = [values[k:k + 7] for k in range(0, len(values), 7)]
    export = Path(export_dir)
    sheet0 = np.asarray(Image.open(next(export.glob("*_sheet0_a_png.png"))).convert("RGBA")).astype(int)
    sheet1 = np.asarray(Image.open(next(export.glob("*_sheet1_a_png.png"))).convert("RGBA")).astype(int)

    def crop(sheet, entry):
        x, y, w, h = (int(v) for v in rects[entry][1:5])
        return sheet[y:y + h, x:x + w]

    def compare(name, mine, baked):
        mine = mine.astype(int)
        opaque = (mine[..., 3] > 250) & (baked[..., 3] > 250)
        rgb = int(np.abs(mine[..., :3] - baked[..., :3])[opaque].max()) if opaque.any() else 0
        alpha = np.abs(mine[..., 3] - baked[..., 3])
        print(f"{name}: rgb max {rgb}, alpha mean {alpha.mean():.3f} max {alpha.max()}")
        return rgb == 0 and alpha.mean() < 1.0

    # Rect entries identified by exact RGB match in sheet 0 / sheet 1.
    ok = all([
        compare("kmc_ts[9][0]", air.bead(0), crop(sheet0, 25)),
        compare("kmc_ts[29][0]", air.bead(1), crop(sheet0, 61)),
        compare("ksmc_t", air.shadow(), crop(sheet0, 212)),
        compare("cw_t", air.wheel(), crop(sheet1, 345)),
    ])
    if not ok:
        raise SystemExit("AIR texture port does not match the baked sheets")
    print("AIR texture port matches the baked sheets")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--verify":
        verify(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 1:
        build()
    else:
        raise SystemExit(__doc__)
