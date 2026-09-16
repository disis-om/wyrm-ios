#ifndef USER_SETTINGS_H
#define USER_SETTINGS_H

#include <cglm/cglm.h>
#include <stdbool.h>
#include <stdint.h>

#include "../constants.h"

typedef struct hotkey {
  int key;
  bool active;
  int mode;
  char description[MAX_HOTKEY_DESC_LENGTH + 1];
} hotkey;

typedef struct gameplay_mode {
  bool food_flicker;
  bool food_float;
  bool uniform_food_color;
  bool show_crosshair;
  bool show_boost;
  bool show_shadows;
  bool show_background;
  bool show_accessories;
  bool death_effect;
  bool player_names_outline;
  bool const_food_scale;
  int food_type;
  int boost_type;
  int render_mode;
  float food_scale;
  float qsm;
  float bg_scale;
  float boost_strength;
  vec3 food_color;
} gameplay_mode;

typedef enum mobile_handedness {
  MOBILE_LEFT_HANDED = 0,
  MOBILE_RIGHT_HANDED = 1
} mobile_handedness;

typedef enum mobile_joystick_mode {
  MOBILE_JOYSTICK_DYNAMIC = 0,
  MOBILE_JOYSTICK_FIXED = 1,
  MOBILE_STEERING_ARROW = 2
} mobile_joystick_mode;

typedef enum mobile_boost_mode {
  MOBILE_BOOST_TOUCH_ZONE = 0,
  MOBILE_BOOST_FIXED = 1
} mobile_boost_mode;

typedef enum mobile_zoom_orientation {
  MOBILE_ZOOM_HORIZONTAL = 0,
  MOBILE_ZOOM_VERTICAL = 1
} mobile_zoom_orientation;

typedef struct mobile_control_settings {
  int handedness;
  int joystick_mode;
  int boost_mode;
  int zoom_orientation;
  bool zoom_enabled;
  bool show_touch_zones;
  float joystick_x;
  float joystick_y;
  float boost_x;
  float boost_y;
  float zoom_x;
  float zoom_y;
  float joystick_size;
  float boost_size;
  float zoom_length;
  float opacity;
} mobile_control_settings;

typedef struct mobile_arrow_settings {
  bool boost_glow;
  float size;
  float separation;
  float smoothness;
  float color[4];
} mobile_arrow_settings;

typedef enum mobile_arrow_style {
  MOBILE_ARROW_CURRENT = 0,
  MOBILE_ARROW_CLASSIC_WIDE = 1,
  MOBILE_ARROW_NEEDLE = 2,
  MOBILE_ARROW_BLADE = 3,
  MOBILE_ARROW_TRIANGLE = 4
} mobile_arrow_style;

typedef struct mobile_hotkey_settings {
  bool visible[NUM_MOBILE_HOTKEYS];
  float x[NUM_MOBILE_HOTKEYS];
  float y[NUM_MOBILE_HOTKEYS];
  float opacity;
  int direct_keys[NUM_MOBILE_DIRECT_HOTKEYS];
  // v1.7: key glyph, function name, or both on the gameplay overlay.
  int label_mode;
  // v1.8: one shared, DPI-aware scale for every gameplay overlay key.
  float key_scale;
} mobile_hotkey_settings;

typedef enum mobile_hotkey_label_mode {
  MOBILE_HOTKEY_LABEL_KEY = 0,
  MOBILE_HOTKEY_LABEL_FUNCTION = 1,
  MOBILE_HOTKEY_LABEL_BOTH = 2
} mobile_hotkey_label_mode;

