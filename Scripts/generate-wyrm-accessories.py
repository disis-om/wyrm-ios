#!/usr/bin/env python3
"""Paints Wyrm's own looks: hair, ears and glasses (OM, 2026-09-28).

Writes the same 2048 x 2048 atlas (8 x 8 cells of 256 px) to both apps:
  Wyrm iOS/Resources/WyrmAccessories.png
  Wyrm Android/app/res/textures/wyrm_accessories.png   (listed in tassets.c)

Nothing here reaches the arena protocol: the join packet keeps slither's own
accessory byte. Only this phone draws these, over its own snake.

Frames
  Head cells (hair caps, ears, glasses) are 4 head radii (R) square, centred on
  the head, heading +x. The head is a circle of radius 1R; the eyes sit at
  (0.41, +-0.45) with radius 0.41 (the engine's `ed`, `esp`, `er` over its
  14.5 x `sc` head radius).
  Flow cells (ponytail, pigtail, braid, long hair) are 3.4R square: the root at
  the middle of the left edge, the hair running +x to its tip. The engine lays
  a flow cell along a swinging chain that trails the head, so the hair sways as
  the snake turns; previews draw it at rest, straight back.

Look (slither's own accessories are the reference)
  Hair is fur: thousands of tapered strands, dark at the root and light at the
  tip, then lit as a soft dome. It is painted near-white so the engine tints it
  (brown, cream, purple, pink, white, black...). Glasses are thin lit rims over
  clear glass, so the eyes show through, with straight temples running back
  along the head. Ears are lit shapes with fur at their edges.

Cells (keep WyrmLook.swift, WyrmLook.kt and wyrm_look.c in step)
  hair caps  0 fluffy  1 flame  2 pom  3 dreadlocks  4 mohawk  5 ponytail
             6 pigtails  7 braid  8 long hair  9 space buns  10 man bun  11 bob
             (a cap cell is 4.4R square, centred 0.6R behind the head)
  flows      12 ponytail  13 pigtail  14 braid  15 long hair
  ears       16 panda  17 bunny  18 lop bunny  19 cat  20 mouse  21 bear
             22 koala  23 fox  24 wolf  25 tiger  26 bat  27 dragon
  glasses    28 heart  29 cat-eye  30 flower  31 pastel round  32 nerd
             33 sparkle  34 aviator  35 pixel shades  36 cyber visor
             37 evil visor  38 steampunk  39 punk spikes
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
IOS_OUT = ROOT / "Resources/WyrmAccessories.png"
ANDROID_OUT = ROOT.parent / "Wyrm Android/app/res/textures/wyrm_accessories.png"

CELL = 256
N = 1024                     # drawn at 4x
GRID = 8
FLOW_SPAN = 3.4              # R across a flow cell

LIGHT = np.array([-0.55, -0.62, 0.72])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
HALF = LIGHT + np.array([0.0, 0.0, 1.0])
HALF = HALF / np.linalg.norm(HALF)


class Frame:
    """Maps R units to drawing pixels for a head cell (centred) or a flow cell."""

    def __init__(self, flow=False):
        self.flow = flow
        self.scale = N / (FLOW_SPAN if flow else 4.0)
        yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
        if flow:
            self.UX = xx / self.scale
            self.UY = yy / self.scale - FLOW_SPAN / 2
        else:
            self.UX = xx / self.scale - 2.0
            self.UY = yy / self.scale - 2.0

    def P(self, x, y):
        if self.flow:
            return (x * self.scale, (y + FLOW_SPAN / 2) * self.scale)
        return ((x + 2.0) * self.scale, (y + 2.0) * self.scale)


F = Frame()


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


# ------------------------------------------------------------------ masks

def _mask(draw):
    img = Image.new("L", (N, N), 0)
    draw(ImageDraw.Draw(img))
    return np.asarray(img).astype(np.float32) / 255.0


def circle(cx, cy, r):
    return _mask(lambda d: d.ellipse([F.P(cx - r, cy - r), F.P(cx + r, cy + r)], fill=255))


def poly(pts):
    return _mask(lambda d: d.polygon([F.P(x, y) for x, y in pts], fill=255))


def ellipse(cx, cy, rx, ry, rot=0.0, n=96):
    pts = [(cx + math.cos(t) * rx * math.cos(rot) - math.sin(t) * ry * math.sin(rot),
            cy + math.cos(t) * rx * math.sin(rot) + math.sin(t) * ry * math.cos(rot))
           for t in np.linspace(0, 2 * math.pi, n, endpoint=False)]
    return poly(pts)


def stroke(pts, width):
    def draw(d):
        w = max(1, int(width * F.scale))
        d.line([F.P(x, y) for x, y in pts], fill=255, width=w, joint="curve")
        for x, y in (pts[0], pts[-1]):
            r = width / 2
            d.ellipse([F.P(x - r, y - r), F.P(x + r, y + r)], fill=255)
    return _mask(draw)


def curve(p0, p1, p2, p3=None, n=40):
    out = []
    for t in np.linspace(0, 1, n):
        if p3 is None:
            x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
            y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        else:
            x = (1 - t) ** 3 * p0[0] + 3 * (1 - t) ** 2 * t * p1[0] + 3 * (1 - t) * t * t * p2[0] + t ** 3 * p3[0]
            y = (1 - t) ** 3 * p0[1] + 3 * (1 - t) ** 2 * t * p1[1] + 3 * (1 - t) * t * t * p2[1] + t ** 3 * p3[1]
        out.append((x, y))
    return out


def tapered(spine, w0, w1, profile=None):
    left, right = [], []
    n = len(spine)
    for i, (x, y) in enumerate(spine):
        a, b = spine[min(i + 1, n - 1)], spine[max(i - 1, 0)]
        dx, dy = a[0] - b[0], a[1] - b[1]
        ln = math.hypot(dx, dy) or 1
        nx, ny = -dy / ln, dx / ln
        t = i / (n - 1)
        w = (profile(t) if profile else (w0 + (w1 - w0) * t)) / 2
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return poly(left + right[::-1])


def minus(a, b):
    return np.clip(a - b, 0, 1)


def grow(m, r):
    return ndimage.binary_dilation(m > 0.5, iterations=max(1, int(r * F.scale))).astype(np.float32)


def shrink(m, r):
    return ndimage.binary_erosion(m > 0.5, iterations=max(1, int(r * F.scale))).astype(np.float32)


# --------------------------------------------------------------- painting

class Item:
    def __init__(self):
        self.rgb = np.zeros((N, N, 3), np.float32)
        self.a = np.zeros((N, N), np.float32)
        self.shadow = 0.32

    def over(self, colour, alpha):
        a = np.clip(alpha, 0, 1)
        c = np.broadcast_to(colour, (N, N, 3)) if np.ndim(colour) == 1 else colour
        self.rgb = c * a[..., None] + self.rgb * (1 - a[..., None])
        self.a = a + self.a * (1 - a)

    def lit(self, mask, colour, bevel=0.10, gloss=0.4, power=28, dome=False, metal=False, texture=None):
        m = np.clip(mask, 0, 1)
        inside = m > 0.5
        base = np.broadcast_to(colour, (N, N, 3)).astype(np.float32) if np.ndim(colour) == 1 else colour
        if texture is not None:
            base = base * texture[..., None]
        d = ndimage.distance_transform_edt(inside).astype(np.float32)
        if dome:
            depth = max(d.max(), 1.0)
            h = np.sqrt(np.clip(1 - (1 - d / depth) ** 2, 0, 1)) * depth * 0.8
        else:
            w = bevel * F.scale
            h = np.sqrt(np.clip(1 - (1 - np.clip(d / w, 0, 1)) ** 2, 0, 1)) * w
        h = ndimage.gaussian_filter(h, 1.5)
        gy, gx = np.gradient(h)
        ln = np.sqrt(gx * gx + gy * gy + 1)
        nx, ny, nz = -gx / ln, -gy / ln, 1 / ln
        diff = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
        spec = np.clip(nx * HALF[0] + ny * HALF[1] + nz * HALF[2], 0, 1) ** power * gloss
        out = base * (0.48 + 0.62 * diff)[..., None] + spec[..., None] * ((base * 0.7 + 0.3) if metal else 1.0)
        return np.clip(out, 0, 1), m

    def part(self, mask, colour, edge=0.012, edge_colour=None, alpha=1.0, **kw):
        out, m = self.lit(mask, colour, **kw)
        if edge > 0:
            ring = np.clip(grow(m, edge) - (m > 0.5), 0, 1)
            ec = edge_colour if edge_colour is not None else np.clip(np.asarray(colour, np.float32).reshape(-1, 3).mean(0) * 0.45, 0, 1) \
                if np.ndim(colour) == 1 else np.array([0.2, 0.2, 0.2], np.float32)
            self.over(ec, ring * 0.9 * alpha)
        self.over(out, m * alpha)

    def glass(self, mask, tint, alpha=0.22, streak=0.5):
        """Clear glass: a faint tint, lighter at the top left, and one bright streak."""
        m = np.clip(mask, 0, 1)
        grad = np.clip(1.15 - 0.35 * (F.UX + F.UY + 1.0), 0.7, 1.3)
        self.over(np.clip(np.broadcast_to(tint, (N, N, 3)) * grad[..., None], 0, 1), m * alpha)
        ys, xs = np.nonzero(m > 0.5)
        if len(xs):
            cx, cy = xs.mean() / F.scale - 2, ys.mean() / F.scale - 2
            band = np.abs((F.UX - cx) + (F.UY - cy) + 0.12) < 0.07
            self.over(np.array([1, 1, 1], np.float32), ndimage.gaussian_filter((band * m).astype(np.float32), 2) * streak)

    def fur(self, strands, colour=None, root=0.55, tip=1.0, width=0.03, light=True, seed=0):
        """Strands (x, y, angle, length, curl, tone) drawn root to tip, then lit as a soft dome."""
        rng = np.random.default_rng(seed)
        img = Image.new("RGB", (N, N), (0, 0, 0))
        al = Image.new("L", (N, N), 0)
        di, da = ImageDraw.Draw(img), ImageDraw.Draw(al)
        base = np.array([1, 1, 1], np.float32) if colour is None else np.asarray(colour, np.float32)
        for (x, y, ang, length, curl, tone) in strands:
            steps = 6
            px, py = x, y
            w0 = width * rng.uniform(0.8, 1.25)
            for s in range(steps):
                t0, t1 = s / steps, (s + 1) / steps
                a = ang + curl * t1
                nx = px + math.cos(a) * length / steps
                ny = py + math.sin(a) * length / steps
                shade = (root + (tip - root) * t1) * tone
                c = tuple(int(np.clip(v * shade, 0, 1) * 255) for v in base)
                w = max(1, int(w0 * (1 - 0.75 * t0) * F.scale))
                di.line([F.P(px, py), F.P(nx, ny)], fill=c, width=w)
                da.line([F.P(px, py), F.P(nx, ny)], fill=int(255 * (1 - 0.35 * t1)), width=w)
                px, py = nx, ny
        rgb_ = np.asarray(img).astype(np.float32) / 255.0
        a = np.asarray(al).astype(np.float32) / 255.0
        if light:
            h = ndimage.gaussian_filter(a, 0.08 * F.scale) * 0.18 * F.scale
            gy, gx = np.gradient(h)
            ln = np.sqrt(gx * gx + gy * gy + 1)
            diff = np.clip((-gx * LIGHT[0] - gy * LIGHT[1] + LIGHT[2]) / ln, 0, 1)
            spec = np.clip((-gx * HALF[0] - gy * HALF[1] + HALF[2]) / ln, 0, 1) ** 18 * 0.25
            rgb_ = np.clip(rgb_ * (0.55 + 0.6 * diff)[..., None] + spec[..., None], 0, 1)
        colour_rgb = np.where(a[..., None] > 0, rgb_ / np.maximum(a[..., None], 1e-3) * a[..., None], 0)
        self.over(np.clip(colour_rgb, 0, 1), a)

    def render(self):
        rgb_, a = self.rgb, self.a
        if self.shadow:
            s = ndimage.gaussian_filter(self.a, 0.06 * F.scale)
            s = np.roll(np.roll(s, int(0.045 * F.scale), axis=0), int(0.03 * F.scale), axis=1) * self.shadow
            sa = s * (1 - a)
            rgb_ = (rgb_ * a[..., None]) / np.maximum(sa + a, 1e-6)[..., None]
            a = sa + a
        img = Image.fromarray((np.dstack([np.clip(rgb_, 0, 1), np.clip(a, 0, 1)]) * 255 + 0.5).astype(np.uint8), "RGBA")
        return img.convert("RGBa").resize((CELL, CELL), Image.LANCZOS).convert("RGBA")


# ------------------------------------------------------------ hair strands

def in_cap(x, y, front=0.22, r=1.0, cx=-0.05):
    fringe = front + 0.05 * math.sin(y * 9)
    return (x - cx) ** 2 + y ** 2 < r * r and x < fringe


def cap_strands(rng, n=1700, parting=(0.3, 0.0), front=0.22, r=1.0, length=(0.3, 0.62), spread=0.25, curl=0.35):
    out = []
    while len(out) < n:
        x, y = rng.uniform(-1.1, 0.4), rng.uniform(-1.1, 1.1)
        if not in_cap(x, y, front, r):
            continue
        a = math.atan2(y - parting[1], x - parting[0]) + rng.normal(0, spread)
        out.append((x, y, a, rng.uniform(*length), rng.normal(0, curl), rng.uniform(0.85, 1.08)))
    out.sort(key=lambda s: -math.hypot(s[0] - parting[0], s[1] - parting[1]))
    return out


def ball_strands(rng, cx, cy, r, n=500, swirl=1.1, length=(0.18, 0.34)):
    out = []
    for _ in range(n):
        rr = r * math.sqrt(rng.uniform(0, 1))
        t = rng.uniform(0, 2 * math.pi)
        x, y = cx + math.cos(t) * rr, cy + math.sin(t) * rr
        a = t + swirl + rng.normal(0, 0.2)
        out.append((x, y, a, rng.uniform(*length) * (0.6 + 0.4 * rr / r), rng.normal(0.4, 0.2), rng.uniform(0.85, 1.08)))
    out.sort(key=lambda s: -math.hypot(s[0] - cx, s[1] - cy))
    return out


def flow_strands(rng, width_at, n=1800, length=(0.35, 0.8), wave=0.0, end=2.3, start=0.03):
    """Strands running +x inside a tapering band: a ponytail, pigtail or long hair."""
    out = []
    while len(out) < n:
        x = rng.uniform(start, end)
        w = width_at(x)
        if w <= 0.01:
            continue
        y = rng.uniform(-w, w) + wave * math.sin(x * 3.0)
        a = rng.normal(0, 0.08) + wave * 0.6 * math.cos(x * 3.0) - (y / max(w, 0.05)) * 0.05
        out.append((x, y, a, rng.uniform(*length), rng.normal(0, 0.12), rng.uniform(0.85, 1.08)))
    out.sort(key=lambda s: abs(s[1]) - s[0] * 0.02, reverse=True)
    return out


def tie(it, x, y, r, colour):
    it.part(circle(x, y, r), colour, dome=True, gloss=0.7, power=36, edge=0.008)


# Hair caps ----------------------------------------------------------------

def h_ponytail(it):
    rng = np.random.default_rng(1)
    it.fur(cap_strands(rng, parting=(0.3, 0.0)), seed=1)
    tie(it, -0.93, 0.0, 0.13, rgb("#FF6FB0"))


def h_pigtails(it):
    rng = np.random.default_rng(2)
    it.fur(cap_strands(rng, parting=(0.3, 0.0)), seed=2)
    for s in (-1, 1):
        tie(it, -0.5, 0.82 * s, 0.12, rgb("#FF6FB0"))


def h_braid(it):
    rng = np.random.default_rng(3)
    it.fur(cap_strands(rng, parting=(0.35, 0.0), length=(0.35, 0.7)), seed=3)


def h_longhair(it):
    rng = np.random.default_rng(4)
    it.fur(cap_strands(rng, n=2000, parting=(0.3, 0.0), r=1.06, length=(0.4, 0.75)), seed=4)


def h_buns(it):
    rng = np.random.default_rng(5)
    it.fur(cap_strands(rng, parting=(0.3, 0.0)), seed=5)
    for s in (-1, 1):
        it.fur(ball_strands(rng, -0.35, 0.86 * s, 0.38, n=700, swirl=1.3 * s), seed=6 + s)


def h_bob(it):
    rng = np.random.default_rng(7)
    it.fur(cap_strands(rng, n=2000, parting=(0.2, 0.0), r=1.13, front=0.3, length=(0.35, 0.7)), seed=7)
    # A soft fringe brushed forward over the forehead, clear of the eyes.
    fr = []
    while len(fr) < 260:
        x, y = rng.uniform(-0.3, 0.12), rng.uniform(-0.28, 0.28)
        fr.append((x, y, rng.normal(0, 0.15), rng.uniform(0.22, 0.34), rng.normal(0, 0.2), rng.uniform(0.9, 1.1)))
    it.fur(fr, seed=8)


def h_messy(it):
    rng = np.random.default_rng(9)
    it.fur(cap_strands(rng, parting=(0.0, 0.0), spread=0.7, curl=0.9, length=(0.3, 0.55)), seed=9)


def h_spiky(it):
    rng = np.random.default_rng(10)
    it.fur(cap_strands(rng, parting=(0.2, 0.0), length=(0.25, 0.4)), seed=10)
    tufts = []
    for k in range(11):
        a = math.pi * (0.58 + k / 10 * 0.84)
        for _ in range(90):
            r0 = rng.uniform(0.2, 0.7)
            x, y = math.cos(a) * r0 + rng.normal(0, 0.05), math.sin(a) * r0 + rng.normal(0, 0.05)
            tufts.append((x, y, a + rng.normal(0, 0.06), rng.uniform(0.55, 0.9) * (1.2 - r0 * 0.4), 0.0, rng.uniform(0.9, 1.1)))
    tufts.sort(key=lambda s: -math.hypot(s[0], s[1]))
    it.fur(tufts, width=0.028, seed=11)


def h_quiff(it):
    rng = np.random.default_rng(12)
    it.fur(cap_strands(rng, parting=(0.1, 0.0), length=(0.28, 0.45)), seed=12)
    q = []
    while len(q) < 520:
        x, y = rng.uniform(-0.55, 0.0), rng.uniform(-0.38, 0.38)
        q.append((x, y, rng.normal(0, 0.12) - y * 0.3, rng.uniform(0.4, 0.62), rng.normal(0.25, 0.1), rng.uniform(0.95, 1.12)))
    q.sort(key=lambda s: s[0])
    it.fur(q, seed=13)


def h_curly(it):
    rng = np.random.default_rng(14)
    curls = []
    for _ in range(70):
        while True:
            x, y = rng.uniform(-1.05, 0.25), rng.uniform(-1.05, 1.05)
            if in_cap(x, y, 0.22, 1.04):
                break
        for _ in range(26):
            t = rng.uniform(0, 2 * math.pi)
            curls.append((x + math.cos(t) * 0.05, y + math.sin(t) * 0.05, t + 1.6, rng.uniform(0.14, 0.24), 2.6, rng.uniform(0.85, 1.1)))
    it.fur(curls, width=0.03, seed=14)


def h_sidepart(it):
    rng = np.random.default_rng(15)
    part_y = -0.38
    out = []
    while len(out) < 1800:
        x, y = rng.uniform(-1.1, 0.4), rng.uniform(-1.1, 1.1)
        if not in_cap(x, y, 0.25, 1.02):
            continue
        side = 1 if y > part_y else -1
        a = (math.pi / 2 * side) * 0.55 + math.pi * 0.72 * (1 if side > 0 else -1) * 0.5 + rng.normal(0, 0.18)
        a = math.atan2(math.sin(a), math.cos(a) - 0.6)
        out.append((x, y, a, rng.uniform(0.32, 0.6), rng.normal(0, 0.2), rng.uniform(0.85, 1.08)))
    out.sort(key=lambda s: -abs(s[1] - part_y))
    it.fur(out, seed=15)


def h_manbun(it):
    rng = np.random.default_rng(16)
    it.fur(cap_strands(rng, parting=(0.3, 0.0), length=(0.28, 0.5)), seed=16)
    it.fur(ball_strands(rng, -1.02, 0.0, 0.34, n=650, swirl=1.2), seed=17)
    tie(it, -0.82, 0.0, 0.09, rgb("#2B2B30"))


# Hair flows (drawn in a flow frame) ----------------------------------------

def f_ponytail(it):
    rng = np.random.default_rng(21)
    width = lambda x: 0.36 * (1 - (x / 2.35) ** 1.6) * (0.7 + 0.3 * math.sin(min(x, 1.2) * 1.3)) + 0.02
    it.fur(flow_strands(rng, width, n=2200), seed=21)


def f_pigtail(it):
    rng = np.random.default_rng(22)
    width = lambda x: 0.26 * (1 - (x / 2.2) ** 1.5) + 0.02
    it.fur(flow_strands(rng, width, n=1600, end=2.15, length=(0.3, 0.6), wave=0.08), seed=22)


def f_braid(it):
    rng = np.random.default_rng(23)
    lobes = []
    x = 0.08
    k = 0
    while x < 2.0:
        w = 0.3 * (1 - x / 2.6)
        side = 1 if k % 2 else -1
        for _ in range(170):
            t = rng.uniform(0, 1)
            y0 = side * w * (1 - 2 * t) * 0.9
            lobes.append((x + t * 0.2, y0, -side * 0.9 + rng.normal(0, 0.1), rng.uniform(0.18, 0.28) * (w / 0.3 + 0.3),
                          rng.normal(0, 0.1), rng.uniform(0.85, 1.08)))
        x += 0.2
        k += 1
    it.fur(lobes, width=0.034, seed=23)
    tuft = [(2.02, rng.normal(0, 0.05), rng.normal(0, 0.35), rng.uniform(0.15, 0.3), 0, rng.uniform(0.9, 1.1)) for _ in range(180)]
    it.fur(tuft, seed=24)
    tie(it, 2.0, 0.0, 0.07, rgb("#FF6FB0"))


def f_longhair(it):
    rng = np.random.default_rng(25)
    width = lambda x: 0.95 * (1 - (x / 2.35) ** 3.0) + 0.05
    it.fur(flow_strands(rng, width, n=3200, length=(0.5, 1.0), wave=0.05), seed=25)


# Ears --------------------------------------------------------------------

def fur_edge(it, mask, colour, n=600, length=(0.05, 0.11), seed=0, tone=1.0):
    """Short fur round a shape's outline, pointing outward."""
    rng = np.random.default_rng(seed)
    m = mask > 0.5
    edge = m & ~ndimage.binary_erosion(m, iterations=3)
    ys, xs = np.nonzero(edge)
    if len(xs) == 0:
        return
    dist = ndimage.gaussian_filter(m.astype(np.float32), 6)
    gy, gx = np.gradient(dist)
    out = []
    for i in rng.choice(len(xs), size=min(n, len(xs)), replace=False):
        px, py = xs[i], ys[i]
        a = math.atan2(-gy[py, px], -gx[py, px]) + rng.normal(0, 0.3)
        out.append((px / F.scale - 2, py / F.scale - 2, a, rng.uniform(*length), rng.normal(0, 0.3), rng.uniform(0.85, 1.05) * tone))
    it.fur(out, colour=colour, root=0.9, tip=1.05, width=0.022, light=False, seed=seed)


