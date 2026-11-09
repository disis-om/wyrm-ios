"""Wyrm's HUD in the original's baked glyphs, label opacity, the original boost
triangle, Near Original food size and the original minimap (OM, 2026-11-01).

The same text goes into Wyrm Android's tree (run once:
`python engine_sheet_hud_2026_11_01.py "<Wyrm Android>"`) and into the
prepared Apple tree (prepare-original-engine.py). Every anchor must occur once.
"""
from pathlib import Path
import sys

PAIRS = {}


def add(path, old, new):
    PAIRS.setdefault('app/src/' + path, []).append((old, new))


# ---- textures: the sheet and the minimap discs as ImGui images ----
add('rendering/renderer.h', '  texture* original_art_tex;\n',
    '  texture* original_art_tex;\n'
    '  /* Wyrm HUD type and the original minimap discs as ImGui images\n'
    '     (OM, 2026-11-01): game/sheet_text.h, game/minimap_art.h. */\n'
    '  texture* minimap_art_tex;\n'
    '  VkDescriptorSet sheet_set, minimap_set;\n')
add('rendering/renderer.c', '#include "../user.h"\n',
    '#include "../user.h"\n'
    '\n/* game/sheet_text.h and game/minimap_art.h (OM, 2026-11-01). */\n'
    'VkDescriptorSet wyrm_sheet_set = VK_NULL_HANDLE;\n'
    'VkDescriptorSet wyrm_minimap_set = VK_NULL_HANDLE;\n')
add('rendering/renderer.c',
    '  r->original_hud_add = spr_renderer_create_original(ctx,2048,r->pipeline_layout,r->render_pass,true);\n',
    '  r->original_hud_add = spr_renderer_create_original(ctx,2048,r->pipeline_layout,r->render_pass,true);\n'
    '  r->minimap_art_tex = create_mipmap_texture(ctx, "app/res/textures/minimap_floors.png");\n'
    '  r->sheet_set = igImplVulkan_AddTexture(r->linear_sampler, r->original_art_tex->view,\n'
    '                                         VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);\n'
    '  r->minimap_set = igImplVulkan_AddTexture(r->linear_sampler, r->minimap_art_tex->view,\n'
    '                                           VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);\n'
    '  wyrm_sheet_set = r->sheet_set;\n'
    '  wyrm_minimap_set = r->minimap_set;\n')
add('rendering/renderer.c', '  destroy_texture(ctx, r->original_art_tex);\n',
    '  if (r->sheet_set) igImplVulkan_RemoveTexture(r->sheet_set);\n'
    '  if (r->minimap_set) igImplVulkan_RemoveTexture(r->minimap_set);\n'
    '  wyrm_sheet_set = wyrm_minimap_set = VK_NULL_HANDLE;\n'
    '  destroy_texture(ctx, r->minimap_art_tex);\n'
    '  destroy_texture(ctx, r->original_art_tex);\n')

# ---- settings: label opacity per key, the food reset ----
add('game/user_settings.h', '  bool zoom_flip;\n} user_settings_ext;',
    '  bool zoom_flip;\n'
    '  /* On-screen key label opacity 0..1 (OM, 2026-11-01), by action; 1 is\n'
    '     full. Starts 4-aligned after zoom_flip\'s padding. Append only. */\n'
    '  float key_label_opacity[20];\n'
    '  /* Food size back to the original once (OM, 2026-11-01). */\n'
    '  bool food_original_v1;\n'
    '} user_settings_ext;')
add('game/user_settings.c', '  for (int i = 0; i < 20; ++i) x->key_fill[i] = 9;\n',
    '  for (int i = 0; i < 20; ++i) x->key_fill[i] = 9;\n'
    '  for (int i = 0; i < 20; ++i) x->key_label_opacity[i] = 1.0f;\n'
    '  x->food_original_v1 = true;\n')
