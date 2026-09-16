#ifndef MOBILE_HOTKEYS_H
#define MOBILE_HOTKEYS_H

#include <stdbool.h>
#include <stdint.h>

#include "../game/user_settings.h"

typedef struct tenv tenv;

typedef struct mobile_hotkeys_state {
  uint64_t finger[NUM_MOBILE_ACTIONS];
  bool down[NUM_MOBILE_ACTIONS];
  bool pressed[NUM_MOBILE_ACTIONS];
  bool rope_mode;
  bool editor_active;
  int editor_focus;
  mobile_hotkey_settings edit_backup;
  int rope_mode_key_backup;
  bool rope_mode_visible_backup;
  float rope_mode_x_backup;
  float rope_mode_y_backup;
} mobile_hotkeys_state;

void mobile_hotkeys_init(tenv* env);
void mobile_hotkeys_reset_runtime(tenv* env);
bool mobile_hotkeys_process_event(tenv* env, const void* event);
void mobile_hotkeys_draw_gameplay(tenv* env);
bool mobile_hotkeys_down(tenv* env, int action);
bool mobile_hotkeys_pressed(tenv* env, int action);

void mobile_hotkeys_begin_editor(tenv* env, int focus_action);
void mobile_hotkeys_finish_editor(tenv* env, bool save);
void mobile_hotkeys_reset_layout(tenv* env);
void mobile_hotkeys_set_position(tenv* env, int action, float x, float y);
void mobile_hotkeys_get_position(tenv* env, int action, float* x, float* y);
void mobile_hotkey_get_layout(const user_settings* settings, int action,
                              bool* visible, float* x, float* y);
void mobile_hotkey_set_layout(user_settings* settings, int action, bool visible,
                              float x, float y);

const char* mobile_hotkey_action_name(int action);
bool mobile_hotkey_is_on_screen_button(int action);
const char* mobile_hotkey_key_name(const user_settings* settings, int action);
int mobile_hotkey_get_key(const user_settings* settings, int action);
void mobile_hotkey_set_key(user_settings* settings, int action, int key);
bool mobile_hotkey_is_hold_action(const user_settings* settings, int action);

#endif