def ear(it, centre, angle, shape_fn, outer, inner=None, inner_scale=0.62, fur=True, seed=0, inner_fur=None):
    for s in (-1, 1):
        cx, cy = centre[0], centre[1] * s
        m = shape_fn(cx, cy, angle * s, 1.0)
        it.part(m, outer, bevel=0.14, gloss=0.35, power=18, edge=0.01)
        if inner is not None:
            mi = shape_fn(cx, cy, angle * s, inner_scale) * m
            it.part(mi, inner, bevel=0.12, gloss=0.3, power=16, edge=0)
            if inner_fur is not None:
                fur_edge(it, mi, inner_fur, n=220, length=(0.04, 0.09), seed=seed + 5 + s)
        if fur:
            fur_edge(it, m, outer, n=500, seed=seed + s)


def round_ear(r):
    """A round ear, a little long and laid back like the bunny's."""
    return lambda cx, cy, a, k: ellipse(cx + math.cos(a) * r * 0.25, cy + math.sin(a) * r * 0.25,
                                        r * 1.18 * k, r * 0.9 * k, rot=a)


def pointed(length, width):
    def shape(cx, cy, a, k):
        L, W = length * k, width * k
        tip = (L, 0.0)
        outline = curve((-0.12 * L, -W / 2), (L * 0.55, -W * 0.42), tip, n=24) + \
            curve(tip, (L * 0.55, W * 0.42), (-0.12 * L, W / 2), n=24)
        outline += [(-0.2 * L, W * 0.3), (-0.22 * L, 0), (-0.2 * L, -W * 0.3)]
        rot = [(cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)) for x, y in outline]
        return poly(rot)
    return shape


