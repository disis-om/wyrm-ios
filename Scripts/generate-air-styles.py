#!/usr/bin/env python3
"""Add the slither Android (AIR) client's four bead styles to the engine atlas
(OM, 2026-10-26). Run after generate-air-skin-assets.py and
generate-wyrm-beads.py.

The AIR Build-a-Slither wheel has six bead styles (`nsks` 0..5): plain and rim
(already in the atlas at cells (6,2) and (6,3)) and four drawn ones,
`sg_roundfluffy`, `sg_dragonscales`, `sg_teardrop`, `sg_egg`, each a white
picture tinted by the bead's colour with a `_shine` picture over it. They were
read from the shipped client's baked sheet (sheet0, finishTextures rect
entries 205/206, 200/195, 218/217, 207/208) into Resources/AirSkin/styles: each
picture's pivot (height / 2, height / 2), the bead's centre, sits in the middle
of a 160 px square (2.5 beads of the client's 64 px), scaled to 224 px.

They go into eight empty 224 px half-cells (rows and columns of 224 px):
  base:  roundfluffy (12,3)  dragonscales (13,3)  teardrop (14,3)  egg (15,3)
  shine: roundfluffy (15,0)  dragonscales (15,1)  teardrop (15,2)  egg (16,8)
None of them is inside another sprite's uv rect (SHADOW_UV ends at x 672 and y
3360, the AIR shadow starts at x 1792). game/redraw.c apple_air_style_uv reads
the same table.

Writes Resources/AirSkin/tex_atlas_8k.png and Wyrm Android's
app/res/textures/tex_atlas_8k.png and prints the new hash for
prepare-original-engine.py's AIR_ATLAS_SHA256.
"""
import hashlib
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ATLAS = ROOT / "Resources/AirSkin/tex_atlas_8k.png"
ANDROID = ROOT.parent / "Wyrm Android/app/res/textures/tex_atlas_8k.png"
STYLES = ROOT / "Resources/AirSkin/styles"
HALF = 224
CELLS = {
    ("roundfluffy", "base"): (12, 3), ("dragonscales", "base"): (13, 3),
    ("teardrop", "base"): (14, 3), ("egg", "base"): (15, 3),
    ("roundfluffy", "shine"): (15, 0), ("dragonscales", "shine"): (15, 1),
    ("teardrop", "shine"): (15, 2), ("egg", "shine"): (16, 8),
}


def build():
    atlas = np.array(Image.open(ATLAS).convert("RGBA"))
    if atlas.shape[:2] != (4032, 3136):
        raise SystemExit(f"unexpected atlas size {atlas.shape}")
    for (name, kind), (row, col) in CELLS.items():
        picture = np.array(Image.open(STYLES / f"{name}_{kind}.png").convert("RGBA"))
        if picture.shape[:2] != (HALF, HALF):
            raise SystemExit(f"{name}_{kind}: {picture.shape}")
        y, x = row * HALF, col * HALF
        region = atlas[y:y + HALF, x:x + HALF]
        if region[..., 3].max() != 0 and not np.array_equal(region, picture):
            raise SystemExit(f"half-cell {(row, col)} is not empty")
        atlas[y:y + HALF, x:x + HALF] = picture
    image = Image.fromarray(atlas, "RGBA")
    image.save(ATLAS, optimize=True)
    ANDROID.write_bytes(ATLAS.read_bytes())
    print("tex_atlas_8k.png", hashlib.sha256(ATLAS.read_bytes()).hexdigest())


if __name__ == "__main__":
    build()
