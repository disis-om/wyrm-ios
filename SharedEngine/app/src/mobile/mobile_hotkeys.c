#include "mobile_hotkeys.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "../game/arena_theme.h"
#include "../user.h"

#ifdef VLITHER_ANDROID
#include <SDL3/SDL.h>
#endif

static const char* ACTION_NAMES[NUM_MOBILE_ACTIONS] = {
    "HUD",         "Show names", "Big food",   "Assist",     "Bot",
    "Hotkey menu", "Restart",    "Quit",       "Zoom in",    "Zoom out",
    "Boost",       "Turn left",  "Turn right", "Fullscreen", "Rope mode"};

bool mobile_hotkey_is_on_screen_button(int action) {
  return action == HOTKEY_SHOW_NAMES || action == HOTKEY_BIG_FOOD ||
         action == HOTKEY_ASSIST || action == HOTKEY_BOT ||
         action == HOTKEY_RESTART || action == HOTKEY_QUIT ||
         action == MOBILE_HOTKEY_ZOOM_IN ||
         action == MOBILE_HOTKEY_ZOOM_OUT;
}

static float clampf_local(float value, float lo, float hi) {
  return value < lo ? lo : (value > hi ? hi : value);
}

static float button_scale(tenv* env) {
  return clampf_local(env->wnd->size[1] / 720.0f, 0.82f, 1.45f);
}

static void action_geometry(tenv* env, int action, float* cx, float* cy,
                            float* width, float* height) {
  float x = 0.5f;
  float y = 0.22f;
  mobile_hotkey_get_layout(&env->usr->usrs, action, NULL, &x, &y);
  *cx = clampf_local(x, 0.0f, 1.0f) * env->wnd->size[0];
  *cy = clampf_local(y, 0.0f, 1.0f) * env->wnd->size[1];
  float scale = button_scale(env) *
                clampf_local(env->usr->usrs.hotkey_scale[action], 0.65f, 1.60f);
  *width = 104.0f * scale;
  *height = 54.0f * scale;
}

static bool hit_action(tenv* env, int action, float x, float y) {
  float cx, cy, width, height;
  action_geometry(env, action, &cx, &cy, &width, &height);
  return fabsf(x - cx) <= width * 0.5f && fabsf(y - cy) <= height * 0.5f;
}

void mobile_hotkeys_init(tenv* env) {
  memset(&env->usr->mobile_hotkeys, 0, sizeof(env->usr->mobile_hotkeys));
  env->usr->mobile_hotkeys.editor_focus = -1;
}

void mobile_hotkeys_reset_runtime(tenv* env) {
  mobile_hotkeys_state* state = &env->usr->mobile_hotkeys;
  memset(state->down, 0, sizeof(state->down));
  memset(state->pressed, 0, sizeof(state->pressed));
  memset(state->finger, 0, sizeof(state->finger));
}

bool mobile_hotkeys_down(tenv* env, int action) {
  return action >= 0 && action < NUM_MOBILE_ACTIONS &&
         env->usr->mobile_hotkeys.down[action];
}

bool mobile_hotkeys_pressed(tenv* env, int action) {
  if (action < 0 || action >= NUM_MOBILE_ACTIONS) return false;
  bool pressed = env->usr->mobile_hotkeys.pressed[action];
  env->usr->mobile_hotkeys.pressed[action] = false;
  return pressed;
}

