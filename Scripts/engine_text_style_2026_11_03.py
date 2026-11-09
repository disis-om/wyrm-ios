"""Shared Wyrm text choice. Applied once to Android and last in iOS prepare."""
from pathlib import Path
import sys
PAIRS = {'app/src/game/sheet_text.h': [('extern float wyrm_sheet_veil;',
                                'extern float wyrm_sheet_veil;\nextern bool wyrm_high_visibility_text;'),
                               ('  if (!text || !text[0]) return false;',
                                '  if (!wyrm_high_visibility_text || !text || !text[0]) return false;'),
                               ('  if (ch < 33 || ch > 126 || !wyrm_text_normal || !wyrm_text_add ||',
                                '  if (!wyrm_high_visibility_text) {\n'
                                '    if (ch < 33 || ch > 126 || !isfinite(k) || k <= 0) return;\n'
                                '    char text[2] = {ch, 0};\n'
                                '    ImFont* face = igGetFont();\n'
                                '    float size = fmaxf(1.0f, k * 52.0f / SHEET_EM);\n'
                                '    ImVec2 bounds;\n'
                                '    ImFont_CalcTextSizeA(&bounds, face, size, 1e9f, 0, text, NULL, NULL);\n'
                                '    ImDrawList_AddText_FontPtr(igGetWindowDrawList(), face, size,\n'
                                '        (ImVec2){cx-bounds.x*.5f, cy-bounds.y*.5f}, colour, text, NULL, 0, '
                                'NULL);\n'
                                '    return;\n'
                                '  }\n'
                                '  if (ch < 33 || ch > 126 || !wyrm_text_normal || !wyrm_text_add ||'),
                               ('  const original_glyph* face = &ORIGINAL_GLYPHS[font+(ch-32)*3];',
                                '  if (!wyrm_high_visibility_text) {\n'
                                '    float k = fminf(w, h) / 52.0f;\n'
                                '    sheet_glyph_centred(ch, font, k, cx, cy, colour);\n'
                                '    return;\n'
                                '  }\n'
                                '  const original_glyph* face = &ORIGINAL_GLYPHS[font+(ch-32)*3];'),
                               ('  if (!wyrm_text_normal || !wyrm_text_add || !(colour & 0xFF000000u) ||\n'
                                '      y1 <= y0 || width <= 0.0f) return;',
                                '  if (!wyrm_high_visibility_text) {\n'
                                '    if (width > 0 && y1 > y0)\n'
                                '      ImDrawList_AddLine(igGetWindowDrawList(), (ImVec2){x,y0}, '
                                '(ImVec2){x,y1}, colour, width);\n'
                                '    return;\n'
                                '  }\n'
                                '  if (!wyrm_text_normal || !wyrm_text_add || !(colour & 0xFF000000u) ||\n'
                                '      y1 <= y0 || width <= 0.0f) return;')],
 'app/src/game/user_settings.c': [('  x->arrow_double_tap_boost_v1 = true;',
                                   '  x->arrow_double_tap_boost_v1 = true;\n  x->native_text_style = 1;'),
                                  ('    size_t food_at = offsetof(user_settings_ext, food_original_v1);',
                                   '    size_t text_at = offsetof(user_settings_ext, native_text_style);\n'
                                   '    fixed |= ext_take_int(&ext->native_text_style,\n'
                                   '                          written >= text_at + '
                                   'sizeof(ext->native_text_style) &&\n'
                                   '                          bytes_read >= ext_at + text_at + '
                                   'sizeof(ext->native_text_style),\n'
                                   '                          0, 1, 1);\n'
                                   '    size_t food_at = offsetof(user_settings_ext, food_original_v1);')],
 'app/src/game/user_settings.h': [('  bool arrow_double_tap_boost_v1;\n} user_settings_ext;',
                                   '  bool arrow_double_tap_boost_v1;\n'
                                   '  /* Append after legacy tail padding; 0 Normal, 1 High visibility '
                                   'texts. */\n'
                                   '  int32_t native_text_style;\n'
                                   '} user_settings_ext;')],
 'app/src/main.c': [('extern float wyrm_sheet_veil; /* rendering/renderer.c */',
                     'extern float wyrm_sheet_veil; /* rendering/renderer.c */\n'
                     'extern bool wyrm_high_visibility_text;'),
                    ('  android_settings_poll(env);',
                     '  android_settings_poll(env);\n'
                     '  /* Apply before measuring or drawing any text in this frame. */\n'
                     '  wyrm_high_visibility_text = android_home_near_original() ||\n'
                     '                              usr->usrs.ext.native_text_style == 1;')],
 'app/src/platform/android_settings.c': [('    {"general.snake_scores", "general", "Show snake scores",',
                                          '    {"general.native_text_style", "general", "Arena text", \n'
                                          '     "Text in Wyrm mode. Near Original keeps its original '
                                          'text.",\n'
                                          '     SETTING_ENUM, 0, 1, "Normal|High visibility texts", '
                                          'OWNER_SETTINGS,\n'
                                          '     SETTINGS_FIELD(ext.native_text_style)},\n'
                                          '    {"general.snake_scores", "general", "Show snake scores",')],
 'app/src/rendering/renderer.c': [('float wyrm_sheet_veil = 1.0f;',
                                   'float wyrm_sheet_veil = 1.0f;\nbool wyrm_high_visibility_text = true;')]}

def apply(root, dry=False):
    pending=[]
    for file, pairs in PAIRS.items():
        path=Path(root)/file
        text=path.read_text(encoding='utf-8')
        if dry and all(text.count(new)==1 for old,new in pairs):
            for old,new in reversed(pairs): text=text.replace(new,old,1)
        for old,new in pairs:
            assert text.count(old)==1,(file,text.count(old),old[:90])
            text=text.replace(old,new,1)
        pending.append((path,text))
    if not dry:
        for path,text in pending:path.write_text(text,encoding='utf-8')
    print('Text style: '+str(sum(map(len,PAIRS.values())))+' paired anchors; dry='+str(dry))
if __name__=='__main__':apply(sys.argv[1],'--dry' in sys.argv)
