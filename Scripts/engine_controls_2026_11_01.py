"""Classic absolute steering and release ownership fixes; applied on both clients."""
from pathlib import Path

PAIRS = {}
def add(path, old, new):
    PAIRS.setdefault('app/src/' + path, []).append((old, new))

add('game/input.c', '               gdata->bot.output.accel);',
    '               (usrs->hotkeys[HOTKEY_BOT].active && gdata->bot.output.accel));')
add('game/user_settings.h', '  MOBILE_STEERING_ARROW = 2',
    '  MOBILE_STEERING_ARROW = 2,\n  MOBILE_STEERING_CLASSIC = 3')
for file in ['game/user_settings.c', 'platform/android_update.c']:
    add(file, '> MOBILE_STEERING_ARROW', '> MOBILE_STEERING_CLASSIC')
add('platform/android_settings.c', '"How you point the snake.", SETTING_ENUM, 0, 2,\n     "Joystick under finger|Fixed joystick|Arrow drag"',
    '"How you point the snake.", SETTING_ENUM, 0, 3,\n     "Joystick under finger|Fixed joystick|Arrow drag|Classic"')
add('mobile/mobile_controls.c', '  if (env->wnd->size[1] > env->wnd->size[0]) return MOBILE_STEERING_ARROW;',
    '  if (env->wnd->size[1] > env->wnd->size[0] &&\n      env->usr->usrs.mobile_controls.joystick_mode != MOBILE_STEERING_CLASSIC)\n    return MOBILE_STEERING_ARROW;')
add('mobile/mobile_controls.c', 'static bool arrow_tap_boost;', '''/* Main.as mode 1: mean absolute positions of every non-button finger,
   relative to the screen centre. IDs are owned until up/cancel, never timed out. */
static struct { uint64_t id; float x, y; bool down; } classic_fingers[16];
static bool arrow_tap_boost;''')
add('mobile/mobile_controls.c', '  arrow_tap_boost = false;\n  state->joystick_down = false;',
    '  arrow_tap_boost = false;\n  arrow_last_down_ms = 0;\n  memset(classic_fingers, 0, sizeof(classic_fingers));\n  state->joystick_down = false;')
add('mobile/mobile_controls.c', '/* Near Original touch (Main.as touch begin):', '''/* No position/hit-test: the original owner receives up/cancel across panels. */
static void release_owned_touch(mobile_controls_state* state, uint64_t finger) {
  if (state->joystick_down && state->joystick_finger == finger) {
    state->joystick_down = false; arrow_tap_boost = false;
  }
  if (state->boost_down && state->boost_finger == finger) state->boost_down = false;
  if (state->zoom_down && state->zoom_finger == finger) state->zoom_down = false;
}

static bool classic_touch(tenv* env, const SDL_Event* event, uint64_t finger,
                          float x, float y) {
  mobile_controls_state* state = &env->usr->mobile_controls;
  int slot = -1;
  for (int i = 0; i < 16; ++i)
    if (classic_fingers[i].down && classic_fingers[i].id == finger) { slot = i; break; }
  if (event->type == SDL_EVENT_FINGER_DOWN && slot < 0) {
    float bx, by;
    bool original = android_home_near_original();
    if (original) original_boost_centre(env, &bx, &by);
    else normalized_position(env, env->usr->usrs.mobile_controls.boost_x,
                                  env->usr->usrs.mobile_controls.boost_y, &bx, &by);
    bool shown = original || env->usr->usrs.mobile_controls.boost_mode == MOBILE_BOOST_FIXED;
    float radius = original ? 160.0f * original_unit(env) :
        112.0f * control_scale(env) * env->usr->usrs.mobile_controls.boost_size;
    if (shown && !state->boost_down && inside_circle(x, y, bx, by, radius)) {
      state->boost_down = true; state->boost_finger = finger; return true;
    }
    if (!state->zoom_down && inside_zoom(env, x, y)) {
      state->zoom_down = true; state->zoom_finger = finger;
      set_zoom_from_touch(env, x, y); return true;
    }
    for (int i = 0; i < 16; ++i) if (!classic_fingers[i].down) { slot = i; break; }
    if (slot >= 0) { classic_fingers[slot].id = finger; classic_fingers[slot].down = true; }
  }
  if (slot < 0) return false;
  classic_fingers[slot].x = x; classic_fingers[slot].y = y;
  if (event->type == SDL_EVENT_FINGER_UP || event->type == SDL_EVENT_FINGER_CANCELED)
    classic_fingers[slot].down = false;
  float dx = 0, dy = 0; int count = 0;
  for (int i = 0; i < 16; ++i) if (classic_fingers[i].down) {
    dx += classic_fingers[i].x - env->wnd->size[0] * 0.5f;
    dy += classic_fingers[i].y - env->wnd->size[1] * 0.5f; ++count;
  }
  if (count) {
    float length = sqrtf(dx * dx + dy * dy);
    if (length > 0.5f) {
      state->joystick_axis[0] = dx / length; state->joystick_axis[1] = dy / length;
      state->aim_valid = true;
    }
  }
  return true;
}

/* Near Original touch (Main.as touch begin):''')
add('mobile/mobile_controls.c', '  /* Playable AI\'s first-entry notice owns the whole touch surface.', '''  /* Releases belong to the input owner even when a panel now covers it.
     Clear before any UI consumer can swallow the event. */
  if (event->type == SDL_EVENT_FINGER_UP || event->type == SDL_EVENT_FINGER_CANCELED) {
    release_owned_touch(state, finger);
    mobile_hotkeys_process_event(env, raw_event);
    if (mobile_controls_steering_mode(env) == MOBILE_STEERING_CLASSIC)
      classic_touch(env, event, finger, x, y);
  }

  /* Playable AI's first-entry notice owns the whole touch surface.''')
