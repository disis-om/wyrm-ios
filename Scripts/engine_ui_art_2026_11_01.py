"""The chat window's X, its scroll bar and the zoom bar's + and - in the
original's baked art (OM, 2026-11-01).

They were ImGui lines. Now they come from the original's glyph sheet, with its
baked black outline (NORMAL) under a white face (ADD), like every other sheet
text: X, + and - are the sheet's own glyphs, centred; the scroll bar is the
'|' glyph cut in three (cap, stretched middle, cap) so its round ends and its
outline keep their baked shape at any length.

Same text for Wyrm Android's tree (run once:
`python engine_ui_art_2026_11_01.py "<Wyrm Android>"`) and the prepared Apple
tree (prepare-original-engine.py, after engine_text_look). Anchors occur once.
"""
from pathlib import Path
import sys

PAIRS = {}


def add(path, old, new):
    PAIRS.setdefault('app/src/' + path, []).append((old, new))


add('game/sheet_text.h',
    '''/* The same signature as ImGui, for engine roster/chat call sites.''',
    '''/* One sheet layer quad in screen px, premultiplied and veiled (OM, 2026-11-01). */
static inline void sheet_quad(spr_renderer* batch, float x, float y, float w,
                              float h, float u, float v, float uw, float vh,
                              vec4s tint) {
  if (!batch || w <= 0.0f || h <= 0.0f) return;
  spr_renderer_push(batch, &(spr_instance){
      {{x + w * .5f, y + h * .5f, w, h}},
      {{u / 2048.0f, v / 2048.0f, uw / 2048.0f, vh / 2048.0f}}, tint});
}

static inline vec4s sheet_tint(ImU32 colour, float alpha_mul) {
  float a = (colour >> 24) / 255.0f * alpha_mul;
  float veil = wyrm_sheet_veil < 0 ? 0 : wyrm_sheet_veil > 1 ? 1 : wyrm_sheet_veil;
  return (vec4s){{(colour & 255) / 255.0f * a * veil,
                  ((colour >> 8) & 255) / 255.0f * a * veil,
                  ((colour >> 16) & 255) / 255.0f * a * veil, a}};
}

/* One sheet glyph (X, +, -...) with its face centred on (cx, cy); `k` is
   screen px per sheet px. Outline NORMAL, face ADD, as the sheet text. */
static inline void sheet_glyph_centred(char ch, int font, float k, float cx,
                                       float cy, ImU32 colour) {
  if (ch < 33 || ch > 126 || !wyrm_text_normal || !wyrm_text_add ||
      !(colour & 0xFF000000u) || k <= 0.0f) return;
  const original_glyph* face = &ORIGINAL_GLYPHS[font + (ch - 32) * 3];
  float fs = k * face->scale;
  /* The face's top-left in glyph space is (-px, -py) * its scale. */
  float ox = cx - face->w * fs * .5f + face->px * fs;
  float oy = cy - face->h * fs * .5f + face->py * fs;
  for (int pass = 0; pass < 2; ++pass) {
    const original_glyph* g = face + (pass == 0 ? 1 : 0);
    float s = k * g->scale;
    if (g->w <= 1) continue;
    sheet_quad(pass == 0 ? wyrm_text_normal : wyrm_text_add,
               ox - g->px * s, oy - g->py * s, g->w * s, g->h * s,
               g->x, g->y, g->w, g->h, sheet_tint(colour, 1.0f));
  }
}

/* A vertical bar from the sheet's '|' (the scroll bar, OM 2026-11-01): its
   face spans y0..y1 at `width` px wide, centred on x. Each layer is cut in
   three, its round caps (half its width tall) kept and the middle stretched,
   so the ends and the baked outline keep their shape at any length. */
static inline void sheet_bar(float x, float y0, float y1, float width,
                             ImU32 colour, int font) {
  if (!wyrm_text_normal || !wyrm_text_add || !(colour & 0xFF000000u) ||
      y1 <= y0 || width <= 0.0f) return;
  const original_glyph* face = &ORIGINAL_GLYPHS[font + ('|' - 32) * 3];
  float k = width / (face->w * face->scale);
  float fs = k * face->scale;
  float stretch = (y1 - y0) - face->h * fs; /* extra length over the glyph */
  float ox = x - face->w * fs * .5f + face->px * fs;
  float oy = y0 + face->py * fs;
  vec4s tint = sheet_tint(colour, 1.0f);
  for (int pass = 0; pass < 2; ++pass) {
    const original_glyph* g = face + (pass == 0 ? 1 : 0);
    if (g->w <= 1) continue;
    spr_renderer* batch = pass == 0 ? wyrm_text_normal : wyrm_text_add;
    float s = k * g->scale;
    float lx = ox - g->px * s, ly = oy - g->py * s;
    float cap = g->w * .5f;
    if (cap * 2.0f > g->h) cap = g->h * .5f;
    float mid = g->h - cap * 2.0f;
    float mid_h = mid * s + stretch;
    if (mid_h < 0.0f) {
      /* Shorter than the glyph: the caps share what there is. */
      float c = (g->h * s + stretch) * .5f;
      if (c <= 0.0f) continue;
      sheet_quad(batch, lx, ly, g->w * s, c, g->x, g->y, g->w, cap, tint);
      sheet_quad(batch, lx, ly + c, g->w * s, c, g->x, g->y + g->h - cap, g->w, cap, tint);
      continue;
    }
    sheet_quad(batch, lx, ly, g->w * s, cap * s, g->x, g->y, g->w, cap, tint);
    sheet_quad(batch, lx, ly + cap * s, g->w * s, mid_h, g->x, g->y + cap, g->w, mid, tint);
    sheet_quad(batch, lx, ly + cap * s + mid_h, g->w * s, cap * s,
               g->x, g->y + g->h - cap, g->w, cap, tint);
  }
}

/* The same signature as ImGui, for engine roster/chat call sites.''')

