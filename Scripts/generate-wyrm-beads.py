#!/usr/bin/env python3
"""Paints Wyrm's own beads into the engine atlas (OM, 2026-09-28).

Writes the same atlas to both apps:
  Wyrm iOS/Resources/AirSkin/tex_atlas_8k.png       (then pin its hash in
                                                     Scripts/prepare-original-engine.py)
  Wyrm Android/app/res/textures/tex_atlas_8k.png

Run it after Scripts/generate-air-skin-assets.py, which rebuilds the atlas
from the original and would drop these cells. It is idempotent: the six
target cells are cleared and repainted every time.

Layout. Six atlas cells that nothing else samples (row 7 cols 3 and 6, row 8
cols 0 to 3; the shadow, cursor and AIR-shadow rectangles stop short of them,
and row 8 col 4 holds another sprite)
are each split into four 224 px quarters. Bead k sits in cell k // 4, quarter
k % 4 (x = k % 2, y = (k % 4) // 2). The engine and both Skin Studios use:
  u = (col + qx / 2) / 7,  v = (row + qy / 2) / 9,  size 0.5/7 x 0.5/9.

Overlap. Beads are drawn tail first, so each bead is covered by the next one
towards the head and only its +x side shows (slither's own star beads put their
stars there, between 0.72 and 0.96 of the width). Motifs therefore sit in that
sliver, small enough to show whole even on a tightly packed body; all-over
patterns cover the whole bead. Shading is slither's grey bead (row 1 col 2): a tube, light along
the body's centre line.

Kinds (alpha byte 0xE0 + k in `skin_rgba`; RGB = the colour the arena's
nearest colour group is picked from):
   0 India flag (fixed)   1 star      2 heart       3 dragon scales
   4 stripes              5 dots      6 lightning   7 flame
   8 crescent             9 chrome (fixed)  10 gold (fixed)  11 galaxy (fixed)
  12 honeycomb  13 argyle  14 zigzag  15 carbon fibre  16 tiger  17 circuit
  18 leopard (fixed)  19 lava (fixed)  20 ice (fixed)  21 marble (fixed)
  22 holographic (fixed)  23 camo (fixed)
Every bead is painted in its own colours (OM, 2026-09-28: tinted grey beads
looked greyed out). The patterned painters below still return a 0..1 pattern
value; PALETTES maps each one to its colours.
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
IOS_ATLAS = ROOT / "Resources/AirSkin/tex_atlas_8k.png"
ANDROID_ATLAS = ROOT.parent / "Wyrm Android/app/res/textures/tex_atlas_8k.png"

CELL = 448
GRID = 3                     # beads per cell side (2026-09-28: 3 x 3, for 54 beads)
PER_CELL = GRID * GRID
TILE = CELL // GRID          # 149 px slot
S = 896                      # drawn at 4x, then reduced
MARGIN = 3                   # px of clear space round each bead in its slot
CELLS = [(7, 3), (7, 6), (8, 0), (8, 1), (8, 2), (8, 3)]

BG, MOTIF, EDGE = 0.64, 1.0, 0.30


def template(atlas):
    """slither's grey bead as a shading map and a disc mask, at S x S."""
    cell = atlas.crop((2 * CELL, 1 * CELL, 3 * CELL, 2 * CELL)).resize((S, S), Image.LANCZOS)
    a = np.asarray(cell).astype(np.float32) / 255.0
    return a[:, :, 0], a[:, :, 3]


def grid():
    v, u = np.mgrid[0:S, 0:S].astype(np.float32)
    return (u + 0.5) / S, (v + 0.5) / S


def mask(draw_fn):
    """A 0..1 float mask from a PIL drawing on an S x S canvas (normalised coords)."""
    img = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(img)
    draw_fn(d, lambda p: (p[0] * S, p[1] * S))
    return np.asarray(img).astype(np.float32) / 255.0


