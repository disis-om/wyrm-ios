"""Wyrm's arrows the original's way (OM, 2026-11-01).

1. Wyrm's five arrow shapes are drawn with slither's arrow layers (Main.as
   arrow texture): a soft DropShadowFilter halo, a 9 px black outline, the fill,
   and the pulsing ADD copy while boosting. The Original style keeps its own
   path. Image arrows keep their pictures.
2. The arrow's colour is the snake's arrow_color (Main.as 20085-20120: a
   quarter white, three quarters the snake's colour, fixed overrides) until
   the player picks a colour. `ext.arrow_colour_own` (appended, default false,
   so every older settings file and account document starts on the snake's
   colour); the apps set it when the player picks a colour. Engine row
   `arrow.colour_own` (platform document, per key, per device).
3. The boost glow also follows Arrow's tap-boost.

Same text for Wyrm Android's tree (run once:
`python engine_arrow_look_2026_11_01.py "<Wyrm Android>"`) and the prepared
Apple tree (prepare-original-engine.py). Every anchor must occur once.
"""
from pathlib import Path
import sys

PAIRS = {}


def add(path, old, new):
    PAIRS.setdefault('app/src/' + path, []).append((old, new))


add('game/user_settings.h',
    '  float near_joy_size;\n} user_settings_ext;',
    '  float near_joy_size;\n'
    '  /* The arrow in the player\'s own colour (true) or the snake\'s, as\n'
    '     slither\'s (false, OM 2026-11-01). Set when a colour is picked. */\n'
    '  bool arrow_colour_own;\n'
    '} user_settings_ext;')
add('game/user_settings.c',
    '  x->near_joy_size = 1.0f;\n',
    '  x->near_joy_size = 1.0f;\n'
    '  x->arrow_colour_own = false;\n')
add('game/user_settings.c',
    '    fixed |= ext_take_float(&ext->near_joy_size, written >= nj_at + 12, 0.65f,\n'
    '                            1.45f, 1.0f);\n'
    '  }\n',
    '    fixed |= ext_take_float(&ext->near_joy_size, written >= nj_at + 12, 0.65f,\n'
    '                            1.45f, 1.0f);\n'
    '  }\n'
    '  /* Missing (every file before 2026-11-01) = the snake\'s colour. */\n'
    '  fixed |= ext_take_bool(&ext->arrow_colour_own,\n'
    '                         written >= offsetof(user_settings_ext, arrow_colour_own) + 1);\n')
add('platform/android_settings.c',
    '    {"arrow.color", "controls.arrow", "Arrow colour", "", SETTING_COLOR3, 0, 1,\n'
    '     NULL, OWNER_ARROW, ARROW_FIELD(color)},\n',
    '    {"arrow.color", "controls.arrow", "Arrow colour", "", SETTING_COLOR3, 0, 1,\n'
    '     NULL, OWNER_ARROW, ARROW_FIELD(color)},\n'
    '    /* OM, 2026-11-01: off = the snake\'s arrow colour, as slither\'s. */\n'
    '    {"arrow.colour_own", "controls.arrow", "My own arrow colour",\n'
    '     "Off: the arrow takes your snake\'s colour, as in slither. Picking a "\n'
    '     "colour turns it on.",\n'
    '     SETTING_BOOL, 0, 1, NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.arrow_colour_own)},\n')

