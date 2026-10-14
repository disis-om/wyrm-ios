"""Arena chat panel round 2 (OM, 2026-10-14), on top of engine_chat_tabs.

  - The fold mark is an X with a big hit area: one tap folds the window, even
    a small one (the tabs could cover the old mark, so it took 2-3 taps).
    Tabs shrink to fit beside it on a narrow window.
  - Unread counts per tab: TEAM and GLOBAL each show their own; the folded
    pill shows both added up. A tab counts as read while it is shown.
  - ONLINE lists from the top and has a scroll bar on its right edge that
    shows how far down you are.

One source for both apps: Wyrm Android's tree gets these pairs once
(`python engine_chat_panel_2026_10_14.py "<Wyrm Android>"`), and
prepare-original-engine.py applies them after engine_chat_tabs.
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


F = "app/src/platform/android_team.c"

pairs(F,
      ("""static float chat_tab_rect[CHAT_TAB_COUNT][4];
""", """static float chat_tab_rect[CHAT_TAB_COUNT][4];
/* The X that folds the window, and how far down the ONLINE list is (0 = top). */
static float chat_close_rect[4];
static float online_scroll = 0.0f;
"""),
      ("""    chat_tab = tab;
    chat_scroll = 0.0f;
  }""", """    chat_tab = tab;
    chat_scroll = 0.0f;
    online_scroll = 0.0f;
  }"""),
      ("""  memset(chat_tab_rect, 0, sizeof(chat_tab_rect));
""", """  memset(chat_tab_rect, 0, sizeof(chat_tab_rect));
  memset(chat_close_rect, 0, sizeof(chat_close_rect));
"""),
      # unread per tab
      ("""  long unread = 0;
  if (openness > 0.5f) {
    seen_chat_total = frame_chat_total;
    seen_global_total = frame_global_total;
  } else {
    if (seen_chat_total >= 0 && frame_chat_total > seen_chat_total)
      unread += frame_chat_total - seen_chat_total;
    if (seen_global_total >= 0 && frame_global_total > seen_global_total)
      unread += frame_global_total - seen_global_total;
  }
  if (seen_chat_total < 0) seen_chat_total = frame_chat_total;
  if (seen_global_total < 0) seen_global_total = frame_global_total;
""", """  /* Unread per tab (OM, 2026-10-14): a tab is read while it is shown; the
     folded pill adds both up. The first list that arrives is not unread. */
  bool open_now = openness > 0.5f;
  if (seen_chat_total < 0 && frame_chat_total > 0) seen_chat_total = frame_chat_total;
  if (seen_global_total < 0 && frame_global_total > 0)
    seen_global_total = frame_global_total;
  if (open_now && chat_tab == CHAT_TAB_TEAM) seen_chat_total = frame_chat_total;
  if (open_now && chat_tab == CHAT_TAB_GLOBAL) seen_global_total = frame_global_total;
  long team_unread = seen_chat_total >= 0 && frame_chat_total > seen_chat_total
                         ? frame_chat_total - seen_chat_total
                         : 0;
  long global_unread =
      seen_global_total >= 0 && frame_global_total > seen_global_total
          ? frame_global_total - seen_global_total
          : 0;
  if (preview) team_unread = global_unread = 0;
  long unread = open_now ? 0 : team_unread + global_unread;
"""),
      # header: tabs with counts, shrink to fit, the X
      ("""    static const char* tab_names[CHAT_TAB_COUNT] = {"TEAM", "GLOBAL", "ONLINE"};
    float tab_x = left + pad;
    for (int t = 0; t < CHAT_TAB_COUNT; ++t) {
      float tw = hud_text_width(bold, label_size, tab_names[t], NULL);
      bool shown = t == chat_tab;
      ImDrawList_AddText_FontPtr(
          draw, bold, label_size,
          (ImVec2){tab_x, top + (header_h - label_size) * 0.5f},
          arena_theme_colour(shown ? ARENA_THEME_INK : ARENA_THEME_QUIET,
                             body_alpha),
          tab_names[t], NULL, 0.0f, NULL);
      if (shown)
        ImDrawList_AddLine(
            draw, (ImVec2){tab_x, top + header_h - 3.0f * scale},
            (ImVec2){tab_x + tw, top + header_h - 3.0f * scale},
            arena_theme_colour(ARENA_THEME_INK, body_alpha), 2.0f * scale);
      chat_tab_rect[t][0] = tab_x - 6.0f * scale;
      chat_tab_rect[t][1] = top;
      chat_tab_rect[t][2] = tw + 12.0f * scale;
      chat_tab_rect[t][3] = header_h;
      tab_x += tw + 18.0f * scale;
    }
    float fold_y = top + header_h * 0.5f;
    ImDrawList_AddLine(
        draw, (ImVec2){left + vis_w - pad - 16.0f * scale, fold_y},
        (ImVec2){left + vis_w - pad, fold_y},
        arena_theme_colour(ARENA_THEME_INK, 0.8f * body_alpha), 2.5f * scale);