def outlined(shape_fn, width=0.022):
    """Fill mask and an outline ring for a polygon/ellipse drawn by shape_fn."""
    fill = mask(lambda d, P: shape_fn(d, P, 255))
    grown = Image.fromarray((fill * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(int(width * S) | 1))
    ring = np.clip(np.asarray(grown).astype(np.float32) / 255.0 - fill, 0, 1)
    return fill, ring


def motif_factor(shape_fn, width=0.022):
    fill, ring = outlined(shape_fn, width)
    f = np.full((S, S), BG, np.float32)
    f = f * (1 - ring) + EDGE * ring
    return f * (1 - fill) + MOTIF * fill


def star_points(cx, cy, R, r, n=5, rot=0.0):
    pts = []
    for i in range(2 * n):
        a = rot + i * math.pi / n
        rad = R if i % 2 == 0 else r
        pts.append((cx + math.cos(a) * rad, cy + math.sin(a) * rad))
    return pts


def poly(points):
    return lambda d, P, fill: d.polygon([P(p) for p in points], fill=fill)


# ---------------------------------------------------------------- tintable

def bead_star():
    return motif_factor(poly(star_points(0.815, 0.5, 0.155, 0.066, rot=0.0)), width=0.018)


def bead_heart():
    pts = []
    s = 0.0078
    for i in range(200):
        t = i / 200 * 2 * math.pi
        hx = 16 * math.sin(t) ** 3
        hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        # Tip (hy = -17) towards the head (-x); lobes towards the tail.
        pts.append((0.82 + hy * s, 0.5 + hx * s))
    return motif_factor(poly(pts), width=0.018)


def bead_scales():
    img = Image.new("L", (S, S), int(BG * 255))
    d = ImageDraw.Draw(img)
    step = 0.19
    radius = step * 0.62
    cols = [1.1 - i * step * 0.62 for i in range(12)]
    # Right to left, so each column overlaps the one on its right: the scale
    # edges face the tail, where the bead shows.
    for ci, x in enumerate(cols):
        off = (ci % 2) * step / 2
        y = -step
        while y < 1.2:
            box = [(x - radius) * S, (y + off - radius) * S, (x + radius) * S, (y + off + radius) * S]
            d.ellipse(box, fill=int(0.95 * 255), outline=int(EDGE * 255), width=int(0.018 * S))
            inner = [(x - radius * 0.55) * S, (y + off - radius * 0.55) * S,
                     (x + radius * 0.35) * S, (y + off + radius * 0.55) * S]
            d.ellipse(inner, fill=255)
            y += step
    return np.asarray(img).astype(np.float32) / 255.0


def bead_stripes():
    u, v = grid()
    phase = ((u + v) / 0.17) % 2.0
    # Soft-edged bands: box-filtered at the 4x size, then reduced.
    band = np.clip(np.minimum(phase, 2.0 - phase) * 6 - 2.5, 0, 1)
    return BG + (MOTIF - BG) * band


def bead_dots():
    u, v = grid()
    f = np.full((S, S), BG, np.float32)
    step = 0.2
    r = 0.062
    for row in range(-1, 8):
        for col in range(-1, 8):
            cx = col * step + (row % 2) * step / 2
            cy = row * step * 0.87
            dist = np.sqrt((u - cx) ** 2 + (v - cy) ** 2)
            dot = np.clip((r - dist) * S / 3 + 0.5, 0, 1)
            f = f * (1 - dot) + MOTIF * dot
    return f


def bead_lightning():
    # Drawn upright (-1..1), then turned so it points along the body (+x).
    raw = [(0.25, -1.0), (-0.45, 0.12), (-0.02, 0.12), (-0.25, 1.0), (0.5, -0.18), (0.06, -0.18), (0.4, -1.0)]
    s = 0.15
    pts = [(0.81 + y * s, 0.5 - x * s) for x, y in raw]
    return motif_factor(poly(pts), width=0.018)


def teardrop(cx, cy, r, tip):
    """A flame body: a circle at (cx, cy) drawn out to a tip `tip` to its right."""
    pts = []
    for i in range(120):
        t = -math.pi / 2 + i / 119 * math.pi
        pts.append((cx - math.cos(t) * r, cy + math.sin(t) * r))
    pts.append((cx + tip, cy))
    return pts


def bead_flame():
    outer = teardrop(0.765, 0.5, 0.09, 0.19)
    inner = teardrop(0.765, 0.5, 0.045, 0.10)
    f = motif_factor(poly(outer), width=0.018)
    core = mask(lambda d, P: d.polygon([P(p) for p in inner], fill=255))
    f = f * (1 - core) + 0.80 * core
    return f


def bead_crescent():
    def shape(d, P, fill):
        d.ellipse([P((0.67, 0.36)), P((0.95, 0.64))], fill=fill)
    fill, ring = outlined(shape, width=0.018)
    bite = mask(lambda d, P: d.ellipse([P((0.735, 0.38)), P((0.975, 0.62))], fill=255))
    fill = np.clip(fill - bite, 0, 1)
    ring = np.clip(ring - bite, 0, 1)
    edge_bite = np.clip(bite - mask(lambda d, P: d.ellipse([P((0.753, 0.398)), P((0.957, 0.602))], fill=255)), 0, 1)
    edge_bite *= mask(lambda d, P: d.ellipse([P((0.661, 0.351)), P((0.959, 0.649))], fill=255))
    ring = np.clip(ring + edge_bite, 0, 1)
    f = np.full((S, S), BG, np.float32)
    f = f * (1 - ring) + EDGE * ring
    return f * (1 - fill) + MOTIF * fill


# ------------------------------------------------------------ fixed colour

def stops(v, table):
    out = np.zeros(v.shape + (3,), np.float32)
    xs = [p for p, _ in table]
    for ch in range(3):
        out[..., ch] = np.interp(v, xs, [c[ch] / 255.0 for _, c in table])
    return out


def highlight(rgb, u, v, cx=0.36, cy=0.30, rx=0.20, ry=0.09, strength=0.55):
    g = np.exp(-(((u - cx) / rx) ** 2 + ((v - cy) / ry) ** 2))
    return rgb + (1 - rgb) * (g * strength)[..., None]


def bead_india():
    u, v = grid()
    rgb = np.zeros((S, S, 3), np.float32)
    saffron, white, green = (1.0, 0.6, 0.2), (0.98, 0.98, 0.98), (0.075, 0.533, 0.031)
    for i, c in enumerate((saffron, white, green)):
        band = ((v >= i / 3) & (v < (i + 1) / 3))
        rgb[band] = c
    wheel = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(wheel)
    cx, cy, R = 0.80 * S, 0.5 * S, 0.11 * S
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=255, width=int(0.018 * S))
    for k in range(24):
        a = k / 24 * 2 * math.pi
        d.line([cx, cy, cx + math.cos(a) * R, cy + math.sin(a) * R], fill=255, width=max(2, int(0.008 * S)))
    h = 0.025 * S
    d.ellipse([cx - h, cy - h, cx + h, cy + h], fill=255)
    w = (np.asarray(wheel).astype(np.float32) / 255.0)[..., None]
    navy = np.array([0.0, 0.0, 0.5], np.float32)
    return rgb * (1 - w) + navy * w


def bead_chrome():
    u, v = grid()
    rgb = stops(v, [(0.0, (250, 252, 255)), (0.40, (176, 186, 198)), (0.50, (66, 74, 88)),
                    (0.60, (196, 204, 214)), (1.0, (112, 120, 132))])
    return highlight(rgb, u, v, strength=0.7)


