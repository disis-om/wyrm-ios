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
  char line[sizeof(presence)];
  snprintf(line, sizeof(line), "%s\t%d\t%d\t%d\t%d\t%s\t%d\t%d\t%d",
           usr->usrs.nickname, playing ? game->data.score : 0, x, y,
           playing && usr->usrs.hotkeys[HOTKEY_BOT].active ? 1 : 0,
           playing ? usr->usrs.ipv4 : "_GAME_MENU_",
           playing ? game->data.rank : 0, sid, tag);

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
  int count = frame_member_count;
  if (count <= 0) return 0.0f;

  tuser_data* usr = env->usr;
  ImFont* label_font = usr->imgui_data.body_font[FONT_SIZE_SMALL];
  ImFont* name_font = usr->imgui_data.body_font[FONT_SIZE_SMALL];
  ImFont* score_font = usr->imgui_data.display_font[FONT_SIZE_SMALL];
  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(NULL);

  ImVec2 title_size, sample;
  igPushFont(label_font, label_font->LegacySize);
  igCalcTextSize(&title_size, "TEAM", NULL, false, -1);
  igPopFont();
  igPushFont(score_font, score_font->LegacySize);
  igCalcTextSize(&sample, "000000", NULL, false, -1);
  igPopFont();

  const float pad = 12.0f;
  float row_height = sample.y + 4.0f;
  float width = 210.0f;
  float height = pad + title_size.y + 8.0f + row_height * count + pad * 0.6f;

  float left = centre_x - width * 0.5f;
  float top = centre_y - height * 0.5f;
  if (left < 16.0f) left = 16.0f;
  if (top < 16.0f) top = 16.0f;
  if (left + width > env->ctx->size[0] - 16.0f)
    left = env->ctx->size[0] - 16.0f - width;
  if (top + height > env->ctx->size[1] - 16.0f)
    top = env->ctx->size[1] - 16.0f - height;
  ImVec2 min = {left, top};
  ImVec2 max = {left + width, top + height};
  ImDrawList_AddRectFilled(draw, (ImVec2){min.x, min.y + 3},
                           (ImVec2){max.x, max.y + 3},
                           team_colour(0, 0, 0, 0.26f), 14.0f, 0);
  ImDrawList_AddRectFilled(draw, min, max,
                           arena_theme_colour(ARENA_THEME_CARD, 0.94f), 14.0f,
                           0);
  ImDrawList_AddRect(draw, min, max,
                     arena_theme_colour(ARENA_THEME_RULE, 1.0f), 14.0f, 0,
                     1.0f);

  ImDrawList_AddText_FontPtr(draw, label_font, label_font->LegacySize,
                             (ImVec2){min.x + pad, min.y + pad * 0.7f},
                             arena_theme_colour(ARENA_THEME_QUIET, 0.86f),
                             "TEAM", NULL, 0, NULL);
  float rule_y = min.y + pad * 0.7f + title_size.y + 4.0f;
  ImDrawList_AddLine(draw, (ImVec2){min.x + pad, rule_y},
                     (ImVec2){max.x - pad, rule_y},
                     arena_theme_colour(ARENA_THEME_RULE, 0.8f),
                     1.0f);

  float y = rule_y + 5.0f;
  for (int i = 0; i < count; ++i) {
    /* Present in this arena, or somewhere else entirely — the difference is
       the whole reason to look at this block, so it is the brightest thing
       about a row. */
    float alpha = frame_members[i].present ? 1.0f : 0.42f;
    ImDrawList_AddCircleFilled(
        draw, (ImVec2){min.x + pad + 4.0f, y + row_height * 0.45f}, 3.5f,
        frame_members[i].present
            ? arena_theme_colour(ARENA_THEME_LIVE, alpha)
            : arena_theme_colour(ARENA_THEME_MUTE, 0.45f),
        14);

    ImDrawList_AddText_FontPtr(draw, name_font, name_font->LegacySize,
                               (ImVec2){min.x + pad + 16.0f, y + 2.0f},
                               arena_theme_colour(ARENA_THEME_INK, 0.86f * alpha),
                               frame_members[i].name, NULL, 0, NULL);

    char score_text[16];
    snprintf(score_text, sizeof(score_text), "%d", frame_members[i].score);
    ImVec2 measured;
    igPushFont(score_font, score_font->LegacySize);
    igCalcTextSize(&measured, score_text, NULL, false, -1);
    igPopFont();
    ImDrawList_AddText_FontPtr(draw, score_font, score_font->LegacySize,
                               (ImVec2){max.x - pad - measured.x, y},
                               arena_theme_colour(ARENA_THEME_INK, alpha),
                               score_text, NULL, 0,
                               NULL);
    y += row_height;
  }
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
  chat_open = true;
  release_at = 0.0;
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
  bool anchored = chat_anchored;
  chat_anchored = false;
  if (!env || chat_open) {
    /* A button that is not on screen has no hit area. Leaving the last one
       behind meant a rectangle from the previous match — or the previous
       orientation, which is a different shape entirely — still opened chat
       when a thumb landed in it. */
    chat_button[2] = 0.0f;
    chat_button[3] = 0.0f;
    return;
  }
  tuser_data* usr = env->usr;
  float scale = usr->usrs.hud_chat_scale;
  float opacity = usr->usrs.hud_chat_opacity;
  ImFont* font = usr->imgui_data.body_font[FONT_SIZE_REGULAR];
  const char* label = "CHAT";
  ImVec2 size;
  igPushFont(font, font->LegacySize);
  igCalcTextSize(&size, label, NULL, false, -1);
  igPopFont();

  /* Sized like something meant to be hit with a thumb in the middle of a
     match, not like a label: the first one was measured off its own text and
     came out too small to aim at. */
  float width = (size.x + 52.0f) * scale;
  if (width < 124.0f * scale) width = 124.0f * scale;
  float height = (size.y + 34.0f) * scale;
  if (height < 56.0f * scale) height = 56.0f * scale;

  /* Beside the leaderboard, where the eye already goes. Without a board — the
     interface hidden — it takes the board's own corner. */
  float x = anchored ? chat_anchor[0] - width * 0.5f
                     : env->ctx->size[0] - 16.0f - width;
  float y = anchored ? chat_anchor[1] - height * 0.5f : 16.0f;
  if (x < 16.0f) x = 16.0f;
  if (y < 16.0f) y = 16.0f;
  if (x + width > env->ctx->size[0] - 16.0f)
    x = env->ctx->size[0] - 16.0f - width;
  if (y + height > env->ctx->size[1] - 16.0f)
    y = env->ctx->size[1] - 16.0f - height;
  chat_button[0] = x;
  chat_button[1] = y;
  chat_button[2] = width;
  chat_button[3] = height;

  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(NULL);
  ImVec2 min = {x, y};
  ImVec2 max = {x + width, y + height};
  ImDrawList_AddRectFilled(draw, (ImVec2){min.x, min.y + 3},
                           (ImVec2){max.x, max.y + 3},
                           team_colour(0, 0, 0, 0.26f * opacity), 999.0f, 0);
  ImDrawList_AddRectFilled(draw, min, max,
                           arena_theme_colour(ARENA_THEME_CARD, 0.92f * opacity), 999.0f,
                           0);
  ImDrawList_AddRect(draw, min, max,
                     arena_theme_colour(ARENA_THEME_INK, 0.34f), 999.0f, 0,
                     1.5f);
  ImDrawList_AddText_FontPtr(draw, font, font->LegacySize,
                             (ImVec2){x + (width - size.x) * 0.5f,
                                      y + (height - size.y) * 0.5f},
                             arena_theme_colour(ARENA_THEME_INK, 0.94f), label,
                             NULL, 0, NULL);
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
  if (!env || chat_open || chat_button[2] <= 0.0f) return false;
  if (env->usr->gdata.curr_screen != PLAYING ||
      env->usr->gdata.conn != CONNECTED)
    return false;

  /* The offered bot key first — it sits under the chat button and would
     otherwise be unreachable behind it. */
  if (bot_helper[2] > 0.0f && x >= bot_helper[0] &&
      x <= bot_helper[0] + bot_helper[2] && y >= bot_helper[1] &&
      y <= bot_helper[1] + bot_helper[3]) {
    user_settings* usrs = &env->usr->usrs;
    usrs->hotkeys[HOTKEY_BOT].active = !usrs->hotkeys[HOTKEY_BOT].active;
    chat_hint_until = 0;
    SDL_Log("Wyrm: bot %s from the chat helper",
            usrs->hotkeys[HOTKEY_BOT].active ? "on" : "off");
    return true;
  }

  bool hit = x >= chat_button[0] && x <= chat_button[0] + chat_button[2] &&
             y >= chat_button[1] && y <= chat_button[1] + chat_button[3];
  if (!hit) return false;

  if (!env->usr->usrs.hotkeys[HOTKEY_BOT].active) {
    chat_hint_has_own_key = env->usr->usrs.mobile_hotkeys.visible[HOTKEY_BOT];
    chat_hint_until = SDL_GetTicks() + CHAT_HINT_MS;
    /* Only for a player with no bot key of their own — anyone who put one on
       the overlay already has a better button than this. Once it is up it
       stays up; see the drawing side for why. */
    if (!chat_hint_has_own_key) bot_helper_shown = true;
    return true;
  }

  open_chat(env);
  return true;
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

#endif