#ifdef VLITHER_ANDROID
bool mobile_hotkeys_process_event(tenv* env, const void* raw_event) {
  const SDL_Event* event = raw_event;
  if (event->type == SDL_EVENT_WILL_ENTER_BACKGROUND ||
      event->type == SDL_EVENT_WINDOW_FOCUS_LOST) {
    mobile_hotkeys_reset_runtime(env);
    return false;
  }
  if (event->type != SDL_EVENT_FINGER_DOWN &&
      event->type != SDL_EVENT_FINGER_MOTION &&
      event->type != SDL_EVENT_FINGER_UP &&
      event->type != SDL_EVENT_FINGER_CANCELED)
    return false;
  if (env->usr->gdata.curr_screen != PLAYING ||
      (env->usr->gdata.conn != CONNECTED &&
       env->usr->gdata.conn != AI_CONNECTED))
    return false;

  mobile_hotkeys_state* state = &env->usr->mobile_hotkeys;
  uint64_t finger = (uint64_t)event->tfinger.fingerID;
  float x = event->tfinger.x * env->wnd->size[0];
  float y = event->tfinger.y * env->wnd->size[1];

  if (event->type == SDL_EVENT_FINGER_DOWN) {
    for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action) {
      if (!mobile_hotkey_is_on_screen_button(action)) continue;
      if (!WYRM_EXPERIMENTAL_ROPE_MODE &&
          action == MOBILE_HOTKEY_ROPE_MODE)
        continue;
      bool visible = false;
      mobile_hotkey_get_layout(&env->usr->usrs, action, &visible, NULL, NULL);
      if (!visible || state->down[action] || !hit_action(env, action, x, y))
        continue;
      state->finger[action] = finger;
      state->down[action] = true;
      state->pressed[action] = true;
      return true;
    }
    return false;
  }

  for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action) {
    if (!state->down[action] || state->finger[action] != finger) continue;
    if (event->type == SDL_EVENT_FINGER_UP ||
        event->type == SDL_EVENT_FINGER_CANCELED)
      state->down[action] = false;
    return true;
  }
  return false;
}
#else
bool mobile_hotkeys_process_event(tenv* env, const void* event) {
  (void)env;
  (void)event;
  return false;
}
#endif

static ImU32 color(float r, float g, float b, float a) {
  return igColorConvertFloat4ToU32((ImVec4){r, g, b, a});
}

static bool action_active(tenv* env, int action) {
  if (action >= 0 && action < NUM_HOTKEYS)
    return env->usr->usrs.hotkeys[action].active;
  if (action == MOBILE_HOTKEY_ROPE_MODE)
    return env->usr->mobile_hotkeys.rope_mode;
  if (action >= NUM_HOTKEYS && action < NUM_MOBILE_ACTIONS)
    return mobile_hotkeys_down(env, action) ||
           twindow_key_down(env->wnd,
                            mobile_hotkey_get_key(&env->usr->usrs, action));
  return false;
}

void mobile_hotkeys_draw_gameplay(tenv* env) {
#ifdef VLITHER_ANDROID
  if (env->usr->gdata.curr_screen != PLAYING ||
      (env->usr->gdata.conn != CONNECTED &&
       env->usr->gdata.conn != AI_CONNECTED))
    return;
  mobile_hotkeys_state* state = &env->usr->mobile_hotkeys;
  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(igGetMainViewport());
  for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action) {
    if (!mobile_hotkey_is_on_screen_button(action)) continue;
    if (!WYRM_EXPERIMENTAL_ROPE_MODE && action == MOBILE_HOTKEY_ROPE_MODE)
      continue;
    bool visible = false;
    mobile_hotkey_get_layout(&env->usr->usrs, action, &visible, NULL, NULL);
    if (!visible) continue;
    float cx, cy, width, height;
    action_geometry(env, action, &cx, &cy, &width, &height);
    bool active = action_active(env, action);
    bool pressed = state->down[action];
    float alpha = clampf_local(env->usr->usrs.hotkey_opacity[action], 0.05f, 1.0f);
    ImVec2 min = {cx - width * 0.5f, cy - height * 0.5f};
    ImVec2 max = {cx + width * 0.5f, cy + height * 0.5f};
    float corner = height * 0.30f;
    /* Paper paint inside the exact same rectangle used by hit_action(). Input,
       mode and placement are deliberately not part of this draw function. */
    ImDrawList_AddRectFilled(draw, (ImVec2){min.x, min.y + height * 0.07f},
                             (ImVec2){max.x, max.y + height * 0.07f},
                             color(0, 0, 0, alpha * 0.16f), corner, 0);
    ImDrawList_AddRectFilled(
        draw, min, max,
        active || pressed
            ? arena_theme_colour(ARENA_THEME_INK, alpha * 0.96f)
            : arena_theme_colour(ARENA_THEME_CARD, alpha * 0.94f),
        corner, 0);
    ImDrawList_AddRect(draw, min, max,
                       arena_theme_colour(ARENA_THEME_INK,
                                          active || pressed ? 0.82f : 0.48f),
                       corner, 0, 1.5f);
    const char* function = mobile_hotkey_action_name(action);
    /* Dark type on a lit key, light type on a dim one. */
    /* Opacity belongs to the surface only. Keeping type and outline at full
       theme contrast means a nearly transparent key is still identifiable. */
    ImU32 primary = arena_theme_colour(ARENA_THEME_INK, 1.0f);
    ImFont* font = env->usr->imgui_data.body_font[FONT_SIZE_REGULAR];
    igPushFont(font, font->LegacySize);
    ImVec2 size;
    igCalcTextSize(&size, function, NULL, false, -1);
    igPopFont();
    ImDrawList_AddText_FontPtr(
        draw, font, font->LegacySize,
        (ImVec2){cx - size.x * 0.5f, cy - size.y * 0.5f}, primary, function,
        NULL, 0, NULL);
  }
