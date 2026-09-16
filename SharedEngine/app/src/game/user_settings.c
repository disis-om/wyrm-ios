#include "user_settings.h"

#include <math.h>
#include <stddef.h>
#include <string.h>
#include <thermite.h>

#include "../mobile/mobile_hotkeys.h"

#define USER_SETTINGS_TEMP_FILE USER_SETTINGS_FILE ".tmp"
#define USER_SETTINGS_BACKUP_FILE USER_SETTINGS_FILE ".bak"

static void arrow_settings_default(mobile_arrow_settings* settings) {
  *settings = (mobile_arrow_settings){.boost_glow = false,
                                      .size = 1.0f,
                                      .separation = 1.0f,
                                      .smoothness = 0.40f,
                                      .color = {1.0f, 1.0f, 1.0f, 1.0f}};
}

static void mobile_hotkeys_default(mobile_hotkey_settings* settings) {
  memset(settings, 0, sizeof(*settings));
  settings->opacity = 0.82f;
  settings->label_mode = MOBILE_HOTKEY_LABEL_FUNCTION;
  settings->key_scale = 1.0f;
  settings->direct_keys[0] = GLFW_KEY_N;
  settings->direct_keys[1] = GLFW_KEY_M;
  settings->direct_keys[2] = GLFW_KEY_SPACE;
  settings->direct_keys[3] = GLFW_KEY_LEFT;
  settings->direct_keys[4] = GLFW_KEY_RIGHT;
  settings->direct_keys[5] = GLFW_KEY_F11;

  // Two compact vertical banks provide collision-free defaults. Everything is
  // hidden initially so upgrading users never receive an unexpected overlay.
  for (int i = 0; i < NUM_MOBILE_HOTKEYS; ++i) {
    bool right = i >= (NUM_MOBILE_HOTKEYS + 1) / 2;
    int row = right ? i - (NUM_MOBILE_HOTKEYS + 1) / 2 : i;
    settings->x[i] = right ? 0.91f : 0.09f;
    settings->y[i] = 0.18f + row * 0.105f;
  }
}

static bool normalize_on_screen_buttons(user_settings* settings) {
  bool changed = false;
  if (settings->mobile_hotkeys.label_mode != MOBILE_HOTKEY_LABEL_FUNCTION) {
    settings->mobile_hotkeys.label_mode = MOBILE_HOTKEY_LABEL_FUNCTION;
    changed = true;
  }
  for (int action = 0; action < NUM_MOBILE_HOTKEYS; ++action) {
    if (!mobile_hotkey_is_on_screen_button(action) &&
        settings->mobile_hotkeys.visible[action]) {
      settings->mobile_hotkeys.visible[action] = false;
      changed = true;
    }
  }
  if (settings->rope_mode_visible) {
    settings->rope_mode_visible = false;
    changed = true;
  }
  return changed;
}

