#include "android_team.h"

#include <stdio.h>
#include <string.h>

#if defined(VLITHER_ANDROID) || defined(WYRM_IOS)
#include <SDL3/SDL.h>
#ifdef VLITHER_ANDROID
#include <jni.h>
#include <SDL3/SDL_system.h>
#endif

#include "../game/arena_theme.h"
#include "../game/tags.h"
#include "../game/ai_mode.h"
#include "android_home.h"
#include <math.h>
#include <stdlib.h>
#include "../user.h"

/*
 * Where the team is, held for exactly as long as it is true.
 *
 * The app polls the team service, parses it and hands the result down here as
 * one flat string; the engine keeps the last one it was given and draws from
 * it. Nothing here waits on a network, so a team service having a bad day
 * costs the arena nothing at all.
 */

#define TEAM_MAX_MEMBERS 16

typedef struct team_member {
  char name[40];
  int x;
  int y;
  int score;
  int rank;
  bool bot;
  /* Whether they are in the same arena as this player. Only those can be
     placed on the map — the coordinates of a snake in another arena mean
     nothing here. */
  bool present;
  int sid;
  int tag;
  /* Team HUD: the NTL key they play under and the arena they are in
     (empty in the menu). */
  char owner[40];
  char server[48];
} team_member;

static tenv* team_env = NULL;
static SDL_Mutex* team_mutex = NULL;
static team_member members[TEAM_MAX_MEMBERS];
static int member_count = 0;
static team_member frame_members[TEAM_MAX_MEMBERS];
static int frame_member_count = 0;
static int frame_tag_snakes[TEAM_MAX_MEMBERS];
static int frame_tag_snake_count = 0;

/* Where this player is, written by the engine thread and read by the app's. */
static char presence[256] = {0};
static Uint64 presence_published_at = 0;
static bool presence_was_playing = false;
#define PRESENCE_PUBLISH_MS 250

/*
 * Chat, and the bot that covers for you while you read it.
 *
 * The panel itself is drawn by the app, not here — while it is open the bot is
 * steering, so there is no gameplay touch left for it to take. All the engine
 * owns is the button that opens it, the bot state, and the countdown that
 * hands the snake back.
 */
static bool chat_open = false;
static double release_at = 0.0;

/*
 * Chat asks for the bot, it does not take it.
 *
 * Reading chat with nobody steering is how you die reading chat, so the button
 * refuses while the bot is off — and then has to say so, because a button that
 * does nothing is worse than one that is not there. What it says depends on
 * whether the player has a bot key of their own on the overlay: if they do,
 * they are told to use it; if they do not, one is put underneath the chat
 * button for them, because otherwise there is no way to turn the bot on at all.
 */
static Uint64 chat_hint_until = 0;
static bool chat_hint_has_own_key = false;
static bool bot_helper_shown = false;
static float bot_helper[4] = {0, 0, 0, 0};
#define CHAT_HINT_MS 5000
static float chat_button[4] = {0, 0, 0, 0};

/* Where the button hangs this frame, handed over by whoever drew the board it
   sits beside. Earned again every frame: a board that stops being drawn stops
   deciding where the button goes. */
static float chat_anchor[2] = {0, 0};
static bool chat_anchored = false;

/* ------------------------------------------------------------- team HUD
 *
 * The roster and the chat window (OM, 2026-10-04). Both are drawn here, as the
 * minimap is, so the layout editor shows exactly the same blocks over the AI
 * arena, with placeholder rows that say what each place holds. Their look
 * comes from the app (saved there and synced with the account); the chat's
 * size and opacity are the engine's own `hud_chat_scale` / `hud_chat_opacity`.
 */
enum {
  STYLE_TEAM_SCALE,
  STYLE_TEAM_OPACITY,
  STYLE_TEAM_WIDTH,
  STYLE_TEAM_HEIGHT,
  STYLE_TEAM_NAME,
  STYLE_TEAM_DATA,
  STYLE_CHAT_WIDTH,
  STYLE_CHAT_HEIGHT,
  STYLE_CHAT_NAME,
  STYLE_CHAT_TEXT,
  STYLE_COUNT
};
static float hud_style[STYLE_COUNT] = {1.0f,   1.0f,   340.0f, 210.0f, 0.0f,
                                       0.0f,   400.0f, 270.0f, 0.0f,   0.0f};

#define TEAM_CHAT_MAX 80
typedef struct team_chat_line {
  char author[40];
  char body[320];
} team_chat_line;
static team_chat_line chat_lines[TEAM_CHAT_MAX];
static int chat_line_count = 0;
static long chat_total = 0;
static unsigned chat_revision = 0;
static team_chat_line frame_chat[TEAM_CHAT_MAX];
static int frame_chat_count = 0;
static long frame_chat_total = 0;
static unsigned frame_chat_revision = 0;
static long seen_chat_total = -1;

static bool chat_expanded = true;
static float chat_scroll = 0.0f;   /* from the newest line up */
static float roster_scroll = 0.0f; /* from the first row down */
static float roster_rect[4] = {0, 0, 0, 0};
static float chat_rect[4] = {0, 0, 0, 0};
static float chat_header[4] = {0, 0, 0, 0};
static float chat_input[4] = {0, 0, 0, 0};
static int hud_touch_mode = 0; /* 0 none, 1 roster scroll, 2 chat scroll */
static unsigned long long hud_touch_finger = 0;
static float hud_touch_last_y = 0.0f;
/* Bumped when the message box is tapped; the iOS shell takes it. */
static SDL_AtomicInt composer_requests;

static float hud_clamp(float value, float low, float high) {
  if (!isfinite(value)) return low;
  return value < low ? low : (value > high ? high : value);
}

static bool hud_inside(const float* rect, float x, float y) {
  return rect[2] > 0.0f && x >= rect[0] && x <= rect[0] + rect[2] &&
         y >= rect[1] && y <= rect[1] + rect[3];
}

/* One tab-separated field of a member row, or empty. */
static void tab_field(const char* row, int index, char* out, size_t cap) {
  out[0] = '\0';
  const char* p = row;
  for (int i = 0; i < index; ++i) {
    p = strchr(p, '\t');
    if (!p) return;
    p++;
  }
  size_t n = strcspn(p, "\t\r\n");
  if (n >= cap) n = cap - 1;
  memcpy(out, p, n);
  out[n] = '\0';
}

/* Palette for the editor's colour choices; 0 keeps the theme's colour. */
static ImU32 hud_text_colour(int index, arena_theme_role fallback,
                             float alpha) {
  static const uint32_t palette[] = {0x000000, 0xFFFFFF, 0x111111,
                                     0xFFD54A, 0x4DD9FF, 0x5BE37D,
                                     0xFF6FB5, 0xFF9A3C, 0xFF5A5A};
  if (index <= 0 || index >= (int)(sizeof(palette) / sizeof(palette[0])))
    return arena_theme_colour(fallback, alpha);
  uint32_t c = palette[index];
  return igColorConvertFloat4ToU32((ImVec4){((c >> 16) & 255) / 255.0f,
                                            ((c >> 8) & 255) / 255.0f,
                                            (c & 255) / 255.0f, alpha});
}

