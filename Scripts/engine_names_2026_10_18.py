"""Snake names readable on every floor (OM, 2026-10-18).

Names were the snake's colour lifted 60 % toward white with no outline on the
phones, so on the light floors (Paper, Marble, Sage, Graygrid...) they all but
vanished. Now the floor's mean colour (the HUD's own table, WYRM_FLOOR_MEAN)
picks the ink once a frame: under luma 0.40 (and on None/Black or a hidden
floor) a light name over a soft dark shadow, from 0.40 a dark name over a soft
light shadow, both still in the snake's own hue. One extra glyph run per name.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree. The phones' branch only; the desktop keeps its outline.
"""
import sys
from pathlib import Path

HELPER = """
/* Snake names on any floor (OM, 2026-10-18): the floor's mean luma, once a
   frame; 0 where no floor shows (None, Black, a mode that hides it). */
float wyrm_floor_luma_now(tenv* env) {
  vec3s mean;
  return wyrm_floor_mean(env, &mean) ? wyrm_luma(mean) : 0.0f;
}

/* A name's ink and its shadow for a floor of `floor_luma`: light over a dark
   shadow on dark and mid floors, dark over a light shadow from 0.40, both in
   the snake's own hue. */
void wyrm_name_inks(float floor_luma, vec3s c, float alpha, unsigned int* text,
                    unsigned int* shadow) {
  float l = wyrm_luma(c);
  if (floor_luma < 0.40f) {
    const float target = 0.74f;
    if (l < target) {
      float t = (target - l) / (1.0f - l + 0.0001f);
      c.x += (1.0f - c.x) * t;
      c.y += (1.0f - c.y) * t;
      c.z += (1.0f - c.z) * t;
    }
    *shadow = igColorConvertFloat4ToU32(
        (ImVec4){WYRM_HALO.x, WYRM_HALO.y, WYRM_HALO.z, 0.85f * alpha});
  } else {
    const float target = 0.20f;
    const float halo = 0.2126f * WYRM_HALO.x + 0.7152f * WYRM_HALO.y +
                       0.0722f * WYRM_HALO.z;
    if (l > target) {
      float t = (l - target) / (l - halo + 0.0001f);
      c.x += (WYRM_HALO.x - c.x) * t;
      c.y += (WYRM_HALO.y - c.y) * t;
      c.z += (WYRM_HALO.z - c.z) * t;
    }
    *shadow = igColorConvertFloat4ToU32((ImVec4){1.0f, 1.0f, 1.0f, 0.6f * alpha});
  }
  *text = igColorConvertFloat4ToU32((ImVec4){c.x, c.y, c.z, alpha});
}
"""

INK_END = """  return igColorConvertFloat4ToU32((ImVec4){c.x, c.y, c.z, alpha});
}

/* Text in Wyrm's ink halo: a wide, low shadow and a tight outline. */"""

PAIRS = {
    "app/src/game/ui_overlay.h": [
        ("void ui_overlay_toggle_leaderboard(tenv* env);\n",
         "void ui_overlay_toggle_leaderboard(tenv* env);\n\n"
         "/* Snake names on any floor (OM, 2026-10-18; ui_overlay.c). Colours are\n"
         "   ImGui's packed ImU32, an unsigned int. */\n"
         "float wyrm_floor_luma_now(tenv* env);\n"
         "void wyrm_name_inks(float floor_luma, vec3s colour, float alpha,\n"
         "                    unsigned int* text, unsigned int* shadow);\n"),
    ],
    "app/src/game/ui_overlay.c": [
        (INK_END, INK_END.replace("\n\n/* Text in Wyrm's ink halo",
                                  "\n" + HELPER + "\n/* Text in Wyrm's ink halo")),
    ],
    "app/src/game/redraw.c": [
        ('#include "redraw.h"\n', '#include "redraw.h"\n#include "ui_overlay.h"\n'),
        ("""  ImDrawList_PushTexture(name_draw_list,
                         snake_name_font->ContainerAtlas->TexRef);
""", """  ImDrawList_PushTexture(name_draw_list,
                         snake_name_font->ContainerAtlas->TexRef);
  /* Names on any floor (OM, 2026-10-18): the floor picks the ink once. */
  const float name_floor_luma = wyrm_floor_luma_now(env);
"""),
        ("""          // The font atlas is bound once around the snake loop (above).
          ImDrawList_AddText_FontPtr(
              name_draw_list, snake_name_font, snake_name_font->LegacySize,
              (ImVec2){ntx, nty},
              igColorConvertFloat4ToU32(
                  (ImVec4){ncolor[0], ncolor[1], ncolor[2], a}),
              usrs->snake_scores ? nk_label_buff : o->nk, NULL, 0, NULL);
""", """          // The font atlas is bound once around the snake loop (above).
          // The floor picks a light or dark ink, with a soft shadow of the
          // other tone under it (OM, 2026-10-18).
          {
            ImU32 name_ink, name_shadow;
            wyrm_name_inks(name_floor_luma, *scolor, a, &name_ink, &name_shadow);
            const char* label = usrs->snake_scores ? nk_label_buff : o->nk;
            float size = snake_name_font->LegacySize;
            float lift = size * 0.07f;
            if (lift < 1.0f) lift = 1.0f;
            ImDrawList_AddText_FontPtr(name_draw_list, snake_name_font, size,
                                       (ImVec2){ntx + lift, nty + lift},
                                       name_shadow, label, NULL, 0, NULL);
            ImDrawList_AddText_FontPtr(name_draw_list, snake_name_font, size,
                                       (ImVec2){ntx, nty}, name_ink, label,
                                       NULL, 0, NULL);
          }
"""),
    ],
}


def apply(root, label="names on any floor 2026-10-18", skip_applied=False):
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