static bool sanitize_mobile_controls(mobile_control_settings* controls) {
  bool changed = false;
  if (controls->handedness != MOBILE_LEFT_HANDED &&
      controls->handedness != MOBILE_RIGHT_HANDED) {
    controls->handedness = MOBILE_RIGHT_HANDED;
    changed = true;
  }
  if (controls->joystick_mode < MOBILE_JOYSTICK_DYNAMIC ||
      controls->joystick_mode > MOBILE_STEERING_ARROW) {
    controls->joystick_mode = MOBILE_JOYSTICK_DYNAMIC;
    changed = true;
  }
  if (controls->boost_mode < MOBILE_BOOST_TOUCH_ZONE ||
      controls->boost_mode > MOBILE_BOOST_FIXED) {
    controls->boost_mode = MOBILE_BOOST_TOUCH_ZONE;
    changed = true;
  }
  if (controls->zoom_orientation < MOBILE_ZOOM_HORIZONTAL ||
      controls->zoom_orientation > MOBILE_ZOOM_VERTICAL) {
    controls->zoom_orientation = MOBILE_ZOOM_HORIZONTAL;
    changed = true;
  }

  bool left = controls->handedness == MOBILE_LEFT_HANDED;
#define REPAIR_POSITION(field, fallback)                                      \
  do {                                                                        \
    if (!isfinite(controls->field) || controls->field < 0.0f ||               \
        controls->field > 1.0f) {                                             \
      controls->field = (fallback);                                           \
      changed = true;                                                         \
    }                                                                         \
  } while (0)
  REPAIR_POSITION(joystick_x, left ? 0.20f : 0.80f);
  REPAIR_POSITION(joystick_y, 0.72f);
  REPAIR_POSITION(boost_x, left ? 0.82f : 0.18f);
  REPAIR_POSITION(boost_y, 0.72f);
  REPAIR_POSITION(zoom_x, 0.50f);
  REPAIR_POSITION(zoom_y, 0.88f);
#undef REPAIR_POSITION

#define REPAIR_RANGE(field, minimum, maximum, fallback)                       \
  do {                                                                        \
    if (!isfinite(controls->field) || controls->field < (minimum) ||          \
        controls->field > (maximum)) {                                        \
      controls->field = (fallback);                                           \
      changed = true;                                                         \
    }                                                                         \
  } while (0)
  REPAIR_RANGE(joystick_size, 0.65f, 1.45f, 1.0f);
  REPAIR_RANGE(boost_size, 0.65f, 1.45f, 1.0f);
  REPAIR_RANGE(zoom_length, 0.65f, 1.55f, 1.0f);
  REPAIR_RANGE(opacity, 0.25f, 1.0f, 0.62f);
#undef REPAIR_RANGE
  return changed;
}

void user_settings_reset_hud_layout(user_settings* settings) {
  /* These are centres on the 19.5:9 landscape canvas used by the phone. They
     preserve the familiar map-left / board-right composition while remaining
     resolution independent. The renderer clamps the measured item itself. */
  settings->hud_minimap_x = 0.095f;
  settings->hud_minimap_y = 0.205f;
  settings->hud_leaderboard_x = 0.905f;
  settings->hud_leaderboard_y = 0.155f;
  settings->hud_stats_x = 0.945f;
  settings->hud_stats_y = 0.530f;
  settings->hud_team_x = 0.095f;
  settings->hud_team_y = 0.610f;
  settings->hud_chat_x = 0.790f;
  settings->hud_chat_y = 0.075f;
}

static void user_settings_default_layout_appearance(user_settings* settings) {
  settings->joystick_opacity = settings->mobile_controls.opacity;
  settings->boost_opacity = settings->mobile_controls.opacity;
  settings->zoom_opacity = settings->mobile_controls.opacity;
  for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action) {
    settings->hotkey_scale[action] = settings->mobile_hotkeys.key_scale;
    settings->hotkey_opacity[action] = settings->mobile_hotkeys.opacity;
  }
  settings->hud_stats_scale = 1.0f;
  settings->hud_stats_opacity = 1.0f;
  settings->hud_chat_scale = 1.0f;
  settings->hud_chat_opacity = 1.0f;
}