def long_ear(length, width, droop=0.0):
    def shape(cx, cy, a, k):
        L, W = length * k, width * k
        spine = curve((0, 0), (L * 0.5, droop * L * 0.4), (L, droop * L))
        pts_l, pts_r = [], []
        for i, (x, y) in enumerate(spine):
            t = i / (len(spine) - 1)
            w = W / 2 * math.sin(math.pi * min(0.98, 0.18 + t * 0.9)) ** 0.7
            pts_l.append((x, y + w))
            pts_r.append((x, y - w))
        outline = pts_l + pts_r[::-1]
        rot = [(cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)) for x, y in outline]
        return poly(rot)
    return shape


# Every ear leans back along the body, as the bunny's does (OM): angles near
# 0.8 pi point out from the side of the head and well behind it.
BACK = math.pi * 0.8


def e_panda(it):
    ear(it, (-0.5, 0.72), BACK, round_ear(0.32), rgb("#1E1E22"), rgb("#3A3A42"), 0.55, seed=31)


def e_bunny(it):
    ear(it, (-0.45, 0.42), math.pi * 0.88, long_ear(1.55, 0.5, 0.12), rgb("#F7F5F2"), rgb("#FF9EC4"), 0.62, seed=32,
        inner_fur=None)


def e_lop(it):
    ear(it, (-0.35, 0.6), math.pi * 0.8, long_ear(1.35, 0.52, 0.3), rgb("#F2E3CC"), rgb("#FFB0CC"), 0.6, seed=33)