add('mobile/mobile_controls.c', '  /* Near Original: slither\'s own fixed controls (releases fall through). */', '''  if (mobile_controls_steering_mode(env) == MOBILE_STEERING_CLASSIC) {
    if (state->zoom_down && state->zoom_finger == finger && event->type == SDL_EVENT_FINGER_MOTION) {
      set_zoom_from_touch(env, x, y); return true;
    }
    return classic_touch(env, event, finger, x, y);
  }

  /* Near Original: slither's own fixed controls (releases fall through). */''')
add('mobile/mobile_controls.c', '    state->joystick_down = false;\n    state->boost_down = false;\n    state->zoom_down = false;\n    state->aim_valid = false;',
    '    reset_touches(state);\n    state->aim_valid = false;')
add('mobile/mobile_controls.c', '  else if (inside_circle(x, y, bx, by, 105.0f * scale * cfg->boost_size))',
    '  else if (inside_circle(x, y, bx, by, 105.0f * scale * cfg->boost_size))')


add('mobile/mobile_controls.c', 'static bool arrow_tap_boost;', 'static uint64_t classic_boost_finger;\nstatic bool arrow_tap_boost;')
add('mobile/mobile_controls.c', '    if (slot >= 0) { classic_fingers[slot].id = finger; classic_fingers[slot].down = true; }', '''    if (slot >= 0) {
      bool alone = true;
      for(int i=0;i<16;++i) if(classic_fingers[i].down) alone=false;
      arrow_note_down(env,x,y,alone && !state->boost_down && !state->zoom_down);
      if(arrow_tap_boost) classic_boost_finger=finger;
      classic_fingers[slot].id = finger; classic_fingers[slot].down = true;
    }''')
add('mobile/mobile_controls.c', '    classic_fingers[slot].down = false;', '''    { classic_fingers[slot].down = false;
      if(classic_boost_finger==finger) arrow_tap_boost=false;
    }''')
add('mobile/mobile_controls.c', "  /* Arrow mode's double tap boosts while its finger is down (Main.as). */", '''  if (arrow_tap_boost && mobile_controls_steering_mode(env) == MOBILE_STEERING_CLASSIC)
    for(int i=0;i<16;++i) if(classic_fingers[i].down && classic_fingers[i].id==classic_boost_finger) return true;
  /* Arrow mode's double tap boosts while its finger is down (Main.as). */''')