add('game/user_settings.c', '    fixed |= ext_take_bool(&ext->zoom_flip, written >= flip_at + 1);\n  }\n',
    '    fixed |= ext_take_bool(&ext->zoom_flip, written >= flip_at + 1);\n  }\n'
    '  {\n'
    '    /* Key label opacity (OM, 2026-11-01): missing = full. */\n'
    '    size_t label_at = offsetof(user_settings_ext, key_label_opacity);\n'
    '    for (int i = 0; i < 20; ++i)\n'
    '      fixed |= ext_take_float(&ext->key_label_opacity[i],\n'
    '                              written >= label_at + 4 * (size_t)(i + 1), 0.0f,\n'
    '                              1.0f, 1.0f);\n'
    '  }\n'
    '  {\n'
    '    /* Food size back to the original once (OM, 2026-11-01): whatever was\n'
    '       set becomes 1x (and follows the zoom again); changed after this, it\n'
    '       stays. */\n'
    '    unsigned char done = 0;\n'
    '    size_t food_at = offsetof(user_settings_ext, food_original_v1);\n'
    '    if (written >= food_at + 1 && bytes_read >= ext_at + food_at + 1)\n'
    '      memcpy(&done, &ext->food_original_v1, 1);\n'
    '    if (done != 1) {\n'
    '      for (int m = 0; m < 2; ++m) {\n'
    '        settings->modes[m].food_scale = 1.0f;\n'
    '        settings->modes[m].const_food_scale = false;\n'
    '      }\n'
    '      ext->food_original_v1 = true;\n'
    '      fixed = 1;\n'
    '    }\n'
    '  }\n')
LABEL_ROWS = ''.join(
    f'    {{"layout.key_{a}_label_opacity", "layout", "", "", SETTING_FLOAT, 0.0f,\n'
    f'     1.0f, NULL, OWNER_SETTINGS, SETTINGS_ARRAY_FIELD(ext.key_label_opacity, {a})}},\n'
    for a in (1, 2, 3, 4, 6, 7, 8, 9, 14, 15, 16))
add('platform/android_settings.c',
    '    {"layout.key_16_fill", "layout", "", "", SETTING_INT, 0, 9, NULL,\n'
    '     OWNER_SETTINGS, SETTINGS_ARRAY_FIELD(ext.key_fill, 16)},\n',
    '    {"layout.key_16_fill", "layout", "", "", SETTING_INT, 0, 9, NULL,\n'
    '     OWNER_SETTINGS, SETTINGS_ARRAY_FIELD(ext.key_fill, 16)},\n'
    '    /* A key\'s label opacity (OM, 2026-11-01), ext.key_label_opacity. */\n'
    + LABEL_ROWS)

# ---- on-screen keys: the label in the thin sheet, at its own opacity ----
add('mobile/mobile_hotkeys.c', '#include "mobile_hotkeys.h"\n',
    '#include "mobile_hotkeys.h"\n#include "../game/sheet_text.h"\n')
add('mobile/mobile_hotkeys.c',
    '    ImU32 primary = color(1.0f, 1.0f, 1.0f, 1.0f);\n'
    '    /* The label takes the key\'s colour (OM, 2026-10-14). */\n'
    '    if (coloured) primary = color(kr, kg, kb, 1.0f);\n'
    '    ImFont* font = env->usr->imgui_data.body_font[FONT_SIZE_REGULAR];\n',
    '    /* LABEL OPACITY (OM, 2026-11-01): the label alone fades. */\n'
    '    float label_alpha =\n'
    '        action >= 0 && action < 20\n'
    '            ? clampf_local(env->usr->usrs.ext.key_label_opacity[action], 0.0f, 1.0f)\n'
    '            : 1.0f;\n'
    '    ImU32 primary = color(1.0f, 1.0f, 1.0f, label_alpha);\n'
    '    /* The label takes the key\'s colour (OM, 2026-10-14). */\n'
    '    if (coloured) primary = color(kr, kg, kb, label_alpha);\n'
    '    ImFont* font = env->usr->imgui_data.body_font[FONT_SIZE_REGULAR];\n'
    '    /* The original\'s thin glyphs (OM, 2026-11-01). */\n'
    '    if (sheet_ok(function)) {\n'
    '      float text_size = font->LegacySize;\n'
    '      float text_w = sheet_width(function, text_size, SHEET_THIN);\n'
    '      float room = width - 16.0f;\n'
    '      if (text_w > room && text_w > 0.0f) {\n'
    '        text_size *= room / text_w;\n'
    '        text_w = room;\n'
    '      }\n'
    '      sheet_layer(draw, function, text_size,\n'
    '                  (ImVec2){cx - text_w * 0.5f, cy - text_size * 0.5f}, primary,\n'
    '                  SHEET_THIN, 0);\n'
    '      continue;\n'
    '    }\n')