def bead_gold():
    u, v = grid()
    rgb = stops(v, [(0.0, (255, 243, 176)), (0.40, (234, 182, 62)), (0.52, (150, 96, 16)),
                    (0.66, (228, 172, 56)), (1.0, (128, 84, 12))])
    return highlight(rgb, u, v, strength=0.6)


def bead_galaxy():
    u, v = grid()
    rgb = np.zeros((S, S, 3), np.float32) + np.array([0.07, 0.05, 0.19], np.float32)
    rng = random.Random(28092026)
    for colour, count in (((0.80, 0.24, 0.78), 4), ((0.24, 0.36, 0.92), 4), ((0.20, 0.75, 0.80), 2)):
        for _ in range(count):
            cx, cy = rng.uniform(0.1, 0.95), rng.uniform(0.15, 0.85)
            rx, ry = rng.uniform(0.10, 0.22), rng.uniform(0.06, 0.14)
            g = np.exp(-(((u - cx) / rx) ** 2 + ((v - cy) / ry) ** 2)) * rng.uniform(0.35, 0.6)
            rgb += g[..., None] * np.array(colour, np.float32)
    stars = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(stars)
    for _ in range(46):
        x, y = rng.uniform(0.05, 0.95) * S, rng.uniform(0.08, 0.92) * S
        r = rng.choice((2, 3, 3, 4, 6))
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    for _ in range(3):
        x, y = rng.uniform(0.55, 0.9) * S, rng.uniform(0.25, 0.75) * S
        d.polygon([(px * S, py * S) for px, py in star_points(x / S, y / S, 0.04, 0.009, n=4)], fill=255)
    s = (np.asarray(stars.filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32) / 255.0)[..., None]
    return np.clip(rgb, 0, 1) * (1 - s) + s


# ------------------------------------------------------------- noise helpers

def value_noise(u, v, scale, seed):
    """Smooth value noise in 0..1 at `scale` cells across the bead."""
    rng = np.random.default_rng(seed)
    n = int(scale) + 3
    lattice = rng.random((n, n)).astype(np.float32)
    x, y = u * scale, v * scale
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = lattice[y0 % n, x0 % n], lattice[y0 % n, (x0 + 1) % n]
    c, d = lattice[(y0 + 1) % n, x0 % n], lattice[(y0 + 1) % n, (x0 + 1) % n]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(u, v, scale, seed, octaves=5):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + value_noise(u, v, scale * (2 ** o), seed + o) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def voronoi(u, v, count, seed, jitter=1.0):
    """Distances to the nearest and second-nearest of `count` points, and the nearest's index."""
    rng = random.Random(seed)
    side = int(math.ceil(math.sqrt(count)))
    pts = []
    for i in range(side + 2):
        for j in range(side + 2):
            pts.append(((i - 0.5 + rng.uniform(0.5 - jitter / 2, 0.5 + jitter / 2)) / side,
                        (j - 0.5 + rng.uniform(0.5 - jitter / 2, 0.5 + jitter / 2)) / side))
    d1 = np.full(u.shape, 9.0, np.float32)
    d2 = np.full(u.shape, 9.0, np.float32)
    idx = np.zeros(u.shape, np.int32)
    for k, (px, py) in enumerate(pts):
        d = np.sqrt((u - px) ** 2 + (v - py) ** 2)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        idx = np.where(closer, k, idx)
        d1 = np.where(closer, d, d1)
    return d1, d2, idx


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ------------------------------------------------- tintable, all-over (batch 2)

def bead_honeycomb():
    u, v = grid()
    # Voronoi cells of a regular hexagonal lattice are hexagons.
    size = 0.13
    d1 = np.full(u.shape, 9.0, np.float32)
    d2 = np.full(u.shape, 9.0, np.float32)
    dy = size * math.sqrt(3) / 2
    row = -2
    while row * dy < 1.2:
        for col in range(-2, int(1.2 / size) + 3):
            px = col * size + (row % 2) * size / 2
            py = row * dy
            d = np.sqrt((u - px) ** 2 + (v - py) ** 2)
            closer = d < d1
            d2 = np.where(closer, d1, np.minimum(d2, d))
            d1 = np.where(closer, d, d1)
        row += 1
    gap = d2 - d1
    wall = 1 - smoothstep(0.006, 0.016, gap)
    bevel = 1.0 - 0.35 * (d1 / (size * 0.58)) ** 2
    return np.clip(bevel, 0.5, 1) * (1 - wall) + 0.22 * wall


def bead_argyle():
    u, v = grid()
    a = (u + v) / 0.25
    b = (u - v) / 0.25
    cell = (np.floor(a) + np.floor(b)) % 2
    f = np.where(cell == 0, 1.0, 0.66).astype(np.float32)
    # Thin dashed overcheck lines through the diamonds' centres.
    la = np.abs(((a + 0.5) % 1.0) - 0.5)
    lb = np.abs(((b + 0.5) % 1.0) - 0.5)
    dash_a = (((b * 4) % 1.0) < 0.55)
    dash_b = (((a * 4) % 1.0) < 0.55)
    line = ((la < 0.035) & dash_a) | ((lb < 0.035) & dash_b)
    return np.where(line, 0.32, f).astype(np.float32)


def bead_zigzag():
    u, v = grid()
    # Chevrons pointing along the body, repeating across its width.
    w = u + np.abs(((v * 3) % 1.0) - 0.5) * 0.34
    phase = (w / 0.16) % 2.0
    band = smoothstep(0.35, 0.55, np.minimum(phase, 2.0 - phase))
    return 0.58 + 0.42 * band


