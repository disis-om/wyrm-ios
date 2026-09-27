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

Kinds (alpha byte 0xE0 + k in `skin_rgba`, RGB = tint or, for a fixed-colour
bead, the colour the arena's nearest colour group is picked from):
   0 India flag (fixed)   1 star      2 heart       3 dragon scales
   4 stripes              5 dots      6 lightning   7 flame
   8 crescent             9 chrome (fixed)  10 gold (fixed)  11 galaxy (fixed)
  12 honeycomb  13 argyle  14 zigzag  15 carbon fibre  16 tiger  17 circuit
  18 leopard (fixed)  19 lava (fixed)  20 ice (fixed)  21 marble (fixed)
  22 holographic (fixed)  23 camo (fixed)
Tintable beads are grey: the engine multiplies them by the picked colour.
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
QUARTER = 224
S = 896                      # drawn at 4x, then reduced
MARGIN = 2                   # px of clear space round each bead in its quarter
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


# ------------------------------------------------------------------ build

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
]


def render(fn, tintable, shade, alpha):
    out = fn()
    if tintable:
        grey = np.clip(out * shade, 0, 1)
        rgb = np.stack([grey, grey, grey], axis=-1)
    else:
        # Fixed colours take a gentler share of the tube shading.
        rgb = np.clip(out * (0.45 + 0.55 * shade)[..., None], 0, 1)
    rgba = np.concatenate([rgb, alpha[..., None]], axis=-1)
    img = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")
    size = QUARTER - 2 * MARGIN
    small = img.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")
    tile = Image.new("RGBA", (QUARTER, QUARTER), (0, 0, 0, 0))
    tile.paste(small, (MARGIN, MARGIN))
    return tile


def main():
    atlas = Image.open(IOS_ATLAS).convert("RGBA")
    shade, alpha = template(atlas)
    for row, col in CELLS:
        atlas.paste(Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0)), (col * CELL, row * CELL))
    for k, (name, fn, tintable) in enumerate(BEADS):
        row, col = CELLS[k // 4]
        qx, qy = k % 2, (k % 4) // 2
        atlas.paste(render(fn, tintable, shade, alpha), (col * CELL + qx * QUARTER, row * CELL + qy * QUARTER))
        print(f"{k:2d} {name:9s} cell r{row} c{col} q({qx},{qy}) {'tint' if tintable else 'fixed'}")
    atlas.save(IOS_ATLAS, optimize=True)
    atlas.save(ANDROID_ATLAS, optimize=True)
    print("wrote", IOS_ATLAS, "and", ANDROID_ATLAS)


if __name__ == "__main__":
    main()
