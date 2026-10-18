"""Chat window: GLOBAL colours of its own and a chat button like the keys
(OM, 2026-10-18).

The arena's chat window had one pair of colours for TEAM and GLOBAL; GLOBAL now
has its own pair. Folded, the window became a theme pill; now it is a button
drawn like the on-screen keys (the same shadow, fill, border and label
colours, the same palettes: label 0 = white, fill 0 = theme card, 9 = grey),
with its own size and opacity. Six team-HUD style values are appended in this
order: GLOBAL name, GLOBAL text, button label, button fill, button size,
button opacity; an older app sends fewer and the engine keeps the defaults.
`android_team_set_chat_tab(3)` is the editor's Button tab: it shows the folded
button while the editor is up.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

REL = "app/src/platform/android_team.c"

PAIRS = [
    ("""  STYLE_ONLINE_DATA, /* ONLINE tab "@username - server" line, 0 = theme */
  STYLE_COUNT
""", """  STYLE_ONLINE_DATA, /* ONLINE tab "@username - server" line, 0 = theme */
  STYLE_GLOBAL_NAME, /* GLOBAL tab names, 0 = theme (OM, 2026-10-18) */
  STYLE_GLOBAL_TEXT, /* GLOBAL tab messages, 0 = theme */
  STYLE_BTN_LABEL,   /* the folded chat button's label + border, 0 = white */
  STYLE_BTN_FILL,    /* its fill: 0 theme card, 1-8 the palette, 9 grey */
  STYLE_BTN_SCALE,   /* its size, x its own */
  STYLE_BTN_OPACITY, /* its opacity */
  STYLE_COUNT
"""),
    ("""                                       1.0f,   0.0f,   1.0f, 1.0f,
                                       0.0f,   0.0f};""",
     """                                       1.0f,   0.0f,   1.0f, 1.0f,
                                       0.0f,   0.0f,
                                       0.0f,   0.0f,   0.0f, 9.0f, 1.0f, 0.9f};"""),
    ("""int android_team_chat_tab(void) { return chat_tab; }