def bead_carbon():
    u, v = grid()
    n = 14
    x, y = u * n, v * n
    cx, cy = np.floor(x), np.floor(y)
    fx, fy = x - cx, y - cy
    horizontal = ((cx + cy) % 2) == 0
    # Each tow is a little barrel: bright along its middle, dark at its edges.
    across = np.where(horizontal, fy, fx)
    along = np.where(horizontal, fx, fy)
    barrel = np.sin(across * math.pi) ** 0.7
    sheen = 0.85 + 0.15 * np.sin(along * math.pi)
    tone = np.where(horizontal, 0.62, 0.48)
    return np.clip(0.22 + tone * barrel * sheen + 0.10, 0, 1)


def bead_tiger():
    u, v = grid()
    wob = fbm(u, v, 3.5, 71) - 0.5
    # Stripes run across the body, tapering towards its sides.
    stripe = np.abs(np.sin((u * 6.2 + wob * 1.6) * math.pi))
    taper = 0.55 + 0.45 * np.abs(v - 0.5) * 2
    dark = smoothstep(0.80, 0.90, stripe + taper * 0.12 - np.abs(v - 0.5) * 0.35)
    return 1.0 * (1 - dark) + 0.18 * dark


def bead_circuit():
    img = Image.new("L", (S, S), int(0.46 * 255))
    d = ImageDraw.Draw(img)
    rng = random.Random(4242)
    step = S / 10
    trace, pad = int(0.018 * S), int(0.028 * S)
    for _ in range(26):
        x, y = rng.randrange(0, 11) * step, rng.randrange(0, 11) * step
        pts = [(x, y)]
        for _ in range(rng.randint(2, 4)):
            dx, dy = rng.choice(((1, 0), (0, 1), (1, 1), (1, -1), (-1, 1)))
            length = rng.randint(1, 3) * step
            x, y = x + dx * length, y + dy * length
            pts.append((x, y))
        d.line(pts, fill=250, width=trace, joint="curve")
        for px, py in (pts[0], pts[-1]):
            d.ellipse([px - pad, py - pad, px + pad, py + pad], fill=255)
            d.ellipse([px - pad / 2.4, py - pad / 2.4, px + pad / 2.4, py + pad / 2.4], fill=int(0.46 * 255))
    return np.asarray(img).astype(np.float32) / 255.0


# ---------------------------------------------- fixed colour, all-over (batch 2)

def colour(*c):
    return np.array([x / 255.0 for x in c], np.float32)


def bead_leopard():
    u, v = grid()
    base = colour(214, 160, 72) * (0.9 + 0.2 * fbm(u, v, 4, 11))[..., None]
    d1, d2, _ = voronoi(u, v, 12, 555, jitter=0.8)
    wob = (fbm(u, v, 7, 12) - 0.5) * 0.035
    rim = smoothstep(0.070, 0.082, d1 + wob) * (1 - smoothstep(0.098, 0.112, d1 + wob))
    centre = 1 - smoothstep(0.055, 0.075, d1 + wob)
    broken = fbm(u, v, 10, 13) > 0.36
    rim = rim * broken
    rgb = base * (1 - centre[..., None]) + colour(170, 104, 30) * centre[..., None]
    return rgb * (1 - rim[..., None]) + colour(40, 22, 10) * rim[..., None]


def bead_lava():
    u, v = grid()
    d1, d2, _ = voronoi(u, v, 28, 909, jitter=0.95)
    crack = 1 - smoothstep(0.004, 0.022, d2 - d1)
    glow = 1 - smoothstep(0.0, 0.06, d2 - d1)
    rock = colour(34, 24, 22) * (0.7 + 0.6 * fbm(u, v, 10, 21))[..., None]
    heat = np.clip(glow * 0.6 + crack, 0, 1)[..., None]
    hot = colour(255, 90, 10) * (1 - crack[..., None]) + colour(255, 214, 90) * crack[..., None]
    return np.clip(rock * (1 - heat) + hot * heat, 0, 1)


def bead_ice():
    u, v = grid()
    d1, d2, idx = voronoi(u, v, 16, 314, jitter=1.0)
    facet = (np.sin(idx * 12.9898) * 43758.5453) % 1.0
    base = colour(150, 205, 240) * (0.78 + 0.28 * facet)[..., None]
    edge = 1 - smoothstep(0.003, 0.012, d2 - d1)
    frost = smoothstep(0.62, 0.8, fbm(u, v, 14, 31))
    rgb = base + (1 - base) * (edge * 0.8 + frost * 0.45)[..., None]
    return np.clip(rgb, 0, 1)


def bead_marble():
    u, v = grid()
    turb = fbm(u, v, 3, 61, octaves=6)
    vein = np.abs(np.sin((u * 2.2 + v * 1.1 + turb * 4.2) * math.pi))
    dark = 1 - smoothstep(0.0, 0.16, vein)
    fine = 1 - smoothstep(0.0, 0.07, np.abs(np.sin((u * 5 - v * 2 + turb * 7) * math.pi)))
    base = colour(246, 244, 238) * (0.92 + 0.08 * fbm(u, v, 5, 62))[..., None]
    rgb = base * (1 - (dark * 0.62)[..., None]) - (fine * 0.22)[..., None]
    gold = (dark > 0.85)[..., None] & (fbm(u, v, 5, 63) > 0.6)[..., None]
    return np.clip(np.where(gold, colour(200, 160, 70), rgb), 0, 1)


def bead_holo():
    u, v = grid()
    t = (u * 0.5 + v * 0.35 + fbm(u, v, 2.2, 81) * 0.45) * 1.25
    hue = t % 1.0
    k = np.stack([(hue + o) % 1.0 for o in (0.0, 2 / 3, 1 / 3)], axis=-1)
    rgb = 0.55 + 0.45 * np.cos((k) * 2 * math.pi)
    rgb = rgb * 0.75 + 0.25                              # pastel foil
    return highlight(np.clip(rgb, 0, 1), u, v, strength=0.65)


