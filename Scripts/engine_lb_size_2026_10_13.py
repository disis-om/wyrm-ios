"""Leaderboard WIDTH and HEIGHT (OM, 2026-10-13).

One source for both apps (the engine_sync_2026_10_12.py pattern): Wyrm
Android's tree gets these pairs once
(`python engine_lb_size_2026_10_13.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree.

The layout editor's leaderboard options get WIDTH and HEIGHT. Both travel
with the team HUD look (`wyrm_team_hud`, appended keys `lb_width`,
`lb_height`; an app that sends fewer values leaves them at 1):
  - WIDTH scales the board, so the name column grows or shrinks: a long
    name shows whole when there is room, and is shortened to fit when not.
  - HEIGHT scales each row; from 1.75 a row holds two lines, and a name too
    long for one folds onto the second instead of being shortened.
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


pairs("app/src/platform/android_team.c",
      ("""  STYLE_STATS_TEXT,  /* the stats panel's text colour, 0 = theme (OM, 2026-10-11) */
  STYLE_COUNT""",
       """  STYLE_STATS_TEXT,  /* the stats panel's text colour, 0 = theme (OM, 2026-10-11) */
  STYLE_LB_WIDTH,    /* the leaderboard's width, x its own (OM, 2026-10-13) */
  STYLE_LB_HEIGHT,   /* its row height, x its own; 1.75+ = two-line names */
  STYLE_COUNT"""),
      ("""                                       1.0f,   0.0f};""",
       """                                       1.0f,   0.0f,   1.0f, 1.0f};"""),
      ("void android_team_set_chat(const char* packed) {\n",
       """/* The leaderboard's WIDTH and HEIGHT (OM, 2026-10-13), drawn by
   ui_overlay.c: multiples of the board's own width and row height. */
float android_team_lb_width(void) {
  return hud_clamp(hud_style[STYLE_LB_WIDTH], 0.7f, 2.2f);
}

float android_team_lb_height(void) {
  return hud_clamp(hud_style[STYLE_LB_HEIGHT], 1.0f, 2.2f);
}

void android_team_set_chat(const char* packed) {
"""))

pairs("app/src/platform/android_team.h",
      ("float android_team_stats_panel(void);\n",
       "float android_team_stats_panel(void);\n"
       "/* The leaderboard's WIDTH and HEIGHT (OM, 2026-10-13). */\n"
       "float android_team_lb_width(void);\n"
       "float android_team_lb_height(void);\n"))

pairs("app/src/game/ui_overlay.c",
      ("""  wyrm_halo_text(draw, font, font->LegacySize, pos, colour, alpha, shortened);
}
""",
       """  wyrm_halo_text(draw, font, font->LegacySize, pos, colour, alpha, shortened);
}

/* A leaderboard name (OM, 2026-10-13): one line, shortened to fit; when the
   row has room for two (the HEIGHT slider), a name too long for one line
   folds onto the second instead, cut only between letters (UTF-8 aware). */
static void wyrm_halo_name_rows(ImDrawList* draw, ImFont* font, ImVec2 pos,
                                ImU32 colour, float alpha, const char* text,
                                float max_width, int lines, float line_step) {
  if (lines < 2 || !text || measure(font, text) <= max_width) {
    wyrm_halo_fitted(draw, font, pos, colour, alpha, text, max_width);
    return;
  }
  char first[MAX_NICKNAME_LEN + 8];
  int length = (int)strlen(text);
  int cut = 0;
  for (int i = 1; i <= length && i < (int)sizeof(first) - 1; ++i) {
    if (i < length && (((unsigned char)text[i]) & 0xC0) == 0x80) continue;
    snprintf(first, sizeof(first), "%.*s", i, text);
    if (measure(font, first) > max_width) break;
    cut = i;
  }
  if (cut <= 0 || cut >= length) {
    wyrm_halo_fitted(draw, font, pos, colour, alpha, text, max_width);
    return;
  }
  snprintf(first, sizeof(first), "%.*s", cut, text);
  wyrm_halo_text(draw, font, font->LegacySize, pos, colour, alpha, first);
  wyrm_halo_fitted(draw, font, (ImVec2){pos.x, pos.y + line_step}, colour,
                   alpha, text + cut, max_width);
}
"""),
      ("""      float row_height = score_size.y + 7.0f;
      float board_width = GLM_MAX(""",
       """      /* HEIGHT (OM, 2026-10-13): taller rows; two lines a name from 1.75. */
      float lb_height = android_team_lb_height();
      int name_lines = lb_height >= 1.75f ? 2 : 1;
      float row_height = (score_size.y + 7.0f) * lb_height;
      float board_width = GLM_MAX("""),
      ("""                                   rank_size.x + 10.0f + name_size.x + 12.0f +
                                       score_size.x));
""",
       """                                   rank_size.x + 10.0f + name_size.x + 12.0f +
                                       score_size.x));
      /* WIDTH (OM, 2026-10-13): the name column grows or shrinks with it. */
      board_width = GLM_MAX(rank_size.x + 10.0f + score_size.x + 60.0f,
                            board_width * android_team_lb_width());
"""),
      ("""        wyrm_halo_fitted(draw, name_font, (ImVec2){name_x, row_y + 3.0f},
                         snake_ink, alpha, gdata->data.lb.entries[row].nickname,
                         board_max.x - score_width - 10.0f - name_x);""",
       """        wyrm_halo_name_rows(draw, name_font, (ImVec2){name_x, row_y + 3.0f},
                            snake_ink, alpha, gdata->data.lb.entries[row].nickname,
                            board_max.x - score_width - 10.0f - name_x,
                            name_lines, name_font->LegacySize * 1.02f);"""))


def apply(root, label="engine leaderboard size 2026-10-13", skip_applied=False):
    root = Path(root)
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        for old, new in items:
            if skip_applied and new in text and (old not in text or old in new):
                continue
            count = text.count(old)
            if count != 1:
                raise SystemExit(f"{label}: anchor x{count} in {relative}: {old[:70]!r}")
            text = text.replace(old, new)
        if text != original:
            target.write_text(text, encoding="utf-8", newline="")
    return len(PAIRS)


if __name__ == "__main__":
    # Wyrm Android's tree: python engine_lb_size_2026_10_13.py "<Wyrm Android>"
    print(apply(sys.argv[1], skip_applied=True), "files patched")