void user_settings_default(user_settings* usr_settings) {
  usr_settings->ui_font_size = FONT_SIZE_SMALL;
  usr_settings->lb_font_size = FONT_SIZE_REGULAR;
  usr_settings->snake_names_font_size = FONT_SIZE_REGULAR;
  usr_settings->stats_font_size = FONT_SIZE_REGULAR;

  strcpy(usr_settings->version, SETTINGS_VERSION);

  usr_settings->bd_color[0] = 1;
  usr_settings->bd_color[1] = 0.25f;
  usr_settings->bd_color[2] = 0.25f;
  usr_settings->laser_color[0] = 0.5f;
  usr_settings->laser_color[1] = 1;
  usr_settings->laser_color[2] = 0.5f;
  usr_settings->laser_color[3] = 1;
  usr_settings->laser_thickness = 2;
  usr_settings->cursor_size = 48;
  usr_settings->minimap_size = 300;
  usr_settings->zoom_step = 0.1f;
  usr_settings->snake_scores = true;
  usr_settings->show_own_name = false;
  usr_settings->tag_index = -1;
  usr_settings->tag_chain = 1.0f;
  usr_settings->tag_swing = 1.0f;
  usr_settings->tag_scale = 1.0f;
  usr_settings->tags_small = false;
  usr_settings->tags_hidden = false;
  usr_settings->tags_team_only = false;
  usr_settings->restart_rc = false;
  usr_settings->quit_mc = false;
  usr_settings->smooth_zoom = false;
  usr_settings->vsync = false;
  usr_settings->instant_restart = false;
  usr_settings->auto_respawn = 0;
  usr_settings->rope_mode_key = GLFW_KEY_V;
  usr_settings->rope_mode_visible = false;
  usr_settings->rope_mode_x = 0.50f;
  usr_settings->rope_mode_y = 0.22f;
  usr_settings->arrow_style = MOBILE_ARROW_CURRENT;
  memset(usr_settings->skin_rgba, 0, sizeof(usr_settings->skin_rgba));
  usr_settings->arena_background = 0;
  /* The persona table's first entry. A fresh install starts on the handshake
     that cannot have gone stale, and a match that lasts writes back whichever
     one actually worked. */
  usr_settings->arena_persona = 0;
  usr_settings->death_hold_s = 1.6f;
  for (int mode = 0; mode < 2; ++mode) {
    usr_settings->head_dot_size[mode] = 10.0f;
    usr_settings->head_dot_color[mode][0] = 1.0f;
    usr_settings->head_dot_color[mode][1] = 1.0f;
    usr_settings->head_dot_color[mode][2] = 1.0f;
  }
  user_settings_reset_hud_layout(usr_settings);
  usr_settings->bot_radius_mult = 20;
  usr_settings->bot_follow_circle_score = 2000;

  usr_settings->mobile_controls =
      (mobile_control_settings){.handedness = MOBILE_RIGHT_HANDED,
                                .joystick_mode = MOBILE_JOYSTICK_DYNAMIC,
                                .boost_mode = MOBILE_BOOST_TOUCH_ZONE,
                                .zoom_orientation = MOBILE_ZOOM_HORIZONTAL,
                                .zoom_enabled = true,
                                .show_touch_zones = true,
                                .joystick_x = 0.80f,
                                .joystick_y = 0.72f,
                                .boost_x = 0.18f,
                                .boost_y = 0.72f,
                                .zoom_x = 0.50f,
                                .zoom_y = 0.88f,
                                .joystick_size = 1.0f,
                                .boost_size = 1.0f,
                                .zoom_length = 1.0f,
                                .opacity = 0.62f};
  arrow_settings_default(&usr_settings->arrow_controls);
  mobile_hotkeys_default(&usr_settings->mobile_hotkeys);
  user_settings_default_layout_appearance(usr_settings);

  // normal mode
  usr_settings->modes[0].food_flicker = true;
  usr_settings->modes[0].food_float = true;
  usr_settings->modes[0].uniform_food_color = false;
  usr_settings->modes[0].food_type = 0;
  usr_settings->modes[0].food_scale = 1;
  usr_settings->modes[0].food_color[0] = 1;
  usr_settings->modes[0].food_color[1] = 1;
  usr_settings->modes[0].food_color[2] = 1;
  usr_settings->modes[0].boost_type = 0;
  usr_settings->modes[0].qsm = 1;
  usr_settings->modes[0].bg_scale = 599 / 4096.0f;
  usr_settings->modes[0].boost_strength = 1;
  usr_settings->modes[0].show_crosshair = false;
  usr_settings->modes[0].show_boost = true;
  usr_settings->modes[0].show_shadows = true;
  usr_settings->modes[0].show_background = true;
  usr_settings->modes[0].show_accessories = true;
  usr_settings->modes[0].death_effect = true;
  usr_settings->modes[0].player_names_outline = false;
  usr_settings->modes[0].render_mode = 0;
  usr_settings->modes[0].const_food_scale = false;

  // assist mode
  usr_settings->modes[1].food_flicker = false;
  usr_settings->modes[1].food_float = false;
  usr_settings->modes[1].uniform_food_color = true;
  usr_settings->modes[1].food_type = 1;
  usr_settings->modes[1].food_scale = 1;
  usr_settings->modes[1].food_color[0] = 0.7f;
  usr_settings->modes[1].food_color[1] = 0.7f;
  usr_settings->modes[1].food_color[2] = 0.7f;
  usr_settings->modes[1].boost_type = 1;
  usr_settings->modes[1].qsm = 1;
  usr_settings->modes[1].bg_scale = 599 / 4096.0f;
  usr_settings->modes[1].boost_strength = 1;
  usr_settings->modes[1].show_crosshair = true;
  usr_settings->modes[1].show_boost = false;
  usr_settings->modes[1].show_shadows = true;
  usr_settings->modes[1].show_background = false;
  usr_settings->modes[1].show_accessories = false;
  usr_settings->modes[1].death_effect = false;
  usr_settings->modes[1].player_names_outline = true;
  usr_settings->modes[1].render_mode = 1;
  usr_settings->modes[1].const_food_scale = false;

  usr_settings->hotkeys[HOTKEY_HUD] = (hotkey){GLFW_KEY_H, true, 0, "HUD"};
  usr_settings->hotkeys[HOTKEY_SHOW_NAMES] =
      (hotkey){GLFW_KEY_P, true, 0, "Show names"};
  usr_settings->hotkeys[HOTKEY_BIG_FOOD] =
      (hotkey){GLFW_KEY_F, false, 0, "Big food"};
  usr_settings->hotkeys[HOTKEY_ASSIST] =
      (hotkey){GLFW_KEY_K, false, 1, "Assist"};
  usr_settings->hotkeys[HOTKEY_BOT] = (hotkey){GLFW_KEY_T, false, 0, "Bot"};
  usr_settings->hotkeys[HOTKEY_MENU] =
      (hotkey){GLFW_KEY_Z, true, 0, "Hotkey menu"};
  usr_settings->hotkeys[HOTKEY_RESTART] =
      (hotkey){GLFW_KEY_R, false, 1, "Restart"};
  usr_settings->hotkeys[HOTKEY_QUIT] = (hotkey){GLFW_KEY_Q, false, 1, "Quit"};
}