def bead_camo():
    u, v = grid()
    palette = [colour(106, 122, 66), colour(146, 132, 88), colour(78, 62, 40), colour(34, 38, 28)]
    rgb = np.zeros((S, S, 3), np.float32) + palette[0]
    for i, c in enumerate(palette[1:]):
        blob = fbm(u, v, 3.0, 90 + i * 7) > (0.54 + i * 0.05)
        rgb = np.where(blob[..., None], c, rgb)
    return rgb



# ------------------------------------------------------ batch 3 (2026-09-28)
# Thirty more, all painted in their own colours. Motif beads keep the motif on
# the +x side (0.72..0.96 of the width), the part a packed body leaves showing.

def put(rgb, m, c):
    """Paint colour c (0..255 tuple) over rgb where mask m (0..1) is set."""
    m = np.asarray(m, np.float32)[..., None]
    return rgb * (1 - m) + colour(*c) * m


def fill(c):
    return np.zeros((S, S, 3), np.float32) + colour(*c)


def soft(m, blur=2.0):
    img = Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(blur))).astype(np.float32) / 255.0


def ellipse_mask(cx, cy, rx, ry):
    return mask(lambda d, P: d.ellipse([P((cx - rx, cy - ry)), P((cx + rx, cy + ry))], fill=255))


def bead_checker():
    u, v = grid()
    c = (np.floor(u * 7) + np.floor(v * 7)) % 2
    return put(fill((24, 24, 26)), c, (246, 246, 242))


def bead_tartan():
    u, v = grid()
    rgb = fill((178, 24, 36))
    for band, alpha in ((np.abs(((u * 3) % 1) - 0.5) < 0.16, 0.55), (np.abs(((v * 3) % 1) - 0.5) < 0.16, 0.55)):
        rgb = put(rgb, band * alpha, (18, 60, 38))
    thin = (np.abs(((u * 3) % 1) - 0.5) < 0.018) | (np.abs(((v * 3) % 1) - 0.5) < 0.018)
    rgb = put(rgb, thin, (240, 200, 70))
    dark = (np.abs(((u * 6) % 1) - 0.5) < 0.03) | (np.abs(((v * 6) % 1) - 0.5) < 0.03)
    return put(rgb, dark * 0.6, (20, 16, 24))


def bead_rainbow():
    u, v = grid()
    return stops(v, [(0.00, (228, 3, 3)), (0.17, (255, 140, 0)), (0.33, (255, 237, 0)),
                     (0.50, (0, 168, 72)), (0.67, (0, 77, 255)), (0.83, (117, 7, 135)), (1.0, (180, 20, 160))])


def flower(cx, cy, r, petals=5, rot=0.0):
    def shape(d, P):
        for k in range(petals):
            a = rot + k / petals * 2 * math.pi
            px, py = cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.55
            d.ellipse([P((px - r * 0.5, py - r * 0.5)), P((px + r * 0.5, py + r * 0.5))], fill=255)
    return mask(shape)


def bead_sakura():
    rgb = fill((252, 214, 224))
    rng = random.Random(33)
    for cx, cy, r in [(0.83, 0.5, 0.12), (0.30, 0.25, 0.10), (0.35, 0.78, 0.09), (0.62, 0.20, 0.07), (0.60, 0.82, 0.07)]:
        rgb = put(rgb, soft(flower(cx, cy, r, rot=rng.uniform(0, 1)), 1.5), (255, 150, 185))
        rgb = put(rgb, ellipse_mask(cx, cy, r * 0.22, r * 0.22), (255, 236, 150))
    return rgb


def bead_snowflake():
    u, v = grid()
    rgb = stops(v, [(0.0, (170, 215, 250)), (1.0, (70, 130, 205))])

    def shape(d, P):
        cx, cy, R = 0.815, 0.5, 0.15
        w = max(3, int(0.016 * S))
        for k in range(6):
            a = k / 6 * 2 * math.pi
            ex, ey = cx + math.cos(a) * R, cy + math.sin(a) * R
            d.line([P((cx, cy)), P((ex, ey))], fill=255, width=w)
            for t in (0.5, 0.75):
                bx, by = cx + math.cos(a) * R * t, cy + math.sin(a) * R * t
                for s in (-1, 1):
                    b = a + s * 0.7
                    d.line([P((bx, by)), P((bx + math.cos(b) * R * 0.28, by + math.sin(b) * R * 0.28))], fill=255, width=w)
    return put(rgb, soft(mask(shape), 1.2), (255, 255, 255))


def bead_skull():
    rgb = fill((22, 22, 26))

    def head(d, P):
        d.ellipse([P((0.72, 0.36)), P((0.92, 0.58))], fill=255)
        d.rounded_rectangle([P((0.755, 0.52)), P((0.885, 0.66))], radius=int(0.02 * S), fill=255)

    def holes(d, P):
        d.ellipse([P((0.745, 0.44)), P((0.805, 0.51))], fill=255)
        d.ellipse([P((0.835, 0.44)), P((0.895, 0.51))], fill=255)
        d.polygon([P((0.82, 0.52)), P((0.805, 0.56)), P((0.835, 0.56))], fill=255)
        for x in (0.785, 0.82, 0.855):
            d.line([P((x, 0.60)), P((x, 0.66))], fill=255, width=max(2, int(0.008 * S)))
    rgb = put(rgb, soft(mask(head), 1), (238, 236, 228))
    return put(rgb, mask(holes), (22, 22, 26))