# ---- the folded chat button: the same, with its own label opacity ----
add('platform/android_team.c', '#include "android_team.h"\n',
    '#include "android_team.h"\n#include "../game/sheet_text.h"\n')
add('platform/android_team.c', '  STYLE_BTN_OPACITY, /* its opacity */\n  STYLE_COUNT',
    '  STYLE_BTN_OPACITY, /* its opacity */\n'
    '  STYLE_BTN_LABEL_OPACITY, /* its label\'s opacity (OM, 2026-11-01) */\n'
    '  STYLE_COUNT')
add('platform/android_team.c', '0.0f,   0.0f,   0.0f, 9.0f, 1.0f, 0.9f};',
    '0.0f,   0.0f,   0.0f, 9.0f, 1.0f, 0.9f,\n'
    '                                       1.0f};')
add('platform/android_team.c',
    '    float bl = label_size * bs;\n'
    '    ImDrawList_AddText_FontPtr(\n'
    '        draw, bold, bl,\n'
    '        (ImVec2){left + 22.0f * scale * bs, top + (vis_h - bl) * 0.5f},\n'
    '        btn_ink, label, NULL, 0.0f, NULL);\n',
    '    float bl = label_size * bs;\n'
    '    /* The thin sheet at the label\'s own opacity (OM, 2026-11-01). */\n'
    '    float lop = hud_clamp(hud_style[STYLE_BTN_LABEL_OPACITY], 0.0f, 1.0f);\n'
    '    ImU32 label_ink = (btn_ink & 0x00FFFFFFu) |\n'
    '                      ((ImU32)(((btn_ink >> 24) & 255u) * lop) << 24);\n'
    '    if (sheet_ok(label))\n'
    '      sheet_layer(draw, label, bl,\n'
    '                  (ImVec2){left + 22.0f * scale * bs, top + (vis_h - bl) * 0.5f},\n'
    '                  label_ink, SHEET_THIN, 0);\n'
    '    else\n'
    '      ImDrawList_AddText_FontPtr(\n'
    '          draw, bold, bl,\n'
    '          (ImVec2){left + 22.0f * scale * bs, top + (vis_h - bl) * 0.5f},\n'
    '          label_ink, label, NULL, 0.0f, NULL);\n')