static float hud_text_width(ImFont* font, float size, const char* text,
                            const char* end) {
  ImVec2 out;
  ImFont_CalcTextSizeA(&out, font, size, 1e9f, 0.0f, text, end, NULL);
  return out.x;
}

/* `text` cut to fit `width`, with "..." when it did not (whole UTF-8 letters
   only). */
static void hud_fit(ImFont* font, float size, const char* text, float width,
                    char* out, size_t cap) {
  snprintf(out, cap, "%s", text);
  if (hud_text_width(font, size, out, NULL) <= width) return;
  size_t n = strlen(out);
  while (n > 0) {
    n--;
    while (n > 0 && ((unsigned char)out[n] & 0xC0) == 0x80) n--;
    if (n + 4 > cap) continue;
    memcpy(out + n, "...", 4);
    if (hud_text_width(font, size, out, NULL) <= width) return;
  }
  out[0] = '\0';
}

/* Draws (or with no list, measures) `text` wrapped into `width`, its first
   line starting `indent` in. Returns the height used. */
static float hud_wrap(ImDrawList* draw, ImFont* font, float size, float x,
                      float y, float width, float indent, const char* text,
                      ImU32 colour) {
  const char* s = text;
  const char* end = text + strlen(text);
  float line = size * 1.22f;
  float cy = y;
  bool first = true;
  if (s == end) return line;
  while (s < end) {
    float avail = width - (first ? indent : 0.0f);
    if (avail < size) avail = size;
    const char* brk = ImFont_CalcWordWrapPosition(font, size, s, end, avail);
    if (!brk || brk <= s) {
      brk = s + 1;
      while (brk < end && ((unsigned char)*brk & 0xC0) == 0x80) brk++;
    }
    if (draw)
      ImDrawList_AddText_FontPtr(draw, font, size,
                                 (ImVec2){x + (first ? indent : 0.0f), cy},
                                 colour, s, brk, 0.0f, NULL);
    cy += line;
    first = false;
    s = brk;
    while (s < end && (*s == ' ' || *s == '\n')) s++;
  }
  return cy - y;
}

void android_team_set_hud_style(const float* values, int count) {
  if (!values) return;
  for (int i = 0; i < count && i < STYLE_COUNT; ++i)
    if (isfinite(values[i])) hud_style[i] = values[i];
}

void android_team_set_chat(const char* packed) {
  if (!team_mutex || !packed) return;
  SDL_LockMutex(team_mutex);
  chat_line_count = 0;
  chat_total = strtol(packed, NULL, 10);
  const char* line = strchr(packed, '\n');
  line = line ? line + 1 : "";
  /* Keep the newest TEAM_CHAT_MAX: count first, then skip the oldest. */
  int total_lines = 0;
  for (const char* p = line; *p;) {
    const char* e = strchr(p, '\n');
    total_lines++;
    if (!e) break;
    p = e + 1;
  }
  int skip = total_lines > TEAM_CHAT_MAX ? total_lines - TEAM_CHAT_MAX : 0;
  while (*line && chat_line_count < TEAM_CHAT_MAX) {
    const char* end = strchr(line, '\n');
    size_t length = end ? (size_t)(end - line) : strlen(line);
    if (skip > 0) {
      skip--;
    } else {
      const char* tab = memchr(line, '\t', length);
      team_chat_line* out = chat_lines + chat_line_count;
      size_t a = tab ? (size_t)(tab - line) : 0;
      if (a >= sizeof(out->author)) a = sizeof(out->author) - 1;
      memcpy(out->author, line, a);
      out->author[a] = '\0';
      const char* body = tab ? tab + 1 : line;
      size_t b = length - (size_t)(body - line);
      if (b >= sizeof(out->body)) b = sizeof(out->body) - 1;
      memcpy(out->body, body, b);
      out->body[b] = '\0';
      chat_line_count++;
    }
    line = end ? end + 1 : "";
  }
  chat_revision++;
  SDL_UnlockMutex(team_mutex);
}

static void snapshot_chat(void) {
  if (!team_mutex) return;
  SDL_LockMutex(team_mutex);
  if (chat_revision != frame_chat_revision) {
    frame_chat_revision = chat_revision;
    frame_chat_count = chat_line_count;
    frame_chat_total = chat_total;
    memcpy(frame_chat, chat_lines,
           sizeof(team_chat_line) * (size_t)chat_line_count);
  }
  SDL_UnlockMutex(team_mutex);
}

/* The editor shows the blocks with placeholder rows; not in the background
   size editor (map and board only) and not in Near Original, whose editor
   does not place them. */
static bool hud_preview(void) {
  return ai_mode_is_editor() && !ai_mode_editor_bare() &&
         !android_home_near_original();
}

static void hud_card(ImDrawList* draw, ImVec2 min, ImVec2 max, float radius,
                     float opacity) {
  ImDrawList_AddRectFilled(
      draw, (ImVec2){min.x, min.y + 3}, (ImVec2){max.x, max.y + 3},
      igColorConvertFloat4ToU32((ImVec4){0, 0, 0, 0.26f * opacity}), radius, 0);
  ImDrawList_AddRectFilled(draw, min, max,
                           arena_theme_colour(ARENA_THEME_CARD, 0.94f * opacity),
                           radius, 0);
  ImDrawList_AddRect(draw, min, max,
                     arena_theme_colour(ARENA_THEME_RULE, opacity), radius, 0,
                     1.0f);
}

/* Keeps a block of this size whole on screen, 16 px in from every edge. */
static void hud_place(tenv* env, float centre_x, float centre_y, float width,
                      float height, float* left, float* top) {
  *left = centre_x - width * 0.5f;
  *top = centre_y - height * 0.5f;
  float w = env->ctx->size[0], h = env->ctx->size[1];
  if (*left + width > w - 16.0f) *left = w - 16.0f - width;
  if (*top + height > h - 16.0f) *top = h - 16.0f - height;
  if (*left < 16.0f) *left = 16.0f;
  if (*top < 16.0f) *top = 16.0f;
}

void android_team_bind_env(tenv* env) {
  team_env = env;
  if (!team_mutex) team_mutex = SDL_CreateMutex();
}

void android_team_poll(tenv* env) {
  if (!env || !team_mutex) return;
  tuser_data* usr = env->usr;
  game_data* game = &usr->gdata;

  bool playing = game->conn == CONNECTED && game->curr_screen == PLAYING;
  Uint64 now = SDL_GetTicks();
  if (presence_published_at && playing == presence_was_playing &&
      now - presence_published_at < PRESENCE_PUBLISH_MS)
    return;
  presence_published_at = now;
  presence_was_playing = playing;

  int x = 0;
  int y = 0;
  int sid = 0;
  if (playing) {
    int length = tdarray_length(game->data.snakes);
    if (length > 0) {
      snake* me = game->data.snakes + (length - 1);
      if (game->data.snake_id == me->id) {
        x = (int)(me->xx + me->fx);
        y = (int)(me->yy + me->fy);
        sid = me->ntl_id;
      }
    }
  }

  /*
   * The tag goes out too, in the mod's own numbering.
   *
   * This is how a player using the NTL extension sees what a Wyrm player is
   * wearing: the service carries it and hands it to everyone on the network.
   * Read off the mod's own report, which sends `tg` beside the rest of this and
   * `sid` as the snake's id — the protocol note used to call `sid` "always 0,
   * never populated, unknown", and it is neither of those things.
   *
   * `-1` is no tag, which is what the mod sends when the player has none.
   */
  int tag = tags_ntl_id(usr->usrs.tag_index);
  int cosmetic = playing ? usr->usrs.accessory : -1;
  char line[sizeof(presence)];
  snprintf(line, sizeof(line), "%s\t%d\t%d\t%d\t%d\t%s\t%d\t%d\t%d\t%d",
           usr->usrs.nickname, playing ? game->data.score : 0, x, y,
           playing && usr->usrs.hotkeys[HOTKEY_BOT].active ? 1 : 0,
           playing ? usr->usrs.ipv4 : "_GAME_MENU_",
           playing ? game->data.rank : 0, sid, tag, cosmetic);

  SDL_LockMutex(team_mutex);
  memcpy(presence, line, sizeof(presence));
  SDL_UnlockMutex(team_mutex);
}