""", """    static const char* tab_names[CHAT_TAB_COUNT] = {"TEAM", "GLOBAL", "ONLINE"};
    long tab_unread[CHAT_TAB_COUNT] = {team_unread, global_unread, 0};
    char tab_count[CHAT_TAB_COUNT][8];
    float close_w = 46.0f * scale;
    float badge_size = label_size * 0.78f;
    /* The tabs shrink to fit beside the X on a narrow window. */
    float total = 18.0f * scale * (CHAT_TAB_COUNT - 1);
    for (int t = 0; t < CHAT_TAB_COUNT; ++t) {
      tab_count[t][0] = '\\0';
      if (tab_unread[t] > 0)
        snprintf(tab_count[t], sizeof(tab_count[t]), "%ld",
                 tab_unread[t] > 99 ? 99 : tab_unread[t]);
      total += hud_text_width(bold, label_size, tab_names[t], NULL);
      if (tab_count[t][0])
        total += hud_text_width(bold, badge_size, tab_count[t], NULL) +
                 14.0f * scale;
    }
    float room = vis_w - pad - close_w - pad * 0.5f;
    float fit = total > room && total > 0.0f ? room / total : 1.0f;
    if (fit < 0.6f) fit = 0.6f;
    float tab_size = label_size * fit;
    float tab_x = left + pad;
    for (int t = 0; t < CHAT_TAB_COUNT; ++t) {
      float tw = hud_text_width(bold, tab_size, tab_names[t], NULL);
      bool shown = t == chat_tab;
      ImDrawList_AddText_FontPtr(
          draw, bold, tab_size,
          (ImVec2){tab_x, top + (header_h - tab_size) * 0.5f},
          arena_theme_colour(shown ? ARENA_THEME_INK : ARENA_THEME_QUIET,
                             body_alpha),
          tab_names[t], NULL, 0.0f, NULL);
      if (shown)
        ImDrawList_AddLine(
            draw, (ImVec2){tab_x, top + header_h - 3.0f * scale},
            (ImVec2){tab_x + tw, top + header_h - 3.0f * scale},
            arena_theme_colour(ARENA_THEME_INK, body_alpha), 2.0f * scale);
      float bw = 0.0f;
      if (tab_count[t][0]) {
        float bs = badge_size * fit;
        float nw = hud_text_width(bold, bs, tab_count[t], NULL);
        float bh = bs + 4.0f * scale;
        float bx = tab_x + tw + 5.0f * scale;
        float by = top + (header_h - bh) * 0.5f;
        ImDrawList_AddRectFilled(
            draw, (ImVec2){bx, by}, (ImVec2){bx + nw + 9.0f * scale, by + bh},
            arena_theme_colour(ARENA_THEME_BADGE, body_alpha), 999.0f, 0);
        ImDrawList_AddText_FontPtr(
            draw, bold, bs, (ImVec2){bx + 4.5f * scale, by + 2.0f * scale},
            team_colour(1, 1, 1, body_alpha), tab_count[t], NULL, 0.0f, NULL);
        bw = nw + 14.0f * scale;
      }
      chat_tab_rect[t][0] = tab_x - 6.0f * scale;
      chat_tab_rect[t][1] = top;
      chat_tab_rect[t][2] = tw + bw + 12.0f * scale;
      chat_tab_rect[t][3] = header_h;
      tab_x += tw + bw + 18.0f * scale * fit;
    }
    /* The X (OM, 2026-10-14): folds the window in one tap; its hit area is
       the whole corner, a little past the panel's edge. */
    float close_cx = left + vis_w - pad * 0.5f - close_w * 0.5f;
    float close_cy = top + header_h * 0.5f;
    float arm = 6.5f * scale;
    ImDrawList_AddLine(
        draw, (ImVec2){close_cx - arm, close_cy - arm},
        (ImVec2){close_cx + arm, close_cy + arm},
        arena_theme_colour(ARENA_THEME_INK, 0.85f * body_alpha), 2.5f * scale);
    ImDrawList_AddLine(
        draw, (ImVec2){close_cx - arm, close_cy + arm},
        (ImVec2){close_cx + arm, close_cy - arm},
        arena_theme_colour(ARENA_THEME_INK, 0.85f * body_alpha), 2.5f * scale);
    chat_close_rect[0] = close_cx - close_w * 0.5f;
    chat_close_rect[1] = top - 10.0f * scale;
    chat_close_rect[2] = close_w + pad * 0.5f + 8.0f * scale;
    chat_close_rect[3] = header_h + 20.0f * scale;