def bead_music():
    rgb = stops(grid()[1], [(0.0, (40, 190, 175)), (1.0, (18, 110, 120))])

    def note(d, P):
        d.ellipse([P((0.74, 0.58)), P((0.83, 0.66))], fill=255)
        d.rectangle([P((0.815, 0.34)), P((0.83, 0.62))], fill=255)
        d.polygon([P((0.83, 0.34)), P((0.90, 0.40)), P((0.90, 0.46)), P((0.83, 0.41))], fill=255)
    return put(rgb, soft(mask(note), 1), (20, 24, 30))


def bead_paw():
    rgb = fill((236, 208, 168))

    def paw(d, P):
        d.ellipse([P((0.76, 0.48)), P((0.90, 0.62))], fill=255)
        for x, y in ((0.745, 0.42), (0.79, 0.36), (0.855, 0.36), (0.90, 0.42)):
            d.ellipse([P((x - 0.028, y - 0.035)), P((x + 0.028, y + 0.035))], fill=255)
    return put(rgb, soft(mask(paw), 1), (110, 66, 36))


def facets(base, light, seed):
    u, v = grid()
    d1, d2, idx = voronoi(u, v, 30, seed, jitter=0.9)
    rng = np.random.default_rng(seed)
    tone = rng.random(int(idx.max()) + 1).astype(np.float32)[idx]
    rgb = colour(*base) * (0.55 + 0.6 * tone)[..., None]
    edge = 1 - smoothstep(0.0, 0.012, d2 - d1)
    rgb = put(np.clip(rgb, 0, 1), edge * 0.7, light)
    return highlight(rgb, u, v, strength=0.75)


def bead_diamond():
    return facets((120, 210, 240), (240, 252, 255), 41)


def bead_ruby():
    return facets((200, 20, 50), (255, 190, 200), 42)


def bead_emerald():
    return facets((20, 160, 90), (190, 255, 215), 43)


def bead_pearl():
    u, v = grid()
    rgb = stops(v, [(0.0, (255, 250, 246)), (0.35, (240, 228, 236)), (0.6, (222, 232, 246)), (1.0, (206, 200, 214))])
    rgb = rgb + (fbm(u, v, 3, 44) - 0.5)[..., None] * np.array([0.10, 0.02, 0.12], np.float32)
    return highlight(np.clip(rgb, 0, 1), u, v, strength=0.9)


def bead_copper():
    u, v = grid()
    rgb = stops(v, [(0.0, (255, 214, 176)), (0.40, (206, 116, 64)), (0.52, (110, 50, 20)),
                    (0.66, (196, 104, 56)), (1.0, (100, 44, 18))])
    return highlight(rgb, u, v, strength=0.6)


def bead_rosegold():
    u, v = grid()
    rgb = stops(v, [(0.0, (255, 232, 226)), (0.40, (232, 170, 160)), (0.52, (150, 86, 80)),
                    (0.66, (224, 158, 148)), (1.0, (140, 82, 78))])
    return highlight(rgb, u, v, strength=0.6)


def bead_neon():
    u, v = grid()
    rgb = stops(v, [(0.0, (36, 8, 60)), (1.0, (12, 4, 30))])
    lines = (np.abs(((u * 6) % 1) - 0.5) > 0.46) | (np.abs(((v * 6) % 1) - 0.5) > 0.46)
    rgb = put(rgb, soft(lines.astype(np.float32), 5) * 0.9, (255, 40, 200))
    rgb = put(rgb, lines, (255, 150, 240))
    return rgb


def bead_sunset():
    u, v = grid()
    rgb = stops(v, [(0.0, (255, 214, 90)), (0.35, (255, 120, 60)), (0.65, (220, 50, 110)), (1.0, (90, 30, 120))])
    sun = ellipse_mask(0.80, 0.52, 0.13, 0.13) * ((np.floor(v * 22) % 2 == 0) | (v < 0.52))
    return put(rgb, soft(sun, 1), (255, 236, 150))


def bead_waves():
    u, v = grid()
    w = np.sin(u * 2 * math.pi * 2.5 + np.sin(v * 9) * 0.6) * 0.06
    t = (v + w) * 6
    band = t % 1
    rgb = stops(np.floor(t) / 6, [(0.0, (130, 220, 245)), (1.0, (10, 70, 150))])
    return put(rgb, smoothstep(0.86, 0.95, band), (245, 252, 255))


def bead_zebra():
    u, v = grid()
    warp = (fbm(u, v, 3, 45) - 0.5) * 1.6
    s = np.sin((u * 7 + warp + v * 1.2) * math.pi)
    return put(fill((244, 242, 236)), smoothstep(0.15, 0.30, s), (18, 18, 20))


def bead_cow():
    u, v = grid()
    n = fbm(u, v, 3, 46)
    rgb = put(fill((248, 246, 240)), smoothstep(0.56, 0.60, n), (26, 24, 24))
    return rgb


def bead_giraffe():
    u, v = grid()
    d1, d2, idx = voronoi(u, v, 14, 47, jitter=0.8)
    rng = np.random.default_rng(47)
    tone = rng.random(int(idx.max()) + 1).astype(np.float32)[idx]
    rgb = colour(196, 120, 46) * (0.8 + 0.3 * tone)[..., None]
    return put(np.clip(rgb, 0, 1), 1 - smoothstep(0.02, 0.04, d2 - d1), (246, 230, 196))


def bead_python():
    u, v = grid()
    d1, d2, idx = voronoi(u, v, 90, 48, jitter=0.5)
    rng = np.random.default_rng(48)
    tone = rng.random(int(idx.max()) + 1).astype(np.float32)[idx]
    blotch = smoothstep(0.55, 0.62, fbm(u, v, 2.5, 49))
    base = colour(168, 150, 80) * (1 - blotch[..., None]) + colour(70, 52, 28) * blotch[..., None]
    rgb = base * (0.8 + 0.35 * tone)[..., None] * (0.7 + 0.3 * smoothstep(0.0, 0.03, d1 * 0 + (d2 - d1)))[..., None]
    return np.clip(rgb, 0, 1)