static int snapshot(team_member* out) {
  if (!team_mutex) return 0;
  SDL_LockMutex(team_mutex);
  int count = member_count;
  memcpy(out, members, sizeof(team_member) * (size_t)count);
  SDL_UnlockMutex(team_mutex);
  return count;
}

void android_team_begin_frame(void) {
  for (int i = 0; i < frame_tag_snake_count; ++i)
    tags_set(frame_tag_snakes[i], -1);
  frame_tag_snake_count = 0;
  frame_member_count = snapshot(frame_members);
  snapshot_chat();
  if (!team_env) return;
  game_data* game = &team_env->usr->gdata;
  int snake_count = tdarray_length(game->data.snakes);
  for (int i = 0; i < frame_member_count; ++i) {
    team_member* member = frame_members + i;
    if (!member->present || member->sid <= 0) continue;
    snake* target = snake_find_by_ntl_id(game->data.snakes, snake_count,
                                         member->sid);
    if (!target) continue;
    tags_set(target->id, tags_from_ntl_id(member->tag));
    frame_tag_snakes[frame_tag_snake_count++] = target->id;
  }
}

static ImU32 team_colour(float r, float g, float b, float a) {
  return igColorConvertFloat4ToU32((ImVec4){r, g, b, a});
}

void android_team_draw_minimap(tenv* env, float left, float top,
                               float diameter) {
  int count = frame_member_count;
  if (count <= 0 || diameter <= 0.0f) return;

  game_data* game = &env->usr->gdata;
  float world_radius = game->data.flux_grd;
  if (world_radius <= 1.0f) return;

  float centre_x = left + diameter * 0.5f;
  float centre_y = top + diameter * 0.5f;
  float radius = diameter * 0.026f;
  if (radius < 4.0f) radius = 4.0f;
  if (radius > 7.0f) radius = 7.0f;

  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(NULL);
  for (int i = 0; i < count; ++i) {
    if (!frame_members[i].present) continue;
    if (frame_members[i].x == 0 && frame_members[i].y == 0) continue;

    float nx = (frame_members[i].x - game->data.grd) / world_radius;
    float ny = (frame_members[i].y - game->data.grd) / world_radius;
    if (nx < -1.0f || nx > 1.0f || ny < -1.0f || ny > 1.0f) continue;

    ImVec2 point = {centre_x + nx * diameter * 0.40f,
                    centre_y + ny * diameter * 0.40f};
    /* A dark ring under the mark so it survives a pale patch of map, then
       Wyrm's green — the one colour the interface reserves for something that
       is alive right now. */
    ImDrawList_AddCircleFilled(draw, point, radius + 2.0f,
                               team_colour(0, 0, 0, 0.70f), 20);
    ImDrawList_AddCircleFilled(draw, point, radius,
                               arena_theme_colour(ARENA_THEME_LIVE, 1.0f), 20);
  }
}

float android_team_draw_roster_centered(tenv* env, float centre_x,
                                        float centre_y) {
  /* The roster (OM, 2026-10-04): each teammate's in-game name and score in
     bold, under it the NTL key they play under and the arena they are in.
     Its own scroll when the team is longer than the block. In the layout
     editor it shows placeholder rows that say what each place holds. */
  roster_rect[2] = 0.0f;
  roster_rect[3] = 0.0f;
  if (!env) return 0.0f;
  bool preview = hud_preview();
  int count = preview ? 3 : frame_member_count;
  if (count <= 0) return 0.0f;

  tuser_data* usr = env->usr;
  float scale = hud_clamp(hud_style[STYLE_TEAM_SCALE], 0.65f, 1.60f);
  float opacity = hud_clamp(hud_style[STYLE_TEAM_OPACITY], 0.05f, 1.0f);
  float width = hud_clamp(hud_style[STYLE_TEAM_WIDTH], 220.0f, 900.0f) * scale;
  float height = hud_clamp(hud_style[STYLE_TEAM_HEIGHT], 120.0f, 800.0f) * scale;
  int name_colour = (int)hud_style[STYLE_TEAM_NAME];
  int data_colour = (int)hud_style[STYLE_TEAM_DATA];
  /* Bold for names and scores: the body face's default instance is too
     light to read over the arena (OM, 2026-10-04). */
  ImFont* bold = usr->imgui_data.regular_font_bold[FONT_SIZE_SMALL];
  ImFont* regular = usr->imgui_data.regular_font[FONT_SIZE_SMALL];
  float name_size = bold->LegacySize * scale;
  float data_size = regular->LegacySize * 0.86f * scale;
  float pad = 12.0f * scale;
  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(NULL);

  float left, top;
  hud_place(env, centre_x, centre_y, width, height, &left, &top);
  ImVec2 min = {left, top};
  ImVec2 max = {left + width, top + height};
  hud_card(draw, min, max, 14.0f * scale, opacity);

  char title[24];
  snprintf(title, sizeof(title), "TEAM  %d", count);
  ImDrawList_AddText_FontPtr(draw, bold, data_size,
                             (ImVec2){min.x + pad, min.y + pad * 0.7f},
                             arena_theme_colour(ARENA_THEME_QUIET, opacity),
                             title, NULL, 0.0f, NULL);
  float rule_y = min.y + pad * 0.7f + data_size + 6.0f * scale;
  ImDrawList_AddLine(draw, (ImVec2){min.x + pad, rule_y},
                     (ImVec2){max.x - pad, rule_y},
                     arena_theme_colour(ARENA_THEME_RULE, 0.8f * opacity),
                     1.0f);

  float list_top = rule_y + 4.0f * scale;
  float list_bottom = max.y - pad * 0.6f;
  float list_height = list_bottom - list_top;
  float row_height = name_size + data_size + 12.0f * scale;
  float content = row_height * count;
  float most = content > list_height ? content - list_height : 0.0f;
  roster_scroll = hud_clamp(roster_scroll, 0.0f, most);

  ImDrawList_PushClipRect(draw, (ImVec2){min.x, list_top},
                          (ImVec2){max.x, list_bottom}, true);
  float text_left = min.x + pad + 14.0f * scale;
  float text_right = max.x - pad - (most > 0.0f ? 6.0f * scale : 0.0f);
  for (int i = 0; i < count; ++i) {
    float y = list_top + row_height * i - roster_scroll;
    if (y + row_height < list_top || y > list_bottom) continue;
    const char* name = preview ? "Player name" : frame_members[i].name;
    const char* owner = preview ? "Key name" : frame_members[i].owner;
    const char* server = preview ? "IP address" : frame_members[i].server;
    bool present = preview ? true : frame_members[i].present;
    char score_text[16];
    if (preview)
      snprintf(score_text, sizeof(score_text), "Score");
    else
      snprintf(score_text, sizeof(score_text), "%d", frame_members[i].score);
    if (!preview && !server[0]) server = "In the menu";
    if (!preview && !owner[0]) owner = "-";
    float alpha = (present ? 1.0f : 0.62f) * opacity;

    ImDrawList_AddCircleFilled(
        draw, (ImVec2){min.x + pad + 4.0f * scale, y + name_size * 0.55f},
        3.5f * scale,
        present ? arena_theme_colour(ARENA_THEME_LIVE, opacity)
                : arena_theme_colour(ARENA_THEME_MUTE, 0.6f * opacity),
        14);

    float score_w = hud_text_width(bold, name_size, score_text, NULL);
    char fitted[96];
    hud_fit(bold, name_size, name,
            text_right - text_left - score_w - 10.0f * scale, fitted,
            sizeof(fitted));
    ImDrawList_AddText_FontPtr(
        draw, bold, name_size, (ImVec2){text_left, y},
        hud_text_colour(name_colour, ARENA_THEME_INK, alpha), fitted, NULL,
        0.0f, NULL);
    ImDrawList_AddText_FontPtr(
        draw, bold, name_size, (ImVec2){text_right - score_w, y},
        hud_text_colour(name_colour, ARENA_THEME_INK, alpha), score_text,
        NULL, 0.0f, NULL);

    float data_y = y + name_size + 3.0f * scale;
    float half = (text_right - text_left) * 0.5f - 6.0f * scale;
    hud_fit(regular, data_size, owner, half, fitted, sizeof(fitted));
    ImDrawList_AddText_FontPtr(
        draw, regular, data_size, (ImVec2){text_left, data_y},
        hud_text_colour(data_colour, ARENA_THEME_QUIET, alpha), fitted, NULL,
        0.0f, NULL);
    hud_fit(regular, data_size, server, half, fitted, sizeof(fitted));
    float server_w = hud_text_width(regular, data_size, fitted, NULL);
    ImDrawList_AddText_FontPtr(
        draw, regular, data_size, (ImVec2){text_right - server_w, data_y},
        hud_text_colour(data_colour, ARENA_THEME_QUIET, alpha), fitted, NULL,
        0.0f, NULL);
  }
  ImDrawList_PopClipRect(draw);

  /* A thin bar says there is more, and where in the list you are. */
  if (most > 0.0f) {
    float bar = list_height * list_height / content;
    float bar_y = list_top + (list_height - bar) * (roster_scroll / most);
    ImDrawList_AddRectFilled(draw, (ImVec2){max.x - pad * 0.5f - 2.0f, bar_y},
                             (ImVec2){max.x - pad * 0.5f + 1.0f, bar_y + bar},
                             arena_theme_colour(ARENA_THEME_QUIET, 0.6f * opacity),
                             2.0f, 0);
  }

  roster_rect[0] = left;
  roster_rect[1] = top;
  roster_rect[2] = width;
  roster_rect[3] = height;
  return height;
}

