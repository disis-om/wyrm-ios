#include "android_settings.h"

#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#ifdef VLITHER_ANDROID
#include <SDL3/SDL.h>
#include <SDL3/SDL_system.h>
#include <jni.h>

#include "../game/tag_count.h"
#include "../mobile/mobile_controls.h"
#include "../mobile/mobile_hotkeys.h"
#include "../user.h"
#include "android_update.h"

/*
 * Everything the settings screens can touch, described once.
 *
 * The alternative was a JNI method per field and a Compose screen that knew
 * the engine's struct by heart; sixty fields in, that is sixty ways for the
 * two halves to disagree. Here the engine is the only thing that knows what a
 * setting is, what it ranges over and what its options are called, and the
 * interface renders whatever it is handed.
 */

typedef enum setting_type {
  SETTING_BOOL,
  SETTING_INT,
  SETTING_FLOAT,
  SETTING_ENUM,
  SETTING_COLOR3,
  SETTING_COLOR4
} setting_type;

typedef enum setting_owner {
  OWNER_SETTINGS,
  OWNER_CONTROLS,
  OWNER_ARROW,
  OWNER_KEYS
} setting_owner;

typedef struct setting_desc {
  const char* id;
  const char* group;
  const char* label;
  const char* hint;
  setting_type type;
  float minimum;
  float maximum;
  const char* options; /* "First|Second|Third", or NULL */
  setting_owner owner;
  size_t offset;
} setting_desc;

/* Fields on a gameplay mode, emitted once for Normal and once for Assist. */
typedef struct mode_desc {
  const char* id;
  const char* label;
  const char* hint;
  setting_type type;
  float minimum;
  float maximum;
  const char* options;
  size_t offset;
} mode_desc;

#define SETTINGS_FIELD(name) offsetof(user_settings, name)
#define SETTINGS_ARRAY_FIELD(name, index) \
  (offsetof(user_settings, name) + sizeof(float) * (index))
#define CONTROLS_FIELD(name) offsetof(mobile_control_settings, name)
#define ARROW_FIELD(name) offsetof(mobile_arrow_settings, name)
#define KEYS_FIELD(name) offsetof(mobile_hotkey_settings, name)
#define MODE_FIELD(name) offsetof(gameplay_mode, name)

