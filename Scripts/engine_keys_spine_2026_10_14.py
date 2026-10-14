"""Key look round 2 + spine owner (OM, 2026-10-14).

One source for both apps (the engine_key_colour_2026_10_14.py pattern); runs
after it. Wyrm Android's tree gets these pairs once
(`python engine_keys_spine_2026_10_14.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree.

1. On-screen key colours are two now: `layout.key_N_colour` paints the label
   and the border, `layout.key_N_fill` the inside (team palette, 0 = theme).
2. A key that is on (or held) only turns its border green: no ink fill, no
   ring, no fade.
3. Key size reaches 5x (was 2.5x): double the old maximum.
4. Spine for everyone or only my snake: `normal.spine_mine` /
   `assist.spine_mine` (false = everyone, as before).
New fields go at the end of user_settings_ext: `key_fill[20]` (int32, phones
@208) and `spine_mine[2]` (@288). An older file reads 0 / everyone.
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


pairs("app/src/game/user_settings.h",
      ("  int32_t key_colour[20];\n} user_settings_ext;",
       "  int32_t key_colour[20];\n"
       "  /* A key's fill colour (OM, 2026-10-14); key_colour is its label and\n"
       "     border. Phones: offset 208. */\n"
       "  int32_t key_fill[20];\n"
       "  /* Spine on my snake only (OM, 2026-10-14), normal and assist; false =\n"
       "     every snake, as before. Phones: offset 288. */\n"
       "  bool spine_mine[2];\n"
       "} user_settings_ext;"))

pairs("app/src/game/user_settings.c",
      ("        ext->key_colour[i] = 0;\n      }\n    }\n  }\n",
       "        ext->key_colour[i] = 0;\n      }\n    }\n  }\n"
       "  {\n"
       "    /* Key fills (OM, 2026-10-14): missing or unknown = theme (0). */\n"
       "    size_t fill_at = offsetof(user_settings_ext, key_fill);\n"
       "    for (int i = 0; i < 20; ++i) {\n"
       "      if (written < fill_at + 4 * (size_t)(i + 1) ||\n"
       "          ext->key_fill[i] < 0 || ext->key_fill[i] > 8) {\n"
       "        if (written >= fill_at + 4 * (size_t)(i + 1)) fixed = 1;\n"
       "        ext->key_fill[i] = 0;\n"
       "      }\n"
       "    }\n"
       "    size_t mine_at = offsetof(user_settings_ext, spine_mine);\n"
       "    fixed |= ext_take_bool(&ext->spine_mine[0], written >= mine_at + 1);\n"
       "    fixed |= ext_take_bool(&ext->spine_mine[1], written >= mine_at + 2);\n"
       "  }\n"),
      ("                          0.65f, 2.50f, settings->mobile_hotkeys.key_scale);",
       "                          0.65f, 5.00f, settings->mobile_hotkeys.key_scale);"),
      ("                            2.50f, settings->mobile_hotkeys.key_scale);",
       "                            5.00f, settings->mobile_hotkeys.key_scale);"),
      ("      usr_settings->mobile_hotkeys.key_scale > 2.50f) {",
       "      usr_settings->mobile_hotkeys.key_scale > 5.00f) {"),
      ("    REPAIR_APPEARANCE(*key_scale, 0.65f, 2.50f,",
       "    REPAIR_APPEARANCE(*key_scale, 0.65f, 5.00f,"))

KEYS = (1, 2, 3, 4, 6, 7, 8, 9, 14, 15, 16)
fills = "".join(
    '    {"layout.key_%d_fill", "layout", "", "", SETTING_INT, 0, 8, NULL,\n'
    "     OWNER_SETTINGS, SETTINGS_ARRAY_FIELD(ext.key_fill, %d)},\n" % (k, k)
    for k in KEYS)
pairs("app/src/platform/android_settings.c",
      ('{"keys.key_scale", "keys", "Button size", "", SETTING_FLOAT, 0.65f, 2.50f,',
       '{"keys.key_scale", "keys", "Button size", "", SETTING_FLOAT, 0.65f, 5.00f,'),
      ('     0.65f, 2.50f, NULL, OWNER_SETTINGS,                                      \\',
       '     0.65f, 5.00f, NULL, OWNER_SETTINGS,                                      \\'),
      ('{"layout.key_15_scale", "layout", "", "", SETTING_FLOAT, 0.65f, 2.50f,',
       '{"layout.key_15_scale", "layout", "", "", SETTING_FLOAT, 0.65f, 5.00f,'),
      ('{"layout.key_16_scale", "layout", "", "", SETTING_FLOAT, 0.65f, 2.50f,',
       '{"layout.key_16_scale", "layout", "", "", SETTING_FLOAT, 0.65f, 5.00f,'),
      ("    /* On-screen key colours (OM, 2026-10-14), ext.key_colour by action. */\n",
       "    /* On-screen key fills (OM, 2026-10-14), ext.key_fill by action. */\n"
       + fills +
       "    /* Spine on my snake only (OM, 2026-10-14). No label: the Modes page\n"
       "       shows it under Spine as Mine / Everyone. */\n"
       '    {"normal.spine_mine", "normal", "", "", SETTING_BOOL, 0, 1, NULL,\n'
       "     OWNER_SETTINGS, SETTINGS_FIELD(ext.spine_mine[0])},\n"
       '    {"assist.spine_mine", "assist", "", "", SETTING_BOOL, 0, 1, NULL,\n'
       "     OWNER_SETTINGS, SETTINGS_FIELD(ext.spine_mine[1])},\n"
       "    /* On-screen key colours (OM, 2026-10-14), ext.key_colour by action. */\n"))

pairs("app/src/mobile/mobile_hotkeys.c",
      ("                clampf_local(key_scale ? *key_scale : 1.0f, 0.65f, 2.50f);",
       "                clampf_local(key_scale ? *key_scale : 1.0f, 0.65f, 5.00f);"),
      ("static bool key_colour(tenv* env, int action, float* r, float* g, float* b) {\n",
       "static bool key_palette(int index, float* r, float* g, float* b);\n"
       "static bool key_colour(tenv* env, int action, float* r, float* g, float* b) {\n"
       "  if (action < 0 || action >= 20) return false;\n"
       "  return key_palette(env->usr->usrs.ext.key_colour[action], r, g, b);\n"
       "}\n"
       "/* A key's fill (OM, 2026-10-14), the same nine colours. */\n"
       "static bool key_fill(tenv* env, int action, float* r, float* g, float* b) {\n"
       "  if (action < 0 || action >= 20) return false;\n"
       "  return key_palette(env->usr->usrs.ext.key_fill[action], r, g, b);\n"
       "}\n"
       "static bool key_palette(int index, float* r, float* g, float* b) {\n"),
      ("  if (action < 0 || action >= 20) return false;\n"
       "  int index = env->usr->usrs.ext.key_colour[action];\n"
       "  if (index <= 0 || index > 8) return false;\n",
       "  if (index <= 0 || index > 8) return false;\n"),
      ("    if (active || pressed)\n"
       "      ImDrawList_AddRect(draw, (ImVec2){min.x - 3.5f, min.y - 3.5f},\n"
       "                         (ImVec2){max.x + 3.5f, max.y + 3.5f},\n"
       "                         color(0.247f, 0.933f, 0.588f, alpha * 0.55f),\n"
       "                         corner + 3.5f, 0, 3.0f);\n",
       "    /* A key that is on only turns its border green (OM, 2026-10-14). */\n"),
      ("    float kr = 0, kg = 0, kb = 0;\n"
       "    bool coloured = key_colour(env, action, &kr, &kg, &kb);\n"
       "    ImDrawList_AddRectFilled(\n"
       "        draw, min, max,\n"
       "        coloured ? color(kr, kg, kb, alpha * (active || pressed ? 0.98f : 0.86f))\n"
       "        : active || pressed\n"
       "            ? arena_theme_colour(ARENA_THEME_INK, alpha * 0.96f)\n"
       "            : arena_theme_colour(ARENA_THEME_CARD, alpha * 0.94f),\n"
       "        corner, 0);\n"
       "    ImDrawList_AddRect(draw, min, max,\n"
       "                       arena_theme_colour(ARENA_THEME_INK,\n"
       "                                          active || pressed ? 0.82f : 0.48f),\n"
       "                       corner, 0, 1.5f);\n",
       "    /* Two colours (OM, 2026-10-14): the fill, and the label + border. */\n"
       "    float kr = 0, kg = 0, kb = 0, fr = 0, fg = 0, fb = 0;\n"
       "    bool coloured = key_colour(env, action, &kr, &kg, &kb);\n"
       "    bool filled = key_fill(env, action, &fr, &fg, &fb);\n"
       "    ImDrawList_AddRectFilled(\n"
       "        draw, min, max,\n"
       "        filled ? color(fr, fg, fb, alpha * 0.94f)\n"
       "               : arena_theme_colour(ARENA_THEME_CARD, alpha * 0.94f),\n"
       "        corner, 0);\n"
       "    bool on = active || pressed;\n"
       "    ImDrawList_AddRect(draw, min, max,\n"
       "                       on ? color(0.247f, 0.933f, 0.588f, 1.0f)\n"
       "                       : coloured ? color(kr, kg, kb, 0.9f)\n"
       "                       : arena_theme_colour(ARENA_THEME_INK, 0.48f),\n"
       "                       corner, 0, on ? 3.0f : 1.5f);\n"),
      ("    /* On a coloured key the type is dark on light colours, light on dark. */\n"
       "    if (coloured)\n"
       "      primary = 0.2126f * kr + 0.7152f * kg + 0.0722f * kb > 0.55f\n"
       "                    ? color(0.07f, 0.07f, 0.08f, 1.0f)\n"
       "                    : color(1.0f, 1.0f, 1.0f, 1.0f);\n",
       "    /* The label takes the key's colour (OM, 2026-10-14). */\n"
       "    if (coloured) primary = color(kr, kg, kb, 1.0f);\n"))

pairs("app/src/game/redraw.c",
      ("            int spine_on = usrs->ext.spine[assist_on] ? 1 : 0;\n",
       "            /* Mine only, or everyone (OM, 2026-10-14). */\n"
       "            int spine_on = usrs->ext.spine[assist_on] &&\n"
       "                                   (!usrs->ext.spine_mine[assist_on] ||\n"
       "                                    o->id == gdata->data.snake_id)\n"
       "                               ? 1\n"
       "                               : 0;\n"))


def apply(root, label="engine keys + spine 2026-10-14", skip_applied=False):
    root = Path(root)
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        crlf = "\r\n" in text
        for old, new in items:
            if crlf:
                old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
            if skip_applied and new in text and old not in text:
                continue
            count = text.count(old)
            if count != 1:
                raise SystemExit(f"{label}: anchor x{count} in {relative}: {old[:70]!r}")
            text = text.replace(old, new)
        if text != original:
            target.write_text(text, encoding="utf-8", newline="")
    return len(PAIRS)


if __name__ == "__main__":
    print(apply(sys.argv[1], skip_applied=True), "files written")