def e_cat(it):
    ear(it, (-0.35, 0.62), BACK, pointed(0.66, 0.6), rgb("#E9E3F0"), rgb("#FF9EC4"), 0.6, seed=34,
        inner_fur=rgb("#FFFFFF"))


def e_mouse(it):
    ear(it, (-0.45, 0.76), BACK, round_ear(0.42), rgb("#B9B7C2"), rgb("#FFB3C8"), 0.66, seed=35)


def e_bear(it):
    ear(it, (-0.5, 0.72), BACK, round_ear(0.3), rgb("#8A5A36"), rgb("#D9A57A"), 0.58, seed=36)


def e_koala(it):
    ear(it, (-0.42, 0.8), BACK, round_ear(0.42), rgb("#9EA3AC"), rgb("#F4F4F6"), 0.66, seed=37, inner_fur=rgb("#FFFFFF"))


def e_fox(it):
    ear(it, (-0.32, 0.6), BACK, pointed(0.86, 0.6), rgb("#E8772E"), rgb("#FFF3E6"), 0.58, seed=38,
        inner_fur=rgb("#FFFFFF"))
    for s in (-1, 1):
        a = BACK * s
        tipx, tipy = -0.32 + math.cos(a) * 0.78, 0.6 * s + math.sin(a) * 0.78
        it.part(circle(tipx, tipy, 0.09), rgb("#2A1A12"), dome=True, gloss=0.3, edge=0)