# ---- the boost button: the original's triangle, at the button's opacity ----
add('mobile/mobile_controls.c',
    '  /* Two chevrons, drawn rather than typed: the interface font has no glyph\n'
    '     worth using here, and lines stay crisp at any control size. */\n'
    '  float glyph = radius * 0.30f;\n'
    '  ImU32 ink = arena_theme_colour(ARENA_THEME_INK, 1.0f);\n'
    '  for (int i = 0; i < 2; ++i) {\n'
    '    float ox = cx + (i == 0 ? -glyph * 0.55f : glyph * 0.45f);\n'
    '    ImVec2 chevron[3] = {{ox - glyph * 0.35f, cy - glyph * 0.62f},\n'
    '                         {ox + glyph * 0.35f, cy},\n'
    '                         {ox - glyph * 0.35f, cy + glyph * 0.62f}};\n'
    '    ImDrawList_AddPolyline(dl, chevron, 3, ink, ImDrawFlags_None,\n'
    '                           radius * 0.075f);\n'
    '  }\n',
    '  /* The original boost\'s triangle (OM, 2026-11-01): boostie\'s, pointing\n'
    '     up, with its soft shadow, on the disc\'s scale (r 110), in Wyrm\'s ink.\n'
    '     It follows the button\'s size and opacity. */\n'
    '  float tk = radius / 110.0f;\n'
    '  for (int i = 1; i <= 4; ++i) {\n'
    '    float drop = (2.0f + 4.0f * i) * tk;\n'
    '    ImDrawList_AddTriangleFilled(\n'
    '        dl, (ImVec2){cx, cy - 41.5f * tk + drop},\n'
    '        (ImVec2){cx + 56.0f * tk, cy + 25.5f * tk + drop},\n'
    '        (ImVec2){cx - 56.0f * tk, cy + 25.5f * tk + drop},\n'
    '        color_u32(0, 0, 0, alpha * 0.07f));\n'
    '  }\n'
    '  ImDrawList_AddTriangleFilled(dl, (ImVec2){cx, cy - 41.5f * tk},\n'
    '                               (ImVec2){cx + 56.0f * tk, cy + 25.5f * tk},\n'
    '                               (ImVec2){cx - 56.0f * tk, cy + 25.5f * tk},\n'
    '                               arena_theme_colour(ARENA_THEME_INK, alpha));\n')

# ---- snake names: the thin sheet in the floor's inks ----
add('game/redraw.c', '#include "original_art.h"\n', '#include "original_art.h"\n#include "sheet_text.h"\n')
add('game/redraw.c',
    '            ImDrawList_AddText_FontPtr(name_draw_list, snake_name_font, size,\n'
    '                                       (ImVec2){ntx + lift, nty + lift},\n'
    '                                       name_shadow, label, NULL, 0, NULL);\n'
    '            ImDrawList_AddText_FontPtr(name_draw_list, snake_name_font, size,\n'
    '                                       (ImVec2){ntx, nty}, name_ink, label,\n'
    '                                       NULL, 0, NULL);\n',
    '            if (sheet_ok(label)) {\n'
    '              /* The original\'s thin glyphs (OM, 2026-11-01), centred on\n'
    '                 their own width. */\n'
    '              float shown = usrs->snake_scores ? tsize.x : nsize.x;\n'
    '              float sx = ntx + (shown - sheet_width(label, size, SHEET_THIN)) * 0.5f;\n'
    '              sheet_layer(name_draw_list, label, size, (ImVec2){sx + lift, nty + lift},\n'
    '                          name_shadow, SHEET_THIN, 0);\n'
    '              sheet_layer(name_draw_list, label, size, (ImVec2){sx, nty}, name_ink,\n'
    '                          SHEET_THIN, 0);\n'
    '            } else {\n'
    '            ImDrawList_AddText_FontPtr(name_draw_list, snake_name_font, size,\n'
    '                                       (ImVec2){ntx + lift, nty + lift},\n'
    '                                       name_shadow, label, NULL, 0, NULL);\n'
    '            ImDrawList_AddText_FontPtr(name_draw_list, snake_name_font, size,\n'
    '                                       (ImVec2){ntx, nty}, name_ink, label,\n'
    '                                       NULL, 0, NULL);\n'
    '            }\n')

# ---- Near Original food: every texture at the original's size ----
FOOD_OLD = '        float d = gdata->fsz[fo->cv2] * food_scale * fo->rad * mode->food_scale;\n'
FOOD_NEW = FOOD_OLD + (
    '        /* Near Original (OM, 2026-11-01): every food texture at the\n'
    '           original\'s size, Main.as newFood sz x rad x fgsc on the game\n'
    '           layer; the orb image\'s half-light disc is 52 of its 70 px. */\n'
    '        if (android_home_near_original() && food_tex != 1) {\n'
    '          float r0 = fo->sz;\n'
    '          float osz = .9f * ((3.6f + (r0 - 1.3f) * (r0 - 1.3f) / 23.5f) / 16);\n'
    '          d = 52.0f * osz * fo->rad * food_scale * 1.2f *\n'
    '              mode->food_scale;\n'
    '        }\n')
