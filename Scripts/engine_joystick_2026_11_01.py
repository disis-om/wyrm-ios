"""The joystick (OM, 2026-11-01): the original's look in Wyrm too, the knob that
follows the snake stays where it was let go, the reset knob goes back to the
middle, and Near Original's joystick can be moved and sized in the layout
editor (its own place; the original's until moved).

Applied after engine_sheet_hud_2026_11_01.py, on Wyrm Android's tree once and
on the prepared Apple tree by prepare-original-engine.py.
"""
from pathlib import Path
import sys

PAIRS = {}


def add(path, old, new):
    PAIRS.setdefault('app/src/' + path, []).append((old, new))


add('game/user_settings.h', '  bool food_original_v1;\n} user_settings_ext;',
    '  bool food_original_v1;\n'
    '  /* Near Original\'s joystick (OM, 2026-11-01): its place, 0..1 of the\n'
    '     screen (-1 = the original\'s), and its size (1 = the original\'s). */\n'
    '  float near_joy_x;\n'
    '  float near_joy_y;\n'
    '  float near_joy_size;\n'
    '} user_settings_ext;')
add('game/user_settings.c', '  x->food_original_v1 = true;\n',
    '  x->food_original_v1 = true;\n'
    '  x->near_joy_x = -1.0f;\n'
    '  x->near_joy_y = -1.0f;\n'
    '  x->near_joy_size = 1.0f;\n')
add('game/user_settings.c',
    '      ext->food_original_v1 = true;\n      fixed = 1;\n    }\n  }\n',
    '      ext->food_original_v1 = true;\n      fixed = 1;\n    }\n  }\n'
    '  {\n'
    '    /* Near Original\'s joystick (OM, 2026-11-01): missing = the original\'s. */\n'
    '    size_t nj_at = offsetof(user_settings_ext, near_joy_x);\n'
    '    fixed |= ext_take_float(&ext->near_joy_x, written >= nj_at + 4, -1.0f,\n'
    '                            1.0f, -1.0f);\n'
    '    fixed |= ext_take_float(&ext->near_joy_y, written >= nj_at + 8, -1.0f,\n'
    '                            1.0f, -1.0f);\n'
    '    fixed |= ext_take_float(&ext->near_joy_size, written >= nj_at + 12, 0.65f,\n'
    '                            1.45f, 1.0f);\n'
    '  }\n')
add('platform/android_settings.c',
    'SETTINGS_ARRAY_FIELD(ext.key_label_opacity, 16)},\n',
    'SETTINGS_ARRAY_FIELD(ext.key_label_opacity, 16)},\n'
    '    /* Near Original\'s joystick (OM, 2026-11-01): its place (-1 = the\n'
    '       original\'s) and size, set in the layout editor. */\n'
    '    {"layout.near_joystick_x", "layout", "", "", SETTING_FLOAT, -1.0f, 1.0f,\n'
    '     NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.near_joy_x)},\n'
    '    {"layout.near_joystick_y", "layout", "", "", SETTING_FLOAT, -1.0f, 1.0f,\n'
    '     NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.near_joy_y)},\n'
    '    {"layout.near_joystick_size", "layout", "", "", SETTING_FLOAT, 0.65f,\n'
    '     1.45f, NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.near_joy_size)},\n')
add('platform/android_settings.c',
    '    } else if (strcmp(id, "hud.chat") == 0) {\n'
    '      x = &settings->hud_chat_x;\n'
    '      y = &settings->hud_chat_y;\n'
    '    }\n',
    '    } else if (strcmp(id, "hud.chat") == 0) {\n'
    '      x = &settings->hud_chat_x;\n'
    '      y = &settings->hud_chat_y;\n'
    '    } else if (strcmp(id, "layout.near_joystick") == 0) {\n'
    '      x = &settings->ext.near_joy_x;\n'
    '      y = &settings->ext.near_joy_y;\n'
    '    }\n')

# Near Original: its place once moved, else the original's.
add('mobile/mobile_controls.c',
    'static void original_joystick_centre(tenv* env, float* x, float* y) {\n',
    'static void original_joystick_centre(tenv* env, float* x, float* y) {\n'
    '  /* Moved in the layout editor (OM, 2026-11-01): that place. */\n'
    '  const user_settings_ext* ext = &env->usr->usrs.ext;\n'
    '  if (ext->near_joy_x >= 0.0f && ext->near_joy_y >= 0.0f) {\n'
    '    *x = clampf(ext->near_joy_x, 0.0f, 1.0f) * env->wnd->size[0];\n'
    '    *y = clampf(ext->near_joy_y, 0.0f, 1.0f) * env->wnd->size[1];\n'
    '    return;\n'
    '  }\n')
add('mobile/mobile_controls.c',
    '    bool on_side = original_joystick_right(env)\n'
    '                       ? x >= env->wnd->size[0] * 0.5f\n'
    '                       : x < env->wnd->size[0] * 0.5f;\n',
    '    /* The half the joystick is on, wherever it was moved (OM, 2026-11-01). */\n'
    '    float side_x, side_y;\n'
    '    original_joystick_centre(env, &side_x, &side_y);\n'
    '    bool on_side = side_x >= env->wnd->size[0] * 0.5f\n'
    '                       ? x >= env->wnd->size[0] * 0.5f\n'
    '                       : x < env->wnd->size[0] * 0.5f;\n')
