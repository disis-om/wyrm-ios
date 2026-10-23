"""Boost glow back, lighter to draw, strength slider back (OM, 2026-10-23).

The 2026-10-18 light glow (engine_boost_2026_10_18.py) made the Simple glow
0.7-1.3x a bead's radius. The glow sprites of the first pass are drawn under
the body, so a glow no wider than the bead was hidden by the snake itself:
players saw no boost glow at all (8.3.0 / 2.3.0 reports). Its strength was
also fixed, with the slider removed.

Now the glow has the reference client's own size and strength again
(Simple 1 + mr beads, Normal + a wide 3x pass, strength 1 + type x slider),
and the Boost strength slider (0.25-3, the stored per-mode value) is back.

It stays light the way the bead mipmaps did it: the same picture for less
work. The glow is additive (bst pipeline: SRC_ALPHA, ONE), so a run of
overlapping sprites can be drawn as every k-th sprite with k times the alpha
and add up to the same light. k is picked per snake from the real gap between
its body points, so sprites stay at most WYRM_BOOST_SPACING of a glow radius
apart (no dotted trail), and capped so one sprite's blended alpha stays
under 1 (the blend clamps above it; bst.slang's falloff peaks at 0.4). Per-bead colours step through every phase of the
stride (wyrm_boost_bead), so a two-colour skin keeps both colours.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py after
engine_boost_2026_10_18, to the generated iOS tree.
"""
import sys
from pathlib import Path

BOOST_START = "          /* Show boost on (OM, 2026-10-18): only mine, or every snake's. */\n"
BOOST_END = "          // draw eyes:\n"

OLD_DEFINES = """
/* Boost glow (OM, 2026-10-18): light and fixed. The glow used to be a sprite
   2-3x a bead (Simple) plus one 6x a bead (Normal) on every body point, which
   alone could drop the frame rate while a long snake boosted. Now about half
   the size, a softer alpha and every third point; no strength slider. */
#define WYRM_BOOST_ALPHA 0.6f
#define WYRM_BOOST_SIMPLE 0.45f
#define WYRM_BOOST_WIDE 1.7f
#define WYRM_BOOST_STRIDE 3
"""

NEW_DEFINES = """
/* Boost glow (OM, 2026-10-23): the reference size and strength (the 10-18
   half-size glow hid under the body), drawn lighter. The glow is additive, so
   every k-th sprite at k times the alpha adds up to the same light; k keeps
   sprites at most WYRM_BOOST_SPACING of a glow radius apart and one sprite's
   blended alpha under 1 (bst.slang's falloff peaks at 0.4 of the instance
   alpha, so the instance alpha may reach WYRM_BOOST_PEAK). */
#define WYRM_BOOST_SPACING 0.45f
#define WYRM_BOOST_MAX_STRIDE 4
#define WYRM_BOOST_PEAK 2.5f

static int wyrm_boost_stride(game_data* gdata, int bp, float glsz,
                             float peak) {
  if (bp < 2 || !(glsz > 0)) return 1;
  float dx = gdata->data.pbx[1] - gdata->data.pbx[0];
  float dy = gdata->data.pby[1] - gdata->data.pby[0];
  float step = sqrtf(dx * dx + dy * dy) * gdata->data.gsc;
  if (!(step > 0.01f)) return 1;
  int k = (int)(glsz * WYRM_BOOST_SPACING / step);
  int cap = (int)(WYRM_BOOST_PEAK / fmaxf(peak, 0.01f));
  if (k > cap) k = cap;
  if (k > WYRM_BOOST_MAX_STRIDE) k = WYRM_BOOST_MAX_STRIDE;
  return k < 1 ? 1 : k;
}

/* The bead a strided sprite takes its colour from: each run of k sprites
   steps through every phase, so a skin whose colours repeat every k beads
   still shows all of them. */
static int wyrm_boost_bead(int j, int k) {
  return k > 1 ? j + (j / k) % k : j;
}
"""

