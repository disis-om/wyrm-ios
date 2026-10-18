"""Light boost glow + "Show boost on: Mine / Everyone" (OM, 2026-10-18).

The boost glow drew a translucent sprite 2-3x a bead's size (Simple) plus one
6x a bead (Normal) on every body point of every boosting snake, so a long
snake boosting filled the screen with blended quads and the frame rate fell.
Now the glow is fixed and light: about half the size, a softer alpha, and on
every third point; the Boost strength slider is gone (its stored value stays,
unread). A new per-mode choice draws only the player's own boost:
`ext.boost_own[2]` (normal, assist), appended to user_settings_ext; a file
without it reads false = everyone's, as before. Settings ids
`normal.boost_own` / `assist.boost_own` (no label: the Modes page shows them
as Mine / Everyone under Boost).

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

BOOST_START = "          if (mode->show_boost && mode->render_mode != 3) {\n"
BOOST_END = "          // draw eyes:\n"
LOOP_OLD = "if (gdata->data.pbu[(int)j] == 2) {"
LOOP_NEW = "if (gdata->data.pbu[(int)j] == 2 && ((int)j % WYRM_BOOST_STRIDE) == 0) {"

DEFINES = """
/* Boost glow (OM, 2026-10-18): light and fixed. The glow used to be a sprite
   2-3x a bead (Simple) plus one 6x a bead (Normal) on every body point, which
   alone could drop the frame rate while a long snake boosted. Now about half
   the size, a softer alpha and every third point; no strength slider. */
#define WYRM_BOOST_ALPHA 0.6f
#define WYRM_BOOST_SIMPLE 0.45f
#define WYRM_BOOST_WIDE 1.7f
#define WYRM_BOOST_STRIDE 3
"""

PAIRS = {
    "app/src/game/user_settings.h": [
        ("  bool keys_grey_fill_v1;\n} user_settings_ext;",
         "  bool keys_grey_fill_v1;\n"
         "  /* Boost glow on my snake only (OM, 2026-10-18), normal and assist;\n"
         "     false = every snake's, as before. Append only. */\n"
         "  bool boost_own[2];\n"
         "} user_settings_ext;"),
    ],
    "app/src/game/user_settings.c": [
        ("  /* A longer tail belongs to a newer build. Do not shrink it just to rewrite\n",
         "  {\n"
         "    /* Boost on my snake only (OM, 2026-10-18): missing = everyone's. */\n"
         "    size_t boost_at = offsetof(user_settings_ext, boost_own);\n"
         "    fixed |= ext_take_bool(&ext->boost_own[0], written >= boost_at + 1);\n"
         "    fixed |= ext_take_bool(&ext->boost_own[1], written >= boost_at + 2);\n"
         "  }\n"
         "  /* A longer tail belongs to a newer build. Do not shrink it just to rewrite\n"),
    ],
    "app/src/platform/android_settings.c": [
        ("""    {"boost_strength", "Boost strength", "", SETTING_FLOAT, 0.25f, 3.0f, NULL,
     MODE_FIELD(boost_strength)},
""", ""),
        ("""    {"assist.spine_mine", "assist", "", "", SETTING_BOOL, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(ext.spine_mine[1])},
""", """    {"assist.spine_mine", "assist", "", "", SETTING_BOOL, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(ext.spine_mine[1])},
    /* Boost glow on my snake only (OM, 2026-10-18). No label: the Modes page
       shows it under Boost as Mine / Everyone. */
    {"normal.boost_own", "normal", "", "", SETTING_BOOL, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(ext.boost_own[0])},
    {"assist.boost_own", "assist", "", "", SETTING_BOOL, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(ext.boost_own[1])},
"""),
    ],
}


def _redraw(text, label):
    if "WYRM_BOOST_STRIDE" in text:
        return text  # applied
    anchor = "#define WYRM_BUILT_BEADS_IN_ARENA 1\n"
    if text.count(anchor) != 1:
        raise SystemExit(f"{label}: redraw.c define anchor x{text.count(anchor)}")
    text = text.replace(anchor, anchor + DEFINES)
    a = text.index(BOOST_START)
    b = text.index(BOOST_END, a)
    part = text[a:b]
    if part.count(LOOP_OLD) != 8:
        raise SystemExit(f"{label}: expected 8 boost loops, found {part.count(LOOP_OLD)}")
    reps = [
        (LOOP_OLD, LOOP_NEW, 8),
        ("float strength = 1 + mode->boost_type * mode->boost_strength;",
         "float strength = (1 + mode->boost_type * WYRM_BOOST_SIMPLE) * WYRM_BOOST_ALPHA;", 2),
        ("float strength = 0.7f * mode->boost_strength;",
         "float strength = 0.7f * WYRM_BOOST_SIMPLE;", 2),
        ("(1 + mode->boost_type + mr) * gdata->data.gsc * lsz;",
         "(0.7f + 0.5f * mode->boost_type + 0.6f * mr) * gdata->data.gsc * lsz;", 2),
        ("float glsz = lsz * 3 * gdata->data.gsc;",
         "float glsz = lsz * WYRM_BOOST_WIDE * gdata->data.gsc;", 2),
        (BOOST_START,
         "          /* Show boost on (OM, 2026-10-18): only mine, or every snake's. */\n"
         "          if (mode->show_boost && mode->render_mode != 3 &&\n"
         "              (!usrs->ext.boost_own[mode == usrs->modes ? 0 : 1] ||\n"
         "               o->id == gdata->data.snake_id)) {\n", 1),
    ]
    for old, new, n in reps:
        if part.count(old) != n:
            raise SystemExit(f"{label}: '{old[:50]}' x{part.count(old)} (want {n})")
        part = part.replace(old, new)
    return text[:a] + part + text[b:]


def apply(root, label="boost 2026-10-18", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        text = path.read_text(encoding="utf-8")
        for old, new in pairs:
            if skip_applied and new and new in text:
                continue
            if skip_applied and not new and old not in text:
                continue
            if text.count(old) != 1:
                raise SystemExit(f"{label}: anchor x{text.count(old)} in {relative}: {old[:80]!r}")
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8", newline="")
    path = Path(root) / "app/src/game/redraw.c"
    path.write_text(_redraw(path.read_text(encoding="utf-8"), label), encoding="utf-8", newline="")


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