/* -------------------------------------------------------------- chat + bot */

/**
 * Tells Compose the panel is up or down.
 *
 * Both directions go through here now. Only the opening did before, and the
 * closing was left to Compose noticing on its own — which it does when the
 * player closes the panel, and does not when the engine lets go of chat
 * underneath it. See `android_team_release_chat`.
 */
static void notify_java_chat(bool shown) {
#ifdef VLITHER_ANDROID
  JNIEnv* jni = (JNIEnv*)SDL_GetAndroidJNIEnv();
  if (!jni) return;
  jclass activity = (*jni)->FindClass(jni, "com/wyrm/omrajput/WyrmActivity");
  if (!activity) {
    (*jni)->ExceptionClear(jni);
    return;
  }
  jmethodID method = (*jni)->GetStaticMethodID(jni, activity,
                                               "setTeamChatFromNative", "(Z)V");
  if (method)
    (*jni)->CallStaticVoidMethod(jni, activity, method,
                                 shown ? JNI_TRUE : JNI_FALSE);
  if ((*jni)->ExceptionCheck(jni)) (*jni)->ExceptionClear(jni);
  (*jni)->DeleteLocalRef(jni, activity);
#else
  (void)shown;
#endif
}

/*
 * Chat no longer touches the bot, and that is the point.
 *
 * It used to force it on for as long as the panel was open and hand it back
 * afterwards, which is a reasonable idea and was the source of a run of bugs:
 * the hold outlived the panel, the death card captured the forced value as the
 * player's own preference, and a player who had never bound a bot key had no
 * way to undo any of it. Every one of those is the same mistake — the app
 * deciding something on the player's behalf and then having to remember to
 * undo it.
 *
 * So the bot is the player's, always. Chat asks whether it is on and refuses to
 * open if it is not, because reading chat with nobody steering is how you die
 * reading chat. `chat_button_hit` is where that is said out loud.
 */
static void open_chat(tenv* env) {
  (void)env;
  chat_open = true;
  release_at = 0.0;
  SDL_AddAtomicInt(&composer_requests, 1);
  notify_java_chat(true);
}

void android_team_close_chat(float seconds) {
  /* The seconds were a countdown before handing the snake back. Nothing is
     held any more, so there is nothing to hand back and nothing to count. */
  (void)seconds;
  chat_open = false;
  release_at = 0.0;
}

bool android_team_chat_open(void) { return chat_open; }

void android_team_release_chat(tenv* env) {
  bool was_open = chat_open;
  (void)env;
  chat_open = false;
  release_at = 0.0;

  /*
   * Compose has to be told, and this is where dying with chat open went wrong.
   *
   * Chat opening moves Compose to `Route.ARENA_CHAT` and remembers where it
   * came from. Dying calls this, which used to clear the engine's flags and
   * say nothing — so Compose stayed on the chat route while the engine went
   * back to thinking chat was closed. Then the death card came up and, on
   * Play, hid the whole interface with that route still latched. From there:
   * the surface never got its focus back, so nothing steered; the engine drew
   * its CHAT button but Compose's stale route swallowed the screen; and
   * opening chat again set `chatReturn` to the chat route itself, after which
   * closing chat returned to chat and the bot it holds could never be let go.
   *
   * Only on a real transition — this is also called every frame while out of a
   * match, and JNI on every one of those would be a poor idea.
   */
  if (was_open) notify_java_chat(false);
}

void android_team_tick(tenv* env) {
  if (!env) return;
  game_data* game = &env->usr->gdata;

  /* Leaving the arena closes chat, and that is all there is left to do here —
     the bot hold and its "TAKE THE SNAKE" countdown are gone with it. */
  if (game->curr_screen != PLAYING || game->conn != CONNECTED)
    android_team_release_chat(env);
}

void android_team_set_chat_centre(float centre_x, float centre_y) {
  chat_anchor[0] = centre_x;
  chat_anchor[1] = centre_y;
  chat_anchored = true;
}