def e_wolf(it):
    ear(it, (-0.3, 0.58), math.pi * 0.82, pointed(0.92, 0.54), rgb("#6E7280"), rgb("#2C2E36"), 0.6, seed=39,
        inner_fur=rgb("#C8CAD2"))


def e_tiger(it):
    ear(it, (-0.4, 0.66), BACK, pointed(0.56, 0.64), rgb("#F08A24"), rgb("#FFF1DE"), 0.55, seed=40)
    for s in (-1, 1):
        a = BACK * s
        for k in (0.18, 0.34):
            x, y = -0.4 + math.cos(a) * k, 0.66 * s + math.sin(a) * k
            it.part(ellipse(x, y, 0.03, 0.15, rot=a), rgb("#1E1410"), bevel=0.03, gloss=0.2, edge=0)


def e_bat(it):
    def bat(cx, cy, a, k):
        L = 1.05 * k
        pts = [(0, -0.3 * k), (L * 0.55, -0.34 * k), (L, 0.0), (L * 0.62, 0.1 * k), (L * 0.35, 0.3 * k), (0, 0.3 * k)]
        rot = [(cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)) for x, y in pts]
        return poly(rot)
    for s in (-1, 1):
        a = math.pi * 0.8 * s
        cx, cy = -0.3, 0.58 * s
        m = bat(cx, cy, a, 1.0)
        it.part(m, rgb("#3B2A4A"), bevel=0.1, gloss=0.5, power=26, edge=0.012)
        it.part(bat(cx, cy, a, 0.72) * m, rgb("#7A3B6A"), bevel=0.08, gloss=0.3, edge=0)
        for t in (0.3, 0.55):
            x0, y0 = cx + math.cos(a) * 0.05, cy + math.sin(a) * 0.05
            x1 = cx + math.cos(a + 0.25 * s * (t - 0.4)) * (0.95 * t + 0.2)
            y1 = cy + math.sin(a + 0.25 * s * (t - 0.4)) * (0.95 * t + 0.2)
            it.over(rgb("#20142A"), stroke([(x0, y0), (x1, y1)], 0.02) * m * 0.7)


def e_dragon(it):
    teal, spine = rgb("#1E9C84"), rgb("#EFE3C4")
    for s in (-1, 1):
        base = (-0.3, 0.58 * s)
        tips = [(base[0] + math.cos(math.pi * (0.66 + 0.1 * k) * s) * 1.0, base[1] + math.sin(math.pi * (0.66 + 0.1 * k) * s) * 1.0)
                for k in range(3)]
        web = [base] + [tips[0], ((tips[0][0] + tips[1][0]) / 2 + 0.05, (tips[0][1] + tips[1][1]) / 2 - 0.05 * s),
                        tips[1], ((tips[1][0] + tips[2][0]) / 2 + 0.05, (tips[1][1] + tips[2][1]) / 2 - 0.05 * s), tips[2]]
        it.part(poly(web), teal, bevel=0.12, gloss=0.45, power=24, edge=0.012)
        for tip in tips:
            it.part(tapered(curve(base, ((base[0] + tip[0]) / 2, (base[1] + tip[1]) / 2), tip), 0.1, 0.015), spine,
                    bevel=0.04, gloss=0.6, edge=0.006)


# Glasses -----------------------------------------------------------------
#
# Sized and placed like slither's own (measured from its round, heart and star
# glasses): wider than the head (about +-1.15 R), the lenses well forward
# (x 0.1 to 0.95) with the eyes inside them, and short straight temples that
# stop about 0.6 R behind the head's centre.

LENSES = [(0.5, -0.6), (0.5, 0.6)]
TEMPLE_END = -0.6