#else
  (void)env;
#endif
}

void mobile_hotkeys_begin_editor(tenv* env, int focus_action) {
  mobile_hotkeys_state* state = &env->usr->mobile_hotkeys;
  state->edit_backup = env->usr->usrs.mobile_hotkeys;
  state->rope_mode_key_backup = env->usr->usrs.rope_mode_key;
  state->rope_mode_visible_backup = env->usr->usrs.rope_mode_visible;
  state->rope_mode_x_backup = env->usr->usrs.rope_mode_x;
  state->rope_mode_y_backup = env->usr->usrs.rope_mode_y;
  state->editor_focus = focus_action >= 0 && focus_action < NUM_MOBILE_ACTIONS
                            ? focus_action
                            : -1;
  state->editor_active = true;
  mobile_hotkeys_reset_runtime(env);
}

void mobile_hotkeys_finish_editor(tenv* env, bool save) {
  mobile_hotkeys_state* state = &env->usr->mobile_hotkeys;
  if (!save) {
    env->usr->usrs.mobile_hotkeys = state->edit_backup;
    env->usr->usrs.rope_mode_key = state->rope_mode_key_backup;
    env->usr->usrs.rope_mode_visible = state->rope_mode_visible_backup;
    env->usr->usrs.rope_mode_x = state->rope_mode_x_backup;
    env->usr->usrs.rope_mode_y = state->rope_mode_y_backup;
  }
  state->editor_active = false;
  state->editor_focus = -1;
  if (save) save_user_settings(&env->usr->usrs);
}

void mobile_hotkeys_reset_layout(tenv* env) {
  mobile_hotkey_settings* cfg = &env->usr->usrs.mobile_hotkeys;
  for (int i = 0; i < NUM_MOBILE_HOTKEYS; ++i) {
    bool right = i >= (NUM_MOBILE_HOTKEYS + 1) / 2;
    int row = right ? i - (NUM_MOBILE_HOTKEYS + 1) / 2 : i;
    cfg->x[i] = right ? 0.91f : 0.09f;
    cfg->y[i] = 0.18f + row * 0.105f;
  }
  env->usr->usrs.rope_mode_x = 0.50f;
  env->usr->usrs.rope_mode_y = 0.22f;
}

void mobile_hotkeys_set_position(tenv* env, int action, float x, float y) {
  if (action < 0 || action >= NUM_MOBILE_ACTIONS) return;
  bool visible = false;
  mobile_hotkey_get_layout(&env->usr->usrs, action, &visible, NULL, NULL);
  mobile_hotkey_set_layout(&env->usr->usrs, action, visible,
                           clampf_local(x / env->wnd->size[0], 0.0f, 1.0f),
                           clampf_local(y / env->wnd->size[1], 0.0f, 1.0f));
}

void mobile_hotkeys_get_position(tenv* env, int action, float* x, float* y) {
  float width, height;
  action_geometry(env, action, x, y, &width, &height);
}

