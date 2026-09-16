#ifndef MOBILE_CONTROLS_H
#define MOBILE_CONTROLS_H

#include <stdbool.h>
#include <stdint.h>

#include "../game/user_settings.h"

typedef struct tenv tenv;

typedef enum mobile_edit_target {
  MOBILE_EDIT_NONE = 0,
  MOBILE_EDIT_JOYSTICK,
  MOBILE_EDIT_BOOST,
  MOBILE_EDIT_ZOOM
} mobile_edit_target;

typedef struct mobile_controls_state {
  uint64_t joystick_finger;
  uint64_t boost_finger;
  uint64_t zoom_finger;
  uint64_t edit_finger;
  uint64_t ui_scroll_finger;
  bool joystick_down;
  bool boost_down;
  bool zoom_down;
  bool edit_down;
  bool aim_valid;
  bool editor_active;
  bool back_requested;
  bool exit_requested;
  bool ui_scroll_down;
  int edit_target;
  float joystick_origin[2];
  float joystick_axis[2];
  float arrow_drag_distance;
  /* Arrow steering. `arrow_vec` is the persistent one the heading is taken
     from — it accumulates every scrap of drag and is never clamped, which is
     what makes this relative steering rather than a stick. `arrow_draw` is the
     only thing that is smoothed, and only because it is what you look at.
     See "wise newton/arrow implementation.md". */
  float arrow_vec[2];
  float arrow_draw[2];
  float arrow_last[2];
  float arrow_opacity;
  float arrow_dead; /* 0 while a finger steers, then rises as it fades out */
  float boost_origin[2];
  float ui_scroll_last_y;
  mobile_control_settings edit_backup;
} mobile_controls_state;

void mobile_controls_init(tenv* env);
void mobile_controls_update(tenv* env);
bool mobile_controls_process_event(tenv* env, const void* event);
bool mobile_controls_get_aim(tenv* env, int* x, int* y);
bool mobile_controls_get_arrow_position(tenv* env, float* x, float* y);
bool mobile_controls_boost_down(tenv* env);
void mobile_controls_draw_gameplay(tenv* env);
void mobile_controls_begin_editor(tenv* env);
void mobile_controls_finish_editor(tenv* env, bool save);
void mobile_controls_set_handedness(tenv* env, int handedness);
void mobile_controls_reset_layout(tenv* env);

#endif