add('mobile/mobile_controls.c',
    'static void draw_original_arrow(tenv* env, ImDrawList* dl);\n\nstatic void draw_arrow(',
    'static void draw_original_arrow(tenv* env, ImDrawList* dl);\n'
    'static ImU32 original_arrow_colour(tenv* env, float alpha);\n'
    '\n'
    '/* slither\'s arrow layers on any outline (OM, 2026-11-01), as\n'
    '   draw_original_arrow lays them: the DropShadowFilter halo as rings out\n'
    '   from the path along each corner\'s bisector (erfc profile, sigma 6 px,\n'
    '   at most 11.5 px past the outline), the 9 px black outline, the fill, and\n'
    '   while boosting the ADD copy (the colour doubled at `glow`). `s` is screen\n'
    '   px per texture px. `convex` fills in one call, else a fan from `centre`. */\n'
    'static void draw_layered_arrow(ImDrawList* dl, const ImVec2* p, int n,\n'
    '                               ImVec2 centre, float s, float alpha,\n'
    '                               ImU32 fill, float glow, bool convex) {\n'
    '  if (n < 3 || n > 8 || alpha <= 0.0f) return;\n'
    '  float area = 0.0f;\n'
    '  for (int i = 0; i < n; ++i) {\n'
    '    int next = (i + 1) % n;\n'
    '    area += p[i].x * p[next].y - p[next].x * p[i].y;\n'
    '  }\n'
    '  float side = area > 0.0f ? 1.0f : -1.0f;\n'
    '  const int bands = 6;\n'
    '  const float sigma = 6.0f, reach = 11.5f;\n'
    '  float before = 0.0f;\n'
    '  for (int j = bands; j >= 1; --j) {\n'
    '    float x = (j - 0.5f) * (reach / bands);\n'
    '    float want = alpha * 0.5f * erfcf(x / (sigma * 1.41421356f));\n'
    '    float a = before >= 0.999f ? 0.0f : 1.0f - (1.0f - want) / (1.0f - before);\n'
    '    if (a > 0.003f) {\n'
    '      float d = (4.5f + j * (reach / bands)) * s;\n'
    '      ImVec2 q[8];\n'
    '      for (int i = 0; i < n; ++i) {\n'
    '        int prev = (i + n - 1) % n, next = (i + 1) % n;\n'
    '        float e1x = p[i].x - p[prev].x, e1y = p[i].y - p[prev].y;\n'
    '        float e2x = p[next].x - p[i].x, e2y = p[next].y - p[i].y;\n'
    '        float l1 = sqrtf(e1x * e1x + e1y * e1y), l2 = sqrtf(e2x * e2x + e2y * e2y);\n'
    '        if (l1 < 0.0001f) l1 = 0.0001f;\n'
    '        if (l2 < 0.0001f) l2 = 0.0001f;\n'
    '        float n1x = e1y / l1, n1y = -e1x / l1;\n'
    '        float n2x = e2y / l2, n2y = -e2x / l2;\n'
    '        float bx = n1x + n2x, by = n1y + n2y;\n'
    '        float bl = sqrtf(bx * bx + by * by);\n'
    '        if (bl < 0.0001f) { bx = n1x; by = n1y; bl = 1.0f; }\n'
    '        q[i] = (ImVec2){p[i].x + bx / bl * d * side, p[i].y + by / bl * d * side};\n'
    '      }\n'
    '      ImU32 shade = color_u32(0, 0, 0, a);\n'
    '      for (int i = 0; i < n; ++i) {\n'
    '        int next = (i + 1) % n;\n'
    '        ImDrawList_AddTriangleFilled(dl, p[i], p[next], q[next], shade);\n'
    '        ImDrawList_AddTriangleFilled(dl, p[i], q[next], q[i], shade);\n'
    '      }\n'
    '    }\n'
    '    if (want > before) before = want;\n'
    '  }\n'
    '  ImDrawList_AddPolyline(dl, p, n, color_u32(0, 0, 0, alpha),\n'
    '                         ImDrawFlags_Closed, 9.0f * s);\n'
    '  for (int pass = 0; pass < 2; ++pass) {\n'
    '    ImU32 colour = fill;\n'
    '    if (pass == 1) {\n'
    '      if (glow <= 0.004f) break;\n'
    '      ImVec4 base;\n'
    '      igColorConvertU32ToFloat4(&base, fill);\n'
    '      colour = color_u32(base.x * 2.0f > 1.0f ? 1.0f : base.x * 2.0f,\n'
    '                         base.y * 2.0f > 1.0f ? 1.0f : base.y * 2.0f,\n'
    '                         base.z * 2.0f > 1.0f ? 1.0f : base.z * 2.0f, glow);\n'
    '    }\n'
    '    if (convex) {\n'
    '      ImDrawList_AddConvexPolyFilled(dl, p, n, colour);\n'
    '    } else {\n'
    '      for (int i = 0; i < n; ++i)\n'
    '        ImDrawList_AddTriangleFilled(dl, centre, p[i], p[(i + 1) % n], colour);\n'
    '    }\n'
    '  }\n'
    '}\n'
    '\n'
    'static void draw_arrow(')
add('mobile/mobile_controls.c',
    '''  if (env->usr->usrs.arrow_style == MOBILE_ARROW_CURRENT) {
    ImDrawList_AddConvexPolyFilled(dl, points, shape.count, fill);
  } else {
    for (int i = 0; i < shape.count; ++i)
      ImDrawList_AddTriangleFilled(dl, (ImVec2){ax, ay}, points[i],
                                   points[(i + 1) % shape.count], fill);
  }
  ImDrawList_AddPolyline(dl, points, shape.count,
                         color_u32(0.015f, 0.022f, 0.028f, alpha),
                         ImDrawFlags_Closed, 4.0f);
}
''',
    '''  /* The snake's arrow colour, as slither's, until the player picks one
     (OM, 2026-11-01); the brightness slider is for a picked colour. */
  if (!env->usr->usrs.ext.arrow_colour_own) fill = original_arrow_colour(env, alpha);
  /* slither's layers (OM, 2026-11-01): its 9 px outline and halo are for a
     52 px long arrow, so they scale with this one's length. */
  float lo = 0.0f, hi = 0.0f;
  for (int i = 0; i < shape.count; ++i) {
    if (shape.along[i] < lo) lo = shape.along[i];
    if (shape.along[i] > hi) hi = shape.along[i];
  }
  float s = (hi - lo) * length / 52.0f;
  float glow = alpha * original_accel_a * (0.5f + 0.5f * cosf(original_accel_fr));
  draw_layered_arrow(dl, points, shape.count, (ImVec2){ax, ay}, s, alpha, fill,
                     glow, env->usr->usrs.arrow_style == MOBILE_ARROW_CURRENT);
}
''')
add('mobile/mobile_controls.c',
    '    if (state->boost_down) {\n'
    '      original_boost_alpha += 0.01f * vfr;\n',
    '    /* Arrow\'s tap-boost glows too (OM, 2026-11-01). */\n'
    '    if (state->boost_down || (arrow_tap_boost && state->joystick_down)) {\n'
    '      original_boost_alpha += 0.01f * vfr;\n')


def apply(root, label='engine arrow look 2026-11-01', dry=False):
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