def spectacles(it, lens, rim_colour, glass_tint, rim=0.06, glass_alpha=0.2, temple=0.05, temple_colour=None,
               bridge=True, metal=False, rim_gloss=0.6):
    temple_colour = rim_colour if temple_colour is None else temple_colour
    lenses = [lens(x, y) for x, y in LENSES]
    # Temples: straight back from the lenses' outer edge, then a small hook in.
    for s, m in zip((-1, 1), lenses):
        ys, xs = np.nonzero(m > 0.5)
        outer = (ys.max() if s > 0 else ys.min()) / F.scale - 2
        y = outer - 0.04 * s
        it.part(stroke([(0.45, y), (TEMPLE_END, y), (TEMPLE_END - 0.08, y - 0.07 * s)], temple), temple_colour,
                bevel=0.02, gloss=0.7, metal=metal, edge=0.006)
    for m in lenses:
        it.glass(m, glass_tint, glass_alpha)
        ring = np.clip(grow(m, rim / 2) - shrink(m, rim / 2), 0, 1)
        it.part(ring, rim_colour, bevel=rim * 0.5, gloss=rim_gloss, power=34, metal=metal, edge=0.006)
    if bridge:
        it.part(stroke(curve((0.62, -0.1), (0.76, 0.0), (0.62, 0.1)), rim * 0.8), rim_colour, bevel=0.02, gloss=0.7,
                metal=metal, edge=0.006)


def heart(x, y, size=0.5):
    pts = []
    for t in np.linspace(0, 2 * math.pi, 120):
        hx = 16 * math.sin(t) ** 3
        hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        # Point of the heart towards the back of the head.
        pts.append((x + 0.02 + hy * size / 17, y + hx * size / 17))
    return poly(pts)


def g_heart(it):
    spectacles(it, lambda x, y: heart(x, y), rgb("#FF3F8E"), rgb("#FF8EC0"), rim=0.07, glass_alpha=0.28)


def g_cateye(it):
    def lens(x, y):
        s = 1 if y > 0 else -1
        pts = [(x + math.cos(t) * 0.44, y + math.sin(t) * 0.42) for t in np.linspace(0, 2 * math.pi, 80)]
        # The wing lifts at the outer front corner.
        pts = [(px + max(0.0, (py - y) * s) * 0.25, py + max(0.0, (px - x)) * max(0.0, (py - y) * s) * 0.7 * s) for px, py in pts]
        return poly(pts)
    spectacles(it, lens, rgb("#B23A8A"), rgb("#E8B4FF"), rim=0.075, glass_alpha=0.22)
    for x, y in LENSES:
        s = 1 if y > 0 else -1
        for k in range(3):
            it.part(circle(x + 0.4 - k * 0.08, y + (0.42 + k * 0.04) * s, 0.036), rgb("#FFFFFF"), dome=True, gloss=1.0, edge=0)


def g_flower(it):
    spectacles(it, lambda x, y: circle(x, y, 0.4), rgb("#FFD23F"), rgb("#FFF2B0"), rim=0.06, glass_alpha=0.2)
    for x, y in LENSES:
        for k in range(9):
            a = k / 9 * 2 * math.pi
            it.part(ellipse(x + math.cos(a) * 0.5, y + math.sin(a) * 0.5, 0.14, 0.085, rot=a),
                    rgb("#FFFFFF"), bevel=0.05, gloss=0.4, edge=0.006, edge_colour=rgb("#E0C050"))


def g_pastel(it):
    spectacles(it, lambda x, y: circle(x, y, 0.48), rgb("#7FE0C8"), rgb("#D8FFF4"), rim=0.09, glass_alpha=0.16)


def g_nerd(it):
    tex = np.clip(0.7 + 0.5 * ndimage.gaussian_filter(np.random.default_rng(5).random((N, N)).astype(np.float32), 9) * 3 - 0.75, 0.55, 1.2)
    spectacles(it, lambda x, y: ellipse(x, y, 0.44, 0.47, n=32), rgb("#7A4A26") * tex[..., None], rgb("#E8F4FF"),
               rim=0.11, glass_alpha=0.14)


def g_sparkle(it):
    spectacles(it, lambda x, y: circle(x, y, 0.48), rgb("#C39BFF"), rgb("#F0E4FF"), rim=0.07, glass_alpha=0.2)
    rng = np.random.default_rng(6)
    for x, y in LENSES:
        for _ in range(3):
            sx, sy = x + rng.uniform(-0.35, 0.35), y + rng.uniform(-0.4, 0.4)
            pts = []
            for k in range(8):
                a = k / 8 * 2 * math.pi
                r = 0.11 if k % 2 == 0 else 0.035
                pts.append((sx + math.cos(a) * r, sy + math.sin(a) * r))
            it.part(poly(pts), rgb("#FFF6B0"), bevel=0.02, gloss=0.8, edge=0)


def g_aviator(it):
    def drop(x, y):
        s = 1 if y > 0 else -1
        pts = [(x + 0.04 + math.cos(t) * 0.44, y + 0.03 * s + math.sin(t) * 0.38 * (1 + 0.3 * max(0.0, math.sin(t) * s)))
               for t in np.linspace(0, 2 * math.pi, 80, endpoint=False)]
        return poly(pts)
    spectacles(it, drop, rgb("#D9AE4A"), rgb("#3F5E4C"), rim=0.04, glass_alpha=0.55, metal=True)
    it.part(stroke([(0.66, -0.16), (0.66, 0.16)], 0.035), rgb("#D9AE4A"), bevel=0.02, gloss=0.9, metal=True, edge=0.005)


def g_pixel(it):
    black = rgb("#0E0E10")
    cells = []
    size = 0.145
    for x, y in LENSES:
        for i in range(-3, 3):
            for j in range(-3, 3):
                cx, cy = x + (i + 0.5) * size, y + (j + 0.5) * size
                if i in (-3, 2) and j in (-3, 2):
                    continue
                cells.append((cx, cy))
    h = size / 2 + 0.003
    m = np.zeros((N, N), np.float32)
    for cx, cy in cells:
        m = np.maximum(m, poly([(cx - h, cy - h), (cx + h, cy - h), (cx + h, cy + h), (cx - h, cy + h)]))
    for s in (-1, 1):
        it.part(stroke([(0.45, 1.02 * s), (TEMPLE_END, 1.02 * s)], 0.09), black, bevel=0.02, gloss=0.3, edge=0)
    it.part(stroke([(0.7, -0.2), (0.7, 0.2)], 0.12), black, bevel=0.02, gloss=0.3, edge=0)
    it.part(m, black, bevel=0.02, gloss=0.2, edge=0, alpha=0.88)
    for x, y in LENSES:
        for k in range(2):
            cx, cy = x + (-2 + k + 0.5) * size, y + (-2 + k + 0.5) * size
            q = size / 2 - 0.01
            it.over(rgb("#FFFFFF"), poly([(cx - q, cy - q), (cx + q, cy - q), (cx + q, cy + q), (cx - q, cy + q)]) * 0.85)