add('game/redraw.c', ('ALL', FOOD_OLD), FOOD_NEW)

# ---- ui_overlay.c: leaderboard, stats, minimap ----
add('game/ui_overlay.c', '#include "original_art.h"\n',
    '#include "original_art.h"\n#include "sheet_text.h"\n#include "minimap_art.h"\n')
add('game/ui_overlay.c', '/**\n * Draws a name, shortened until it fits.',
    '/* Wyrm HUD type from the original sheet (OM, 2026-11-01): printable ASCII\n'
    '   in its glyphs, anything else in Wyrm\'s font. The leaderboard is the\n'
    '   thin set, as the original\'s; the stats set their own. */\n'
    'static int hud_sheet_font = SHEET_THIN;\n'
    'static void hud_text(ImDrawList* draw, ImFont* font, float size, ImVec2 pos,\n'
    '                     ImU32 colour, const char* text) {\n'
    '  if (sheet_ok(text))\n'
    '    sheet_layer(draw, text, size, pos, colour, hud_sheet_font, 0);\n'
    '  else\n'
    '    ImDrawList_AddText_FontPtr(draw, font, size, pos, colour, text, NULL, 0,\n'
    '                               NULL);\n'
    '}\n'
    'static float hud_measure(ImFont* font, const char* text) {\n'
    '  return sheet_ok(text) ? sheet_width(text, font->LegacySize, hud_sheet_font)\n'
    '                        : measure(font, text);\n'
    '}\n'
    'static ImVec2 hud_measure_scaled(ImFont* font, const char* text, float scale,\n'
    '                                 int sheet_font) {\n'
    '  ImVec2 size = measure_scaled(font, text, scale);\n'
    '  if (sheet_ok(text)) size.x = sheet_width(text, font->LegacySize * scale, sheet_font);\n'
    '  return size;\n'
    '}\n\n'
    '/**\n * Draws a name, shortened until it fits.')
add('game/ui_overlay.c',
    '  float scale = usr->usrs.hud_stats_scale;\n'
    '  alpha *= usr->usrs.hud_stats_opacity;\n'
    '  ImVec2 value_size = measure_scaled(display, value, scale);\n'
    '\n'
    '  ImDrawList_AddText_FontPtr(draw, display, display->LegacySize * scale,\n'
    '                             (ImVec2){right - value_size.x, y},\n'
    '                             android_team_stats_colour(ARENA_THEME_INK, alpha), value,\n'
    '                             NULL, 0, NULL);\n'
    '\n'
    '  ImVec2 label_size = measure_scaled(body, label, scale);\n'
    '  ImDrawList_AddText_FontPtr(\n'
    '      draw, body, body->LegacySize * scale,\n'
    '      (ImVec2){right - value_size.x - 10.0f * scale - label_size.x,\n'
    '               y + (value_size.y - label_size.y) * 0.72f},\n'
    '      android_team_stats_colour(ARENA_THEME_QUIET, 0.92f * alpha), label, NULL, 0,\n'
    '      NULL);\n',
    '  float scale = usr->usrs.hud_stats_scale;\n'
    '  alpha *= usr->usrs.hud_stats_opacity;\n'
    '  /* The original\'s sheet (OM, 2026-11-01): values in its stats\' Black,\n'
    '     labels in the thin set. */\n'
    '  ImVec2 value_size = hud_measure_scaled(display, value, scale, SHEET_BLACK);\n'
    '\n'
    '  hud_sheet_font = SHEET_BLACK;\n'
    '  hud_text(draw, display, display->LegacySize * scale,\n'
    '           (ImVec2){right - value_size.x, y},\n'
    '           android_team_stats_colour(ARENA_THEME_INK, alpha), value);\n'
    '\n'
    '  ImVec2 label_size = hud_measure_scaled(body, label, scale, SHEET_THIN);\n'
    '  hud_sheet_font = SHEET_THIN;\n'
    '  hud_text(draw, body, body->LegacySize * scale,\n'
    '           (ImVec2){right - value_size.x - 10.0f * scale - label_size.x,\n'
    '                    y + (value_size.y - label_size.y) * 0.72f},\n'
    '           android_team_stats_colour(ARENA_THEME_QUIET, 0.92f * alpha), label);\n')