const char* mobile_hotkey_action_name(int action) {
  return action >= 0 && action < NUM_MOBILE_ACTIONS ? ACTION_NAMES[action]
                                                    : "Unknown";
}

int mobile_hotkey_get_key(const user_settings* settings, int action) {
  if (action >= 0 && action < NUM_HOTKEYS) return settings->hotkeys[action].key;
  if (action == MOBILE_HOTKEY_ROPE_MODE) return settings->rope_mode_key;
  int direct = action - NUM_HOTKEYS;
  if (direct >= 0 && direct < NUM_MOBILE_DIRECT_HOTKEYS)
    return settings->mobile_hotkeys.direct_keys[direct];
  return GLFW_KEY_UNKNOWN;
}

void mobile_hotkey_set_key(user_settings* settings, int action, int key) {
  if (action >= 0 && action < NUM_HOTKEYS)
    settings->hotkeys[action].key = key;
  else if (action == MOBILE_HOTKEY_ROPE_MODE)
    settings->rope_mode_key = key;
  else {
    int direct = action - NUM_HOTKEYS;
    if (direct >= 0 && direct < NUM_MOBILE_DIRECT_HOTKEYS)
      settings->mobile_hotkeys.direct_keys[direct] = key;
  }
}

const char* mobile_hotkey_key_name(const user_settings* settings, int action) {
  static char labels[4][12];
  static int slot;
  int key = mobile_hotkey_get_key(settings, action);
  switch (key) {
    case GLFW_KEY_SPACE:
      return "SPACE";
    case GLFW_KEY_LEFT:
      return "LEFT";
    case GLFW_KEY_RIGHT:
      return "RIGHT";
    case GLFW_KEY_UP:
      return "UP";
    case GLFW_KEY_DOWN:
      return "DOWN";
    case GLFW_KEY_F11:
      return "F11";
    default:
      slot = (slot + 1) % 4;
      if ((key >= GLFW_KEY_0 && key <= GLFW_KEY_9) ||
          (key >= GLFW_KEY_A && key <= GLFW_KEY_Z)) {
        snprintf(labels[slot], sizeof(labels[slot]), "%c", (char)key);
        return labels[slot];
      }
      return "KEY";
  }
}

bool mobile_hotkey_is_hold_action(const user_settings* settings, int action) {
  if (action >= 0 && action < NUM_HOTKEYS)
    return action != HOTKEY_RESTART && action != HOTKEY_QUIT &&
           settings->hotkeys[action].mode != 0;
  return action == MOBILE_HOTKEY_BOOST || action == MOBILE_HOTKEY_TURN_LEFT ||
         action == MOBILE_HOTKEY_TURN_RIGHT;
}

void mobile_hotkey_get_layout(const user_settings* settings, int action,
                              bool* visible, float* x, float* y) {
  if (action >= 0 && action < NUM_MOBILE_HOTKEYS) {
    if (visible) *visible = settings->mobile_hotkeys.visible[action];
    if (x) *x = settings->mobile_hotkeys.x[action];
    if (y) *y = settings->mobile_hotkeys.y[action];
  } else if (action == MOBILE_HOTKEY_ROPE_MODE) {
    if (visible) *visible = settings->rope_mode_visible;
    if (x) *x = settings->rope_mode_x;
    if (y) *y = settings->rope_mode_y;
  }
}

void mobile_hotkey_set_layout(user_settings* settings, int action, bool visible,
                              float x, float y) {
  x = clampf_local(x, 0.0f, 1.0f);
  y = clampf_local(y, 0.0f, 1.0f);
  if (action >= 0 && action < NUM_MOBILE_HOTKEYS) {
    settings->mobile_hotkeys.visible[action] = visible;
    settings->mobile_hotkeys.x[action] = x;
    settings->mobile_hotkeys.y[action] = y;
  } else if (action == MOBILE_HOTKEY_ROPE_MODE) {
    settings->rope_mode_visible = visible;
    settings->rope_mode_x = x;
    settings->rope_mode_y = y;
  }
}