def bead_peacock():
    u, v = grid()
    rgb = stops(v, [(0.0, (20, 140, 120)), (1.0, (10, 60, 100))])
    rgb = rgb + (fbm(u, v, 6, 50) - 0.5)[..., None] * 0.15
    r = np.sqrt(((u - 0.81) / 1.2) ** 2 + (v - 0.5) ** 2)
    for radius, c in ((0.17, (230, 190, 60)), (0.13, (30, 170, 120)), (0.09, (40, 110, 200)), (0.05, (12, 20, 60))):
        rgb = put(rgb, soft((r < radius).astype(np.float32), 1.5), c)
    return np.clip(rgb, 0, 1)


def bead_wood():
    u, v = grid()
    r = np.sqrt((u - 0.2) ** 2 * 0.3 + (v - 1.4) ** 2)
    rings = np.sin((r * 26 + fbm(u, v, 4, 51) * 5) * math.pi) * 0.5 + 0.5
    rgb = stops(rings, [(0.0, (120, 70, 34)), (0.6, (176, 112, 58)), (1.0, (206, 146, 86))])
    return rgb * (0.9 + 0.2 * fbm(u * 8, v, 6, 52))[..., None]


def bead_denim():
    u, v = grid()
    twill = np.sin((u + v) * 2 * math.pi * 40) * 0.5 + 0.5
    fade = fbm(u, v, 4, 53)
    rgb = colour(40, 76, 140) * (0.75 + 0.25 * twill)[..., None]
    return np.clip(rgb + (fade * 0.25)[..., None] * np.array([0.5, 0.6, 0.7], np.float32), 0, 1)


def bead_bubblegum():
    u, v = grid()
    x, y = u - 0.5, v - 0.5
    theta = np.arctan2(y, x)
    r = np.sqrt(x * x + y * y)
    s = np.sin(theta * 3 + r * 26)
    return stops(s, [(-1.0, (255, 120, 180)), (0.0, (255, 180, 215)), (1.0, (255, 250, 252))])


def bead_aurora():
    u, v = grid()
    rgb = stops(v, [(0.0, (10, 16, 40)), (1.0, (4, 8, 22))])
    for c, phase, amp, width in (((60, 255, 160), 0.0, 0.10, 0.06), ((40, 200, 230), 1.7, 0.08, 0.05), ((170, 80, 255), 3.1, 0.07, 0.04)):
        center = 0.45 + np.sin(u * 7 + phase) * amp
        g = np.exp(-((v - center) / width) ** 2) * (0.6 + 0.4 * fbm(u * 3, v, 5, 54))
        rgb = rgb + g[..., None] * colour(*c)
    return np.clip(rgb, 0, 1)


def bead_sun():
    u, v = grid()
    x, y = u - 0.80, v - 0.5
    r = np.sqrt(x * x + y * y)
    theta = np.arctan2(y, x)
    rays = (np.sin(theta * 12) * 0.5 + 0.5) * smoothstep(0.5, 0.1, r)
    rgb = stops(r, [(0.0, (255, 250, 200)), (0.18, (255, 210, 40)), (0.6, (255, 130, 20)), (1.2, (220, 60, 20))])
    return put(rgb, rays * 0.35, (255, 240, 150))


def bead_electric():
    u, v = grid()
    rgb = stops(v, [(0.0, (12, 20, 60)), (1.0, (4, 6, 24))])
    d1, d2, _ = voronoi(u, v, 16, 55, jitter=1.0)
    crack = 1 - smoothstep(0.0, 0.01, d2 - d1)
    rgb = put(rgb, soft(crack, 6) * 0.8, (40, 150, 255))
    return put(rgb, crack, (220, 245, 255))


def bead_watermelon():
    u, v = grid()
    rgb = fill((236, 64, 82))
    rgb = put(rgb, (v < 0.12) | (v > 0.88), (40, 130, 50))
    rgb = put(rgb, ((v >= 0.12) & (v < 0.18)) | ((v > 0.82) & (v <= 0.88)), (220, 245, 200))

    def seeds(d, P):
        for x, y in ((0.80, 0.38), (0.86, 0.56), (0.76, 0.62), (0.45, 0.35), (0.35, 0.60), (0.60, 0.50)):
            d.ellipse([P((x - 0.018, y - 0.03)), P((x + 0.018, y + 0.03))], fill=255)
    return put(rgb, mask(seeds), (30, 20, 20))


def bead_pixel():
    u, v = grid()
    n = 12
    cu, cv = np.floor(u * n), np.floor(v * n)
    rng = np.random.default_rng(56)
    table = rng.integers(0, 5, (n, n))
    palette = np.array([colour(46, 204, 113), colour(52, 152, 219), colour(241, 196, 15),
                        colour(231, 76, 60), colour(155, 89, 182)], np.float32)
    rgb = palette[table[cv.astype(int).clip(0, n - 1), cu.astype(int).clip(0, n - 1)]]
    grid_line = (((u * n) % 1) < 0.06) | (((v * n) % 1) < 0.06)
    return put(rgb, grid_line * 0.5, (20, 20, 30))


# ------------------------------------------------------------------ build