add('game/ui_overlay.c',
    '  for (int i = 0; i < 8; ++i) {\n'
    '    float a = 6.2831853f * (i + 0.5f) / 8.0f;\n'
    '    ImDrawList_AddText_FontPtr(\n'
    '        draw, font, size,\n'
    '        (ImVec2){pos.x + cosf(a) * soft, pos.y + sinf(a) * soft + soft * 0.35f},\n'
    '        shadow, text, NULL, 0, NULL);\n'
    '  }\n',
    '  for (int i = 0; i < 8; ++i) {\n'
    '    float a = 6.2831853f * (i + 0.5f) / 8.0f;\n'
    '    hud_text(draw, font, size,\n'
    '             (ImVec2){pos.x + cosf(a) * soft, pos.y + sinf(a) * soft + soft * 0.35f},\n'
    '             shadow, text);\n'
    '  }\n')
add('game/ui_overlay.c',
    '  for (int i = 0; i < 8; ++i) {\n'
    '    float a = 6.2831853f * i / 8.0f;\n'
    '    ImDrawList_AddText_FontPtr(\n'
    '        draw, font, size,\n'
    '        (ImVec2){pos.x + cosf(a) * tight, pos.y + sinf(a) * tight}, ink, text,\n'
    '        NULL, 0, NULL);\n'
    '  }\n'
    '  ImDrawList_AddText_FontPtr(draw, font, size, pos, colour, text, NULL, 0, NULL);\n',
    '  for (int i = 0; i < 8; ++i) {\n'
    '    float a = 6.2831853f * i / 8.0f;\n'
    '    hud_text(draw, font, size,\n'
    '             (ImVec2){pos.x + cosf(a) * tight, pos.y + sinf(a) * tight}, ink, text);\n'
    '  }\n'
    '  hud_text(draw, font, size, pos, colour, text);\n')
add('game/ui_overlay.c', '  if (measure(font, text) <= max_width) {\n    wyrm_halo_text(',
    '  if (hud_measure(font, text) <= max_width) {\n    wyrm_halo_text(')
add('game/ui_overlay.c', '    if (measure(font, shortened) <= max_width) break;\n  }\n  wyrm_halo_text(',
    '    if (hud_measure(font, shortened) <= max_width) break;\n  }\n  wyrm_halo_text(')
add('game/ui_overlay.c', '  if (lines < 2 || !text || measure(font, text) <= max_width) {',
    '  if (lines < 2 || !text || hud_measure(font, text) <= max_width) {')
add('game/ui_overlay.c', '    if (measure(font, first) > max_width) break;',
    '    if (hud_measure(font, first) > max_width) break;')
add('game/ui_overlay.c',
    '      igCalcTextSize(&hint_size, "Tap on leaderboard to expand", NULL, false,\n'
    '                     -1);\n'
    '      igPopFont();\n',
    '      igCalcTextSize(&hint_size, "Tap on leaderboard to expand", NULL, false,\n'
    '                     -1);\n'
    '      igPopFont();\n'
    '      /* Widths in the sheet the board is drawn in (OM, 2026-11-01). */\n'
    '      hud_sheet_font = SHEET_THIN;\n'
    '      rank_size.x = hud_measure(rank_font, "10");\n'
    '      score_size.x = hud_measure(score_font, "999999");\n'
    '      name_size.x = hud_measure(name_font, widest);\n'
    '      title_size.x = hud_measure(label_font, "Wyrm Leaderboard");\n'
    '      position_size.x = hud_measure(label_font, "Your position  999 / 999");\n'
    '      hint_size.x = hud_measure(label_font, "Tap on leaderboard to expand");\n')