add('mobile/mobile_controls.c',
    '  float base = 64.0f * 0.7f * u;\n',
    '  /* Its size from the layout editor (OM, 2026-11-01), 1 = the original\'s. */\n'
    '  float js = env->usr->usrs.ext.near_joy_size;\n'
    '  if (!(js >= 0.65f && js <= 1.45f)) js = 1.0f;\n'
    '  u *= js;\n'
    '  float base = 64.0f * 0.7f * u;\n')

# Wyrm: the original's joystick, both knob modes.
add('mobile/mobile_controls.c', 'static void draw_joystick(tenv* env, ImDrawList* dl, float cx, float cy,\n',
    'static void original_halo(ImDrawList* dl, float cx, float cy, float radius,\n'
    '                          float spread, float alpha);\n'
    'static void draw_joystick(tenv* env, ImDrawList* dl, float cx, float cy,\n')
JOY_START = ('  draw_paper_disc(dl, cx, cy, radius, alpha, active);\n'
             '  /* How far the thumb may travel, at the faintest weight that still reads. */\n')
JOY_END = '\n}\n\nstatic void draw_boost('
JOY_NEW = (
    '  /* The original\'s joystick in Wyrm too (OM, 2026-11-01; Main.as\n'
    '     26514-26539): a #808080 disc and a white knob, each with a black halo;\n'
    '     the knob 0.40 of the disc, 0.54 of it out at full tilt. Size and\n'
    '     opacity are the player\'s (the default 0.62 is the original\'s 0.35). */\n'
    '  float a = clampf(alpha, 0.05f, 1.0f) * 0.35f / 0.62f;\n'
    '  if (a > 1.0f) a = 1.0f;\n'
    '  float base = radius * 0.73f;\n'
    '  float ax = state->joystick_axis[0];\n'
    '  float ay = state->joystick_axis[1];\n'
    '  float hx, hy;\n'
    '  bool still = fabsf(ax) < 0.08f && fabsf(ay) < 0.08f;\n'
    '  if (editor) {\n'
    '    ax = ay = 0.0f;\n'
    '  } else if (!active && !knob_follows_snake()) {\n'
    '    ax = ay = 0.0f; /* the reset knob: back to the middle */\n'
    '  } else if ((!state->aim_valid || still) && knob_follows_snake() &&\n'
    '             joystick_heading(env, &hx, &hy)) {\n'
    '    /* Nothing steered yet: where the snake goes. Once let go, the knob\n'
    '       stays exactly where it was (OM, 2026-11-01): no jump back to the\n'
    '       middle or to the head\'s still-turning angle. */\n'
    '    ax = hx;\n'
    '    ay = hy;\n'
    '  }\n'
    '  original_halo(dl, cx, cy, base, base * 0.109f, a);\n'
    '  ImDrawList_AddCircleFilled(dl, (ImVec2){cx, cy}, base,\n'
    '                             color_u32(0.502f, 0.502f, 0.502f, a), 48);\n'
    '  float knob = base * 0.402f;\n'
    '  float kx = cx + ax * base * 0.536f;\n'
    '  float ky = cy + ay * base * 0.536f;\n'
    '  original_halo(dl, kx, ky, knob, knob * 0.146f, a);\n'
    '  ImDrawList_AddCircleFilled(dl, (ImVec2){kx, ky}, knob, color_u32(1, 1, 1, a), 32);\n'
    '  (void)active;\n')
add('mobile/mobile_controls.c', ('SPAN', JOY_START, JOY_END), JOY_NEW)


def apply(root, label='engine joystick 2026-11-01', dry=False):
    root = Path(root)
    edits = 0
    for file, pairs in PAIRS.items():
        path = root / file
        raw = path.read_bytes().decode('utf-8')
        crlf = '\r\n' in raw
        text = raw.replace('\r\n', '\n')
        for old, new in pairs:
            if isinstance(old, tuple):
                _, start, end = old
                if text.count(start) != 1:
                    raise SystemExit(f'{label}: {file}: {text.count(start)} starts: {start[:70]!r}')
                a = text.index(start)
                b = text.index(end, a)
                text = text[:a] + new + text[b:]
            else:
                if text.count(old) != 1:
                    raise SystemExit(f'{label}: {file}: {text.count(old)} anchors: {old[:70]!r}')
                if old in new and text.count(new) >= 1:
                    raise SystemExit(f'{label}: {file}: already applied: {old[:60]!r}')
                text = text.replace(old, new, 1)
            edits += 1
        if not dry:
            path.write_bytes((text.replace('\n', '\r\n') if crlf else text).encode('utf-8'))
    print(f'{label}: {edits} edits in {len(PAIRS)} files{" (dry run)" if dry else ""}')


if __name__ == '__main__':
    apply(sys.argv[1], dry='--dry' in sys.argv)
