# Android Build-a-Slither wheel (Build 56)

Wyrm iOS carries the colour wheel and the first two bead textures of the
official slither.io Android client ("AIR", Adobe AIR, package
`air.com.hypah.io.slither`, embedded SWF SHA-256 `8d21d353…685a`). Everything
below is transcribed from that client's decompiled `gaim.Main`; nothing is
approximated by eye.

## What the player sees

Skin › Pattern has a round Liquid Glass button beside UNDO and CLEAR. It swaps
the 42-bead palette for the wheel; pressed again it brings the palette back.

- **Wheel**: AIR's hue/saturation disc (`buildColorWheel`): angle picks the hue,
  distance from the centre the saturation, flat grey inside radius 16.
- **Hue pointer**: moves by the drag (not to the finger), limited to radius 107.
- **Bezel knob**: rides on radius 151. Its angle is AIR's `bsk_br`: the top half
  lightens toward white (to 1), the bottom half darkens (to −0.5). The wheel is
  overlaid with white or black at alpha |br|, as AIR does.
- **Bezel**: a ring tinted with the unshaded wheel colour (AIR tints its bezel
  bitmap the same colour), with a light top and shaded bottom.
- **Glass**: the toggle and the two bead buttons are Liquid Glass on iOS 26 and
  a material lens on iOS 15–25. Since Build 57 the bezel and both knobs are
  glass-styled plain layers instead: live Liquid Glass on parts that move or
  re-tint every frame flickered and lagged on the owner's iPhone (Build 56).
- **Dragging** (Build 57): one gesture covers the whole wheel. A finger on the
  hue pointer moves it by the drag (AIR's behaviour); a finger elsewhere on the
  disc starts the pointer under the finger; a finger on the bezel sets the
  knob's angle directly. Only the panel's own state changes while dragging;
  the persisted wheel state is written once, when the finger lifts, so the
  Skin page and its 256-bead preview are not re-rendered per touch sample.
- **Two bead buttons**: AIR's `n_bskbtns` 0 and 1 (its first row starts with
  them): nsk 0, the plain bead (`kmc_ts[9][0]`), and nsk 1, the dark-core bead
  with a light rim (`kmc_ts[29][0]`). They show the picked colour untouched
  and turned half a revolution, as AIR shows them. A tap appends that bead.

## Stored data

Each wheel bead appends two things to the existing pattern:

| Field | Value |
|---|---|
| colour group (`wyrm.ios.skin.custom-groups`) | nearest arena group to the RGB, Android Wyrm's green-weighted `nearestGroup` over the engine palette, dead groups 36/38/40/41 excluded |
| ARGB (`wyrm.ios.skin.custom-colors`) | `0xFE______` nsk 0 or `0xFD______` nsk 1; low 24 bits = exact picked RGB |

The join packet is unchanged: it still carries only colour groups, so players
on the official clients see the nearest palette colour. The ARGB travels, as
before, through settings and `/v1/arena/skin(s)`. Wyrm iOS draws the AIR bead;
Android/Desktop Wyrm draw any non-zero ARGB as a flat tinted bead until they
learn the two alpha markers. An Android Wyrm colour whose alpha is exactly
253 or 254 would be read as an AIR bead on iOS; the colour is unchanged.

## Other players' skins

- **Wyrm iOS players** who build with the wheel: their exact colour and AIR
  bead texture reach every other Wyrm iOS player in the same arena through
  `/v1/arena/skin(s)` (engine `built_skin_rgba` reads remote rows the same way
  as the local snake), shadow included. Both must be signed in; the id and
  nickname must still match the live snake.
- **Android/Desktop Wyrm players** with exact colours: shown in their exact
  colour (flat bead), as before.
- **Official slither.io Android app players** who use its wheel: *not*
  possible today. Their RGB beads reach the arena in the AIR `custom_skin2`
  format (opcodes 2–7), which the server forwards only to AIR-identity
  clients. Wyrm joins with the web identity because the arena refused the AIR
  identity (`arena_persona.h`: the server hung up after the AIR challenge
  answer), so Wyrm receives the web palette form and draws that. Build 57 logs
  the raw skin bytes the arena sends (`Wyrm arena skin id=… len=… bytes=…`, at
  most 24 per connection, no nickname) so one Developer Mode export beside an
  Android-app player wearing a wheel skin settles exactly what arrives.

## Engine rendering

`Scripts/prepare-original-engine.py`:

1. Verifies the original atlas hash, then replaces it in the prepared tree
   with `Resources/AirSkin/tex_atlas_8k.png` (hash pinned). The app bundles
   `build-original-source/app/res`, not `SharedEngine/app/res`.
2. Patches render mode 0 of `redraw.c` (all other modes keep the flat bead):
   - bead UV = the AIR cell; colour = AIR `setSkin` tint: when mid + max
     channel < 255, every channel gets `1 + (255 − (mid + max)) / 2`, capped at
     255 and truncated;
   - `ksmc_t` (outline disc plus drop shadow 4.5 px down, unrotated, 102/64 of
     the bead) under every AIR bead, in AIR's order: points 8…0 at alpha
     `1 − k/9`, then the last four, then point `j − 4` before bead `j` at alpha
     `k < 9 ? k/9 : 1`, faded where stamps bunch (`|dx| + |dy|` / 6);
   - Wyrm's own shadow stamp is skipped for AIR beads.

Atlas cells (448 px per bead cell = AIR's 64 px bitmaps at 7×):

| Cell | UV (x, y, w, h) | Content |
|---|---|---|
| nsk 0 | 2/7, 6/9, 1/7, 1/9 | `kmc_ts[9][0]` |
| nsk 1 | 3/7, 6/9, 1/7, 1/9 | `kmc_ts[29][0]` (frame 0 of 5) |
| shadow | 4/7, 6/9, (102/64)/7, (102/64)/9 | `ksmc_t` |

`SourcesOriginal/Main.m` re-copies `app/res` once per asset revision
(`56-air-skin`), so a phone that already has Build 55 assets gets the new
atlas. `user.dat` lives outside `app/res` and is kept.

## Regenerating and verifying the textures

```powershell
python Scripts/generate-air-skin-assets.py
```

writes both PNGs deterministically and prints their hashes (update
`AIR_ATLAS_SHA256` in the prepare script if they change). With the untouched
AIR client exported by FFDec (never committed):

```powershell
python Scripts/generate-air-skin-assets.py --verify <ffdec image dir> <gaim/Main.as>
```

Result on 2026-09-25: RGB identical to the baked sheets for both beads, the
shadow and the wheel. Edge alpha: mean 0.9/255 for beads and 0.5/255 for the
wheel (Flash draws circles as eight quadratic curves; a true circle 0.2 px
wider reproduces its coverage), `ksmc_t` within 1/255.

## Known limits

- Boost glow for a custom skin still uses the first bead's colour-group glow.
- Only render mode 0 (the default textured body) draws AIR textures.
- The texture assets are the official client's art, used for this personal
  client; confirm rights before any public store release.