static bool load_current_backup(user_settings* settings) {
  FILE* file = fopen(USER_SETTINGS_BACKUP_FILE, "rb");
  if (!file) return false;
  user_settings recovered = {0};
  fseek(file, 0, SEEK_END);
  long file_size = ftell(file);
  rewind(file);
  /* `recovered` starts zeroed, so every field a shorter generation never wrote
   * already holds the value its migration would have assigned — except the
   * arrow style, whose default is not zero. */
  const size_t v20_size = offsetof(user_settings, arrow_style);
  const size_t v21_size = offsetof(user_settings, skin_rgba);
  const size_t v25_size = offsetof(user_settings, head_dot_size);
  const size_t v26_size = offsetof(user_settings, hud_minimap_x);
  bool current = file_size == (long)sizeof(recovered);
  bool v26 = file_size == (long)v26_size;
  bool v25 = file_size == (long)v25_size;
  bool v21 = file_size == (long)v21_size;
  bool v20 = file_size == (long)v20_size;
  size_t want = current ? sizeof(recovered)
                        : v26 ? v26_size
                              : v25 ? v25_size : v21 ? v21_size : v20_size;
  bool valid =
      (current || v26 || v25 || v21 || v20) &&
      fread(&recovered, want, 1, file) == 1;
  int trailing = fgetc(file);
  fclose(file);
  valid = valid && trailing == EOF &&
          ((current && strncmp(recovered.version, SETTINGS_VERSION,
                               strlen(SETTINGS_VERSION)) == 0) ||
           (v26 && strncmp(recovered.version, "2.6", 3) == 0) ||
           (v25 && strncmp(recovered.version, "2.5", 3) == 0) ||
           (v21 && strncmp(recovered.version, "2.1", 3) == 0) ||
           (v20 && strncmp(recovered.version, "2.0", 3) == 0));
  if (valid && v20) recovered.arrow_style = MOBILE_ARROW_CURRENT;
  if (valid && v25) {
    for (int mode = 0; mode < 2; ++mode) {
      recovered.head_dot_size[mode] = 10.0f;
      recovered.head_dot_color[mode][0] = 1.0f;
      recovered.head_dot_color[mode][1] = 1.0f;
      recovered.head_dot_color[mode][2] = 1.0f;
    }
  }
  if (valid && v26) user_settings_reset_hud_layout(&recovered);
  if (valid && !current) strcpy(recovered.version, SETTINGS_VERSION);
  if (valid) *settings = recovered;
  return valid;
}