void android_team_draw_chat_button(tenv* env) {
  /* The chat window (OM, 2026-10-04): the team chat, the same messages the
     app's Team page shows, open or folded to a pill, played through while
     open. Tap the header to fold it, the message box to write. */
  bool anchored = chat_anchored;
  chat_anchored = false;
  chat_rect[2] = 0.0f;
  chat_header[2] = 0.0f;
  chat_input[2] = 0.0f;
  chat_button[2] = 0.0f;
  chat_button[3] = 0.0f;
  if (!env || ai_mode_editor_bare()) return;
  bool preview = hud_preview();
  if (!preview) {
    if (env->usr->gdata.curr_screen != PLAYING ||
        env->usr->gdata.conn != CONNECTED)
      return;
    /* No team, no chat to show. */
    if (frame_member_count <= 0 && frame_chat_count <= 0) return;
  }

  tuser_data* usr = env->usr;
  float scale = hud_clamp(usr->usrs.hud_chat_scale, 0.65f, 1.60f);
  float opacity = hud_clamp(usr->usrs.hud_chat_opacity, 0.05f, 1.0f);
  int name_colour = (int)hud_style[STYLE_CHAT_NAME];
  int text_colour = (int)hud_style[STYLE_CHAT_TEXT];
  ImFont* bold = usr->imgui_data.regular_font_bold[FONT_SIZE_SMALL];
  ImFont* regular = usr->imgui_data.regular_font[FONT_SIZE_SMALL];
  float text_size = regular->LegacySize * scale;
  float label_size = bold->LegacySize * 0.86f * scale;
  float pad = 12.0f * scale;
  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(NULL);
  float centre_x = anchored ? chat_anchor[0] : env->ctx->size[0] - 220.0f;
  float centre_y = anchored ? chat_anchor[1] : 120.0f;
  bool open = preview || chat_expanded;

  long unread = 0;
  if (open)
    seen_chat_total = frame_chat_total;
  else if (seen_chat_total >= 0 && frame_chat_total > seen_chat_total)
    unread = frame_chat_total - seen_chat_total;
  if (seen_chat_total < 0) seen_chat_total = frame_chat_total;

  if (!open) {
    const char* label = "TEAM CHAT";
    float label_w = hud_text_width(bold, label_size, label, NULL);
    char badge[16] = {0};
    if (unread > 0) snprintf(badge, sizeof(badge), "%ld", unread > 99 ? 99 : unread);
    float badge_w = badge[0] ? hud_text_width(bold, label_size, badge, NULL) +
                                   14.0f * scale
                             : 0.0f;
    float width = label_w + badge_w + 44.0f * scale;
    float height = label_size + 26.0f * scale;
    float left, top;
    hud_place(env, centre_x, centre_y, width, height, &left, &top);
    ImVec2 min = {left, top}, max = {left + width, top + height};
    hud_card(draw, min, max, 999.0f, opacity);
    ImDrawList_AddText_FontPtr(
        draw, bold, label_size,
        (ImVec2){left + 22.0f * scale, top + (height - label_size) * 0.5f},
        arena_theme_colour(ARENA_THEME_INK, opacity), label, NULL, 0.0f, NULL);
    if (badge[0]) {
      float bx = left + 22.0f * scale + label_w + 8.0f * scale;
      float bh = label_size + 6.0f * scale;
      float by = top + (height - bh) * 0.5f;
      ImDrawList_AddRectFilled(draw, (ImVec2){bx, by},
                               (ImVec2){bx + badge_w, by + bh},
                               arena_theme_colour(ARENA_THEME_BADGE, opacity),
                               999.0f, 0);
      ImDrawList_AddText_FontPtr(
          draw, bold, label_size, (ImVec2){bx + 7.0f * scale, by + 3.0f * scale},
          team_colour(1, 1, 1, opacity), badge, NULL, 0.0f, NULL);
    }
    chat_rect[0] = chat_header[0] = left;
    chat_rect[1] = chat_header[1] = top;
    chat_rect[2] = chat_header[2] = width;
    chat_rect[3] = chat_header[3] = height;
    chat_button[0] = left;
    chat_button[1] = top;
    chat_button[2] = width;
    chat_button[3] = height;
    return;
  }

  float width = hud_clamp(hud_style[STYLE_CHAT_WIDTH], 240.0f, 1000.0f) * scale;
  float height = hud_clamp(hud_style[STYLE_CHAT_HEIGHT], 150.0f, 900.0f) * scale;
  float left, top;
  hud_place(env, centre_x, centre_y, width, height, &left, &top);
  ImVec2 min = {left, top}, max = {left + width, top + height};
  hud_card(draw, min, max, 14.0f * scale, opacity);

  /* Header: the title, and a bar that folds the window. */
  float header_h = label_size + 18.0f * scale;
  ImDrawList_AddText_FontPtr(
      draw, bold, label_size,
      (ImVec2){left + pad, top + (header_h - label_size) * 0.5f},
      arena_theme_colour(ARENA_THEME_QUIET, opacity), "TEAM CHAT", NULL, 0.0f,
      NULL);
  float fold_y = top + header_h * 0.5f;
  ImDrawList_AddLine(draw, (ImVec2){max.x - pad - 16.0f * scale, fold_y},
                     (ImVec2){max.x - pad, fold_y},
                     arena_theme_colour(ARENA_THEME_INK, 0.8f * opacity),
                     2.5f * scale);
  ImDrawList_AddLine(draw, (ImVec2){left + pad, top + header_h},
                     (ImVec2){max.x - pad, top + header_h},
                     arena_theme_colour(ARENA_THEME_RULE, 0.8f * opacity), 1.0f);

  /* The message box at the bottom. */
  float input_h = text_size + 16.0f * scale;
  ImVec2 input_min = {left + pad * 0.6f, max.y - pad * 0.6f - input_h};
  ImVec2 input_max = {max.x - pad * 0.6f, max.y - pad * 0.6f};
  ImDrawList_AddRectFilled(draw, input_min, input_max,
                           arena_theme_colour(ARENA_THEME_WELL, 0.9f * opacity),
                           999.0f, 0);
  ImDrawList_AddText_FontPtr(
      draw, regular, text_size,
      (ImVec2){input_min.x + pad, input_min.y + (input_h - text_size) * 0.5f},
      arena_theme_colour(ARENA_THEME_QUIET, opacity), "Message", NULL, 0.0f,
      NULL);

  /* The lines, newest at the bottom, scrolled by `chat_scroll`. */
  float list_top = top + header_h + 4.0f * scale;
  float list_bottom = input_min.y - 6.0f * scale;
  float list_left = left + pad;
  float list_width = width - pad * 2.0f;
  float gap = 5.0f * scale;
  static const char* sample[][2] = {{"Player name", "Message"},
                                    {"Player name", "Message"},
                                    {"Key name", "Message"},
                                    {"Player name", "Message"}};
  int lines = preview ? 4 : frame_chat_count;
  float content = 0.0f;
  for (int i = 0; i < lines; ++i) {
    const char* author = preview ? sample[i][0] : frame_chat[i].author;
    const char* body = preview ? sample[i][1] : frame_chat[i].body;
    char lead[48];
    snprintf(lead, sizeof(lead), "%s: ", author);
    float lead_w = hud_text_width(bold, text_size, lead, NULL);
    bool own_line = lead_w > list_width * 0.6f;
    float h = hud_wrap(NULL, regular, text_size, 0, 0, list_width,
                       own_line ? 0.0f : lead_w, body, 0);
    if (own_line) h += text_size * 1.22f;
    content += h + gap;
  }
  float list_height = list_bottom - list_top;
  float most = content > list_height ? content - list_height : 0.0f;
  chat_scroll = hud_clamp(chat_scroll, 0.0f, most);

  ImDrawList_PushClipRect(draw, (ImVec2){left, list_top},
                          (ImVec2){max.x, list_bottom}, true);
  if (lines == 0) {
    const char* empty = "No messages yet";
    float w = hud_text_width(regular, text_size, empty, NULL);
    ImDrawList_AddText_FontPtr(
        draw, regular, text_size,
        (ImVec2){left + (width - w) * 0.5f,
                 list_top + (list_height - text_size) * 0.5f},
        arena_theme_colour(ARENA_THEME_QUIET, opacity), empty, NULL, 0.0f,
        NULL);
  }
  float y = list_bottom + chat_scroll;
  for (int i = lines - 1; i >= 0; --i) {
    const char* author = preview ? sample[i][0] : frame_chat[i].author;
    const char* body = preview ? sample[i][1] : frame_chat[i].body;
    char lead[48];
    snprintf(lead, sizeof(lead), "%s: ", author);
    float lead_w = hud_text_width(bold, text_size, lead, NULL);
    bool own_line = lead_w > list_width * 0.6f;
    float h = hud_wrap(NULL, regular, text_size, 0, 0, list_width,
                       own_line ? 0.0f : lead_w, body, 0);
    if (own_line) h += text_size * 1.22f;
    y -= h + gap;
    if (y > list_bottom) continue;
    if (y + h < list_top) break;
    ImDrawList_AddText_FontPtr(
        draw, bold, text_size, (ImVec2){list_left, y},
        hud_text_colour(name_colour, ARENA_THEME_INK, opacity), lead, NULL,
        0.0f, NULL);
    float body_y = own_line ? y + text_size * 1.22f : y;
    hud_wrap(draw, regular, text_size, list_left, body_y, list_width,
             own_line ? 0.0f : lead_w, body,
             hud_text_colour(text_colour, ARENA_THEME_INK, 0.92f * opacity));
  }
  ImDrawList_PopClipRect(draw);

  chat_rect[0] = left;
  chat_rect[1] = top;
  chat_rect[2] = width;
  chat_rect[3] = height;
  chat_header[0] = left;
  chat_header[1] = top;
  chat_header[2] = width;
  chat_header[3] = header_h;
  chat_input[0] = input_min.x;
  chat_input[1] = input_min.y;
  chat_input[2] = input_max.x - input_min.x;
  chat_input[3] = input_max.y - input_min.y;
  /* The respawn toggle hangs off this, beside the header. */
  chat_button[0] = left;
  chat_button[1] = top;
  chat_button[2] = width;
  chat_button[3] = header_h;
}