# ---- the chat window's X ----
add('platform/android_team.c',
    '''    float arm = 6.5f * scale;
    ImDrawList_AddLine(
        draw, (ImVec2){close_cx - arm, close_cy - arm},
        (ImVec2){close_cx + arm, close_cy + arm},
        arena_theme_colour(ARENA_THEME_INK, 0.85f * body_alpha), 2.5f * scale);
    ImDrawList_AddLine(
        draw, (ImVec2){close_cx - arm, close_cy + arm},
        (ImVec2){close_cx + arm, close_cy - arm},
        arena_theme_colour(ARENA_THEME_INK, 0.85f * body_alpha), 2.5f * scale);
''',
    '''    /* The original's X (OM, 2026-11-01): the sheet glyph, white face over
       its baked outline, about 15 px tall at scale 1 (was two ink lines). */
    sheet_glyph_centred('X', SHEET_THIN, 15.0f * scale / 38.0f, close_cx, close_cy,
                        team_colour(1, 1, 1, 0.92f * body_alpha));
''')

# ---- the ONLINE list's scroll bar ----
add('platform/android_team.c',
    '''        ImDrawList_AddLine(
            draw, (ImVec2){bar_x, list_top}, (ImVec2){bar_x, list_bottom},
            arena_theme_colour(ARENA_THEME_RULE, 0.7f * body_alpha), 3.0f * scale);
        ImDrawList_AddLine(
            draw, (ImVec2){bar_x, thumb_y}, (ImVec2){bar_x, thumb_y + thumb_h},
            arena_theme_colour(ARENA_THEME_INK, 0.6f * body_alpha), 3.0f * scale);
''',
    '''        /* The original's bar (OM, 2026-11-01): the sheet's '|' with its
           baked outline, a faint track and a white thumb. */
        sheet_bar(bar_x, list_top, list_bottom, 3.0f * scale,
                  team_colour(1, 1, 1, 0.22f * body_alpha), SHEET_THIN);
        sheet_bar(bar_x, thumb_y, thumb_y + thumb_h, 4.0f * scale,
                  team_colour(1, 1, 1, 0.9f * body_alpha), SHEET_THIN);
''')

# ---- the zoom bar's - and + ----
add('mobile/mobile_controls.c',
    '''    ImDrawList_AddLine(dl, (ImVec2){minus.x - mark, minus.y}, (ImVec2){minus.x + mark, minus.y}, sign, 2.5f);
    ImDrawList_AddLine(dl, (ImVec2){plus.x - mark, plus.y}, (ImVec2){plus.x + mark, plus.y}, sign, 2.5f);
    ImDrawList_AddLine(dl, (ImVec2){plus.x, plus.y - mark}, (ImVec2){plus.x, plus.y + mark}, sign, 2.5f);
''',
    '''    /* The original's - and + (OM, 2026-11-01): the sheet's Black glyphs,
       white over their baked outline, as wide as the old marks. */
    (void)sign;
    ImU32 white = color_u32(1, 1, 1, alpha * 0.95f);
    sheet_glyph_centred('-', SHEET_BLACK, 2.0f * mark / 19.0f, minus.x, minus.y, white);
    sheet_glyph_centred('+', SHEET_BLACK, 2.0f * mark / 26.0f, plus.x, plus.y, white);
''')
add('mobile/mobile_controls.c', '#include "mobile_controls.h"\n',
    '#include "mobile_controls.h"\n'
    '#include "../game/sheet_text.h" /* the zoom bar\'s - and + (OM, 2026-11-01) */\n')


def apply(root, label='engine UI art 2026-11-01', dry=False):
    root = Path(root)
    report = []
    for file, pairs in PAIRS.items():
        path = root / file
        raw = path.read_bytes().decode('utf-8')
        crlf = '\r\n' in raw
        text = raw.replace('\r\n', '\n')
        for old, new in pairs:
            count = text.count(old)
            if count != 1:
                raise SystemExit(f'{label}: {file}: {count} anchors: {old[:80]!r}')
            if new in text:
                raise SystemExit(f'{label}: {file}: already applied: {old[:60]!r}')
            text = text.replace(old, new, 1)
            report.append(file)
        if not dry:
            path.write_bytes((text.replace('\n', '\r\n') if crlf else text).encode('utf-8'))
    print(f'{label}: {len(report)} edits in {len(PAIRS)} files{" (dry run)" if dry else ""}')


if __name__ == '__main__':
    apply(sys.argv[1], dry='--dry' in sys.argv)