def g_cyber(it):
    bar = ellipse(0.5, 0, 0.38, 1.15)
    it.glass(bar, rgb("#00E5FF"), 0.45, streak=0.6)
    ring = np.clip(grow(bar, 0.03) - shrink(bar, 0.03), 0, 1)
    it.part(ring, rgb("#1C2A36"), bevel=0.02, gloss=0.9, power=40, metal=True, edge=0.006)
    it.over(rgb("#9FF8FF"), ndimage.gaussian_filter(stroke([(0.7, -0.95), (0.7, 0.95)], 0.025), 3) * 0.9)
    for s in (-1, 1):
        it.part(stroke([(0.4, 1.08 * s), (TEMPLE_END, 1.08 * s), (TEMPLE_END - 0.08, 1.0 * s)], 0.055), rgb("#1C2A36"),
                bevel=0.02, gloss=0.8, metal=True, edge=0.006)


def g_evil(it):
    visor = ellipse(0.48, 0, 0.38, 1.15)
    it.part(visor, rgb("#16161C"), bevel=0.12, gloss=0.9, power=50, edge=0.008)
    slit = ellipse(0.58, 0, 0.07, 0.86)
    it.over(rgb("#FF2A2A"), ndimage.gaussian_filter(slit, 10) * 0.8)
    it.part(slit, rgb("#FF4040"), bevel=0.02, gloss=0.9, edge=0)
    for s in (-1, 1):
        it.part(stroke([(0.35, 1.08 * s), (TEMPLE_END, 1.08 * s), (TEMPLE_END - 0.08, 1.0 * s)], 0.055), rgb("#16161C"),
                bevel=0.02, gloss=0.8, edge=0.006)


def g_steampunk(it):
    brass = rgb("#C08F38")
    spectacles(it, lambda x, y: circle(x, y, 0.42), brass, rgb("#F0A840"), rim=0.15, glass_alpha=0.42,
               metal=True, temple=0.09, temple_colour=rgb("#6B4423"))
    for x, y in LENSES:
        for k in range(9):
            a = k / 9 * 2 * math.pi
            it.part(circle(x + math.cos(a) * 0.5, y + math.sin(a) * 0.5, 0.03), rgb("#F4D98A"), dome=True,
                    gloss=0.9, metal=True, edge=0)


def g_punk(it):
    black = rgb("#141418")
    spectacles(it, lambda x, y: ellipse(x, y, 0.42, 0.48), black, rgb("#6A2E80"), rim=0.08, glass_alpha=0.55)
    steel = rgb("#D0D6DE")
    for x, y in LENSES:
        for k in range(7):
            a = -math.pi / 2 + k / 6 * math.pi
            a = a if y > 0 else a + math.pi
            bx, by = x + math.cos(a) * 0.46, y + math.sin(a) * 0.52
            tx, ty = x + math.cos(a) * 0.66, y + math.sin(a) * 0.74
            nx, ny = -math.sin(a) * 0.05, math.cos(a) * 0.05
            it.part(poly([(bx + nx, by + ny), (tx, ty), (bx - nx, by - ny)]), steel, bevel=0.02, gloss=1.0, power=40,
                    metal=True, edge=0.005)


# Hair, from slither's own painted hair ---------------------------------------
#
# Procedural strands never looked like slither's hand-painted hair, so every
# hair cell is built from the originals already in the engine atlas (row 8,
# cols 5-6: 17 dreadlocks, 18 fluffy, 19 flame, 20 pom, 21 mohawk). They are
# turned into light greys that keep their painted shading, so the engine can
# tint them any colour, and recombined into new styles. Each original sits
# where the engine puts it (half size `sc` R, `of` x 0.414 R forward).
#
# Cap frame: 4.4 R square, centred 0.6 R behind the head centre.

CAP_SIDE, CAP_X = 4.4, -0.6
ORIGINAL_ATLAS = ROOT / "Resources/AirSkin/tex_atlas_8k.png"
SC = {17: 2.4, 18: 2.1, 19: 2.0, 20: 1.8, 21: 2.1}
OF = {17: -1.15, 18: -1.8, 19: -1.8, 20: -1.8, 21: -3.0}
_originals = {}