# Colours for the patterned beads: (pattern value, sRGB) stops. The values are
# the levels each painter uses: 0.30 outline, 0.64 bead, 1.0 motif, unless noted.
PALETTES = {
    "star": [(0.30, (12, 20, 52)), (0.64, (31, 58, 138)), (1.0, (255, 200, 61))],
    "heart": [(0.30, (90, 10, 26)), (0.64, (247, 182, 200)), (1.0, (232, 36, 60))],
    "scales": [(0.30, (11, 46, 26)), (0.95, (47, 164, 94)), (1.0, (143, 227, 162))],
    "stripes": [(0.64, (215, 38, 61)), (1.0, (255, 243, 232))],
    "dots": [(0.64, (31, 95, 214)), (1.0, (255, 255, 255))],
    "lightning": [(0.30, (18, 8, 38)), (0.64, (75, 42, 140)), (1.0, (255, 225, 74))],
    "flame": [(0.30, (26, 4, 0)), (0.64, (60, 12, 12)), (0.80, (255, 106, 26)), (1.0, (255, 210, 74))],
    "crescent": [(0.30, (5, 10, 30)), (0.64, (22, 36, 90)), (1.0, (255, 241, 176))],
    # 0.22 walls, 0.5..1 bevelled cells
    "honeycomb": [(0.22, (90, 48, 0)), (0.50, (196, 122, 0)), (1.0, (255, 196, 58))],
    # 0.32 lines, 0.66 and 1.0 the two diamonds
    "argyle": [(0.32, (246, 231, 200)), (0.66, (30, 47, 92)), (1.0, (163, 36, 63))],
    "zigzag": [(0.58, (28, 28, 28)), (1.0, (255, 138, 30))],
    "carbon": [(0.35, (10, 11, 13)), (0.93, (106, 113, 124))],
    "tiger": [(0.18, (18, 10, 4)), (1.0, (242, 138, 28))],
    # 0.46 board, 0.98..1 traces and pads
    "circuit": [(0.46, (14, 90, 52)), (0.98, (233, 194, 90)), (1.0, (255, 224, 138))],
}

BEADS = [
    ("india", bead_india, False),
    ("star", bead_star, True),
    ("heart", bead_heart, True),
    ("scales", bead_scales, True),
    ("stripes", bead_stripes, True),
    ("dots", bead_dots, True),
    ("lightning", bead_lightning, True),
    ("flame", bead_flame, True),
    ("crescent", bead_crescent, True),
    ("chrome", bead_chrome, False),
    ("gold", bead_gold, False),
    ("galaxy", bead_galaxy, False),
    ("honeycomb", bead_honeycomb, True),
    ("argyle", bead_argyle, True),
    ("zigzag", bead_zigzag, True),
    ("carbon", bead_carbon, True),
    ("tiger", bead_tiger, True),
    ("circuit", bead_circuit, True),
    ("leopard", bead_leopard, False),
    ("lava", bead_lava, False),
    ("ice", bead_ice, False),
    ("marble", bead_marble, False),
    ("holographic", bead_holo, False),
    ("camo", bead_camo, False),
    # batch 3: tags 0xC0 + (k - 24)
    ("checker", bead_checker, False),
    ("tartan", bead_tartan, False),
    ("rainbow", bead_rainbow, False),
    ("sakura", bead_sakura, False),
    ("snowflake", bead_snowflake, False),
    ("skull", bead_skull, False),
    ("music", bead_music, False),
    ("paw", bead_paw, False),
    ("diamond", bead_diamond, False),
    ("ruby", bead_ruby, False),
    ("emerald", bead_emerald, False),
    ("pearl", bead_pearl, False),
    ("copper", bead_copper, False),
    ("rosegold", bead_rosegold, False),
    ("neon", bead_neon, False),
    ("sunset", bead_sunset, False),
    ("waves", bead_waves, False),
    ("zebra", bead_zebra, False),
    ("cow", bead_cow, False),
    ("giraffe", bead_giraffe, False),
    ("python", bead_python, False),
    ("peacock", bead_peacock, False),
    ("wood", bead_wood, False),
    ("denim", bead_denim, False),
    ("bubblegum", bead_bubblegum, False),
    ("aurora", bead_aurora, False),
    ("sun", bead_sun, False),
    ("electric", bead_electric, False),
    ("watermelon", bead_watermelon, False),
    ("pixel", bead_pixel, False),
]


def render(name, fn, patterned, shade, alpha):
    out = fn()
    if patterned:
        out = stops(np.asarray(out, np.float32), PALETTES[name])
    # Every bead takes a gentle share of the tube shading.
    rgb = np.clip(out * (0.45 + 0.55 * shade)[..., None], 0, 1)
    rgba = np.concatenate([rgb, alpha[..., None]], axis=-1)
    img = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")
    size = TILE - 2 * MARGIN
    return img.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")


def main():
    atlas = Image.open(IOS_ATLAS).convert("RGBA")
    shade, alpha = template(atlas)
    for row, col in CELLS:
        atlas.paste(Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0)), (col * CELL, row * CELL))
    for k, (name, fn, tintable) in enumerate(BEADS):
        row, col = CELLS[k // PER_CELL]
        qx, qy = k % GRID, (k % PER_CELL) // GRID
        # Slot k spans exactly [col + qx/3, col + (qx+1)/3) of a cell, as the uv says.
        x0 = col * CELL + round(qx * CELL / GRID)
        y0 = row * CELL + round(qy * CELL / GRID)
        atlas.paste(render(name, fn, tintable, shade, alpha), (x0 + MARGIN, y0 + MARGIN))
        print(f"{k:2d} {name:11s} cell r{row} c{col} slot({qx},{qy})")
    atlas.save(IOS_ATLAS, optimize=True)
    atlas.save(ANDROID_ATLAS, optimize=True)
    print("wrote", IOS_ATLAS, "and", ANDROID_ATLAS)


if __name__ == "__main__":
    main()
