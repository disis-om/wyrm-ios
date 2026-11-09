"""Bake the original minimap disc for every floor (OM, 2026-11-01).

Main.as setMinimapSize (18567-18705), step for step, at mmsz 80 with the map at
the top left (mtl_offset 23):
  - a 104 x 134 bitmap; the disc (radius 40) at (52, 75) is its alpha;
  - the floor image scaled by max(1, 512 / short side) x 0.5, BlurFilter(64, 64,
    3), centred, then the classic floor x0.6 + 4, then x0.75 (bgl) or
    x1.35 + 12;
  - the top-left and bottom-right quarters lifted by #202020 (ADD);
  - DropShadowFilter(3, 90, black, 0.5, 12, 12, 1, 3) under it all.
The "server N" line is the same bitmap's text (Nunito Bold 18, alpha 0.75,
under the same shadow): "server " and the ten digits are baked as pieces so
any number can be set at run time. Floors the original never had count as
bgl when their mean is light (else their disc washes out under white cells).

Usage: python Scripts/generate-minimap-floors.py   (writes both trees)
"""
from pathlib import Path
import re
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT.parent / 'Wyrm Android'
TREES = [ANDROID, ROOT / 'SharedEngine']
W, H, CX, CY, R = 104, 134, 52, 75, 40
MTL = 23
BGL = {"bluecube", "redcube", "purplecube", "hexb", "snakey", "circuits", "circuits2",
       "stainedglass", "leaves", "hexice", "paint", "kitties", "hearts", "seigaiha",
       "graygrid", "asanoha"}


def box(a, size, axis):
    """One pass of Flash's box blur: `size` pixels wide, transparent outside."""
    if size <= 1:
        return a
    pad = [(0, 0)] * a.ndim
    lo, hi = size // 2, size - size // 2
    pad[axis] = (lo, hi)
    p = np.pad(a, pad)
    c = np.cumsum(p, axis=axis, dtype=np.float64)
    c = np.concatenate([np.zeros_like(np.take(c, [0], axis=axis)), c], axis=axis)
    n = a.shape[axis]
    return (np.take(c, range(size, size + n), axis=axis) - np.take(c, range(0, n), axis=axis)) / size


def blur(a, size, passes=3):
    for _ in range(passes):
        a = box(box(a, size, 0), size, 1)
    return a


def disc_mask():
    """Flash's anti-aliased circle, 4 x 4 supersampled."""
    s = 4
    yy, xx = np.mgrid[0:H * s, 0:W * s]
    inside = ((xx + 0.5) / s - CX) ** 2 + ((yy + 0.5) / s - CY) ** 2 <= R * R
    return inside.reshape(H, s, W, s).mean(axis=(1, 3))


def floor_disc(entry):
    fid, path = entry
    rgb = np.zeros((H, W, 3))
    if path:
        img = Image.open(ANDROID / path).convert('RGB')
        k = max(1.0, 512 / min(img.size)) * 0.5
        size = (max(1, int(img.size[0] * k)), max(1, int(img.size[1] * k)))
        small = np.asarray(img.resize(size, Image.NEAREST), dtype=np.float64)
        # Premultiplied blur: opaque inside, transparent beyond the edges.
        alpha = blur(np.ones(small.shape[:2]), 64)
        colour = np.stack([blur(small[..., i], 64) for i in range(3)], -1)
        ox = int(round(-size[0] / 2 + W / 2))
        oy = int(round(-size[1] / 2 + H / 2 + MTL))
        for y in range(H):
            sy = y - oy
            if not 0 <= sy < size[1]:
                continue
            for x in range(W):
                sx = x - ox
                if 0 <= sx < size[0]:
                    rgb[y, x] = colour[sy, sx]  # premultiplied: over black
        if fid == 'classic':
            rgb = rgb * 0.6 + 4
        light = fid in BGL
        if fid.startswith('wyrm_'):
            mean = np.asarray(img, dtype=np.float64).mean(axis=(0, 1))
            light = (0.2126 * mean[0] + 0.7152 * mean[1] + 0.0722 * mean[2]) / 255 > 0.40
        rgb = rgb * 0.75 if light else rgb * 1.35 + 12
        rgb = np.clip(rgb, 0, 255)
    quarter = np.zeros((H, W, 1))
    quarter[MTL:MTL + 52, 0:52] = 32
    quarter[MTL + 52:MTL + 104, 52:104] = 32
    rgb = np.clip(rgb + quarter, 0, 255)
    return rgb, disc_mask()