# Ask SDL about actual live fingers, not elapsed hold time: a missed up/cancel
# is repaired while a genuinely held boost remains held for as long as needed.
add('mobile/mobile_controls.c', '  /*\n   * Outside a live match, nothing may still be holding a gameplay control.', '''#ifdef WYRM_SDL_JNI
  static Uint64 last_touch_audit;
  Uint64 now = SDL_GetTicks();
  if (now-last_touch_audit >= 100) {
    last_touch_audit=now;
    uint64_t live[64]; int live_count=0, device_count=0;
    SDL_TouchID* devices=SDL_GetTouchDevices(&device_count);
    for(int d=0;devices && d<device_count;++d) {
      int count=0; SDL_Finger** fingers=SDL_GetTouchFingers(devices[d],&count);
      for(int f=0;fingers && f<count && live_count<64;++f) live[live_count++]=(uint64_t)fingers[f]->id;
      SDL_free(fingers);
    }
    SDL_free(devices);
    uint64_t owners[3]={state->joystick_finger,state->boost_finger,state->zoom_finger};
    for(int i=0;i<3;++i) {
      bool found=false; for(int j=0;j<live_count;++j) if(owners[i]==live[j]) found=true;
      if(!found) release_owned_touch(state,owners[i]);
    }
    for(int i=0;i<16;++i) if(classic_fingers[i].down) {
      bool found=false; for(int j=0;j<live_count;++j) if(classic_fingers[i].id==live[j]) found=true;
      if(!found) { if(classic_boost_finger==classic_fingers[i].id) arrow_tap_boost=false; classic_fingers[i].down=false; }
    }
    mobile_hotkeys_state* keys=&env->usr->mobile_hotkeys;
    for(int i=0;i<NUM_MOBILE_ACTIONS;++i) if(keys->down[i]) {
      bool found=false; for(int j=0;j<live_count;++j) if(keys->finger[i]==live[j]) found=true;
      if(!found) keys->down[i]=false;
    }
  }
#endif

  /*
   * Outside a live match, nothing may still be holding a gameplay control.''')

add('mobile/mobile_controls.c', '  else\n    draw_original_joystick(env, dl);', '  else if (mobile_controls_steering_mode(env) != MOBILE_STEERING_CLASSIC)\n    draw_original_joystick(env, dl);')

add('mobile/mobile_controls.c', 'static struct { uint64_t id; float x, y; bool down; } classic_fingers[16];', 'static struct { uint64_t id; float x, y; bool down, ignored; } classic_fingers[16];')
add('mobile/mobile_controls.c', '      classic_fingers[slot].id = finger; classic_fingers[slot].down = true;', '      float px=0,py=0; int count=0;\n      for(int i=0;i<16;++i) if(classic_fingers[i].down && !classic_fingers[i].ignored) {\n        px+=classic_fingers[i].x; py+=classic_fingers[i].y; ++count;\n      }\n      float dx=count ? x-px/count : 0, dy=count ? y-py/count : 0;\n      float reach=180*original_unit(env);\n      classic_fingers[slot].ignored=count && dx*dx+dy*dy>reach*reach;\n      classic_fingers[slot].id = finger; classic_fingers[slot].down = true;')
add('mobile/mobile_controls.c', '  for (int i = 0; i < 16; ++i) if (classic_fingers[i].down) {\n    dx +=', '  for (int i = 0; i < 16; ++i) if (classic_fingers[i].down && !classic_fingers[i].ignored) {\n    dx +=')

def apply(root, label='controls 2026-11-01'):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        text = path.read_text(encoding='utf-8')
        # iOS selects SDL using WYRM_MOBILE; none of these edits changes a platform macro.
        for old, new in pairs:
            if not (Path(root) / 'android').exists():
                old = old.replace('WYRM_SDL_JNI', 'WYRM_MOBILE')
                new = new.replace('WYRM_SDL_JNI', 'WYRM_MOBILE')
            if old == new: continue
            if text.count(old) != 1:
                raise SystemExit(f'{label}: expected one anchor in {relative}: {old[:100]!r} ({text.count(old)})')
            text = text.replace(old, new, 1)
        path.write_text(text, encoding='utf-8')

if __name__ == '__main__':
    import sys
    apply(Path(sys.argv[1]))
