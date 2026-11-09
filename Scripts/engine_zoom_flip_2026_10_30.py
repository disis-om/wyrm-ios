"""Zoom bar flip (OM, 2026-10-30).

The zoom bar could already lie horizontal or stand vertical; now + and - can
swap ends too, for either hand ("Flip"). `ext.zoom_flip` is appended to the
user.dat ext block (an older file reads it as off), listed as
`controls.zoom_flip` so the app's settings page, the layout editor's zoom
popup and the account sync carry it like every other engine setting.

Drawing and touch both mirror the bar along its own axis around its centre:
the knob, the filled run, the spring bar's - and + marks and the finger's
reading. Display and touch only.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

PAIRS = {
    "app/src/game/user_settings.h": [
        ("  bool skin_tex_mine;\n} user_settings_ext;",
         "  bool skin_tex_mine;\n  /* Zoom bar flipped (OM, 2026-10-30): + and - swap ends. Append only. */\n  bool zoom_flip;\n} user_settings_ext;"),
    ],
    "app/src/game/user_settings.c": [
        ("""    size_t mine_at = offsetof(user_settings_ext, skin_tex_mine);
    fixed |= ext_take_bool(&ext->skin_tex_mine, written >= mine_at + 1);
  }""", """    size_t mine_at = offsetof(user_settings_ext, skin_tex_mine);
    fixed |= ext_take_bool(&ext->skin_tex_mine, written >= mine_at + 1);
  }
  {
    /* Zoom bar flip (OM, 2026-10-30): missing = not flipped. */
    size_t flip_at = offsetof(user_settings_ext, zoom_flip);
    fixed |= ext_take_bool(&ext->zoom_flip, written >= flip_at + 1);
  }"""),
    ],
    "app/src/platform/android_settings.c": [
        ("""    {"controls.zoom_orientation", "controls.zoom", "Zoom bar", "", SETTING_ENUM,
     0, 1, "Horizontal|Vertical", OWNER_CONTROLS,
     CONTROLS_FIELD(zoom_orientation)},""", """    {"controls.zoom_orientation", "controls.zoom", "Zoom bar", "", SETTING_ENUM,
     0, 1, "Horizontal|Vertical", OWNER_CONTROLS,
     CONTROLS_FIELD(zoom_orientation)},
    /* + and - swap ends (OM, 2026-10-30). */
    {"controls.zoom_flip", "controls.zoom", "Flip zoom bar", "", SETTING_BOOL,
     0, 1, NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.zoom_flip)},"""),
    ],
    "app/src/mobile/mobile_controls.c": [
        ("""static void set_zoom_from_touch(tenv* env, float x, float y) {
  mobile_control_settings* cfg = &env->usr->usrs.mobile_controls;
  float cx, cy, length, thickness;
  zoom_geometry(env, &cx, &cy, &length, &thickness);
""", """static void set_zoom_from_touch(tenv* env, float x, float y) {
  mobile_control_settings* cfg = &env->usr->usrs.mobile_controls;
  float cx, cy, length, thickness;
  zoom_geometry(env, &cx, &cy, &length, &thickness);
  /* A flipped bar reads the finger mirrored around its centre (2026-10-30). */
  if (env->usr->usrs.ext.zoom_flip) {
    x = 2.0f * cx - x;
    y = 2.0f * cy - y;
  }
"""),
        ("""    if (cfg->zoom_orientation == MOBILE_ZOOM_HORIZONTAL)
      knob = (ImVec2){cx + zoom_spring_t * half_len, cy};
    else
      knob = (ImVec2){cx, cy - zoom_spring_t * half_len};
  }
""", """    if (cfg->zoom_orientation == MOBILE_ZOOM_HORIZONTAL)
      knob = (ImVec2){cx + zoom_spring_t * half_len, cy};
    else
      knob = (ImVec2){cx, cy - zoom_spring_t * half_len};
  }
  /* Flipped (OM, 2026-10-30): the knob, run and marks mirror along the bar. */
  const bool zoom_flip = env->usr->usrs.ext.zoom_flip;
  if (zoom_flip) {
    if (cfg->zoom_orientation == MOBILE_ZOOM_HORIZONTAL)
      knob.x = 2.0f * cx - knob.x;
    else
      knob.y = 2.0f * cy - knob.y;
  }
"""),
        ("""      minus = (ImVec2){cx, track_max.y - inset};
      plus = (ImVec2){cx, track_min.y + inset};
    }
""", """      minus = (ImVec2){cx, track_max.y - inset};
      plus = (ImVec2){cx, track_min.y + inset};
    }
    if (zoom_flip) {
      ImVec2 swap = minus;
      minus = plus;
      plus = swap;
    }
"""),
        ("""  } else if (cfg->zoom_orientation == MOBILE_ZOOM_HORIZONTAL)
    fill_max.x = knob.x;
  else
    fill_min.y = knob.y;
""", """  } else if (cfg->zoom_orientation == MOBILE_ZOOM_HORIZONTAL) {
    if (zoom_flip) fill_min.x = knob.x; else fill_max.x = knob.x;
  } else {
    if (zoom_flip) fill_max.y = knob.y; else fill_min.y = knob.y;
  }
"""),
    ],
}


def apply(root, label="zoom bar flip 2026-10-30", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        text = path.read_text(encoding="utf-8")
        for old, new in pairs:
            if skip_applied and new in text:
                continue
            if text.count(old) != 1:
                raise SystemExit(f"{label}: anchor x{text.count(old)} in {relative}: {old[:80]!r}")
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8", newline="\n" if "build-original-source" in str(root) else "")


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
