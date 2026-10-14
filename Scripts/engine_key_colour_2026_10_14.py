"""On-screen key colours (OM, 2026-10-14).

One source for both apps (the engine_rain_key_2026_10_14.py pattern): Wyrm
Android's tree gets these pairs once
(`python engine_key_colour_2026_10_14.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree.

Every on-screen key (Rain too) can take one of the nine colours the team
roster and chat offer (`layout.key_N_colour`, 0 = the theme's paper, as
before). The colour fills the key; its text turns dark or light so it stays
readable. Stored at the end of user_settings_ext (`key_colour[20]`, int32,
phones offset 128): an older file reads every key as 0 (theme).
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


pairs("app/src/game/user_settings.h",
      ("  float rain_opacity;\n} user_settings_ext;",
       "  float rain_opacity;\n"
       "  /* On-screen key colours (OM, 2026-10-14), by action: one of the team\n"
       "     roster's nine colours, 0 = the theme. Phones: offset 128. */\n"
       "  int32_t key_colour[20];\n"
       "} user_settings_ext;"))

pairs("app/src/game/user_settings.c",
      ("    fixed |= ext_take_float(&ext->rain_opacity, written >= rain_at + 16,\n"
       "                            0.05f, 1.0f, 0.90f);\n  }\n",
       "    fixed |= ext_take_float(&ext->rain_opacity, written >= rain_at + 16,\n"
       "                            0.05f, 1.0f, 0.90f);\n  }\n"
       "  {\n"
       "    /* Key colours (OM, 2026-10-14): missing or unknown = theme (0). */\n"
       "    size_t colour_at = offsetof(user_settings_ext, key_colour);\n"
       "    for (int i = 0; i < 20; ++i) {\n"
       "      if (written < colour_at + 4 * (size_t)(i + 1) ||\n"
       "          ext->key_colour[i] < 0 || ext->key_colour[i] > 8) {\n"
       "        if (written >= colour_at + 4 * (size_t)(i + 1)) fixed = 1;\n"
       "        ext->key_colour[i] = 0;\n"
       "      }\n"
       "    }\n"
       "  }\n"))

KEYS = (1, 2, 3, 4, 6, 7, 8, 9, 14, 15, 16)
entries = "".join(
    '    {"layout.key_%d_colour", "layout", "", "", SETTING_INT, 0, 8, NULL,\n'
    "     OWNER_SETTINGS, SETTINGS_ARRAY_FIELD(ext.key_colour, %d)},\n" % (k, k)
    for k in KEYS)
pairs("app/src/platform/android_settings.c",
      ('    {"layout.key_16_opacity", "layout", "", "", SETTING_FLOAT, 0.05f, 1.0f,\n'
       "     NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.rain_opacity)},\n",
       '    {"layout.key_16_opacity", "layout", "", "", SETTING_FLOAT, 0.05f, 1.0f,\n'
       "     NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.rain_opacity)},\n"
       "    /* On-screen key colours (OM, 2026-10-14), ext.key_colour by action. */\n"
       + entries))

pairs("app/src/mobile/mobile_hotkeys.c",
      ("static ImU32 color(float r, float g, float b, float a) {\n"
       "  return igColorConvertFloat4ToU32((ImVec4){r, g, b, a});\n}\n",
       "static ImU32 color(float r, float g, float b, float a) {\n"
       "  return igColorConvertFloat4ToU32((ImVec4){r, g, b, a});\n}\n"
       "\n"
       "/* A key's colour (OM, 2026-10-14): the team roster's nine, 0 = theme.\n"
       "   Returns false for the theme; else the RGB in r, g, b (0..1). */\n"
       "static bool key_colour(tenv* env, int action, float* r, float* g, float* b) {\n"
       "  static const uint32_t palette[] = {0x000000, 0xFFFFFF, 0x111111,\n"
       "                                     0xFFD54A, 0x4DD9FF, 0x5BE37D,\n"
       "                                     0xFF6FB5, 0xFF9A3C, 0xFF5A5A};\n"
       "  if (action < 0 || action >= 20) return false;\n"
       "  int index = env->usr->usrs.ext.key_colour[action];\n"
       "  if (index <= 0 || index > 8) return false;\n"
       "  uint32_t c = palette[index];\n"
       "  *r = ((c >> 16) & 255) / 255.0f;\n"
       "  *g = ((c >> 8) & 255) / 255.0f;\n"
       "  *b = (c & 255) / 255.0f;\n"
       "  return true;\n}\n"),
      ("    ImDrawList_AddRectFilled(\n"
       "        draw, min, max,\n"
       "        active || pressed\n"
       "            ? arena_theme_colour(ARENA_THEME_INK, alpha * 0.96f)\n"
       "            : arena_theme_colour(ARENA_THEME_CARD, alpha * 0.94f),\n"
       "        corner, 0);\n",
       "    float kr = 0, kg = 0, kb = 0;\n"
       "    bool coloured = key_colour(env, action, &kr, &kg, &kb);\n"
       "    ImDrawList_AddRectFilled(\n"
       "        draw, min, max,\n"
       "        coloured ? color(kr, kg, kb, alpha * (active || pressed ? 0.98f : 0.86f))\n"
       "        : active || pressed\n"
       "            ? arena_theme_colour(ARENA_THEME_INK, alpha * 0.96f)\n"
       "            : arena_theme_colour(ARENA_THEME_CARD, alpha * 0.94f),\n"
       "        corner, 0);\n"),
      ("    ImU32 primary = arena_theme_colour(ARENA_THEME_INK, 1.0f);\n",
       "    ImU32 primary = arena_theme_colour(ARENA_THEME_INK, 1.0f);\n"
       "    /* On a coloured key the type is dark on light colours, light on dark. */\n"
       "    if (coloured)\n"
       "      primary = 0.2126f * kr + 0.7152f * kg + 0.0722f * kb > 0.55f\n"
       "                    ? color(0.07f, 0.07f, 0.08f, 1.0f)\n"
       "                    : color(1.0f, 1.0f, 1.0f, 1.0f);\n"))


def apply(root, label="engine key colour 2026-10-14", skip_applied=False):
    root = Path(root)
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        crlf = "\r\n" in text
        for old, new in items:
            if crlf:
                old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
            if skip_applied and new in text:
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
