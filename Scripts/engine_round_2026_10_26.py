"""OM's round of 2026-10-26, engine side (on top of engine_round_2026_10_25).

1. Skin textures: only Wyrm (0), Rounded plain (1) and NTL textured (3) stay;
   a saved 2 or 4 (Squared / Striped plain, gone) draws Wyrm's beads. Rounded
   plain and NTL textured draw no shadow under the snake (NTL draws none with
   them), and NTL textured beads stand upright as NTL draws its sheet (they were
   turned with the body, which showed their dark side).
2. Food: one texture whatever the distance or the crowd (the far / crowded
   dot swapped looks while zooming and as food appeared); only the Slither app
   shadow is left out when a pellet is tiny. Food is drawn solid: the food
   pipeline blends normally instead of adding light (light floors washed it
   out), and every texture is opaque (fd.slang). Small is gone; 5 is now Gem.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py after
engine_round_2026_10_25, to the generated iOS tree. Each change is skipped when
its marker is already present. fd.slang is a file (Android's res/shaders and
SharedEngine's carry the same bytes).
"""
import sys
from pathlib import Path

FOOD_OLD = '''  if (crowded || d * 0.9f < WYRM_FOOD_LIGHT_PX) {
    float z = d * 0.35f;
    fd_renderer_push(fdr, &(fd_instance){{cx - z * 0.5f, cy - z * 0.5f, z},
                                         (vec4s){c.r, c.g, c.b, fade}, 0.0f,
                                         5 * 16.0f});
    return;
  }
  switch (tex) {
    case 1: {
      /* The AIR client: a dark disc a little larger and lower, blurred,
         under an additive orb (Main.as foimg_t / per_color_imgs img_t). */
      float z = d * 0.58f;
      fd_renderer_push_u(fdr,'''
FOOD_NEW = '''  /* One look at every distance (OM, 2026-10-26): no far or crowded swap,
     which showed a different pellet while zooming and as food appeared. */
  (void)crowded;
  switch (tex) {
    case 1: {
      /* The AIR client: a dark disc a little larger and lower, blurred,
         under the orb (Main.as foimg_t / per_color_imgs img_t). Too small to
         see, the shadow is left out. */
      float z = d * 0.58f;
      if (d * 0.9f >= WYRM_FOOD_LIGHT_PX)
        fd_renderer_push_u(fdr,'''

GEM_OLD = '''    case 5: {
      float z = d * 0.6f;
      fd_renderer_push(fdr, &(fd_instance){{cx - z * 0.5f, cy - z * 0.5f, z},
                                           (vec4s){c.r, c.g, c.b, fade}, flicker,
                                           shape});
      return;
    }
'''
GEM_NEW = '''    case 5:
      /* Gem (OM, 2026-10-26; it replaced Small): a cut stone. */
      fd_renderer_push(fdr, &(fd_instance){{cx - d * 0.5f, cy - d * 0.5f, d},
                                           (vec4s){c.r, c.g, c.b, fade}, 0.0f,
                                           5 * 16.0f});
      return;
'''

TEX_OLD = '''  int tex = usrs->ext.skin_tex;
  if (tex < 1 || tex > 4) return;
'''
TEX_NEW = '''  int tex = usrs->ext.skin_tex;
  /* Only Rounded plain (1) and NTL textured (3) are offered (OM, 2026-10-26);
     a saved Squared or Striped plain draws Wyrm's beads. */
  if (tex != 1 && tex != 3) return;
'''
KEEP_OLD = '''    bp_instance in = r->instances[i];
    if (!skin_texture_bead(&in)) {
      r->instances[kept++] = in;
      continue;
    }
'''
KEEP_NEW = '''    bp_instance in = r->instances[i];
    if (!skin_texture_bead(&in)) {
      /* No shadow under a plain or NTL snake: NTL draws none with them. Studio
         beads (their own atlas) stay. */
      if (in.uv_rect.x >= 3.0f) r->instances[kept++] = in;
      continue;
    }
'''
NTL_OLD = '''    } else if (tex == 3) {
      kind = 3;
'''
NTL_NEW = '''    } else if (tex == 3) {
      /* Upright, as NTL draws its sheet: the light comes from the top left
         whichever way the body runs. */
      kind = 3;
      in.circle.w = 0;
'''

BLEND_MARK = "Food is solid (OM, 2026-10-26)"


def _blend(text, label):
    if BLEND_MARK in text:
        return text
    old = "                          .dstColorBlendFactor = VK_BLEND_FACTOR_ONE,\n"
    if text.count(old) < 1:
        raise SystemExit(f"{label}: fd blend anchor missing")
    new = ("                          /* " + BLEND_MARK + ": normal blending, not\n"
           "                             added light, so light floors keep it. */\n"
           "                          .dstColorBlendFactor =\n"
           "                              VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,\n")
    return text.replace(old, new, 1)  # the first block is pipelines[0], the food


PAIRS = [
    ("game/redraw.c", "no far or crowded swap", FOOD_OLD, FOOD_NEW),
    ("game/redraw.c", "Gem (OM, 2026-10-26", GEM_OLD, GEM_NEW),
    ("game/redraw.c", "Only Rounded plain (1) and NTL textured (3)", TEX_OLD, TEX_NEW),
    ("game/redraw.c", "No shadow under a plain or NTL snake", KEEP_OLD, KEEP_NEW),
    ("game/redraw.c", "Upright, as NTL draws its sheet", NTL_OLD, NTL_NEW),
]


def _edit(path, change):
    raw = path.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")
    new = change(text)
    if new != text:
        if crlf:
            new = new.replace("\n", "\r\n")
        path.write_bytes(new.encode("utf-8"))


def apply(root, label="engine round 2026-10-26"):
    src = Path(root) / "app" / "src"
    for name, marker, old, new in PAIRS:
        def change(text, old=old, new=new, marker=marker, name=name):
            if marker in text:
                return text
            if text.count(old) != 1:
                raise SystemExit(f"{label}: {name}: anchor x{text.count(old)}: {old[:60]!r}")
            return text.replace(old, new)
        _edit(src / name, change)
    _edit(src / "rendering" / "fd_renderer.c", lambda t: _blend(t, label))


if __name__ == "__main__":
    apply(Path(sys.argv[1]) if len(sys.argv) > 1 else Path("."))
