"""HUD sizing, continuous names, Classic contact laser (OM 2026-11-01)."""
from pathlib import Path
import sys

PAIRS = {'app/src/game/user_settings.h': [('  bool arrow_colour_own;\n} user_settings_ext;',
                                   '  bool arrow_colour_own;\n'
                                   '  float name_scale;\n'
                                   '  bool name_scale_v1;\n'
                                   '  float chat_text_scale;\n'
                                   '} user_settings_ext;')],
 'app/src/game/user_settings.c': [('  x->arrow_colour_own = false;',
                                   '  x->arrow_colour_own = false;\n'
                                   '  x->name_scale = 1.0f;\n'
                                   '  x->name_scale_v1 = true;\n'
                                   '  x->chat_text_scale = 1.0f;'),
                                  ('    fixed |= ext_take_float(&ext->lb_size, true, .25f, 3.0f, '
                                   '.75f);',
                                   '    fixed |= ext_take_float(&ext->lb_size, true, .25f, 3.0f, '
                                   '.75f);\n'
                                   '    size_t name_at = offsetof(user_settings_ext, '
                                   'name_scale_v1);\n'
                                   '    unsigned char name_done = 0;\n'
                                   '    if (written >= name_at+1 && bytes_read >= '
                                   'ext_at+name_at+1)\n'
                                   '      memcpy(&name_done, &ext->name_scale_v1, 1);\n'
                                   '    if (name_done != 1) {\n'
                                   '      int old = settings->snake_names_font_size;\n'
                                   '      ext->name_scale = old == 0 ? .8f : old == 2 ? 1.2f : '
                                   '1.0f;\n'
                                   '      ext->name_scale_v1 = true;\n'
                                   '      fixed = 1;\n'
                                   '    }\n'
                                   '    fixed |= ext_take_float(&ext->name_scale, true, .5f, 2.5f, '
                                   '1.0f);\n'
                                   '    size_t chat_at = offsetof(user_settings_ext, '
                                   'chat_text_scale);\n'
                                   '    fixed |= ext_take_float(&ext->chat_text_scale, written >= '
                                   'chat_at+4,\n'
                                   '                            .5f, 2.5f, 1.0f);')],
 'app/src/platform/android_settings.c': [('    {"general.name_font", "general.type", "Player '
                                          'names", "", SETTING_ENUM, 0,\n'
                                          '     2, "Small|Regular|Large", OWNER_SETTINGS,\n'
                                          '     SETTINGS_FIELD(snake_names_font_size)},',
                                          '    {"general.name_font", "general.type", "Player '
                                          'names", "", SETTING_FLOAT, .5f,\n'
                                          '     2.5f, NULL, OWNER_SETTINGS, '
                                          'SETTINGS_FIELD(ext.name_scale)},\n'
                                          '    {"layout.chat_text_scale", "layout", "Chat text '
                                          'size", "", SETTING_FLOAT, .5f,\n'
                                          '     2.5f, NULL, OWNER_SETTINGS, '
                                          'SETTINGS_FIELD(ext.chat_text_scale)},')],
 'app/src/game/redraw.c': [('float size=13*z*unit/(textz > .001f ? textz : .001f);',
                            'float size=13*z*unit/(textz > .001f ? textz : '
                            '.001f)*usrs->ext.name_scale;'),
                           ('            float size = snake_name_font->LegacySize;',
                            '            float size = '
                            '13.0f*fminf(ctx->size[0],ctx->size[1])/480.0f/SHEET_EM*usrs->ext.name_scale;'),
                           ('usr->imgui_data.mono_font[usrs->snake_names_font_size];',
                            'usr->imgui_data.mono_font[FONT_SIZE_REGULAR];'),
                           ('usr->imgui_data.mono_font_bold[usrs->snake_names_font_size];',
                            'usr->imgui_data.mono_font_bold[FONT_SIZE_REGULAR];'),
                           ('  igPushFont(\n'
                            '      usr->imgui_data.mono_font[usrs->snake_names_font_size],\n'
                            '      '
                            'usr->imgui_data.mono_font[usrs->snake_names_font_size]->LegacySize);\n'
                            '  ImFont* snake_name_font =\n'
                            '      usr->imgui_data.mono_font[FONT_SIZE_REGULAR];\n'
                            '#if !defined(__ANDROID__)\n'
                            '  ImFont* snake_score_font =\n'
                            '      usr->imgui_data.mono_font_bold[FONT_SIZE_REGULAR];\n'
                            '  const float snake_name_font_size = snake_name_font->LegacySize;',
                            '  ImFont* snake_name_font = '
                            'usr->imgui_data.mono_font[FONT_SIZE_REGULAR];\n'
                            '#if defined(__ANDROID__)\n'
                            '  const float snake_name_font_size =\n'
                            '      '
                            '13.0f*fminf(ctx->size[0],ctx->size[1])/480.0f/SHEET_EM*usrs->ext.name_scale;\n'
                            '#else\n'
                            '  const float snake_name_font_size = '
                            'snake_name_font->LegacySize*usrs->ext.name_scale;\n'
                            '#endif\n'
                            '  /* Measure fallback strings at the same size that is actually '
                            'drawn. */\n'
                            '  igPushFont(snake_name_font, snake_name_font_size);\n'
                            '#if !defined(__ANDROID__)\n'
                            '  ImFont* snake_score_font =\n'
                            '      usr->imgui_data.mono_font_bold[FONT_SIZE_REGULAR];')],
 'app/src/mobile/mobile_controls.c': [('  for (int i = 0; i < 16; ++i)\n'
                                       '    if (classic_fingers[i].down && '
                                       '!classic_fingers[i].ignored) {\n'
                                       '      if (!state->aim_valid) return false;\n'
                                       '      *dx = state->joystick_axis[0];\n'
                                       '      *dy = state->joystick_axis[1];\n'
                                       '      return true;\n'
                                       '    }\n'
                                       '  return false;\n'
                                       '}',
                                       '  float x = 0, y = 0; int count = 0;\n'
                                       '  for (int i = 0; i < 16; ++i)\n'
                                       '    if (classic_fingers[i].down && '
                                       '!classic_fingers[i].ignored) {\n'
                                       '      x += classic_fingers[i].x; y += '
                                       'classic_fingers[i].y; ++count;\n'
                                       '    }\n'
                                       '  if (!count || !state->aim_valid) return false;\n'
                                       '  *dx = x/count; *dy = y/count;\n'
                                       '  return true;\n'
                                       '}'),
                                      ("sheet_glyph_centred('-', SHEET_BLACK, 2.0f * mark / 19.0f, "
                                       'minus.x, minus.y, white);',
                                       "sheet_glyph_fit('-', SHEET_BLACK, half*1.1f, half*1.1f, "
                                       'minus.x, minus.y, white);'),
                                      ("sheet_glyph_centred('+', SHEET_BLACK, 2.0f * mark / 26.0f, "
                                       'plus.x, plus.y, white);',
                                       "sheet_glyph_fit('+', SHEET_BLACK, half*1.1f, half*1.1f, "
                                       'plus.x, plus.y, white);'),
                                      ('    float mark = half * 0.9f;',
                                       '    /* Fit the complete baked glyph, including its halo, '
                                       'inside the track. */')],
 'app/src/game/ui_overlay.c': [('        float aim_x, aim_y;\n'
                                '        if (mobile_controls_classic_aim(env, &aim_x, &aim_y)) {\n'
                                '          lx = aim_x;\n'
                                '          ly = aim_y;\n'
                                '        }',
                                '        float aim_x = 0, aim_y = 0;\n'
                                '        bool classic = mobile_controls_steering_mode(env) == '
                                'MOBILE_STEERING_CLASSIC;\n'
                                '        bool contact = mobile_controls_classic_aim(env, &aim_x, '
                                '&aim_y);\n'
                                '        float head_x = '
                                'mww2+(hx-gdata->data.view_xx)*gdata->data.gsc;\n'
                                '        float head_y = '
                                'mhh2+(hy-gdata->data.view_yy)*gdata->data.gsc;\n'
                                '        float distance = hypotf(aim_x-head_x, aim_y-head_y);\n'
                                '        if (classic && contact && distance > .001f) {\n'
                                '          lx = (aim_x-head_x)/distance; ly = '
                                '(aim_y-head_y)/distance;\n'
                                '        }'),
                               ('        ImDrawList_AddLine(\n'
                                '            igGetWindowDrawList(), from,\n'
                                '            (ImVec2){from.x + lx * reach, from.y + ly * reach},',
                                '        if (!classic || (contact && distance > front)) '
                                'ImDrawList_AddLine(\n'
                                '            igGetWindowDrawList(), from,\n'
                                '            classic ? (ImVec2){aim_x, aim_y} : (ImVec2){from.x + '
                                'lx * reach, from.y + ly * reach},'),
                               ('minimap_art_server(draw, baked_server, c, k * art, 0.7f);',
                                'minimap_art_server(draw, baked_server, c, k, 0.7f);'),
                               ('bool original_hud = android_home_near_original();',
                                'bool original_hud = android_home_near_original() && '
                                '(!ai_mode_is_editor() || ai_mode_editor_bare());'),
                               ('      !env->usr->gdata.data.gotlb)\n    return false;',
                                '      !env->usr->gdata.data.gotlb || ai_mode_is_editor())\n'
                                '    return false;'),
                               ('float reveal = '
                                'leaderboard_expand*leaderboard_expand*(3-2*leaderboard_expand);',
                                'float reveal = ai_mode_is_editor() ? 1.0f : '
                                'leaderboard_expand*leaderboard_expand*(3-2*leaderboard_expand);'),
                               ('minimap_art_server(draw, baked_server, c, k, 0.7f);',
                                'minimap_art_server(draw, baked_server, c, k * art, k, 0.7f);')],
 'app/src/game/sheet_text.h': [("/* A vertical bar from the sheet's '|'",
                                '/* Fit the union of face and outline, including their different '
                                'pivots. */\n'
                                'static inline void sheet_glyph_fit(char ch, int font, float w, '
                                'float h,\n'
                                '                                    float cx, float cy, ImU32 '
                                'colour) {\n'
                                '  const original_glyph* face = &ORIGINAL_GLYPHS[font+(ch-32)*3];\n'
                                '  float left=1e9f, top=1e9f, right=-1e9f, bottom=-1e9f;\n'
                                '  for(int i=0;i<2;++i) {\n'
                                '    const original_glyph* g=face+i;\n'
                                '    left=fminf(left,-g->px*g->scale); '
                                'top=fminf(top,-g->py*g->scale);\n'
                                '    right=fmaxf(right,(g->w-g->px)*g->scale);\n'
                                '    bottom=fmaxf(bottom,(g->h-g->py)*g->scale);\n'
                                '  }\n'
                                '  float k=fminf(w/(right-left),h/(bottom-top));\n'
                                '  /* Centre the union, rather than the face, to keep the shadow '
                                'in bounds. */\n'
                                '  sheet_glyph_centred(ch,font,k,\n'
                                '      '
                                'cx-((left+right)*.5f-(face->w*.5f-face->px)*face->scale)*k,\n'
                                '      '
                                'cy-((top+bottom)*.5f-(face->h*.5f-face->py)*face->scale)*k,colour);\n'
                                '}\n'
                                '\n'
                                "/* A vertical bar from the sheet's '|' ")],
 'app/src/platform/android_team.c': [('  float text_size = regular->LegacySize * scale;',
                                      '  float text_size = regular->LegacySize * scale * '
                                      'env->usr->usrs.ext.chat_text_scale;')],
 'app/src/mobile/mobile_controls.h': [("   unit direction from the screen's centre to it. False "
                                       'otherwise.',
                                       '   mean steering contact in screen pixels. False when no '
                                       'contact is down.')],
 'app/src/game/minimap_art.h': [('float scale, float alpha) {\n'
                                 '  if (!wyrm_minimap_set || !draw || server <= 0)',
                                 'float scale, float label_scale, float alpha) {\n'
                                 '  if (!wyrm_minimap_set || !draw || server <= 0)'),
                                ('  ImVec2 tl = minimap_art_origin(centre, scale);\n'
                                 '  float pen = 2.0f + (MINIMAP_ART_W - 4.0f - width) * 0.5f;',
                                 '  ImVec2 tl = minimap_art_origin(centre, scale);\n'
                                 '  tl.x = centre.x - MINIMAP_ART_CX * label_scale;\n'
                                 '  float pen = 2.0f + (MINIMAP_ART_W - 4.0f - width) * 0.5f;'),
                                ('    ImVec2 a = {tl.x + (pen - p[4]) * scale, tl.y + (base - '
                                 'p[5]) * scale};\n'
                                 '    ImDrawList_AddImage(draw, tex, a, (ImVec2){a.x + p[2] * '
                                 'scale, a.y + p[3] * scale},\n'
                                 '                        (ImVec2){p[0] / 1024.0f, p[1] / '
                                 '1024.0f},\n'
                                 '                        (ImVec2){(p[0] + p[2]) / 1024.0f, (p[1] '
                                 '+ p[3]) / 1024.0f}, tint);\n',
                                 '    ImVec2 a = {tl.x + (pen - p[4]) * label_scale, tl.y + (base '
                                 '- p[5]) * label_scale};\n'
                                 '    ImDrawList_AddImage(draw, tex, a, (ImVec2){a.x + p[2] * '
                                 'label_scale, a.y + p[3] * label_scale},\n'
                                 '                        (ImVec2){p[0] / 1024.0f, p[1] / '
                                 '1024.0f},\n'
                                 '                        (ImVec2){(p[0] + p[2]) / 1024.0f, (p[1] '
                                 '+ p[3]) / 1024.0f}, tint);\n')]}

