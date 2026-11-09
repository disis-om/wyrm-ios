"""The slither Android (AIR) client's six bead styles (OM, 2026-10-26).

The AIR colour wheel has six styles (`nsks` 0..5). Wyrm had the first two;
this adds `sg_roundfluffy`, `sg_dragonscales`, `sg_teardrop` and `sg_egg`
(atlas cells from Scripts/generate-air-styles.py). Only this phone sees them:
the arena gets the nearest colour group as before, no packet changes.

A wheel bead names its style in the alpha byte: 0xFE nsk 0, 0xFD nsk 1, and now
0xFC nsk 2 (roundfluffy), 0xFB nsk 3 (dragonscales), 0xFA nsk 4 (teardrop),
0xF9 nsk 5 (egg). As AIR draws them (Main.as redraw, `ssd.t == 2`): the white
picture tinted by the bead's colour, lifted until mid + max channel reaches
`nsk_min2c` 128 (255 for nsk 0 and 1), turned with the body, the bead's centre
at the picture's pivot, then the `_shine` picture in white at `nsk_default_shine_a`
(0.8, 0.8, 0.7, 0.55). The pictures sit in 160-pixel squares of the client's
64-pixel bead, so their quad is 2.5 beads wide.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree. Skipped when its marker is present.
"""
import sys
from pathlib import Path

MARK = "AIR bead styles 2..5 (OM, 2026-10-26)"

KIND_OLD = '''static int apple_air_kind(uint32_t rgba) {
  uint32_t tag = rgba >> 24;
  return tag == 0xFEu ? 0 : tag == 0xFDu ? 1 : -1;
}

static vec4s apple_air_bead_uv(int kind) {
  return (vec4s){{(2 + kind) / 7.0f, 6 / 9.0f, 1 / 7.0f, 1 / 9.0f}};
}
'''
KIND_NEW = '''static int apple_air_kind(uint32_t rgba) {
  uint32_t tag = rgba >> 24;
  /* ''' + MARK + ''': 0xFC..0xF9 name nsk 2..5. */
  if (tag >= 0xF9u && tag <= 0xFEu) return (int)(0xFEu - tag);
  return -1;
}

/* The styles' 224 px half-cells (generate-air-styles.py), as (row, column)
   in 224 px units of the 3136 x 4032 atlas: base, then shine. */
static const unsigned char apple_air_style_cells[4][2][2] = {
    {{12, 3}, {15, 0}}, {{13, 3}, {15, 1}}, {{14, 3}, {15, 2}}, {{15, 3}, {16, 8}}};
static const float apple_air_style_shine_a[4] = {0.8f, 0.8f, 0.7f, 0.55f};
#define APPLE_AIR_STYLE_SPAN 2.5f

static vec4s apple_air_style_uv(int kind, int shine) {
  const unsigned char* cell = apple_air_style_cells[kind - 2][shine ? 1 : 0];
  return (vec4s){{cell[1] / 14.0f, cell[0] / 18.0f, 1 / 14.0f, 1 / 18.0f}};
}

static vec4s apple_air_bead_uv(int kind) {
  if (kind >= 2) return apple_air_style_uv(kind, 0);
  return (vec4s){{(2 + kind) / 7.0f, 6 / 9.0f, 1 / 7.0f, 1 / 9.0f}};
}

/* After a style bead was pushed (its quad one bead wide): the picture is 2.5
   beads wide round the same centre, and its shine goes over it. */
static void apple_air_style_finish(bp_renderer* r, int kind, float alpha) {
  if (kind < 2 || kind > 5 || r->num_instances <= 0) return;
  bp_instance* last = r->instances + r->num_instances - 1;
  float grow = last->circle.z * (APPLE_AIR_STYLE_SPAN - 1) * 0.5f;
  last->circle.x -= grow;
  last->circle.y -= grow;
  last->circle.z *= APPLE_AIR_STYLE_SPAN;
  /* Light at a distance (OM, 2026-10-26): under 8 px the shine is not seen,
     so it is not drawn; nothing else changes, so nothing flickers. */
  if (last->circle.z < 8.0f) return;
  bp_instance shine = *last;
  shine.uv_rect = apple_air_style_uv(kind, 1);
  shine.color = (vec4s){{1, 1, 1, alpha * apple_air_style_shine_a[kind - 2]}};
  bp_renderer_push(r, &shine);
}
'''

TINT_OLD = '''  float mid = c[0] + c[1] + c[2] - lo - hi;
  if (mid + hi < 255) {
    float lift = 1 + (255 - (mid + hi)) / 2;'''
TINT_NEW = '''  float mid = c[0] + c[1] + c[2] - lo - hi;
  /* nsk_min2c: 255 for nsk 0 and 1, 128 for the drawn styles. */
  float min2c = apple_air_kind(rgba) >= 2 ? 128.0f : 255.0f;
  if (mid + hi < min2c) {
    float lift = 1 + (min2c - (mid + hi)) / 2;'''

PUSH_OLD = '''                          wyrm_bead_kind(built) >= 0
                              ? wyrm_bead_color(built, wyrm_bead_kind(built), a)
                          : apple_air_kind(built) >= 0
                              ? apple_air_tint(built, a)
                          : built ? built_skin_color(built, a)
                                  : (vec4s){{1, 1, 1, a}}});
'''
PUSH_NEW = PUSH_OLD + '''                  if (!studio_own(env, o) && apple_air_kind(built) >= 2)
                    apple_air_style_finish(usr->r->bpr, apple_air_kind(built), a);
'''


def apply(root, label="engine AIR styles 2026-10-26"):
    path = Path(root) / "app" / "src" / "game" / "redraw.c"
    raw = path.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")
    if MARK in text:
        return
    for old, new in ((KIND_OLD, KIND_NEW), (TINT_OLD, TINT_NEW), (PUSH_OLD, PUSH_NEW)):
        if text.count(old) != 1:
            raise SystemExit(f"{label}: anchor x{text.count(old)}: {old[:60]!r}")
        text = text.replace(old, new)
    if crlf:
        text = text.replace("\n", "\r\n")
    path.write_bytes(text.encode("utf-8"))


if __name__ == "__main__":
    apply(Path(sys.argv[1]) if len(sys.argv) > 1 else Path("."))