"""),
      # ONLINE leaves room for its scroll bar
      ("""    if (list_width < text_size) list_width = text_size;
    float gap = 5.0f * scale;
    int lines = preview ? 4""", """    if (online) list_width -= 10.0f * scale;
    if (list_width < text_size) list_width = text_size;
    float gap = 5.0f * scale;
    int lines = preview ? 4"""),
      # rows: ONLINE from the top, chats from the bottom; the scroll bar
      ("""      float y = list_bottom + chat_scroll;
      for (int i = lines - 1; i >= 0; --i) {
        const char* author = "";""", """      /* ONLINE lists from the top (OM, 2026-10-14); chats from the newest up. */
      online_scroll = hud_clamp(online_scroll, 0.0f, most);
      float y = online ? list_top - online_scroll : list_bottom + chat_scroll;
      for (int k = 0; k < lines; ++k) {
        int i = online ? k : lines - 1 - k;
        const char* author = "";"""),
      ("""        if (own_line) h += text_size * 1.22f;
        y -= h + gap;
        if (y > list_bottom) continue;
        if (y + h < list_top) break;
        ImDrawList_AddText_FontPtr(
            draw, bold, text_size, (ImVec2){list_left, y},""", """        if (own_line) h += text_size * 1.22f;
        float row_y;
        if (online) {
          row_y = y;
          y += h + gap;
          if (row_y + h < list_top) continue;
          if (row_y > list_bottom) break;
        } else {
          y -= h + gap;
          row_y = y;
          if (row_y > list_bottom) continue;
          if (row_y + h < list_top) break;
        }
        ImDrawList_AddText_FontPtr(
            draw, bold, text_size, (ImVec2){list_left, row_y},"""),
      ("""        float body_y = own_line ? y + text_size * 1.22f : y;""",
       """        float body_y = own_line ? row_y + text_size * 1.22f : row_y;"""),
      ("""                 hud_text_colour(body_colour, ARENA_THEME_INK,
                                 0.92f * body_alpha));
      }
      ImDrawList_PopClipRect(draw);
    }""", """                 hud_text_colour(body_colour, ARENA_THEME_INK,
                                 0.92f * body_alpha));
      }
      ImDrawList_PopClipRect(draw);
      /* The scroll bar (OM, 2026-10-14): the list scrolls, and the thumb
         shows how far down it is. */
      if (online && most > 0.5f && content > 0.0f) {
        float bar_x = left + vis_w - pad * 0.55f;
        float thumb_h = list_height * list_height / content;
        if (thumb_h < 24.0f * scale) thumb_h = 24.0f * scale;
        if (thumb_h > list_height) thumb_h = list_height;
        float thumb_y = list_top + (list_height - thumb_h) * (online_scroll / most);
        ImDrawList_AddLine(
            draw, (ImVec2){bar_x, list_top}, (ImVec2){bar_x, list_bottom},
            arena_theme_colour(ARENA_THEME_RULE, 0.7f * body_alpha), 3.0f * scale);
        ImDrawList_AddLine(
            draw, (ImVec2){bar_x, thumb_y}, (ImVec2){bar_x, thumb_y + thumb_h},
            arena_theme_colour(ARENA_THEME_INK, 0.6f * body_alpha), 3.0f * scale);
      }
    }"""),
      # touch: the X first, then tabs; ONLINE scrolls from the top
      ("""    if (hud_inside(chat_rect, x, y)) {
      /* A tab (OM, 2026-10-14) shows its list. */""", """    /* The X (OM, 2026-10-14): one tap folds the window, even a small one. */
    if (chat_openness > 0.72f && hud_inside(chat_close_rect, x, y)) {
      chat_toggle_fold(env->ctx->size[0]);
      return true;
    }
    if (hud_inside(chat_rect, x, y)) {
      /* A tab (OM, 2026-10-14) shows its list. */"""),
      ("""      roster_scroll -= dy;
    else
      chat_scroll += dy;""", """      roster_scroll -= dy;
    else if (chat_tab == CHAT_TAB_ONLINE)
      online_scroll -= dy;
    else
      chat_scroll += dy;"""),
      )

# Wyrm Desktop's wheel (Android tree only)
pairs(F, ("""    if (chat_openness > 0.5f) chat_scroll += notches * step;""",
          """    if (chat_openness > 0.5f) {
      if (chat_tab == CHAT_TAB_ONLINE)
        online_scroll -= notches * step;
      else
        chat_scroll += notches * step;
    }""", "android"))


def apply(root, label="engine chat panel 2026-10-14", skip_applied=False, tree="android"):
    root = Path(root)
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        crlf = "\r\n" in text
        for item in items:
            old, new = item[0], item[1]
            only = item[2] if len(item) > 2 else None
            if only and only != tree:
                continue
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
    print(apply(sys.argv[1], skip_applied=True, tree="android"), "files written")