add('game/ui_overlay.c',
    '      /* A slate plate only where the floor is light (OM, 2026-10-02). */\n'
    '      if (wyrm_floor_light(env)) {\n',
    '      /* No plate on light floors any more (OM, 2026-11-01): the sheet\'s\n'
    '         type in its halo reads on its own. */\n'
    '      (void)wyrm_floor_light;\n'
    '      if (0) {\n')
add('game/ui_overlay.c',
    '        igPushFont(rank_font, rank_font->LegacySize);\n'
    '        igCalcTextSize(&measured, rank_text, NULL, false, -1);\n'
    '        igPopFont();\n',
    '        measured.x = hud_measure(rank_font, rank_text);\n')
add('game/ui_overlay.c', '        float score_width = measure(score_font, score_text_row);',
    '        float score_width = hud_measure(score_font, score_text_row);')
add('game/ui_overlay.c', '      float rank_width = measure(score_font, rank_text);',
    '      float rank_width = hud_measure(score_font, rank_text);')
add('game/ui_overlay.c',
    '      const char* labels[] = {"SCORE", "KILLS", "RANK", "TIME", "PING", "FPS"};',
    '      /* Ping in brackets (OM, 2026-11-01): "PING(ms)  64(ms)". */\n'
    '      const char* labels[] = {"SCORE", "KILLS", "RANK", "TIME", "PING(ms)", "FPS"};')
add('game/ui_overlay.c', '    snprintf(ping_text, sizeof(ping_text), "%d ms", gdata->data.ping);',
    '    snprintf(ping_text, sizeof(ping_text), "%d(ms)", gdata->data.ping);')
add('game/ui_overlay.c',
    '      ImVec2 sample = measure_scaled(value_font, "000000", stats_scale);\n'
    '      ImVec2 caption_size = measure_scaled(stats_label_font, user_settings_arena(usrs),\n'
    '                                           stats_scale);\n',
    '      ImVec2 sample = hud_measure_scaled(value_font, "000000", stats_scale, SHEET_BLACK);\n'
    '      ImVec2 caption_size = hud_measure_scaled(stats_label_font, user_settings_arena(usrs),\n'
    '                                               stats_scale, SHEET_THIN);\n')
add('game/ui_overlay.c',
    '        float row = measure_scaled(stats_label_font, labels[i], stats_scale).x +\n'
    '                    12.0f * stats_scale +\n'
    '                    measure_scaled(value_font, values[i], stats_scale).x;\n',
    '        float row = hud_measure_scaled(stats_label_font, labels[i], stats_scale, SHEET_THIN).x +\n'
    '                    12.0f * stats_scale +\n'
    '                    hud_measure_scaled(value_font, values[i], stats_scale, SHEET_BLACK).x;\n')
add('game/ui_overlay.c',
    '      ImDrawList_AddText_FontPtr(draw, stats_label_font,\n'
    '                                 stats_label_font->LegacySize * stats_scale,\n'
    '                                 (ImVec2){min.x + pad, min.y + pad * 0.7f},\n'
    '                                 android_team_stats_colour(ARENA_THEME_QUIET,\n'
    '                                                           0.78f * stats_alpha),\n'
    '                                 user_settings_arena(usrs), NULL, 0,\n'
    '                                 NULL);\n',
    '      hud_sheet_font = SHEET_THIN;\n'
    '      hud_text(draw, stats_label_font, stats_label_font->LegacySize * stats_scale,\n'
    '               (ImVec2){min.x + pad, min.y + pad * 0.7f},\n'
    '               android_team_stats_colour(ARENA_THEME_QUIET, 0.78f * stats_alpha),\n'
    '               user_settings_arena(usrs));\n')
# The leaderboard after the stats draws in the thin set again.
add('game/ui_overlay.c',
    '      for (int i = 0; i < 6; ++i) {\n'
    '        draw_stat_row(env, draw, max.x - pad, y, labels[i], values[i], 0.88f);\n'
    '        y += row_height;\n'
    '      }\n',
    '      for (int i = 0; i < 6; ++i) {\n'
    '        draw_stat_row(env, draw, max.x - pad, y, labels[i], values[i], 0.88f);\n'
    '        y += row_height;\n'
    '      }\n'
    '      hud_sheet_font = SHEET_THIN;\n')