bool android_team_hud_touch(tenv* env, int type, unsigned long long finger,
                            float x, float y) {
  if (!env) return false;
  if (env->usr->gdata.curr_screen != PLAYING ||
      env->usr->gdata.conn != CONNECTED) {
    hud_touch_mode = 0;
    return false;
  }
  if (type == SDL_EVENT_FINGER_DOWN) {
    if (hud_touch_mode) return false;
    if (hud_inside(chat_rect, x, y)) {
      if (!chat_expanded || hud_inside(chat_header, x, y)) {
        chat_expanded = !chat_expanded;
        chat_scroll = 0.0f;
        return true;
      }
      if (hud_inside(chat_input, x, y)) {
        open_chat(env);
        return true;
      }
      hud_touch_mode = 2;
    } else if (hud_inside(roster_rect, x, y)) {
      hud_touch_mode = 1;
    } else {
      return false;
    }
    hud_touch_finger = finger;
    hud_touch_last_y = y;
    return true;
  }
  if (!hud_touch_mode || finger != hud_touch_finger) return false;
  if (type == SDL_EVENT_FINGER_MOTION) {
    float dy = y - hud_touch_last_y;
    hud_touch_last_y = y;
    if (hud_touch_mode == 1)
      roster_scroll -= dy;
    else
      chat_scroll += dy;
    return true;
  }
  if (type == SDL_EVENT_FINGER_UP || type == SDL_EVENT_FINGER_CANCELED) {
    hud_touch_mode = 0;
    return true;
  }
  return false;
}

/* ------------------------------------------------- auto respawn, in the arena
 *
 * It lives beside the chat button because that is the only anchor on this side
 * of the screen, and it is drawn here for the same reason — `chat_button` is
 * the rectangle it hangs off.
 *
 * It is only ever shown while auto respawn is *on*, and pressing it only ever
 * turns it off. There is no second state to draw: once it is off, dying puts
 * the card up, and the card is where turning it back on lives. So the button
 * does not toggle in place, it leaves — and it leaves in a way you notice,
 * because a control that silently vanishes reads as a bug.
 */
/* Long enough after the match starts that it is not part of the rush of things
   appearing at once, and short enough to still be about this match. */
#define RESPAWN_ARRIVE_MS 3000
#define SPARKLE_MS 500

/*
 * All three timers are SDL ticks and none of them is `glfwGetTime()`.
 *
 * That distinction cost a bug: the arena calls `glfwSetTime(0)` on every
 * connect, so a timestamp taken before a match and compared after it goes
 * *negative*. The sparkle read as "still running, forever", and the button
 * never came back — turn it off, die, turn it back on from the card, and it
 * was simply gone for the rest of the session.
 */
static float respawn_button[4] = {0, 0, 0, 0};
static Uint64 respawn_arrive_at = 0;
static Uint64 respawn_leaving_at = 0;

/** The specks, thrown out or drawn in depending on which way it is going. */
static void draw_sparkle(ImDrawList* draw, float cx, float cy, float t,
                         bool arriving) {
  float spread = arriving ? (1.0f - t) : (1.0f - (1.0f - t) * (1.0f - t));
  float alpha = arriving ? t : (1.0f - t);
  for (int i = 0; i < 8; ++i) {
    float a = (float)i / 8.0f * 6.28318530718f;
    float reach = (26.0f + (i % 3) * 13.0f) * spread;
    ImVec2 at = {cx + cosf(a) * reach * 1.5f, cy + sinf(a) * reach};
    ImDrawList_AddCircleFilled(draw, at, 3.4f * alpha,
                               arena_theme_overlay_text(0.85f * alpha), 0);
  }
}