void android_team_set_chat_tab(int tab) {
""", """int android_team_chat_tab(void) { return chat_tab; }
/* The editor's Button tab (OM, 2026-10-18): tab 3 shows the folded chat
   button instead of the window while the editor is up. */
static bool chat_button_preview = false;
void android_team_set_chat_tab(int tab) {
  chat_button_preview = tab == 3;
"""),
    ("""  int name_colour = (int)hud_style[STYLE_CHAT_NAME];
  int text_colour = (int)hud_style[STYLE_CHAT_TEXT];
  ImFont* bold = usr->imgui_data.regular_font_bold[FONT_SIZE_SMALL];""",
     """  /* GLOBAL has its own colours (OM, 2026-10-18). */
  bool global_tab = chat_tab == CHAT_TAB_GLOBAL;
  int name_colour = (int)hud_style[global_tab ? STYLE_GLOBAL_NAME : STYLE_CHAT_NAME];
  int text_colour = (int)hud_style[global_tab ? STYLE_GLOBAL_TEXT : STYLE_CHAT_TEXT];
  ImFont* bold = usr->imgui_data.regular_font_bold[FONT_SIZE_SMALL];"""),
    ("""  float openness = preview ? 1.0f : chat_fold_sample();
""", """  float openness = preview ? (chat_button_preview ? 0.0f : 1.0f) : chat_fold_sample();
"""),
    ("""  float pill_w = label_w + badge_w + 44.0f * scale;
  float pill_h = label_size + 26.0f * scale;
""", """  /* The folded window is a chat button drawn like the on-screen keys, with
     its own size, opacity, label and fill (OM, 2026-10-18). */
  float btn_scale = hud_clamp(hud_style[STYLE_BTN_SCALE], 0.6f, 2.5f);
  float btn_opacity = hud_clamp(hud_style[STYLE_BTN_OPACITY], 0.1f, 1.0f);
  int btn_label_index = (int)hud_style[STYLE_BTN_LABEL];
  int btn_fill_index = (int)hud_style[STYLE_BTN_FILL];
  float pill_w = (label_w + badge_w + 44.0f * scale) * btn_scale;
  float pill_h = (label_size + 26.0f * scale) * btn_scale;
"""),
    ("""  float radius = 999.0f + (14.0f * scale - 999.0f) * openness;
  hud_card(draw, min, max, radius, panel * opacity);
""", """  float key_corner = pill_h * 0.30f;
  float radius = key_corner + (14.0f * scale - key_corner) * openness;
  hud_card(draw, min, max, radius, panel * opacity * openness);
  float btn_alpha = btn_opacity * (1.0f - openness);
  ImU32 btn_ink = btn_label_index > 0
                      ? hud_text_colour(btn_label_index, ARENA_THEME_INK, 1.0f - openness)
                      : team_colour(1, 1, 1, 1.0f - openness);
  if (btn_alpha > 0.01f) {
    /* As a key: a soft shadow, the fill, then a 1.5 px border. */
    ImDrawList_AddRectFilled(draw, (ImVec2){min.x, min.y + vis_h * 0.07f},
                             (ImVec2){max.x, max.y + vis_h * 0.07f},
                             team_colour(0, 0, 0, btn_alpha * 0.16f), radius, 0);
    ImU32 fill = btn_fill_index == 9
                     ? team_colour(0.502f, 0.502f, 0.502f, btn_alpha * 0.94f)
                     : hud_text_colour(btn_fill_index, ARENA_THEME_CARD,
                                       btn_alpha * 0.94f);
    ImDrawList_AddRectFilled(draw, min, max, fill, radius, 0);
    ImDrawList_AddRect(draw, min, max,
                       btn_label_index > 0
                           ? hud_text_colour(btn_label_index, ARENA_THEME_INK,
                                             0.9f * (1.0f - openness))
                           : team_colour(1, 1, 1, 0.9f * (1.0f - openness)),
                       radius, 0, 1.5f);
  }
"""),
    ("""  float pill_alpha = opacity * (1.0f - openness);
  if (pill_alpha > 0.02f) {
    ImDrawList_AddText_FontPtr(
        draw, bold, label_size,
        (ImVec2){left + 22.0f * scale, top + (vis_h - label_size) * 0.5f},
        arena_theme_colour(ARENA_THEME_INK, pill_alpha), label, NULL, 0.0f,
        NULL);
    if (badge[0]) {
      float bx = left + 22.0f * scale + label_w + 8.0f * scale;
      float bh = label_size + 6.0f * scale;
      float by = top + (vis_h - bh) * 0.5f;
      ImDrawList_AddRectFilled(
          draw, (ImVec2){bx, by}, (ImVec2){bx + badge_w, by + bh},
          arena_theme_colour(ARENA_THEME_BADGE, pill_alpha), 999.0f, 0);
      ImDrawList_AddText_FontPtr(
          draw, bold, label_size,
          (ImVec2){bx + 7.0f * scale, by + 3.0f * scale},
          team_colour(1, 1, 1, pill_alpha), badge, NULL, 0.0f, NULL);
    }
  }
""", """  float pill_alpha = 1.0f - openness;
  if (pill_alpha > 0.02f) {
    /* Label and badge keep full contrast, as on the keys. */
    float bs = btn_scale;
    float bl = label_size * bs;
    ImDrawList_AddText_FontPtr(
        draw, bold, bl,
        (ImVec2){left + 22.0f * scale * bs, top + (vis_h - bl) * 0.5f},
        btn_ink, label, NULL, 0.0f, NULL);
    if (badge[0]) {
      float bx = left + (22.0f * scale + label_w + 8.0f * scale) * bs;
      float bh = (label_size + 6.0f * scale) * bs;
      float by = top + (vis_h - bh) * 0.5f;
      ImDrawList_AddRectFilled(
          draw, (ImVec2){bx, by}, (ImVec2){bx + badge_w * bs, by + bh},
          arena_theme_colour(ARENA_THEME_BADGE, pill_alpha), 999.0f, 0);
      ImDrawList_AddText_FontPtr(
          draw, bold, bl,
          (ImVec2){bx + 7.0f * scale * bs, by + 3.0f * scale * bs},
          team_colour(1, 1, 1, pill_alpha), badge, NULL, 0.0f, NULL);
    }
  }
"""),
]


def apply(root, label="chat button 2026-10-18", skip_applied=False):
    path = Path(root) / REL
    text = path.read_text(encoding="utf-8")
    for old, new in PAIRS:
        if skip_applied and new in text:
            continue
        if text.count(old) != 1:
            raise SystemExit(f"{label}: anchor x{text.count(old)} in {REL}: {old[:80]!r}")
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8", newline="")


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
