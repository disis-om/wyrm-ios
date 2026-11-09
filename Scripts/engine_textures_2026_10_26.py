"""Eight skin textures and eight food textures (OM, 2026-10-26).

Skin (ext.skin_tex, settings skin.texture 0..9): 0 Wyrm, 1 Rounded plain,
3 NTL textured, and five new ones drawn by bp.slang (uv.x = -kind): 5 Glossy,
6 Matte, 7 Neon, 8 Pearl, 9 Metal. Like NTL textured they stand upright with
the light at the top left (the same both ways, whichever way the body runs)
and keep the body's light and dark rhythm. 2 and 4 (Squared / Striped plain)
stay retired and draw Wyrm's beads.

Food (ext.food_tex, settings normal/assist.food_texture 0..7): 0 Wyrm,
1 Slither app, 2 Crisp, 3 Square, 4 Glossy, 5 Gem, and two new ones drawn by
fd.slang: 6 Candy (style 7) and 7 Pixel (style 8); fd.slang's style 6 is the
Slither app's shadow.

Every texture is a few shader instructions over one quad per bead or pellet,
with no switch at any distance, so nothing pops while zooming.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree. Each change is skipped when its marker is present.
"""
import sys
from pathlib import Path

PAIRS = [
    ("game/user_settings.c", "food_at + 4, 0, 7, 0",
     "    fixed |= ext_take_int(&ext->food_tex[0], written >= food_at + 4, 0, 5, 0);\n"
     "    fixed |= ext_take_int(&ext->food_tex[1], written >= food_at + 8, 0, 5, 0);\n",
     "    fixed |= ext_take_int(&ext->food_tex[0], written >= food_at + 4, 0, 7, 0);\n"
     "    fixed |= ext_take_int(&ext->food_tex[1], written >= food_at + 8, 0, 7, 0);\n"),
    ("game/user_settings.c", "tex_at + 4, 0, 9, 0",
     "    fixed |= ext_take_int(&ext->skin_tex, written >= tex_at + 4, 0, 4, 0);\n",
     "    fixed |= ext_take_int(&ext->skin_tex, written >= tex_at + 4, 0, 9, 0);\n"),
    ("platform/android_settings.c", '"normal.food_texture", "normal", "", "", SETTING_INT, 0, 7,',
     '    {"normal.food_texture", "normal", "", "", SETTING_INT, 0, 5, NULL,\n',
     '    {"normal.food_texture", "normal", "", "", SETTING_INT, 0, 7, NULL,\n'),
    ("platform/android_settings.c", '"assist.food_texture", "assist", "", "", SETTING_INT, 0, 7,',
     '    {"assist.food_texture", "assist", "", "", SETTING_INT, 0, 5, NULL,\n',
     '    {"assist.food_texture", "assist", "", "", SETTING_INT, 0, 7, NULL,\n'),
    ("platform/android_settings.c", '"skin.texture", "skin", "", "", SETTING_INT, 0, 9,',
     '    {"skin.texture", "skin", "", "", SETTING_INT, 0, 4, NULL,\n',
     '    {"skin.texture", "skin", "", "", SETTING_INT, 0, 9, NULL,\n'),
    ("game/redraw.c", "Rounded plain (1), NTL textured (3) and the five",
     "  if (tex != 1 && tex != 3) return;\n",
     "  /* Rounded plain (1), NTL textured (3) and the five of 2026-10-26 (5..9). */\n"
     "  if (tex != 1 && tex != 3 && (tex < 5 || tex > 9)) return;\n"),
    ("game/redraw.c", "Glossy, Matte, Neon, Pearl, Metal (OM, 2026-10-26)",
     "    } else if (tex == 3) {\n"
     "      /* Upright, as NTL draws its sheet: the light comes from the top left\n"
     "         whichever way the body runs. */\n"
     "      kind = 3;\n",
     "    } else if (tex >= 5) {\n"
     "      /* Glossy, Matte, Neon, Pearl, Metal (OM, 2026-10-26): upright like NTL\n"
     "         textured, with the body's light and dark rhythm. */\n"
     "      kind = tex;\n"
     "      in.circle.w = 0;\n"
     "      col.r *= shade;\n"
     "      col.g *= shade;\n"
     "      col.b *= shade;\n"
     "    } else if (tex == 3) {\n"
     "      /* Upright, as NTL draws its sheet: the light comes from the top left\n"
     "         whichever way the body runs. */\n"
     "      kind = 3;\n"),
    ("game/redraw.c", "Candy and Pixel (OM, 2026-10-26)",
     "    case 5:\n"
     "      /* Gem (OM, 2026-10-26; it replaced Small): a cut stone. */\n",
     "    case 6:\n"
     "    case 7:\n"
     "      /* Candy and Pixel (OM, 2026-10-26): fd.slang styles 7 and 8 (6 is the\n"
     "         Slither app's shadow). */\n"
     "      fd_renderer_push(fdr, &(fd_instance){{cx - d * 0.5f, cy - d * 0.5f, d},\n"
     "                                           (vec4s){c.r, c.g, c.b, fade}, 0.0f,\n"
     "                                           (tex + 1) * 16.0f});\n"
     "      return;\n"
     "    case 5:\n"
     "      /* Gem (OM, 2026-10-26; it replaced Small): a cut stone. */\n"),
]


def apply(root, label="engine textures 2026-10-26"):
    src = Path(root) / "app" / "src"
    for name, marker, old, new in PAIRS:
        path = src / name
        raw = path.read_bytes().decode("utf-8")
        crlf = "\r\n" in raw
        text = raw.replace("\r\n", "\n")
        if marker in text:
            continue
        if text.count(old) != 1:
            raise SystemExit(f"{label}: {name}: anchor x{text.count(old)}: {old[:60]!r}")
        text = text.replace(old, new)
        if crlf:
            text = text.replace("\n", "\r\n")
        path.write_bytes(text.encode("utf-8"))


if __name__ == "__main__":
    apply(Path(sys.argv[1]) if len(sys.argv) > 1 else Path("."))