void android_team_draw_respawn_toggle(tenv* env) {
  respawn_button[2] = 0.0f;
  respawn_button[3] = 0.0f;
  if (!env) return;
  tuser_data* usr = env->usr;
  user_settings* usrs = &usr->usrs;

  if (usr->gdata.curr_screen != PLAYING || usr->gdata.conn != CONNECTED ||
      chat_button[2] <= 0.0f) {
    /* Out of the arena the count starts again, so every match gets its own
       three seconds rather than inheriting the last one's. */
    respawn_arrive_at = 0;
    respawn_leaving_at = 0;
    return;
  }

  Uint64 now = SDL_GetTicks();
  ImFont* font = usr->imgui_data.body_font[FONT_SIZE_REGULAR];
  /* Says what pressing it does, not what is currently true. "AUTO" said
     neither, and a button that only ever turns something off should say so. */
  const char* label = "TURN OFF AUTO";
  ImVec2 size;
  igPushFont(font, font->LegacySize);
  igCalcTextSize(&size, label, NULL, false, -1);
  igPopFont();

  float height = chat_button[3];
  float width = size.x + 44.0f;
  float x = chat_button[0] - width - 12.0f;
  float y = chat_button[1];
  float cx = x + width * 0.5f;
  float cy = y + height * 0.5f;
  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(NULL);

  if (!usrs->auto_respawn) {
    respawn_arrive_at = 0;
    if (!respawn_leaving_at) return;
    float t = (float)(now - respawn_leaving_at) / (float)SPARKLE_MS;
    if (t >= 1.0f) {
      respawn_leaving_at = 0;
      return;
    }
    draw_sparkle(draw, cx, cy, t, false);
    return;
  }

  respawn_leaving_at = 0;
  if (!respawn_arrive_at) respawn_arrive_at = now + RESPAWN_ARRIVE_MS;
  if (now < respawn_arrive_at) return;

  float t = (float)(now - respawn_arrive_at) / (float)SPARKLE_MS;
  if (t < 1.0f) {
    /* Arriving, the same way it leaves — so the two read as one thing coming
       and going rather than two unrelated effects. */
    draw_sparkle(draw, cx, cy, t, true);
    return;
  }

  respawn_button[0] = x;
  respawn_button[1] = y;
  respawn_button[2] = width;
  respawn_button[3] = height;

  ImVec2 min = {x, y};
  ImVec2 max = {x + width, y + height};
  ImDrawList_AddRectFilled(draw, (ImVec2){min.x, min.y + 3},
                           (ImVec2){max.x, max.y + 3},
                           team_colour(0, 0, 0, 0.26f), 999.0f, 0);
  /* Red rather than green: it is a stop, not a state. */
  ImDrawList_AddRectFilled(draw, min, max,
                           arena_theme_colour(ARENA_THEME_BADGE, 0.18f), 999.0f,
                           0);
  ImDrawList_AddRect(draw, min, max,
                     arena_theme_colour(ARENA_THEME_BADGE, 0.58f),
                     999.0f, 0, 1.5f);
  ImDrawList_AddText_FontPtr(draw, font, font->LegacySize,
                             (ImVec2){x + (width - size.x) * 0.5f,
                                      y + (height - size.y) * 0.5f},
                             arena_theme_colour(ARENA_THEME_BADGE, 1.0f), label,
                             NULL,
                             0, NULL);
}

bool android_team_respawn_toggle_hit(tenv* env, float x, float y) {
  if (!env || respawn_button[2] <= 0.0f) return false;
  if (env->usr->gdata.curr_screen != PLAYING ||
      env->usr->gdata.conn != CONNECTED)
    return false;
  bool hit = x >= respawn_button[0] &&
             x <= respawn_button[0] + respawn_button[2] &&
             y >= respawn_button[1] &&
             y <= respawn_button[1] + respawn_button[3];
  if (!hit) return false;
  env->usr->usrs.auto_respawn = 0;
  save_user_settings(&env->usr->usrs);
  respawn_leaving_at = SDL_GetTicks();
  respawn_arrive_at = 0;
  SDL_Log("Wyrm: auto respawn off");
  return true;
}

bool android_team_chat_button_hit(tenv* env, float x, float y) {
  /* The chat window takes its own touches now (android_team_hud_touch), and
     chat no longer asks for the bot: it is played through while open. */
  (void)env;
  (void)x;
  (void)y;
  return false;
}

/**
 * What the chat button said when it refused, and the key it offered.
 *
 * Drawn after the chat button so it can hang off its rectangle, and only while
 * in a match — a hint about steering means nothing on a menu.
 */
void android_team_draw_chat_help(tenv* env) {
  bot_helper[2] = 0.0f;
  bot_helper[3] = 0.0f;
  if (!env) return;
  tuser_data* usr = env->usr;
  user_settings* usrs = &usr->usrs;
  if (usr->gdata.curr_screen != PLAYING || usr->gdata.conn != CONNECTED) {
    /* Leaving the arena is the only thing that takes it away. */
    bot_helper_shown = false;
    chat_hint_until = 0;
    return;
  }
  /*
   * Chat being open hides it and must not forget it.
   *
   * That distinction is the whole of a bug: this used to clear the flag here,
   * so opening chat once and closing it took the button away for good — and
   * with it the only way a player without a bot key had of turning the bot
   * back off. Once it has been asked for, it stays for the rest of the match.
   */
  if (chat_open || chat_button[2] <= 0.0f) return;

  Uint64 now = SDL_GetTicks();
  bool bot_on = usrs->hotkeys[HOTKEY_BOT].active;
  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(NULL);
  float top = chat_button[1] + chat_button[3] + 10.0f;

  if (bot_helper_shown) {
    ImFont* font = usr->imgui_data.body_font[FONT_SIZE_REGULAR];
    const char* label = bot_on ? "BOT ON" : "BOT OFF";
    ImVec2 size;
    igPushFont(font, font->LegacySize);
    igCalcTextSize(&size, label, NULL, false, -1);
    igPopFont();

    float width = chat_button[2];
    float height = chat_button[3];
    float x = chat_button[0];
    ImVec2 min = {x, top};
    ImVec2 max = {x + width, top + height};
    bot_helper[0] = x;
    bot_helper[1] = top;
    bot_helper[2] = width;
    bot_helper[3] = height;

    ImDrawList_AddRectFilled(draw, (ImVec2){min.x, min.y + 3},
                             (ImVec2){max.x, max.y + 3},
                             team_colour(0, 0, 0, 0.26f), 999.0f, 0);
    ImDrawList_AddRectFilled(
        draw, min, max,
        bot_on ? arena_theme_colour(ARENA_THEME_LIVE, 0.26f)
               : arena_theme_colour(ARENA_THEME_CARD, 0.92f),
        999.0f, 0);
    ImDrawList_AddRect(draw, min, max,
                       bot_on ? arena_theme_colour(ARENA_THEME_LIVE, 0.60f)
                              : arena_theme_colour(ARENA_THEME_INK, 0.34f),
                       999.0f, 0, 1.5f);
    ImDrawList_AddText_FontPtr(draw, font, font->LegacySize,
                               (ImVec2){x + (width - size.x) * 0.5f,
                                        top + (height - size.y) * 0.5f},
                               arena_theme_colour(ARENA_THEME_INK, 0.94f), label,
                               NULL, 0, NULL);
    top += height + 10.0f;
  }

  if (now >= chat_hint_until) return;

  ImFont* font = usr->imgui_data.body_font[FONT_SIZE_LARGE];
  const char* text = chat_hint_has_own_key
                         ? "First turn on the bot mode"
                         : "Turn on the bot mode below the chat button";
  ImVec2 size;
  igPushFont(font, font->LegacySize);
  igCalcTextSize(&size, text, NULL, false, -1);
  igPopFont();

  float right = chat_button[0] + chat_button[2];
  ImVec2 min = {right - size.x - 34.0f, top};
  ImVec2 max = {right, top + size.y + 22.0f};
  ImDrawList_AddRectFilled(draw, (ImVec2){min.x, min.y + 3},
                           (ImVec2){max.x, max.y + 3},
                           team_colour(0, 0, 0, 0.30f), 12.0f, 0);
  ImDrawList_AddRectFilled(draw, min, max,
                           arena_theme_colour(ARENA_THEME_CARD, 0.96f), 12.0f,
                           0);
  ImDrawList_AddRect(draw, min, max,
                     arena_theme_colour(ARENA_THEME_BADGE, 0.55f),
                     12.0f, 0, 1.5f);
  ImDrawList_AddText_FontPtr(draw, font, font->LegacySize,
                             (ImVec2){min.x + 17.0f, min.y + 11.0f},
                             arena_theme_colour(ARENA_THEME_INK, 0.94f), text,
                             NULL, 0, NULL);
}