def apply(root, dry=False):
    pairs = PAIRS
    pending = []
    for file, changes in pairs.items():
        path = Path(root) / file
        text = path.read_text(encoding='utf-8')
        # Preparation selects WYRM_MOBILE before applying engine pairs.
        if file == 'app/src/game/redraw.c' and '#if !defined(WYRM_MOBILE)' in text:
            changes = [(old.replace('defined(__ANDROID__)', 'defined(WYRM_MOBILE)'),
                        new.replace('defined(__ANDROID__)', 'defined(WYRM_MOBILE)'))
                       for old, new in changes]
        # Dry-run accepts fresh or applied trees; reconstruct the predecessor
        # in memory, then prove every original anchor occurs exactly once.
        if dry:
            trial = text
            for old, new in changes:
                if trial.count(old) != 1:
                    for before, after in reversed(changes):
                        if text.count(after) != 1:
                            raise SystemExit(f'controls refine: {file}: invalid applied anchor {after[:70]!r}')
                        text = text.replace(after, before, 1)
                    break
                trial = trial.replace(old, new, 1)
        for old, new in changes:
            count = text.count(old)
            if count != 1:
                raise SystemExit(f'controls refine: {file}: {count} anchors: {old[:90]!r}')
            text = text.replace(old, new, 1)
        pending.append((path, text))
    if not dry:
        for path, text in pending:
            path.write_text(text, encoding='utf-8')
    print(f'controls refine: {sum(map(len, pairs.values()))} single anchors / {len(pairs)} files; dry={dry}')


if __name__ == '__main__':
    apply(sys.argv[1], '--dry' in sys.argv)