typedef struct user_settings {
  char version[4];
  char nickname[MAX_NICKNAME_LEN + 1];
  char ipv4[MAX_IPV4_LEN + 1];
  char skin_code[MAX_SKIN_CODE_LEN + 1];
  uint8_t accessory;
  bool custom_skin;
  uint8_t default_skin;
  int score;
  double play_time;
  int kills;
  font_size ui_font_size;
  font_size lb_font_size;
  font_size snake_names_font_size;
  font_size stats_font_size;

  // global settings:
  vec3 bd_color;
  vec4 laser_color;
  int laser_thickness;
  int cursor_size;
  int minimap_size;
  bool restart_rc;
  bool quit_mc;
  bool vsync;
  bool smooth_zoom;
  bool snake_scores;
  /* Whether your own name is drawn over your own snake. Off by default — you
     know what you called yourself — but in a crowd it is the fastest way to
     find which snake is yours. */
  bool show_own_name;

  /* Tags — the bobble that hangs from the head on a rope. The names match what
     the NTL mod calls them, because players arriving from it will go looking
     for exactly these. */
  int tag_index;   /* which tag you wear; -1 for none */
  float tag_chain; /* rope length. 1 is the length the mod started with */
  float tag_swing; /* how freely it swings; 1 is the mod's own feel */
  float tag_scale; /* overall size, on top of each tag's own */
  bool tags_small;
  bool tags_hidden;    /* hide every tag, including your own */
  bool tags_team_only; /* hide tags for snakes outside your team */

  bool instant_restart;
  float zoom_step;
  int bot_radius_mult;
  int bot_follow_circle_score;

  gameplay_mode modes[2];
  mobile_control_settings mobile_controls;

  // hotkeys:
  hotkey hotkeys[NUM_HOTKEYS];

  // Appended in settings v1.5 so v1.4 saves can be migrated in place.
  mobile_arrow_settings arrow_controls;

  // Appended in settings v1.6. Positions are normalized to the Android safe
  // area so a layout remains usable across resolutions and display cutouts.
  mobile_hotkey_settings mobile_hotkeys;

  /* Appended in settings v1.9, and reused rather than added to.
     It was
     briefly a death-screen delay; the delay stopped being a setting within the
     hour, and this slot became the auto-respawn flag instead. Same four bytes,
     same offset, so no save has to move for it. Non-zero means the snake comes
     straight back and the card never appears. */
  int auto_respawn;

  /* Appended in settings v2.0. Rope mode itself is session state; only the

   * draggable key's binding and layout belong in the durable settings file. */
  int rope_mode_key;
  bool rope_mode_visible;
  float rope_mode_x;
  float rope_mode_y;

  /* Appended in settings v2.1. Kept outside `arrow_controls` so every field
   * added after the v1.5 arrow block retains its old file offset. */
  int arrow_style;

  /* Appended in settings v2.2: one packed ARGB per position of `skin_code`.
   *
   * The wire only carries colour-group indices, so `skin_code` remains the
   * whole of what an arena is told. This runs alongside it and is Wyrm's own
   * decoration: the exact colour the player mixed, plus an alpha the protocol
   * has no way to express. A zero entry means the position was not built with
   * the picker and renders from the palette exactly as it always did. */
  uint32_t skin_rgba[MAX_SKIN_CODE_LEN];

  /* Appended in settings v2.3: which arena floor is drawn, as an index into
     the background table. The table is only ever appended to, so an index
     written by a newer build simply falls back on an older one. */
  int arena_background;

  /* Appended in settings v2.4: which client Wyrm last joined an arena as, as an
     index into the persona table in `network/arena_persona.h`.
     Only a match that outlived `SHORT_LIFE` writes here, so this is the last
     identity that demonstrably worked rather than the last one tried. It is a
     starting guess and never a constraint — the retry path stays free to
     alternate, and `arena_persona_get` clamps an index it does not know. */
  int arena_persona;

  /* Appended in settings v2.5: seconds the arena stays on screen after death
     before the lobby. 0 goes straight back. Max 4 s. Default 1.6 is original slither. */
  float death_hold_s;

  /* Appended in settings v2.6. The enable switch remains in each gameplay
     mode; size and colour live at the tail so older user.dat layouts remain a
     byte-for-byte prefix and can be migrated without moving any field. Values
     are screen pixels, which lets the Compose preview show the exact diameter
     the arena renderer will use. Index 0 is Normal, 1 is Assist. */
  float head_dot_size[2];
  vec3 head_dot_color[2];

  /* Appended in settings v2.7. Screen-space HUD centres, normalized to the
     current landscape viewport. World-space labels and gameplay controls do
     not belong here; these five pairs only place the arena overlay. */
  float hud_minimap_x;
  float hud_minimap_y;
  float hud_leaderboard_x;
  float hud_leaderboard_y;
  float hud_stats_x;
  float hud_stats_y;
  float hud_team_x;
  float hud_team_y;
  float hud_chat_x;
  float hud_chat_y;

  /* Appended in settings v2.8. Each editor object owns its appearance. The old
     global values remain in place for file compatibility and seed migration. */
  float joystick_opacity;
  float boost_opacity;
  float zoom_opacity;
  float hotkey_scale[NUM_MOBILE_ACTIONS];
  float hotkey_opacity[NUM_MOBILE_ACTIONS];
  float hud_stats_scale;
  float hud_stats_opacity;
  float hud_chat_scale;
  float hud_chat_opacity;
} user_settings;

void user_settings_default(user_settings* usr_settings);
void user_settings_reset_hud_layout(user_settings* usr_settings);
void read_user_settings(user_settings* usr_settings);
void save_user_settings(user_settings* usr_settings);

#endif