static const setting_desc GLOBAL_FIELDS[] = {
    /* GENERAL. Mouse-button bindings are deliberately absent: this build has
       no middle or right button to bind them to. */
    {"general.vsync", "general", "VSync",
     "Caps the frame rate to the display. Off costs battery.", SETTING_BOOL, 0,
     1, NULL, OWNER_SETTINGS, SETTINGS_FIELD(vsync)},
    {"general.smooth_zoom", "general", "Smooth zoom",
     "Eases between zoom levels instead of snapping.", SETTING_BOOL, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(smooth_zoom)},
    {"general.zoom_step", "general", "Zoom step",
     "How far one zoom press travels.", SETTING_FLOAT, 0.05f, 0.5f, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(zoom_step)},
    {"general.snake_scores", "general", "Show snake scores",
     "Prints each snake's score under its name.", SETTING_BOOL, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(snake_scores)},
    {"general.show_own_name", "general", "Show own name",
     "Draws your name over your own snake, the way everyone else sees it.",
     SETTING_BOOL, 0, 1, NULL, OWNER_SETTINGS, SETTINGS_FIELD(show_own_name)},
    {"normal.head_dot_size", "normal", "Dot size",
     "Diameter relative to the snake head, independent of the screen.", SETTING_FLOAT, 4,
     32, NULL, OWNER_SETTINGS, SETTINGS_FIELD(head_dot_size)},
    {"normal.head_dot_color", "normal", "Dot colour", "", SETTING_COLOR3,
     0, 1, NULL, OWNER_SETTINGS, SETTINGS_FIELD(head_dot_color)},
    {"assist.head_dot_size", "assist", "Dot size",
     "Diameter relative to the snake head, independent of the screen.", SETTING_FLOAT, 4,
     32, NULL, OWNER_SETTINGS,
     SETTINGS_FIELD(head_dot_size) + sizeof(float)},
    {"assist.head_dot_color", "assist", "Dot colour", "", SETTING_COLOR3,
     0, 1, NULL, OWNER_SETTINGS,
     SETTINGS_FIELD(head_dot_color) + sizeof(vec3)},
    /* TAGS. These are bridged like everything else but they are not listed in
       the settings tree — the skin editor's Tags tab shows them, next to the
       preview, because every one of them is a thing you judge by looking at
       it. The ranges are the mod's own: chain 1 to 3, swing 1 to 2. */
    {"tags.index", "tags", "Tag",
     "Which tag hangs from your head. Below zero is none.", SETTING_INT, -1,
     TAG_COUNT - 1, NULL, OWNER_SETTINGS, SETTINGS_FIELD(tag_index)},
    {"tags.chain", "tags", "Chain length",
     "How far the tag trails behind the head.", SETTING_FLOAT, 1.0f, 3.0f, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(tag_chain)},
    {"tags.swing", "tags", "Swing",
     "How far the tag carries past a turn before it settles.", SETTING_FLOAT,
     1.0f, 2.0f, NULL, OWNER_SETTINGS, SETTINGS_FIELD(tag_swing)},
    {"tags.scale", "tags", "Size", "", SETTING_FLOAT, 0.4f, 2.0f, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(tag_scale)},
    {"tags.small", "tags", "Small tags",
     "Shrinks any tag that would otherwise be drawn large.", SETTING_BOOL, 0, 1,
     NULL, OWNER_SETTINGS, SETTINGS_FIELD(tags_small)},
    {"tags.hidden", "tags", "Hide all tags",
     "Hides every tag, including your own.", SETTING_BOOL, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(tags_hidden)},
    {"tags.team_only", "tags", "Team tags only",
     "Hides tags for snakes outside your team.", SETTING_BOOL, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(tags_team_only)},
    /* "Instant restart" used to sit here and had stopped meaning anything — the
       respawn became unconditional and the switch was left behind describing a
       pause that no longer existed. The pause is real again, and it is not a
       setting: the watch lasts exactly as long as the arena is willing to keep
       a dead player connected, which is not a number anyone can usefully pick
       in advance. See `android_home.c`. */
    {"general.minimap_size", "general", "Minimap size", "", SETTING_INT, 128,
     512, NULL, OWNER_SETTINGS, SETTINGS_FIELD(minimap_size)},
    {"general.cursor_size", "general", "Cursor size", "", SETTING_INT, 16, 64,
     NULL, OWNER_SETTINGS, SETTINGS_FIELD(cursor_size)},
    {"general.bd_color", "general", "Arena border",
     "The colour of the world's edge.", SETTING_COLOR3, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(bd_color)},

    {"general.ui_font", "general.type", "Interface text", "", SETTING_ENUM, 0,
     2, "Small|Regular|Large", OWNER_SETTINGS, SETTINGS_FIELD(ui_font_size)},
    {"general.stats_font", "general.type", "Stats text", "", SETTING_ENUM, 0, 2,
     "Small|Regular|Large", OWNER_SETTINGS, SETTINGS_FIELD(stats_font_size)},
    {"general.lb_font", "general.type", "Leaderboard text", "", SETTING_ENUM, 0,
     2, "Small|Regular|Large", OWNER_SETTINGS, SETTINGS_FIELD(lb_font_size)},
    {"general.name_font", "general.type", "Player names", "", SETTING_ENUM, 0,
     2, "Small|Regular|Large", OWNER_SETTINGS,
     SETTINGS_FIELD(snake_names_font_size)},

    {"general.laser_color", "general.bot", "Laser colour", "", SETTING_COLOR4,
     0, 1, NULL, OWNER_SETTINGS, SETTINGS_FIELD(laser_color)},
    {"general.laser_thickness", "general.bot", "Laser thickness", "",
     SETTING_INT, 1, 4, NULL, OWNER_SETTINGS, SETTINGS_FIELD(laser_thickness)},
    {"general.bot_circle", "general.bot", "Circle after score",
     "The score at which the bot starts circling instead of hunting.",
     SETTING_INT, 1000, 6000, NULL, OWNER_SETTINGS,
     SETTINGS_FIELD(bot_follow_circle_score)},
    {"general.bot_radius", "general.bot", "Bot radius",
     "How wide the bot keeps its distance.", SETTING_INT, 10, 40, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(bot_radius_mult)},

    /* CONTROLS. Steering is one choice of three rather than a checkbox and a
       menu that can contradict each other. */
    {"controls.joystick_mode", "controls", "Steering",
     "How you point the snake.", SETTING_ENUM, 0, 2,
     "Joystick under finger|Fixed joystick|Arrow drag", OWNER_CONTROLS,
     CONTROLS_FIELD(joystick_mode)},
    {"controls.handedness", "controls", "Handedness",
     "Which side the joystick lives on.", SETTING_ENUM, 0, 1,
     "Left handed|Right handed", OWNER_CONTROLS, CONTROLS_FIELD(handedness)},
    {"controls.joystick_size", "controls", "Joystick size", "", SETTING_FLOAT,
     0.65f, 1.45f, NULL, OWNER_CONTROLS, CONTROLS_FIELD(joystick_size)},
    {"controls.opacity", "controls", "Control opacity",
     "How solid the controls sit over the arena.", SETTING_FLOAT, 0.25f, 1.0f,
     NULL, OWNER_CONTROLS, CONTROLS_FIELD(opacity)},

    {"controls.boost_mode", "controls.boost", "Boost method", "", SETTING_ENUM,
     0, 1, "Tap the other half|Boost button", OWNER_CONTROLS,
     CONTROLS_FIELD(boost_mode)},
    {"controls.boost_size", "controls.boost", "Boost button size", "",
     SETTING_FLOAT, 0.65f, 1.45f, NULL, OWNER_CONTROLS,
     CONTROLS_FIELD(boost_size)},

    {"controls.zoom_enabled", "controls.zoom", "Show zoom bar", "",
     SETTING_BOOL, 0, 1, NULL, OWNER_CONTROLS, CONTROLS_FIELD(zoom_enabled)},
    {"controls.zoom_orientation", "controls.zoom", "Zoom bar", "", SETTING_ENUM,
     0, 1, "Horizontal|Vertical", OWNER_CONTROLS,
     CONTROLS_FIELD(zoom_orientation)},
    {"controls.zoom_length", "controls.zoom", "Zoom bar length", "",
     SETTING_FLOAT, 0.65f, 1.55f, NULL, OWNER_CONTROLS,
     CONTROLS_FIELD(zoom_length)},

    {"arrow.size", "controls.arrow", "Arrow size", "", SETTING_FLOAT, 0.30f,
     2.40f, NULL, OWNER_ARROW, ARROW_FIELD(size)},
    {"arrow.style", "controls.arrow", "Arrow style", "", SETTING_ENUM, 0, 4,
     "Classic|Classic wide|Needle|Blade|Triangle", OWNER_SETTINGS,
     SETTINGS_FIELD(arrow_style)},
    /* Both of these changed meaning when the arrow became relative steering.
       The drag is cumulative and has no maximum, so there is no "distance at
       full drag" to set any more — what is left to choose is where the arrow
       starts, and how lazily the drawn one follows the real one. Neither
       touches the heading; see "wise newton/arrow implementation.md". */
    {"arrow.separation", "controls.arrow", "Start distance",
     "How far ahead of the head the arrow begins. It moves from there with "
     "your thumb.",
     SETTING_FLOAT, 0.40f, 2.00f, NULL, OWNER_ARROW, ARROW_FIELD(separation)},
    {"arrow.smoothness", "controls.arrow", "Arrow lag",
     "How lazily the arrow follows your thumb. Steering is never smoothed — "
     "only the arrow you are looking at.",
     SETTING_FLOAT, 0.0f, 0.85f, NULL, OWNER_ARROW, ARROW_FIELD(smoothness)},
    {"arrow.color", "controls.arrow", "Arrow colour", "", SETTING_COLOR3, 0, 1,
     NULL, OWNER_ARROW, ARROW_FIELD(color)},

    /* ON-SCREEN BUTTONS. Positions and per-action modes use their own bridge. */
    {"keys.key_scale", "keys", "Button size", "", SETTING_FLOAT, 0.65f, 1.60f,
     NULL, OWNER_KEYS, KEYS_FIELD(key_scale)},
    {"keys.opacity", "keys", "Button opacity", "", SETTING_FLOAT, 0.25f, 1.0f,
     NULL, OWNER_KEYS, KEYS_FIELD(opacity)},
    {"layout.joystick_opacity", "layout", "", "", SETTING_FLOAT, 0.05f, 1.0f,
     NULL, OWNER_SETTINGS, SETTINGS_FIELD(joystick_opacity)},
    {"layout.boost_opacity", "layout", "", "", SETTING_FLOAT, 0.05f, 1.0f,
     NULL, OWNER_SETTINGS, SETTINGS_FIELD(boost_opacity)},
    {"layout.zoom_opacity", "layout", "", "", SETTING_FLOAT, 0.05f, 1.0f,
     NULL, OWNER_SETTINGS, SETTINGS_FIELD(zoom_opacity)},
#define KEY_APPEARANCE(action)                                                \
    {"layout.key_" #action "_scale", "layout", "", "", SETTING_FLOAT,     \
     0.65f, 1.60f, NULL, OWNER_SETTINGS,                                      \
     SETTINGS_ARRAY_FIELD(hotkey_scale, action)},                             \
    {"layout.key_" #action "_opacity", "layout", "", "", SETTING_FLOAT,   \
     0.05f, 1.0f, NULL, OWNER_SETTINGS,                                       \
     SETTINGS_ARRAY_FIELD(hotkey_opacity, action)}
    KEY_APPEARANCE(1),
    KEY_APPEARANCE(2),
    KEY_APPEARANCE(3),
    KEY_APPEARANCE(4),
    KEY_APPEARANCE(6),
    KEY_APPEARANCE(7),
    KEY_APPEARANCE(8),
    KEY_APPEARANCE(9),
#undef KEY_APPEARANCE
    {"layout.stats_scale", "layout", "", "", SETTING_FLOAT, 0.65f, 1.60f,
     NULL, OWNER_SETTINGS, SETTINGS_FIELD(hud_stats_scale)},
    {"layout.stats_opacity", "layout", "", "", SETTING_FLOAT, 0.05f, 1.0f,
     NULL, OWNER_SETTINGS, SETTINGS_FIELD(hud_stats_opacity)},
    {"layout.chat_scale", "layout", "", "", SETTING_FLOAT, 0.65f, 1.60f,
     NULL, OWNER_SETTINGS, SETTINGS_FIELD(hud_chat_scale)},
    {"layout.chat_opacity", "layout", "", "", SETTING_FLOAT, 0.05f, 1.0f,
     NULL, OWNER_SETTINGS, SETTINGS_FIELD(hud_chat_opacity)},
    /* LAYOUT. Written by the landscape editors, never listed as rows. */
    {"layout.joystick_x", "layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_CONTROLS, CONTROLS_FIELD(joystick_x)},
    {"layout.joystick_y", "layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_CONTROLS, CONTROLS_FIELD(joystick_y)},
    {"layout.boost_x", "layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_CONTROLS, CONTROLS_FIELD(boost_x)},
    {"layout.boost_y", "layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_CONTROLS, CONTROLS_FIELD(boost_y)},
    {"layout.zoom_x", "layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_CONTROLS, CONTROLS_FIELD(zoom_x)},
    {"layout.zoom_y", "layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_CONTROLS, CONTROLS_FIELD(zoom_y)},
    {"hud.minimap_x", "hud.layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(hud_minimap_x)},
    {"hud.minimap_y", "hud.layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(hud_minimap_y)},
    {"hud.leaderboard_x", "hud.layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(hud_leaderboard_x)},
    {"hud.leaderboard_y", "hud.layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(hud_leaderboard_y)},
    {"hud.stats_x", "hud.layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(hud_stats_x)},
    {"hud.stats_y", "hud.layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(hud_stats_y)},
    {"hud.team_x", "hud.layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(hud_team_x)},
    {"hud.team_y", "hud.layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(hud_team_y)},
    {"hud.chat_x", "hud.layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(hud_chat_x)},
    {"hud.chat_y", "hud.layout", "", "", SETTING_FLOAT, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(hud_chat_y)},
};

static const mode_desc MODE_FIELDS[] = {
    {"show_background", "Show background", "", SETTING_BOOL, 0, 1, NULL,
     MODE_FIELD(show_background)},
    {"bg_scale", "Background scale", "", SETTING_FLOAT, 0.05f, 4.0f, NULL,
     MODE_FIELD(bg_scale)},
    {"show_crosshair", "Head collision dot",
     "Marks the front collision point in Dynamic and Fixed joystick modes. Hidden in Arrow mode.",
     SETTING_BOOL, 0, 1, NULL,
     MODE_FIELD(show_crosshair)},
    {"show_accessories", "Show accessories",
     "Hats and other worn items on every snake.", SETTING_BOOL, 0, 1, NULL,
     MODE_FIELD(show_accessories)},
    {"show_shadows", "Show shadows", "", SETTING_BOOL, 0, 1, NULL,
     MODE_FIELD(show_shadows)},
    {"death_effect", "Death effect", "", SETTING_BOOL, 0, 1, NULL,
     MODE_FIELD(death_effect)},
    {"player_names_outline", "Outline names", "", SETTING_BOOL, 0, 1, NULL,
     MODE_FIELD(player_names_outline)},
    {"render_mode", "Snake rendering", "", SETTING_ENUM, 0, 2,
     "Texture|Solid|Flat", MODE_FIELD(render_mode)},
    {"qsm", "Segment separation", "Higher values space the body out.",
     SETTING_FLOAT, 1.0f, 4.0f, NULL, MODE_FIELD(qsm)},
    {"show_boost", "Boost effect", "", SETTING_BOOL, 0, 1, NULL,
     MODE_FIELD(show_boost)},
    {"boost_type", "Boost style", "", SETTING_ENUM, 0, 1, "Normal|Simple",
     MODE_FIELD(boost_type)},
    {"boost_strength", "Boost strength", "", SETTING_FLOAT, 0.25f, 3.0f, NULL,
     MODE_FIELD(boost_strength)},
    {"food_type", "Food style", "", SETTING_ENUM, 0, 8,
     "Original|Rings|Mixed|Star|Triangle|Diamond|Hexagon|Square|Flower",
     MODE_FIELD(food_type)},
    {"food_scale", "Food size", "", SETTING_FLOAT, 0.25f, 3.0f, NULL,
     MODE_FIELD(food_scale)},
    {"food_float", "Food drifts", "", SETTING_BOOL, 0, 1, NULL,
     MODE_FIELD(food_float)},
    {"food_flicker", "Food flickers", "", SETTING_BOOL, 0, 1, NULL,
     MODE_FIELD(food_flicker)},
    {"const_food_scale", "Constant food size",
     "Food stays the same size however far you are zoomed out.", SETTING_BOOL,
     0, 1, NULL, MODE_FIELD(const_food_scale)},
    {"uniform_food_color", "One food colour", "", SETTING_BOOL, 0, 1, NULL,
     MODE_FIELD(uniform_food_color)},
    {"food_color", "Food colour", "", SETTING_COLOR3, 0, 1, NULL,
     MODE_FIELD(food_color)},
};

static const int GLOBAL_COUNT =
    (int)(sizeof(GLOBAL_FIELDS) / sizeof(GLOBAL_FIELDS[0]));
static const int MODE_COUNT =
    (int)(sizeof(MODE_FIELDS) / sizeof(MODE_FIELDS[0]));

/* Every key an action can be bound to, in the order they are offered. */
static const int BINDABLE_KEYS[] = {
    GLFW_KEY_0,    GLFW_KEY_1,     GLFW_KEY_2,    GLFW_KEY_3,     GLFW_KEY_4,
    GLFW_KEY_5,    GLFW_KEY_6,     GLFW_KEY_7,    GLFW_KEY_8,     GLFW_KEY_9,
    GLFW_KEY_A,    GLFW_KEY_B,     GLFW_KEY_C,    GLFW_KEY_D,     GLFW_KEY_E,
    GLFW_KEY_F,    GLFW_KEY_G,     GLFW_KEY_H,    GLFW_KEY_I,     GLFW_KEY_J,
    GLFW_KEY_K,    GLFW_KEY_L,     GLFW_KEY_M,    GLFW_KEY_N,     GLFW_KEY_O,
    GLFW_KEY_P,    GLFW_KEY_Q,     GLFW_KEY_R,    GLFW_KEY_S,     GLFW_KEY_T,
    GLFW_KEY_U,    GLFW_KEY_V,     GLFW_KEY_W,    GLFW_KEY_X,     GLFW_KEY_Y,
    GLFW_KEY_Z,    GLFW_KEY_SPACE, GLFW_KEY_LEFT, GLFW_KEY_RIGHT, GLFW_KEY_UP,
    GLFW_KEY_DOWN, GLFW_KEY_F11};
static const int BINDABLE_COUNT =
    (int)(sizeof(BINDABLE_KEYS) / sizeof(BINDABLE_KEYS[0]));

static tenv* settings_env = NULL;
static SDL_Mutex* settings_mutex = NULL;

/* The mailbox. Compose writes, the engine drains once a frame. */
typedef struct pending_change {
  char id[56];
  float values[4];
  int count;
} pending_change;

#define MAX_PENDING 128
static pending_change pending[MAX_PENDING];
static int pending_count = 0;

typedef struct pending_hotkey {
  bool used;
  int key;
  int mode;
  bool visible;
  float x;
  float y;
} pending_hotkey;
static pending_hotkey pending_hotkeys[NUM_MOBILE_ACTIONS];

/* 1 reset everything, 2 controls, 4 buttons, 8 arena HUD positions. */
static int pending_actions = 0;

void android_settings_bind_env(tenv* env) {
  settings_env = env;
  if (!settings_mutex) settings_mutex = SDL_CreateMutex();
}

static void* owner_base(user_settings* settings, setting_owner owner) {
  switch (owner) {
    case OWNER_CONTROLS:
      return &settings->mobile_controls;
    case OWNER_ARROW:
      return &settings->arrow_controls;
    case OWNER_KEYS:
      return &settings->mobile_hotkeys;
    case OWNER_SETTINGS:
    default:
      return settings;
  }
}

/** Resolves an id to the field it names, and to how that field is shaped. */
static bool resolve(user_settings* settings, const char* id, void** out_field,
                    setting_type* out_type) {
  for (int i = 0; i < GLOBAL_COUNT; ++i) {
    if (strcmp(GLOBAL_FIELDS[i].id, id) != 0) continue;
    *out_field = (char*)owner_base(settings, GLOBAL_FIELDS[i].owner) +
                 GLOBAL_FIELDS[i].offset;
    *out_type = GLOBAL_FIELDS[i].type;
    return true;
  }
  int mode_index = -1;
  const char* field = NULL;
  if (strncmp(id, "normal.", 7) == 0) {
    mode_index = 0;
    field = id + 7;
  } else if (strncmp(id, "assist.", 7) == 0) {
    mode_index = 1;
    field = id + 7;
  }
  if (mode_index < 0) return false;
  for (int i = 0; i < MODE_COUNT; ++i) {
    if (strcmp(MODE_FIELDS[i].id, field) != 0) continue;
    *out_field = (char*)&settings->modes[mode_index] + MODE_FIELDS[i].offset;
    *out_type = MODE_FIELDS[i].type;
    return true;
  }
  return false;
}

static void write_field(tenv* env, const char* id, const float* values,
                        int count) {
  user_settings* settings = &env->usr->usrs;

  /* A control position is one value. Applying its axes together prevents an
     orientation change or a busy native frame from persisting only half of a
     drag. */
  if (count >= 2 && (strncmp(id, "layout.", 7) == 0 ||
                     strncmp(id, "hud.", 4) == 0)) {
    float* x = NULL;
    float* y = NULL;
    if (strcmp(id, "layout.joystick") == 0) {
      x = &settings->mobile_controls.joystick_x;
      y = &settings->mobile_controls.joystick_y;
    } else if (strcmp(id, "layout.boost") == 0) {
      x = &settings->mobile_controls.boost_x;
      y = &settings->mobile_controls.boost_y;
    } else if (strcmp(id, "layout.zoom") == 0) {
      x = &settings->mobile_controls.zoom_x;
      y = &settings->mobile_controls.zoom_y;
    } else if (strcmp(id, "hud.minimap") == 0) {
      x = &settings->hud_minimap_x;
      y = &settings->hud_minimap_y;
    } else if (strcmp(id, "hud.leaderboard") == 0) {
      x = &settings->hud_leaderboard_x;
      y = &settings->hud_leaderboard_y;
    } else if (strcmp(id, "hud.stats") == 0) {
      x = &settings->hud_stats_x;
      y = &settings->hud_stats_y;
    } else if (strcmp(id, "hud.team") == 0) {
      x = &settings->hud_team_x;
      y = &settings->hud_team_y;
    } else if (strcmp(id, "hud.chat") == 0) {
      x = &settings->hud_chat_x;
      y = &settings->hud_chat_y;
    }
    if (x && y && isfinite(values[0]) && isfinite(values[1])) {
      *x = values[0] < 0.0f ? 0.0f : (values[0] > 1.0f ? 1.0f : values[0]);
      *y = values[1] < 0.0f ? 0.0f : (values[1] > 1.0f ? 1.0f : values[1]);
    }
    return;
  }

  /* Swapping hands mirrors the layout as well as the flag, so it goes through
     the engine's own routine rather than straight into the field. */
  if (strcmp(id, "controls.handedness") == 0 && count >= 1) {
    mobile_controls_set_handedness(env, (int)values[0]);
    return;
  }

  void* field = NULL;
  setting_type type = SETTING_BOOL;
  if (!resolve(settings, id, &field, &type)) {
    SDL_Log("Wyrm settings: unknown setting '%s'", id);
    return;
  }

  switch (type) {
    case SETTING_BOOL:
      *(bool*)field = values[0] != 0.0f;
      break;
    case SETTING_INT:
    case SETTING_ENUM:
      *(int*)field = (int)(values[0] + (values[0] < 0 ? -0.5f : 0.5f));
      break;
    case SETTING_FLOAT:
      *(float*)field = values[0];
      break;
    case SETTING_COLOR3:
    case SETTING_COLOR4: {
      float* channels = (float*)field;
      int wanted = type == SETTING_COLOR3 ? 3 : 4;
      for (int i = 0; i < wanted && i < count; ++i) channels[i] = values[i];
      break;
    }
  }

  /* Existing settings pages still expose a group appearance control. It now
     means "set all", while the layout popup can tune each object afterwards. */
  if (strcmp(id, "controls.opacity") == 0) {
    settings->joystick_opacity = settings->mobile_controls.opacity;
    settings->boost_opacity = settings->mobile_controls.opacity;
    settings->zoom_opacity = settings->mobile_controls.opacity;
  } else if (strcmp(id, "keys.key_scale") == 0) {
    for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action)
      settings->hotkey_scale[action] = settings->mobile_hotkeys.key_scale;
  } else if (strcmp(id, "keys.opacity") == 0) {
    for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action)
      settings->hotkey_opacity[action] = settings->mobile_hotkeys.opacity;
  }

  if (strcmp(id, "general.vsync") == 0) {
    env->config.vsync = settings->vsync;
    twindow_request_refresh(env->wnd);
  }
}

void android_settings_poll(tenv* env) {
  if (!env || !settings_mutex) return;

  pending_change changes[MAX_PENDING];
  pending_hotkey hotkeys[NUM_MOBILE_ACTIONS];
  int count = 0;
  int actions = 0;

  SDL_LockMutex(settings_mutex);
  count = pending_count;
  if (count > 0)
    memcpy(changes, pending, sizeof(pending_change) * (size_t)count);
  memcpy(hotkeys, pending_hotkeys, sizeof(pending_hotkeys));
  actions = pending_actions;
  pending_count = 0;
  pending_actions = 0;
  memset(pending_hotkeys, 0, sizeof(pending_hotkeys));
  SDL_UnlockMutex(settings_mutex);

  bool dirty = count > 0 || actions != 0;

  if (actions & 1) {
    user_settings_default(&env->usr->usrs);
    env->config.vsync = env->usr->usrs.vsync;
    twindow_request_refresh(env->wnd);
  }
  if (actions & 2) mobile_controls_reset_layout(env);
  if (actions & 4) mobile_hotkeys_reset_layout(env);
  if (actions & 8) user_settings_reset_hud_layout(&env->usr->usrs);

  for (int i = 0; i < count; ++i)
    write_field(env, changes[i].id, changes[i].values, changes[i].count);

  user_settings* settings = &env->usr->usrs;
  for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action) {
    if (!hotkeys[action].used) continue;
    dirty = true;
    mobile_hotkey_set_key(settings, action, hotkeys[action].key);
    if (action < NUM_HOTKEYS)
      settings->hotkeys[action].mode = hotkeys[action].mode;
    mobile_hotkey_set_layout(settings, action, hotkeys[action].visible,
                             hotkeys[action].x, hotkeys[action].y);
  }

  /* Settings are written the moment they change rather than on a Save button:
     there is no Save button any more, and a setting that survives only until
     the next crash is not a setting. */
  if (dirty) save_user_settings(settings);
}

/* ---------------------------------------------------------------- snapshots */

typedef struct text_builder {
  char* text;
  size_t length;
  size_t capacity;
} text_builder;

static void append(text_builder* builder, const char* piece) {
  size_t extra = strlen(piece);
  if (builder->length + extra + 1 > builder->capacity) return;
  memcpy(builder->text + builder->length, piece, extra + 1);
  builder->length += extra;
}

static void append_float(text_builder* builder, float value) {
  char buffer[32];
  snprintf(buffer, sizeof(buffer), "%.4f", value);
  append(builder, buffer);
}

static void append_int(text_builder* builder, int value) {
  char buffer[32];
  snprintf(buffer, sizeof(buffer), "%d", value);
  append(builder, buffer);
}

static void append_value(text_builder* builder, const void* field,
                         setting_type type) {
  switch (type) {
    case SETTING_BOOL:
      append(builder, *(const bool*)field ? "1" : "0");
      break;
    case SETTING_INT:
    case SETTING_ENUM:
      append_int(builder, *(const int*)field);
      break;
    case SETTING_FLOAT:
      append_float(builder, *(const float*)field);
      break;
    case SETTING_COLOR3:
    case SETTING_COLOR4: {
      const float* channels = (const float*)field;
      int wanted = type == SETTING_COLOR3 ? 3 : 4;
      for (int i = 0; i < wanted; ++i) {
        if (i) append(builder, ",");
        append_float(builder, channels[i]);
      }
      break;
    }
  }
}

static const char* type_name(setting_type type) {
  switch (type) {
    case SETTING_BOOL:
      return "bool";
    case SETTING_INT:
      return "int";
    case SETTING_FLOAT:
      return "float";
    case SETTING_ENUM:
      return "enum";
    case SETTING_COLOR3:
      return "color3";
    case SETTING_COLOR4:
      return "color4";
  }
  return "float";
}

/* One row: id, group, type, label, hint, value, min, max, options. */
static void append_row(text_builder* builder, const char* id, const char* group,
                       const char* label, const char* hint, setting_type type,
                       float minimum, float maximum, const char* options,
                       const void* field) {
  append(builder, id);
  append(builder, "\t");
  append(builder, group);
  append(builder, "\t");
  append(builder, type_name(type));
  append(builder, "\t");
  append(builder, label);
  append(builder, "\t");
  append(builder, hint ? hint : "");
  append(builder, "\t");
  append_value(builder, field, type);
  append(builder, "\t");
  append_float(builder, minimum);
  append(builder, "\t");
  append_float(builder, maximum);
  append(builder, "\t");
  append(builder, options ? options : "");
  append(builder, "\n");
}

JNIEXPORT jstring JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSettingsSnapshot(JNIEnv* env,
                                                           jclass clazz) {
  (void)clazz;
  if (!settings_env) return (*env)->NewStringUTF(env, "");
  user_settings* settings = &settings_env->usr->usrs;

  static char buffer[32768];
  text_builder builder = {buffer, 0, sizeof(buffer)};
  buffer[0] = '\0';

  for (int i = 0; i < GLOBAL_COUNT; ++i) {
    const setting_desc* desc = &GLOBAL_FIELDS[i];
    const void* field =
        (const char*)owner_base(settings, desc->owner) + desc->offset;
    append_row(&builder, desc->id, desc->group, desc->label, desc->hint,
               desc->type, desc->minimum, desc->maximum, desc->options, field);
  }
  for (int mode = 0; mode < 2; ++mode) {
    const char* prefix = mode == 0 ? "normal." : "assist.";
    for (int i = 0; i < MODE_COUNT; ++i) {
      const mode_desc* desc = &MODE_FIELDS[i];
      char id[64];
      snprintf(id, sizeof(id), "%s%s", prefix, desc->id);
      const void* field = (const char*)&settings->modes[mode] + desc->offset;
      append_row(&builder, id, mode == 0 ? "normal" : "assist", desc->label,
                 desc->hint, desc->type, desc->minimum, desc->maximum,
                 desc->options, field);
    }
  }
  return (*env)->NewStringUTF(env, buffer);
}

/* One row per action: index, name, key, keyName, mode, fixedMode, visible, x,
 * y. */
JNIEXPORT jstring JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeHotkeysSnapshot(JNIEnv* env,
                                                          jclass clazz) {
  (void)clazz;
  if (!settings_env) return (*env)->NewStringUTF(env, "");
  user_settings* settings = &settings_env->usr->usrs;

  static char buffer[4096];
  text_builder builder = {buffer, 0, sizeof(buffer)};
  buffer[0] = '\0';

  for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action) {
    if (!mobile_hotkey_is_on_screen_button(action)) continue;
    if (!WYRM_EXPERIMENTAL_ROPE_MODE && action == MOBILE_HOTKEY_ROPE_MODE)
      continue;
    /* Restart, quit and the movement actions have no toggle to offer: they
       either fire or they are held, and saying otherwise would be a lie in a
       dropdown. */
    bool fixed_mode = action >= NUM_HOTKEYS || action == HOTKEY_RESTART ||
                      action == HOTKEY_QUIT;
    int mode = fixed_mode
                   ? (mobile_hotkey_is_hold_action(settings, action) ? 1 : 0)
                   : settings->hotkeys[action].mode;
    append_int(&builder, action);
    append(&builder, "\t");
    append(&builder, mobile_hotkey_action_name(action));
    append(&builder, "\t");
    append_int(&builder, mobile_hotkey_get_key(settings, action));
    append(&builder, "\t");
    append(&builder, mobile_hotkey_key_name(settings, action));
    append(&builder, "\t");
    append_int(&builder, mode);
    append(&builder, "\t");
    append(&builder, fixed_mode ? "1" : "0");
    append(&builder, "\t");
    bool visible = false;
    float x = 0.5f;
    float y = 0.22f;
    mobile_hotkey_get_layout(settings, action, &visible, &x, &y);
    append(&builder, visible ? "1" : "0");
    append(&builder, "\t");
    append_float(&builder, x);
    append(&builder, "\t");
    append_float(&builder, y);
    append(&builder, "\n");
  }
  return (*env)->NewStringUTF(env, buffer);
}

/** Every bindable key and what it is called, so the list is the engine's. */
JNIEXPORT jstring JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeKeyOptions(
    JNIEnv* env, jclass clazz) {
  (void)clazz;
  if (!settings_env) return (*env)->NewStringUTF(env, "");

  static char buffer[2048];
  text_builder builder = {buffer, 0, sizeof(buffer)};
  buffer[0] = '\0';

  user_settings preview = settings_env->usr->usrs;
  for (int i = 0; i < BINDABLE_COUNT; ++i) {
    mobile_hotkey_set_key(&preview, HOTKEY_HUD, BINDABLE_KEYS[i]);
    append_int(&builder, BINDABLE_KEYS[i]);
    append(&builder, "\t");
    append(&builder, mobile_hotkey_key_name(&preview, HOTKEY_HUD));
    append(&builder, "\n");
  }
  return (*env)->NewStringUTF(env, buffer);
}

/**
 * The version stamped on the settings file.
 *
 * Read off the loaded settings rather than off the build, so what is shown is
 * the version of the file actually in use — which is the useful one when a save
 * has just been migrated, or has failed to be and been rewritten from defaults.
 */
JNIEXPORT jstring JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSettingsVersion(JNIEnv* env,
                                                          jclass clazz) {
  (void)clazz;
  if (!settings_env) return (*env)->NewStringUTF(env, "");
  return (*env)->NewStringUTF(env, settings_env->usr->usrs.version);
}

/* ------------------------------------------------------------------ writers */

JNIEXPORT void JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeSetSetting(
    JNIEnv* env, jclass clazz, jstring id, jfloat a, jfloat b, jfloat c,
    jfloat d, jint count) {
  (void)clazz;
  if (!settings_mutex || !id) return;
  const char* text = (*env)->GetStringUTFChars(env, id, NULL);
  SDL_LockMutex(settings_mutex);
  pending_change* change = NULL;
  /* A drag or slider can outpace the render thread. Only the newest pending
     value for the same field matters, so replace it instead of filling the
     mailbox with stale intermediate positions. */
  for (int i = pending_count - 1; i >= 0; --i) {
    if (text && strcmp(pending[i].id, text) == 0) {
      change = &pending[i];
      break;
    }
  }
  if (!change && pending_count < MAX_PENDING)
    change = &pending[pending_count++];
  if (change) {
    snprintf(change->id, sizeof(change->id), "%s", text ? text : "");
    change->values[0] = a;
    change->values[1] = b;
    change->values[2] = c;
    change->values[3] = d;
    change->count = count < 1 ? 1 : (count > 4 ? 4 : count);
  }
  SDL_UnlockMutex(settings_mutex);
  if (text) (*env)->ReleaseStringUTFChars(env, id, text);
}

JNIEXPORT void JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeSetHotkey(
    JNIEnv* env, jclass clazz, jint action, jint key, jint mode,
    jboolean visible, jfloat x, jfloat y) {
  (void)env;
  (void)clazz;
  if (!settings_mutex || action < 0 || action >= NUM_MOBILE_ACTIONS) return;
  SDL_LockMutex(settings_mutex);
  pending_hotkeys[action] =
      (pending_hotkey){true, key, mode, visible == JNI_TRUE, x, y};
  SDL_UnlockMutex(settings_mutex);
}

JNIEXPORT void JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeSettingsAction(
    JNIEnv* env, jclass clazz, jint action) {
  (void)env;
  (void)clazz;
  if (!settings_mutex) return;
  SDL_LockMutex(settings_mutex);
  pending_actions |= (int)action;
  SDL_UnlockMutex(settings_mutex);
}

/* ------------------------------------------------------------------ updates */

/**
 * The updater, as one line of text.
 *
 * status, progress, title, detail, version — everything the Check for updates
 * screen shows. The updater itself is untouched: this only gives Compose the
 * same view the old native screen had.
 */
JNIEXPORT jstring JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeUpdateSnapshot(JNIEnv* env,
                                                         jclass clazz) {
  (void)clazz;
  android_update_snapshot snapshot;
  android_update_get_snapshot(&snapshot);

  static char buffer[2048];
  snprintf(buffer, sizeof(buffer), "%d\t%d\t%s\t%s\t%s\t%d\t%d\t%s\t%s",
           snapshot.update_status, snapshot.update_progress,
           snapshot.update_title, snapshot.update_detail,
           snapshot.available_version_name, snapshot.backup_status,
           snapshot.backup_count, snapshot.backup_title,
           snapshot.backup_detail);
  return (*env)->NewStringUTF(env, buffer);
}

/** Update actions 0..1; backup actions 2..5. Java performs their I/O. */
JNIEXPORT void JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeUpdateAction(
    JNIEnv* env, jclass clazz, jint action) {
  (void)env;
  (void)clazz;
  if (!settings_env) return;
  if (action == 0) {
    android_update_check();
  } else if (action == 1) {
    android_update_download(&settings_env->usr->usrs,
                            sizeof(settings_env->usr->usrs));
  } else if (action == 2) {
    android_update_create_backup(&settings_env->usr->usrs,
                                 sizeof(settings_env->usr->usrs));
  } else if (action == 3) {
    android_update_check_backups();
  } else if (action == 4) {
    android_update_restore_latest();
  } else if (action == 5) {
    android_update_choose_backup_folder();
  }
}

#else

void android_settings_bind_env(tenv* env) { (void)env; }
void android_settings_poll(tenv* env) { (void)env; }

#endif