#ifdef VLITHER_ANDROID
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeCloseTeamChat(JNIEnv* env,
                                                         jclass clazz,
                                                         jfloat seconds) {
  (void)env;
  (void)clazz;
  android_team_close_chat(seconds);
}
#endif

/* ------------------------------------------------------------------ bridge */

/**
 * Where this player is, for the next poll.
 *
 * Tab separated: nickname, score, x, y, bot, arena, rank. The arena is the
 * literal `_GAME_MENU_` when not in a match, which is what the team service
 * expects and what tells the others you are not on the map.
 */
#ifdef VLITHER_ANDROID
JNIEXPORT jstring JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeTeamPresence(JNIEnv* env,
                                                        jclass clazz) {
  (void)clazz;
  if (!team_mutex) return (*env)->NewStringUTF(env, "");
  char line[sizeof(presence)];
  SDL_LockMutex(team_mutex);
  memcpy(line, presence, sizeof(line));
  SDL_UnlockMutex(team_mutex);
  return (*env)->NewStringUTF(env, line);
}
#endif

const char* WyrmIOSTeamPresenceSnapshot(void) {
  static char apple_presence[sizeof(presence)];
  if (!team_mutex) return "";
  SDL_LockMutex(team_mutex);
  memcpy(apple_presence, presence, sizeof(apple_presence));
  SDL_UnlockMutex(team_mutex);
  return apple_presence;
}

static void apply_team_members(const char* text) {
  if (!team_mutex) return;
  if (!text) text = "";

  team_member parsed[TEAM_MAX_MEMBERS];
  int count = 0;
  const char* line = text;
  while (*line && count < TEAM_MAX_MEMBERS) {
    const char* end = strchr(line, '\n');
    size_t length = end ? (size_t)(end - line) : strlen(line);
    char row[320];
    if (length >= sizeof(row)) length = sizeof(row) - 1;
    memcpy(row, line, length);
    row[length] = '\0';

    team_member* member = &parsed[count];
    memset(member, 0, sizeof(*member));
    int x = 0, y = 0, score = 0, rank = 0, bot = 0, present = 0;
    int sid = 0, tag = -1;
    char name[64] = {0};
    if (sscanf(row, "%63[^\t]\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d",
               name, &x, &y, &score, &rank, &bot, &present, &sid, &tag) == 9) {
      snprintf(member->name, sizeof(member->name), "%s", name);
      member->x = x;
      member->y = y;
      member->score = score;
      member->rank = rank;
      member->bot = bot != 0;
      member->present = present != 0;
      tab_field(row, 9, member->owner, sizeof(member->owner));
      tab_field(row, 10, member->server, sizeof(member->server));
      member->sid = sid;
      member->tag = tag;
      count++;
    }
    line = end ? end + 1 : "";
  }

  SDL_LockMutex(team_mutex);
  member_count = count;
  memcpy(members, parsed, sizeof(team_member) * (size_t)count);
  SDL_UnlockMutex(team_mutex);
}

void WyrmIOSSetTeamMembers(const char* packed) { apply_team_members(packed); }
void WyrmIOSSetTeamChat(const char* packed) { android_team_set_chat(packed); }
void WyrmIOSSetTeamHudStyle(const float* values, int count) {
  android_team_set_hud_style(values, count);
}
/* How many times the message box was tapped since the last call. */
int WyrmIOSTakeTeamComposerRequest(void) {
  return SDL_SetAtomicInt(&composer_requests, 0);
}

/** One line per member: name, x, y, score, rank, bot, in-this-arena. */
#ifdef VLITHER_ANDROID
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetTeamMembers(JNIEnv* env,
                                                          jclass clazz,
                                                          jstring packed) {
  (void)clazz;
  if (!team_mutex) return;
  const char* text = packed ? (*env)->GetStringUTFChars(env, packed, NULL) : "";

  apply_team_members(text);
  if (packed) (*env)->ReleaseStringUTFChars(env, packed, text);
}
#endif

#else

void android_team_bind_env(tenv* env) { (void)env; }
void android_team_poll(tenv* env) { (void)env; }
void android_team_begin_frame(void) {}
void android_team_tick(tenv* env) { (void)env; }
void android_team_draw_chat_button(tenv* env) { (void)env; }
void android_team_draw_respawn_toggle(tenv* env) { (void)env; }
void android_team_draw_chat_help(tenv* env) { (void)env; }
bool android_team_respawn_toggle_hit(tenv* env, float x, float y) {
  (void)env; (void)x; (void)y;
  return false;
}
bool android_team_chat_button_hit(tenv* env, float x, float y) {
  (void)env;
  (void)x;
  (void)y;
  return false;
}
void android_team_close_chat(float seconds) { (void)seconds; }
void android_team_release_chat(tenv* env) { (void)env; }
void android_team_set_chat_centre(float centre_x, float centre_y) {
  (void)centre_x;
  (void)centre_y;
}
bool android_team_chat_open(void) { return false; }
void android_team_set_chat(const char* packed) { (void)packed; }
void android_team_set_hud_style(const float* values, int count) {
  (void)values;
  (void)count;
}
bool android_team_hud_touch(tenv* env, int type, unsigned long long finger,
                            float x, float y) {
  (void)env;
  (void)type;
  (void)finger;
  (void)x;
  (void)y;
  return false;
}
void android_team_draw_minimap(tenv* env, float left, float top,
                               float diameter) {
  (void)env;
  (void)left;
  (void)top;
  (void)diameter;
}
float android_team_draw_roster_centered(tenv* env, float centre_x,
                                        float centre_y) {
  (void)env;
  (void)centre_x;
  (void)centre_y;
  return 0.0f;
}
const char* WyrmIOSTeamPresenceSnapshot(void) { return ""; }
void WyrmIOSSetTeamMembers(const char* packed) { (void)packed; }
void WyrmIOSSetTeamChat(const char* packed) { (void)packed; }
void WyrmIOSSetTeamHudStyle(const float* values, int count) {
  (void)values;
  (void)count;
}
int WyrmIOSTakeTeamComposerRequest(void) { return 0; }

#endif