IND = "                "
SIMPLE_OLD = "float strength = (1 + mode->boost_type * WYRM_BOOST_SIMPLE) * WYRM_BOOST_ALPHA;\n"
SIMPLE_NEW = ("float strength = 1 + mode->boost_type * mode->boost_strength;\n"
              + IND + "int bstk = wyrm_boost_stride(gdata, bp, glsz, strength * .38f);\n"
              + IND + "strength *= bstk;\n")
WIDE_OLD = "float strength = 0.7f * WYRM_BOOST_SIMPLE;\n"
WIDE_NEW = ("float strength = 0.7f * mode->boost_strength;\n"
            + IND + "int bstk = wyrm_boost_stride(gdata, bp, glsz, strength * .37f);\n"
            + IND + "strength *= bstk;\n")

REPS = [
    ("((int)j % WYRM_BOOST_STRIDE) == 0", "((int)j % bstk) == 0", 8),
    (SIMPLE_OLD, SIMPLE_NEW, 2),
    (WIDE_OLD, WIDE_NEW, 2),
    ("(0.7f + 0.5f * mode->boost_type + 0.6f * mr) * gdata->data.gsc * lsz;",
     "(1 + mode->boost_type + mr) * gdata->data.gsc * lsz;", 2),
    ("float glsz = lsz * WYRM_BOOST_WIDE * gdata->data.gsc;",
     "float glsz = lsz * 3 * gdata->data.gsc;", 2),
    ("o->cusk_data[(int)j % o->cusk_len]",
     "o->cusk_data[wyrm_boost_bead((int)j, bstk) % o->cusk_len]", 2),
    ("studio_glow_for(env, o, (int)j, &studio_glow,",
     "studio_glow_for(env, o, wyrm_boost_bead((int)j, bstk), &studio_glow,", 2),
    ("[1 + ((int)j % default_skin_len)]",
     "[1 + (wyrm_boost_bead((int)j, bstk) % default_skin_len)]", 2),
]

SETTINGS_OLD = """    {"boost_type", "Boost style", "", SETTING_ENUM, 0, 1, "Normal|Simple",
     MODE_FIELD(boost_type)},
"""
SETTINGS_NEW = SETTINGS_OLD + """    /* Back (OM, 2026-10-23): how bright the boost glow is. */
    {"boost_strength", "Boost strength", "", SETTING_FLOAT, 0.25f, 3.0f, NULL,
     MODE_FIELD(boost_strength)},
"""


def _redraw(text, label):
    if "WYRM_BOOST_SPACING" in text:
        return text  # applied
    if text.count(OLD_DEFINES) != 1:
        raise SystemExit(f"{label}: 10-18 boost defines x{text.count(OLD_DEFINES)}")
    text = text.replace(OLD_DEFINES, NEW_DEFINES)
    a = text.index(BOOST_START)
    b = text.index(BOOST_END, a)
    part = text[a:b]
    for old, new, n in REPS:
        if part.count(old) != n:
            raise SystemExit(f"{label}: '{old[:60]}' x{part.count(old)} (want {n})")
        part = part.replace(old, new)
    if "WYRM_BOOST_" in part.replace("WYRM_BOOST_SPACING", ""):
        raise SystemExit(f"{label}: a 10-18 boost constant is left in the boost code")
    return text[:a] + part + text[b:]


def _edit(path, change):
    """Applies change to the text with LF endings; the file keeps its own."""
    raw = path.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = change(raw.replace("\r\n", "\n"))
    if crlf:
        text = text.replace("\n", "\r\n")
    path.write_bytes(text.encode("utf-8"))


def _settings(text, label):
    if SETTINGS_NEW in text:
        return text
    if text.count(SETTINGS_OLD) != 1:
        raise SystemExit(f"{label}: settings anchor x{text.count(SETTINGS_OLD)}")
    return text.replace(SETTINGS_OLD, SETTINGS_NEW)


def apply(root, label="boost 2026-10-23"):
    _edit(Path(root) / "app/src/game/redraw.c", lambda t: _redraw(t, label))
    _edit(Path(root) / "app/src/platform/android_settings.c", lambda t: _settings(t, label))


if __name__ == "__main__":
    apply(sys.argv[1])
