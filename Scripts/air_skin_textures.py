"""Exact ports of the slither.io Android (AIR) Build-a-Slither textures.

Every formula below is transcribed from `gaim.Main.rootCreated` and
`gaim.Main.buildColorWheel` of the official AIR client (SWF SHA-256
8d21d353...685a). The shipped app draws baked copies of these bitmaps;
`generate-air-skin-assets.py --verify` checks this port against those baked
pixels before anything is written.

Coordinates are the AIR pixel grid scaled by `scale`: native pixel (x, y) of
the 64 px bead maps to (x * scale, y * scale). Colour is sampled where AIR
samples it (the integer pixel corner); alpha is the coverage the Flash
rasteriser gives the drawn circle, measured by supersampling.
"""
import numpy as np

BEAD_RADIUS = 32          # `_loc15_ = 32`
SHADOW_OUTER = 14         # `_loc69_`
SHADOW_RING = 5           # `_loc68_`
SHADOW_SIZE = BEAD_RADIUS * 2 + SHADOW_OUTER * 2 + 10   # 102


def _grid(size_native, scale):
    n = int(round(size_native * scale))
    p = np.arange(n, dtype=np.float64) / scale
    x, y = np.meshgrid(p, p, indexing="xy")
    return n, x, y


# Flash draws `drawCircle` as eight quadratic curves and antialiases them its
# own way. Against the baked sheets a true circle 0.2 px wider reproduces that
# coverage with a mean alpha error below 1/255 (bead and wheel alike).
FLASH_CIRCLE_BIAS = 0.2


def _circle_coverage(n, scale, cx, cy, radius, samples=4):
    """Area of each output pixel inside the circle, in native units."""
    acc = np.zeros((n, n), dtype=np.float64)
    for sy in range(samples):
        for sx in range(samples):
            px = (np.arange(n) + (sx + 0.5) / samples) / scale
            py = (np.arange(n) + (sy + 0.5) / samples) / scale
            gx, gy = np.meshgrid(px, py, indexing="xy")
            acc += ((gx - cx) ** 2 + (gy - cy) ** 2) <= radius * radius
    return acc / (samples * samples)


def bead(kind, scale=1.0):
    """kind 0 = `kmc_ts[9][0]` (nsk 0), kind 1 = `kmc_ts[29][0]` (nsk 1).

    Returns an (n, n, 4) uint8 RGBA array, straight alpha.
    """
    r = BEAD_RADIUS
    c = r  # `_loc61_ = _loc60_ / 2`
    n, x, y = _grid(2 * r, scale)
    f = np.power(np.clip(1 - np.abs(y - r) / r, 0, 1), 0.5)
    g = np.clip(1 - np.sqrt((x - c) ** 2 + (y - c) ** 2) / (r * 2 + 2), 0, 1)
    f = f + (g - f) * 0.5
    if kind == 0:
        # Colour 9 is (255,255,255); single frame so `_loc4_ *= 1.22`.
        f = f * 1.22
        value = np.floor(255.0 * f)
    elif kind == 1:
        # Colour 29, frame `_loc3_ = 0` of five: `1.44 - 0.88 * 0 / 4`.
        e = np.sqrt((0.5 * (x - c)) ** 2 + (1 * (y - c)) ** 2) / c
        e = np.minimum(np.power(e, 2), 1)
        f = f * 1.44
        value = 32.0 * f
        value = value + (255 * 1 - value) * e
        value = np.floor(value * 1)
    else:
        raise ValueError(kind)
    value = np.clip(value, 0, 255)
    alpha = np.clip(np.round(_circle_coverage(n, scale, c, c, r + FLASH_CIRCLE_BIAS) * 255), 0, 255)
    out = np.zeros((n, n, 4), dtype=np.uint8)
    out[..., 0] = out[..., 1] = out[..., 2] = value.astype(np.uint8)
    out[..., 3] = alpha.astype(np.uint8)
    return out


def shadow(scale=1.0):
    """`ksmc_t`: the black outline disc plus soft drop shadow under each bead."""
    size = SHADOW_SIZE
    c = size / 2
    r = BEAD_RADIUS
    n, x, y = _grid(size, scale)
    d = np.sqrt((c - x) ** 2 + (c + 4.5 - y) ** 2) - (r + 2)
    f = np.where(d > 0, np.sqrt(np.maximum(d, 0) / SHADOW_OUTER), 0.0)
    f = np.clip(f, 0, 1)
    a = 0.4 * (1 - f)
    d2 = np.sqrt((c - x) ** 2 + (c - y) ** 2) - (r - 0)
    a = np.where(d2 <= SHADOW_RING, np.minimum(1, a + (SHADOW_RING - d2)), a)
    alpha = np.floor(255 * a)  # `int(255 * _loc4_)`
    out = np.zeros((n, n, 4), dtype=np.uint8)
    out[..., 3] = np.clip(alpha, 0, 255).astype(np.uint8)
    return out


def _closest_mod(value, target, period):
    """`hypah.mod.Mod.closestMod`: `value` shifted by periods nearest `target`."""
    return value + np.round((target - value) / period) * period


def wheel_rgb(angle, distance):
    """Colour at a wheel point, as `buildColorWheel` and the pointer compute it."""
    rad, inner, outer = 128, 16, 24
    d = np.clip(distance - inner, 0, rad - outer - inner)
    sat = np.minimum(1, np.maximum(0, d) / (rad - outer - inner))
    two_pi = np.pi * 2
    k1 = np.pi * 2 / 3
    k2 = np.pi * 4 / 3
    rr = (1 - np.abs(_closest_mod(angle, 0, two_pi)) / np.pi - 1 / 3) * 3
    gg = (1 - np.abs(_closest_mod(angle, k1, two_pi) - k1) / np.pi - 1 / 3) * 3
    bb = (1 - np.abs(_closest_mod(angle, k2, two_pi) - k2) / np.pi - 1 / 3) * 3
    chans = []
    for ch in (rr, gg, bb):
        ch = np.clip(ch, 0, 1)
        chans.append(np.clip(np.round(128 + (256 * ch - 128) * sat), 0, 255))
    return chans


def wheel(scale=1.0):
    """`cw_t`: 256 px hue/saturation disc, alpha from a radius-126 circle."""
    n, x, y = _grid(256, scale)
    dx = x - 128
    dy = y - 128
    r, g, b = wheel_rgb(np.arctan2(dy, dx), np.sqrt(dx * dx + dy * dy))
    alpha = np.clip(np.round(_circle_coverage(n, scale, 128, 128, 126 + FLASH_CIRCLE_BIAS) * 255), 0, 255)
    out = np.zeros((n, n, 4), dtype=np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = r, g, b
    out[..., 3] = alpha
    return out