# Wyrm's minimap: the original's disc for this floor.
add('game/ui_overlay.c',
    '  ImVec2 c = {left + R, top + R};\n'
    '  original_disc_shadow(draw, c, R + 1.5f, 2.0f, 5.0f, 0.30f);\n',
    '  ImVec2 c = {left + R, top + R};\n'
    '  /* The original\'s own disc for this floor (OM, 2026-11-01): the floor\n'
    '     blurred into it, so it reads on every floor (game/minimap_art.h). */\n'
    '  if (!minimap_art_draw(draw, env->usr->usrs.arena_background, c,\n'
    '                        R / MINIMAP_ART_R, 0.7f)) {\n'
    '  original_disc_shadow(draw, c, R + 1.5f, 2.0f, 5.0f, 0.30f);\n')
add('game/ui_overlay.c',
    '  ImDrawList_AddCircle(draw, c, R * 0.45f, faint, 48, 1.0f);\n',
    '  ImDrawList_AddCircle(draw, c, R * 0.45f, faint, 48, 1.0f);\n'
    '  }\n')
# Near Original: the original's bitmap and its "server N" line.
add('game/ui_overlay.c',
    '  /* The bitmap\'s shadow (0.5) under the bitmap\'s own alpha (0.7). */\n'
    '  original_disc_shadow(draw, c, R, 3.0f * k, 6.0f * k, 0.5f * 0.7f);\n',
    '  /* The original\'s own bitmap for this floor and its "server N" line\n'
    '     (OM, 2026-11-01), at the bitmap\'s alpha 0.7 (game/minimap_art.h). */\n'
    '  float art = (float)mmsz / (2.0f * MINIMAP_ART_R);\n'
    '  bool baked = minimap_art_draw(draw, usrs->arena_background, c, k * art, 0.7f);\n'
    '  if (baked) {\n'
    '    int baked_server = android_home_near_original_server();\n'
    '    if (baked_server > 0) minimap_art_server(draw, baked_server, c, k * art, 0.7f);\n'
    '  } else {\n'
    '  /* The bitmap\'s shadow (0.5) under the bitmap\'s own alpha (0.7). */\n'
    '  original_disc_shadow(draw, c, R, 3.0f * k, 6.0f * k, 0.5f * 0.7f);\n')
add('game/ui_overlay.c',
    '        igColorConvertFloat4ToU32((ImVec4){1, 1, 1, 0.75f * 0.7f}), label, NULL, 0, NULL);\n'
    '  }\n',
    '        igColorConvertFloat4ToU32((ImVec4){1, 1, 1, 0.75f * 0.7f}), label, NULL, 0, NULL);\n'
    '  }\n'
    '  }\n')


def apply(root, label='engine sheet HUD 2026-11-01', dry=False):
    root = Path(root)
    report = []
    for file, pairs in PAIRS.items():
        path = root / file
        raw = path.read_bytes().decode('utf-8')
        crlf = '\r\n' in raw
        text = raw.replace('\r\n', '\n')
        for old, new in pairs:
            every = isinstance(old, tuple)
            anchor = old[1] if every else old
            count = text.count(anchor)
            if (every and count < 1) or (not every and count != 1):
                raise SystemExit(f'{label}: {file}: {count} anchors: {anchor[:80]!r}')
            if new.replace(anchor, '') and anchor in new and text.count(new) >= (count if every else 1):
                raise SystemExit(f'{label}: {file}: already applied: {anchor[:60]!r}')
            text = text.replace(anchor, new) if every else text.replace(anchor, new, 1)
            report.append(file)
        if not dry:
            path.write_bytes((text.replace('\n', '\r\n') if crlf else text).encode('utf-8'))
    print(f'{label}: {len(report)} edits in {len(PAIRS)} files{" (dry run)" if dry else ""}')


if __name__ == '__main__':
    apply(sys.argv[1], dry='--dry' in sys.argv)