def drop_shadow(rgb, alpha):
    """DropShadowFilter(3, 90, black, 0.5, 12, 12, 1, 3), knockout off."""
    shifted = np.zeros_like(alpha)
    shifted[3:] = alpha[:-3]
    shadow = np.clip(blur(shifted, 12) * 0.5, 0, 1)
    out_a = alpha + shadow * (1 - alpha)
    out_rgb = np.where(out_a[..., None] > 0, rgb * alpha[..., None] / np.maximum(out_a, 1e-6)[..., None], 0)
    return out_rgb, out_a


def label_piece(text, font):
    """One piece of "server N": white at 0.75 under the minimap's shadow."""
    pad = 24
    asc, desc = font.getmetrics()
    w = int(np.ceil(font.getlength(text))) + pad * 2
    h = asc + desc + pad * 2
    mask = Image.new('L', (w, h))
    ImageDraw.Draw(mask).text((pad, pad + asc), text, font=font, fill=255, anchor='ls')
    a = np.asarray(mask, dtype=np.float64) / 255 * 0.75
    rgb, out_a = drop_shadow(np.full(a.shape + (3,), 255.0), a)
    img = np.dstack([rgb, out_a * 255]).round().clip(0, 255).astype(np.uint8)
    return img, pad, pad + asc, font.getlength(text)


def main():
    table = (ANDROID / 'app/src/game/backgrounds.h').read_text(encoding='utf-8')
    entries = [(m.group(1), m.group(2)) for m in
               re.finditer(r'\{"([a-z0-9_]+)", "[^"]*", (?:"([^"]+)"|NULL)', table)]
    assert len(entries) >= 48, len(entries)
    font = ImageFont.truetype(str(ANDROID / 'app/res/fonts/nunito_bold.ttf'), 18)
    pieces = [label_piece(t, font) for t in ['server '] + [str(d) for d in range(10)]]
    cols = 9
    rows = (len(entries) + cols - 1) // cols
    atlas_w = 1024
    atlas_h = 1024
    atlas = np.zeros((atlas_h, atlas_w, 4), dtype=np.uint8)
    floors = []
    for i, entry in enumerate(entries):
        rgb, alpha = floor_disc(entry)
        rgb, alpha = drop_shadow(rgb, alpha)
        x, y = (i % cols) * (W + 4) + 2, (i // cols) * (H + 4) + 2
        atlas[y:y + H, x:x + W] = np.dstack([rgb, alpha * 255]).round().clip(0, 255).astype(np.uint8)
        floors.append((x, y))
    px, py, row_h = 2, rows * (H + 4) + 4, 0
    labels = []
    for img, ox, base, advance in pieces:
        h, w = img.shape[:2]
        if px + w + 2 > atlas_w:
            px, py, row_h = 2, py + row_h + 4, 0
        assert py + h <= atlas_h
        atlas[py:py + h, px:px + w] = img
        labels.append((px, py, w, h, ox, base, advance))
        px += w + 4
        row_h = max(row_h, h)
    header = ['/* Generated by Wyrm iOS/Scripts/generate-minimap-floors.py; do not edit. */',
              '#ifndef WYRM_MINIMAP_ART_DATA_H', '#define WYRM_MINIMAP_ART_DATA_H',
              '/* The baked original minimap per floor (BACKGROUNDS order): a 104 x 134',
              '   bitmap whose disc (radius 40) sits at (52, 75); atlas 1024 x 1024. */',
              f'#define MINIMAP_ART_W {W}', f'#define MINIMAP_ART_H {H}',
              f'#define MINIMAP_ART_CX {CX}', f'#define MINIMAP_ART_CY {CY}', f'#define MINIMAP_ART_R {R}',
              f'static const float MINIMAP_FLOOR_XY[{len(floors)}][2] = {{']
    header += [f'  {{{x}.0f, {y}.0f}},' for x, y in floors]
    header += ['};', '/* "server " then 0-9: atlas x, y, w, h, pen x and baseline inside the',
               '   piece, and the advance (Nunito Bold 18, Main.as\'s TextFormat). */',
               'static const float MINIMAP_LABEL[11][7] = {']
    header += ['  {' + ', '.join(f'{v:.3f}f' for v in piece) + '},' for piece in labels]
    header += ['};', '#endif', '']
    text = '\n'.join(header)
    for tree in TREES:
        (tree / 'app/src/game/minimap_art_data.h').write_text(text, encoding='utf-8', newline='\n')
        Image.fromarray(atlas, 'RGBA').save(tree / 'app/res/textures/minimap_floors.png', optimize=True)
    print(f'baked {len(floors)} floors and {len(labels)} label pieces')


if __name__ == '__main__':
    main()