def original(k):
    if k not in _originals:
        atlas = Image.open(ORIGINAL_ATLAS).convert("RGBA")
        x, y = 5 * 448 + (k % 8) * 112, 8 * 448 + (k // 8) * 112
        # Each original is greyed on its own, so a dark one (the black pom)
        # tints as brightly as a light one beside it.
        _originals[k] = to_grey(atlas.crop((x, y, x + 112, y + 112)))
    return _originals[k]


def to_grey(img, lo=0.36):
    """Painted colour to a light grey that keeps its shading, for tinting."""
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11
    seen = a[..., 3] > 0.25
    if seen.any():
        p0, p1 = np.percentile(lum[seen], 3), np.percentile(lum[seen], 99)
        lum = np.clip((lum - p0) / max(p1 - p0, 1e-3), 0, 1)
    g = lo + (1 - lo) * lum
    out = np.dstack([g, g, g, a[..., 3]])
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")


def paste(canvas, img, cx, cy, side, px_per_r, origin, rot=0.0, stretch_y=1.0, flip=False, stretch_x=1.0):
    """Paste `img` (a square cell `side` R wide) centred at (cx, cy) R in a canvas."""
    w = max(2, int(side * px_per_r * stretch_x))
    h = max(2, int(side * px_per_r * stretch_y))
    im = img.resize((w, h), Image.LANCZOS)
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    if rot:
        im = im.rotate(rot, resample=Image.BICUBIC, expand=True)
    px = (cx - origin[0]) * px_per_r - im.width / 2
    py = (cy - origin[1]) * px_per_r - im.height / 2
    canvas.alpha_composite(im, (int(round(px)), int(round(py))))


def cap_canvas():
    return Image.new("RGBA", (N, N), (0, 0, 0, 0)), N / CAP_SIDE, (CAP_X - CAP_SIDE / 2, -CAP_SIDE / 2)


def put_original(canvas, pxr, origin, k, scale=1.0, dx=0.0, dy=0.0, stretch_y=1.0, rot=0.0):
    paste(canvas, original(k), OF[k] * 0.414 + dx, dy, 2 * SC[k] * scale, pxr, origin, rot=rot, stretch_y=stretch_y)


def finish(canvas):
    return canvas.convert("RGBa").resize((CELL, CELL), Image.LANCZOS).convert("RGBA")


def hair_cap(k):
    c, pxr, o = cap_canvas()
    if k == 0:                       # fluffy (slither's own)
        put_original(c, pxr, o, 18)
    elif k == 1:                     # flame spiky
        put_original(c, pxr, o, 19)
    elif k == 2:                     # pom
        put_original(c, pxr, o, 20)
    elif k == 3:                     # dreadlocks
        put_original(c, pxr, o, 17)
    elif k == 4:                     # mohawk
        put_original(c, pxr, o, 21)
    elif k in (5, 6, 7, 8):          # ponytail, pigtails, braid, long hair: a fluffy cap over the flow's root
        put_original(c, pxr, o, 18, scale=0.92, dx=0.12)
        # A gathered knot where the flow leaves the cap, so no gap shows between them.
        # A small fluffy lock across the neck where the hair gathers.
        knots = {5: [(-1.5, 0.0, 1.15)], 6: [(-1.25, -0.8, 0.95), (-1.25, 0.8, 0.95)], 7: [(-1.5, 0.0, 1.05)]}
        for x, y, side in knots.get(k, []):
            paste(c, original(18), x, y, side, pxr, o, stretch_y=0.85)
    elif k == 9:                     # space buns
        put_original(c, pxr, o, 18, scale=0.9, dx=0.12)
        for s in (-1, 1):
            paste(c, original(20), -0.3, 0.9 * s, 1.35, pxr, o)
    elif k == 10:                    # man bun
        put_original(c, pxr, o, 18, scale=0.82, dx=0.2)
        paste(c, original(20), -1.05, 0.0, 1.15, pxr, o)
    elif k == 11:                    # bob: fluffy, fuller at the sides
        put_original(c, pxr, o, 18, scale=0.94, dx=0.14, stretch_y=1.12)
    return finish(c)


def hair_flow(k):
    """A flow cell: the root at the left middle, hair running +x, built from
    copies of the fluffy original brushed along the flow, root on top."""
    c = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    pxr = N / FLOW_SPAN
    origin = (0.0, -FLOW_SPAN / 2)
    fluffy = original(18)
    # (centre x, centre y, side, stretch x, stretch y, tilt): the fluffy original
    # drawn long along the flow reads as one flowing lock; a thinner lock over
    # its end tapers it. Drawn tip first so the root sits on top.
    if k == 0:       # ponytail
        locks = [(2.75, 0.0, 0.95, 1.5, 0.5, 0.0), (2.2, 0.0, 1.35, 1.45, 0.6, 0.0),
                 (1.55, 0.0, 1.75, 1.4, 0.7, 0.0), (0.95, 0.0, 2.0, 1.3, 0.8, 0.0)]
    elif k == 1:     # pigtail
        locks = [(2.3, 0.0, 0.8, 1.5, 0.5, 0.0), (1.8, 0.0, 1.1, 1.45, 0.58, 0.0),
                 (1.2, 0.0, 1.45, 1.4, 0.66, 0.0), (0.75, 0.0, 1.6, 1.3, 0.72, 0.0)]
    elif k == 2:     # braid: locks tilted left and right in turn
        locks = [(0.6 + i * 0.26, 0.0, 1.4 - i * 0.06, 1.0, 0.95, 34.0 * (1 if i % 2 else -1)) for i in range(10)][::-1]
    else:            # long hair
        locks = [(2.55, 0.0, 1.6, 1.8, 1.0, 0.0), (1.9, 0.0, 2.2, 1.6, 1.15, 0.0), (1.15, 0.0, 2.6, 1.4, 1.3, 0.0)]
    for x, y, side, sx, sy, rot in locks:
        paste(c, fluffy, x, y, side, pxr, origin, rot=rot, stretch_x=sx, stretch_y=sy, flip=True)
    return finish(c)


HEAD_ITEMS = [("cap", k) for k in range(12)]
FLOW_ITEMS = [("flow", k) for k in range(4)]
EAR_ITEMS = [e_panda, e_bunny, e_lop, e_cat, e_mouse, e_bear, e_koala, e_fox, e_wolf, e_tiger, e_bat, e_dragon]
GLASS_ITEMS = [g_heart, g_cateye, g_flower, g_pastel, g_nerd, g_sparkle, g_aviator, g_pixel, g_cyber, g_evil,
               g_steampunk, g_punk]
CELLS = HEAD_ITEMS + FLOW_ITEMS + EAR_ITEMS + GLASS_ITEMS


def build(only=None, base=None):
    global F
    atlas = base.copy() if base is not None else Image.new("RGBA", (CELL * GRID, CELL * GRID), (0, 0, 0, 0))
    for k, fn in enumerate(CELLS):
        if only is not None and k not in only:
            continue
        box = ((k % GRID) * CELL, (k // GRID) * CELL, (k % GRID) * CELL + CELL, (k // GRID) * CELL + CELL)
        atlas.paste(Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0)), box[:2])
        if isinstance(fn, tuple):
            kind, index = fn
            atlas.paste(hair_cap(index) if kind == "cap" else hair_flow(index), box[:2])
            print(f"{k:2d} hair {kind} {index}", flush=True)
            continue
        F = Frame()
        it = Item()
        fn(it)
        atlas.paste(it.render(), box[:2])
        print(f"{k:2d} {fn.__name__}", flush=True)
    return atlas


if __name__ == "__main__":
    import sys
    only = None
    base = None
    if len(sys.argv) > 1:
        only = {int(v) for v in sys.argv[1].split(",")}
        if IOS_OUT.exists():
            base = Image.open(IOS_OUT).convert("RGBA")
    atlas = build(only, base)
    atlas.save(IOS_OUT, optimize=True)
    atlas.save(ANDROID_OUT, optimize=True)
    print("wrote", IOS_OUT, "and", ANDROID_OUT)