void write_default_settings(user_settings* usr_settings) {
  user_settings_default(usr_settings);
  save_user_settings(usr_settings);
}

void read_user_settings(user_settings* usr_settings) {
  FILE* f = fopen(USER_SETTINGS_FILE, "rb");

  if (f == NULL) {
    if (load_current_backup(usr_settings)) {
      save_user_settings(usr_settings);
      return;
    }
    // File doesn't exist → create it
    write_default_settings(usr_settings);
    return;
  }

  fseek(f, 0, SEEK_END);
  long file_size = ftell(f);
  rewind(f);

  /* v2.8 appends per-object layout appearance. Seed it from the old global
     controls so upgrading cannot visibly change an existing layout. */
  const size_t v27_size = offsetof(user_settings, joystick_opacity);
  if (file_size == (long)v27_size) {
    size_t read_v27 = fread(usr_settings, v27_size, 1, f);
    fclose(f);
    if (read_v27 == 1 && strncmp(usr_settings->version, "2.7", 3) == 0) {
      user_settings_default_layout_appearance(usr_settings);
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  /* v2.7 appends only normalized arena-HUD positions. */
  const size_t v26_size = offsetof(user_settings, hud_minimap_x);
  if (file_size == (long)v26_size) {
    size_t read_v26 = fread(usr_settings, v26_size, 1, f);
    fclose(f);
    if (read_v26 == 1 && strncmp(usr_settings->version, "2.6", 3) == 0) {
      user_settings_reset_hud_layout(usr_settings);
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    return;
  }

  /* v2.6 appends per-mode head-dot appearance. The older file is the exact
     prefix ending at head_dot_size, so no earlier preference moves. */
  const size_t v25_size = offsetof(user_settings, head_dot_size);
  if (file_size == (long)v25_size) {
    size_t read_v25 = fread(usr_settings, v25_size, 1, f);
    fclose(f);
    if (read_v25 == 1 && strncmp(usr_settings->version, "2.5", 3) == 0) {
      for (int mode = 0; mode < 2; ++mode) {
        usr_settings->head_dot_size[mode] = 10.0f;
        usr_settings->head_dot_color[mode][0] = 1.0f;
        usr_settings->head_dot_color[mode][1] = 1.0f;
        usr_settings->head_dot_color[mode][2] = 1.0f;
      }
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  // v1.5 appends arrow settings after the old v1.4 structure. Read the
  // shared prefix, initialise only the new fields, then rewrite once.
  const size_t v14_size = offsetof(user_settings, arrow_controls);
  if (file_size == (long)v14_size) {
    size_t read_v14 = fread(usr_settings, v14_size, 1, f);
    fclose(f);
    if (read_v14 == 1 && strncmp(usr_settings->version, "1.4", 3) == 0) {
      arrow_settings_default(&usr_settings->arrow_controls);
      mobile_hotkeys_default(&usr_settings->mobile_hotkeys);
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  // v1.6 only appends the mobile keyboard layout. Preserve every existing
  // control, visual and gameplay preference from a valid v1.5 save.
  const size_t v15_size = offsetof(user_settings, mobile_hotkeys);
  if (file_size == (long)v15_size) {
    size_t read_v15 = fread(usr_settings, v15_size, 1, f);
    fclose(f);
    if (read_v15 == 1 && strncmp(usr_settings->version, "1.5", 3) == 0) {
      mobile_hotkeys_default(&usr_settings->mobile_hotkeys);
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  // v1.7 appends only the overlay label preference. Preserve the complete
  // v1.6 layout and initialize the new display mode to Key + Function.
  const size_t v16_size = offsetof(user_settings, mobile_hotkeys) +
                          offsetof(mobile_hotkey_settings, label_mode);
  if (file_size == (long)v16_size) {
    size_t read_v16 = fread(usr_settings, v16_size, 1, f);
    fclose(f);
    if (read_v16 == 1 && strncmp(usr_settings->version, "1.6", 3) == 0) {
      usr_settings->mobile_hotkeys.label_mode = MOBILE_HOTKEY_LABEL_FUNCTION;
      usr_settings->mobile_hotkeys.key_scale = 1.0f;
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  // v1.8 appends only the overlay key-size multiplier. Preserve the complete
  // v1.7 layout and initialise the new scale without touching any positions.
  const size_t v17_size = offsetof(user_settings, mobile_hotkeys) +
                          offsetof(mobile_hotkey_settings, key_scale);
  if (file_size == (long)v17_size) {
    size_t read_v17 = fread(usr_settings, v17_size, 1, f);
    fclose(f);
    if (read_v17 == 1 && strncmp(usr_settings->version, "1.7", 3) == 0) {
      usr_settings->mobile_hotkeys.key_scale = 1.0f;
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  /* v2.0 appends only the Rope Mode key binding and layout. The runtime toggle

   * deliberately is not saved, so opening the app never silently changes the

   * player's own snake. */
  const size_t v19_size = offsetof(user_settings, rope_mode_key);
  if (file_size == (long)v19_size) {
    size_t read_v19 = fread(usr_settings, v19_size, 1, f);
    fclose(f);
    if (read_v19 == 1 && (strncmp(usr_settings->version, "1.9", 3) == 0 ||
                          strncmp(usr_settings->version, "1.8", 3) == 0)) {
      if (strncmp(usr_settings->version, "1.8", 3) == 0)
        usr_settings->auto_respawn = 0;
      usr_settings->rope_mode_key = GLFW_KEY_V;
      usr_settings->rope_mode_visible = false;
      usr_settings->rope_mode_x = 0.50f;
      usr_settings->rope_mode_y = 0.22f;
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  /* v2.1 adds only the arrow silhouette after the complete v2.0 structure.
   * The old arrow remains the default, so an update cannot visually change a
   * player's controls until they choose another style themselves. */
  const size_t v20_size = offsetof(user_settings, arrow_style);
  if (file_size == (long)v20_size) {
    size_t read_v20 = fread(usr_settings, v20_size, 1, f);
    fclose(f);
    if (read_v20 == 1 && strncmp(usr_settings->version, "2.0", 3) == 0) {
      usr_settings->arrow_style = MOBILE_ARROW_CURRENT;
      memset(usr_settings->skin_rgba, 0, sizeof(usr_settings->skin_rgba));
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  /* v2.5 appends how long the arena stays on screen after death. An older
   * file gets original slither's 1.6 s. */
  const size_t v24_size = offsetof(user_settings, death_hold_s);
  if (file_size == (long)v24_size) {
    size_t read_v24 = fread(usr_settings, v24_size, 1, f);
    fclose(f);
    if (read_v24 == 1 && strncmp(usr_settings->version, "2.4", 3) == 0) {
      usr_settings->death_hold_s = 1.6f;
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  /* v2.4 appends only the wire persona Wyrm last joined an arena as. An older
   * file starts from the table's own first entry, which is what a fresh install
   * does and what the retry path will correct on its own anyway. */
  const size_t v23_size = offsetof(user_settings, arena_persona);
  if (file_size == (long)v23_size) {
    size_t read_v23 = fread(usr_settings, v23_size, 1, f);
    fclose(f);
    if (read_v23 == 1 && strncmp(usr_settings->version, "2.3", 3) == 0) {
      usr_settings->arena_persona = 0;
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  /* v2.3 appends only the chosen arena background. An older file keeps Wyrm's
   * own, which is what it was already drawing. */
  const size_t v22_size = offsetof(user_settings, arena_background);
  if (file_size == (long)v22_size) {
    size_t read_v22 = fread(usr_settings, v22_size, 1, f);
    fclose(f);
    if (read_v22 == 1 && strncmp(usr_settings->version, "2.2", 3) == 0) {
      usr_settings->arena_background = 0;
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  /* v2.2 appends the built-skin colours after the complete v2.1 structure.
   * An all-zero array means every position still renders from the palette, so
   * a skin built before this version looks exactly the same afterwards. */
  const size_t v21_size = offsetof(user_settings, skin_rgba);
  if (file_size == (long)v21_size) {
    size_t read_v21 = fread(usr_settings, v21_size, 1, f);
    fclose(f);
    if (read_v21 == 1 && strncmp(usr_settings->version, "2.1", 3) == 0) {
      memset(usr_settings->skin_rgba, 0, sizeof(usr_settings->skin_rgba));
      strcpy(usr_settings->version, SETTINGS_VERSION);
      save_user_settings(usr_settings);
      return;
    }
    write_default_settings(usr_settings);
    return;
  }

  size_t read = fread(usr_settings, sizeof(user_settings), 1, f);
  fclose(f);

  /*
   * v1.9 appended one float — and every check above missed it, because it
   * fitted in padding the v1.8 struct already had. The file is exactly the same
   * size, so nothing sized can tell the two apart, and a v1.8 save read cleanly
   * here and was then thrown away by the version check below: every setting the
   * player had, gone, for a field that fitted in a gap. It happened once, on
   * the machine this was written on.
   *
   * So the version string decides, and a new field that does not change
   * `sizeof` has to be migrated here rather than up there.
   */
  if (read == 1 && strncmp(usr_settings->version, "1.8", 3) == 0) {
    usr_settings->auto_respawn = 0;
    strcpy(usr_settings->version, SETTINGS_VERSION);
    save_user_settings(usr_settings);
    return;
  }

  if (read != 1 || strncmp(usr_settings->version, SETTINGS_VERSION,
                           strlen(SETTINGS_VERSION)) != 0) {
    if (load_current_backup(usr_settings)) {
      remove(USER_SETTINGS_FILE);
      save_user_settings(usr_settings);
      return;
    }
    printf("Settings file unavailable, recreating safe defaults.\n");
    write_default_settings(usr_settings);
    return;
  }

  if (sanitize_mobile_controls(&usr_settings->mobile_controls))
    save_user_settings(usr_settings);
  if (normalize_on_screen_buttons(usr_settings)) save_user_settings(usr_settings);
  if (!isfinite(usr_settings->mobile_hotkeys.key_scale) ||
      usr_settings->mobile_hotkeys.key_scale < 0.65f ||
      usr_settings->mobile_hotkeys.key_scale > 1.60f) {
    usr_settings->mobile_hotkeys.key_scale = 1.0f;
    save_user_settings(usr_settings);
  }
  if (usr_settings->rope_mode_key < 0 || usr_settings->rope_mode_key > 512 ||
      !isfinite(usr_settings->rope_mode_x) ||
      !isfinite(usr_settings->rope_mode_y) ||
      usr_settings->rope_mode_x < 0.0f ||
      usr_settings->rope_mode_x > 1.0f ||
      usr_settings->rope_mode_y < 0.0f || usr_settings->rope_mode_y > 1.0f) {
    usr_settings->rope_mode_key = GLFW_KEY_V;
    usr_settings->rope_mode_visible = false;
    usr_settings->rope_mode_x = 0.50f;
    usr_settings->rope_mode_y = 0.22f;
    save_user_settings(usr_settings);
  }
  if (usr_settings->arrow_style < MOBILE_ARROW_CURRENT ||
      usr_settings->arrow_style > MOBILE_ARROW_TRIANGLE) {
    usr_settings->arrow_style = MOBILE_ARROW_CURRENT;
    save_user_settings(usr_settings);
  }
  if (!isfinite(usr_settings->death_hold_s) || usr_settings->death_hold_s < 0.0f ||
      usr_settings->death_hold_s > 4.0f) {
    usr_settings->death_hold_s = 1.6f;
    save_user_settings(usr_settings);
  }
  bool repair_head_dot = false;
  for (int mode = 0; mode < 2; ++mode) {
    if (!isfinite(usr_settings->head_dot_size[mode]) ||
        usr_settings->head_dot_size[mode] < 4.0f ||
        usr_settings->head_dot_size[mode] > 32.0f) {
      usr_settings->head_dot_size[mode] = 10.0f;
      repair_head_dot = true;
    }
    for (int channel = 0; channel < 3; ++channel) {
      if (!isfinite(usr_settings->head_dot_color[mode][channel]) ||
          usr_settings->head_dot_color[mode][channel] < 0.0f ||
          usr_settings->head_dot_color[mode][channel] > 1.0f) {
        usr_settings->head_dot_color[mode][channel] = 1.0f;
        repair_head_dot = true;
      }
    }
  }
  if (repair_head_dot) save_user_settings(usr_settings);

  float* hud[] = {&usr_settings->hud_minimap_x, &usr_settings->hud_minimap_y,
                  &usr_settings->hud_leaderboard_x,
                  &usr_settings->hud_leaderboard_y, &usr_settings->hud_stats_x,
                  &usr_settings->hud_stats_y, &usr_settings->hud_team_x,
                  &usr_settings->hud_team_y, &usr_settings->hud_chat_x,
                  &usr_settings->hud_chat_y};
  bool repair_hud = false;
  for (size_t i = 0; i < sizeof(hud) / sizeof(hud[0]); ++i)
    repair_hud = repair_hud || !isfinite(*hud[i]) || *hud[i] < 0.0f ||
                 *hud[i] > 1.0f;
  if (repair_hud) {
    user_settings_reset_hud_layout(usr_settings);
    save_user_settings(usr_settings);
  }

  bool repair_appearance = false;
#define REPAIR_APPEARANCE(value, lo, hi, fallback)                            \
  do {                                                                        \
    if (!isfinite(value) || (value) < (lo) || (value) > (hi)) {              \
      (value) = (fallback);                                                    \
      repair_appearance = true;                                               \
    }                                                                         \
  } while (0)
  REPAIR_APPEARANCE(usr_settings->joystick_opacity, 0.05f, 1.0f,
                    usr_settings->mobile_controls.opacity);
  REPAIR_APPEARANCE(usr_settings->boost_opacity, 0.05f, 1.0f,
                    usr_settings->mobile_controls.opacity);
  REPAIR_APPEARANCE(usr_settings->zoom_opacity, 0.05f, 1.0f,
                    usr_settings->mobile_controls.opacity);
  for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action) {
    REPAIR_APPEARANCE(usr_settings->hotkey_scale[action], 0.65f, 1.60f,
                      usr_settings->mobile_hotkeys.key_scale);
    REPAIR_APPEARANCE(usr_settings->hotkey_opacity[action], 0.05f, 1.0f,
                      usr_settings->mobile_hotkeys.opacity);
  }
  REPAIR_APPEARANCE(usr_settings->hud_stats_scale, 0.65f, 1.60f, 1.0f);
  REPAIR_APPEARANCE(usr_settings->hud_stats_opacity, 0.05f, 1.0f, 1.0f);
  REPAIR_APPEARANCE(usr_settings->hud_chat_scale, 0.65f, 1.60f, 1.0f);
  REPAIR_APPEARANCE(usr_settings->hud_chat_opacity, 0.05f, 1.0f, 1.0f);
#undef REPAIR_APPEARANCE
  if (repair_appearance) save_user_settings(usr_settings);
}

void save_user_settings(user_settings* usr_settings) {
  normalize_on_screen_buttons(usr_settings);
  strcpy(usr_settings->version, SETTINGS_VERSION);
  FILE* file = fopen(USER_SETTINGS_TEMP_FILE, "wb");
  if (!file) {
    printf("Error opening temporary settings file.\n");
    return;
  }
  bool written = fwrite(usr_settings, sizeof(*usr_settings), 1, file) == 1;
  if (fflush(file) != 0 || fclose(file) != 0) written = false;
  if (!written) {
    remove(USER_SETTINGS_TEMP_FILE);
    printf("Error writing settings snapshot.\n");
    return;
  }

  FILE* current = fopen(USER_SETTINGS_FILE, "rb");
  bool had_current = current != NULL;
  if (current) fclose(current);
  if (had_current) {
    remove(USER_SETTINGS_BACKUP_FILE);
    if (rename(USER_SETTINGS_FILE, USER_SETTINGS_BACKUP_FILE) != 0) {
      remove(USER_SETTINGS_TEMP_FILE);
      printf("Error preserving previous settings snapshot.\n");
      return;
    }
  }
  if (rename(USER_SETTINGS_TEMP_FILE, USER_SETTINGS_FILE) != 0) {
    if (had_current) rename(USER_SETTINGS_BACKUP_FILE, USER_SETTINGS_FILE);
    remove(USER_SETTINGS_TEMP_FILE);
    printf("Error committing settings snapshot.\n");
  }
}
