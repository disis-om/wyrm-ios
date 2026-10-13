"""Snakey Rain key (OM, 2026-10-14).

One source for both apps (the engine_key_size_2026_10_13.py pattern): Wyrm
Android's tree gets these pairs once
(`python engine_rain_key_2026_10_14.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree.

The arena's Rain button is an on-screen key like the others (action 16): it is
moved in the layout editor and its SIZE / OPACITY come from the long press
(`layout.key_16_*`). It shows only while Snakey Rain is on (rain_bridge), so
it has no stored visible flag. A tap only counts an open request; the app reads
the count from the Rain snapshot and opens its panel. Its place, size and
opacity are appended at the end of user_settings_ext (phones offset 112).
rain_bridge.c/.h themselves are copied whole (SharedEngine = Android tree).
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


pairs("app/src/constants.h",
      ("#define MOBILE_HOTKEY_EYES_BACK 15\n#define NUM_MOBILE_ACTIONS 16",
       "#define MOBILE_HOTKEY_EYES_BACK 15\n"
       "/* Snakey Rain (OM, 2026-10-14): the arena's Rain key opens the app's Rain\n"
       "   panel. Its layout and look live in user_settings_ext too. */\n"
       "#define MOBILE_HOTKEY_RAIN 16\n#define NUM_MOBILE_ACTIONS 17"))

pairs("app/src/game/user_settings.h",
      ("  int32_t wyrm_skin;\n} user_settings_ext;",
       "  int32_t wyrm_skin;\n"
       "  /* Snakey Rain key (OM, 2026-10-14), on-screen action 16: place, size\n"
       "     and opacity. Shown only while Rain is on, so no visible flag.\n"
       "     Phones: offset 112; Wyrm Desktop: 116. */\n"
       "  float rain_x;\n  float rain_y;\n  float rain_scale;\n  float rain_opacity;\n"
       "} user_settings_ext;"))

pairs("app/src/game/user_settings.c",
      ("  x->snake_shadow[1] = false;\n",
       "  x->snake_shadow[1] = false;\n"
       "  x->rain_x = 0.50f;\n  x->rain_y = 0.12f;\n  x->rain_scale = 1.0f;\n"
       "  x->rain_opacity = 0.90f;\n"),
      ("  if (action == MOBILE_HOTKEY_EYES_BACK) return &settings->ext.eyes_back_scale;\n",
       "  if (action == MOBILE_HOTKEY_EYES_BACK) return &settings->ext.eyes_back_scale;\n"
       "  if (action == MOBILE_HOTKEY_RAIN) return &settings->ext.rain_scale;\n"),
      ("  if (action == MOBILE_HOTKEY_EYES_BACK)\n    return &settings->ext.eyes_back_opacity;\n",
       "  if (action == MOBILE_HOTKEY_EYES_BACK)\n    return &settings->ext.eyes_back_opacity;\n"
       "  if (action == MOBILE_HOTKEY_RAIN) return &settings->ext.rain_opacity;\n"),
      ("      ext->wyrm_skin = 0;\n      fixed = 1;\n    }\n  }\n",
       "      ext->wyrm_skin = 0;\n      fixed = 1;\n    }\n  }\n"
       "  {\n"
       "    /* The Rain key (OM, 2026-10-14): a file without it gets the defaults. */\n"
       "    size_t rain_at = offsetof(user_settings_ext, rain_x);\n"
       "    fixed |= ext_take_float(&ext->rain_x, written >= rain_at + 4, 0.0f, 1.0f,\n"
       "                            0.50f);\n"
       "    fixed |= ext_take_float(&ext->rain_y, written >= rain_at + 8, 0.0f, 1.0f,\n"
       "                            0.12f);\n"
       "    fixed |= ext_take_float(&ext->rain_scale, written >= rain_at + 12, 0.65f,\n"
       "                            2.50f, settings->mobile_hotkeys.key_scale);\n"
       "    fixed |= ext_take_float(&ext->rain_opacity, written >= rain_at + 16,\n"
       "                            0.05f, 1.0f, 0.90f);\n"
       "  }\n"))

pairs("app/src/mobile/mobile_hotkeys.h",
      ("  float eyes_back_y_backup;\n} mobile_hotkeys_state;",
       "  float eyes_back_y_backup;\n  float rain_x_backup;\n  float rain_y_backup;\n"
       "} mobile_hotkeys_state;"))

pairs("app/src/mobile/mobile_hotkeys.c",
      ('#include "../user.h"\n',
       '#include "../user.h"\n#include "../platform/rain_bridge.h"\n'),
      ('    "Eyes back"};',
       '    "Eyes back",   "Rain"};'),
      ("         action == MOBILE_HOTKEY_EYES_BACK;\n}",
       "         action == MOBILE_HOTKEY_EYES_BACK ||\n"
       "         /* Snakey Rain (OM, 2026-10-14): opens the Rain panel. */\n"
       "         action == MOBILE_HOTKEY_RAIN;\n}"),
      ("  state->eyes_back_y_backup = env->usr->usrs.ext.eyes_back_y;\n",
       "  state->eyes_back_y_backup = env->usr->usrs.ext.eyes_back_y;\n"
       "  state->rain_x_backup = env->usr->usrs.ext.rain_x;\n"
       "  state->rain_y_backup = env->usr->usrs.ext.rain_y;\n"),
      ("    env->usr->usrs.ext.eyes_back_y = state->eyes_back_y_backup;\n",
       "    env->usr->usrs.ext.eyes_back_y = state->eyes_back_y_backup;\n"
       "    env->usr->usrs.ext.rain_x = state->rain_x_backup;\n"
       "    env->usr->usrs.ext.rain_y = state->rain_y_backup;\n"),
      ("  env->usr->usrs.ext.eyes_back_y = 0.33f;\n}",
       "  env->usr->usrs.ext.eyes_back_y = 0.33f;\n"
       "  env->usr->usrs.ext.rain_x = 0.50f;\n  env->usr->usrs.ext.rain_y = 0.12f;\n}"),
      ("    if (x) *x = settings->ext.eyes_back_x;\n    if (y) *y = settings->ext.eyes_back_y;\n  }\n}",
       "    if (x) *x = settings->ext.eyes_back_x;\n    if (y) *y = settings->ext.eyes_back_y;\n"
       "  } else if (action == MOBILE_HOTKEY_RAIN) {\n"
       "    /* Shown exactly while Snakey Rain is on. */\n"
       "    if (visible) *visible = wyrm_rain_enabled();\n"
       "    if (x) *x = settings->ext.rain_x;\n    if (y) *y = settings->ext.rain_y;\n  }\n}"),
      ("    settings->ext.eyes_back_x = x;\n    settings->ext.eyes_back_y = y;\n  }\n}",
       "    settings->ext.eyes_back_x = x;\n    settings->ext.eyes_back_y = y;\n"
       "  } else if (action == MOBILE_HOTKEY_RAIN) {\n"
       "    settings->ext.rain_x = x;\n    settings->ext.rain_y = y;\n  }\n}"))

pairs("app/src/game/input.c",
      ("  if (mobile_hotkeys_pressed(env, MOBILE_HOTKEY_EYES_BACK))\n    eyes_back_toggle(gdata, usrs);\n",
       "  if (mobile_hotkeys_pressed(env, MOBILE_HOTKEY_EYES_BACK))\n    eyes_back_toggle(gdata, usrs);\n"
       "  /* Snakey Rain (OM, 2026-10-14): the Rain key opens the app's Rain panel. */\n"
       "  if (mobile_hotkeys_pressed(env, MOBILE_HOTKEY_RAIN)) wyrm_rain_key_press();\n"))

pairs("app/src/platform/android_settings.c",
      ("     NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.eyes_back_opacity)},\n",
       "     NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.eyes_back_opacity)},\n"
       "    /* Snakey Rain key (OM, 2026-10-14), action 16, in the ext block too. */\n"
       '    {"layout.key_16_scale", "layout", "", "", SETTING_FLOAT, 0.65f, 2.50f,\n'
       "     NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.rain_scale)},\n"
       '    {"layout.key_16_opacity", "layout", "", "", SETTING_FLOAT, 0.05f, 1.0f,\n'
       "     NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.rain_opacity)},\n"),
      # Wyrm Desktop's key list only: the generated iOS tree has no such line.
      ("    if (action == MOBILE_HOTKEY_FULLSCREEN) continue;",
       "    if (action == MOBILE_HOTKEY_FULLSCREEN || action == MOBILE_HOTKEY_RAIN)\n      continue;",
       "optional"))


def apply(root, label="engine rain key 2026-10-14", skip_applied=False):
    root = Path(root)
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        crlf = "\r\n" in text
        for item in items:
            old, new = item[0], item[1]
            if crlf:
                old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
            if skip_applied and new in text:
                continue
            count = text.count(old)
            if count == 0 and len(item) > 2:
                continue
            if count != 1:
                raise SystemExit(f"{label}: anchor x{count} in {relative}: {old[:70]!r}")
            text = text.replace(old, new)
        if text != original:
            target.write_text(text, encoding="utf-8", newline="")
    return len(PAIRS)


if __name__ == "__main__":
    print(apply(sys.argv[1], skip_applied=True), "files written")
