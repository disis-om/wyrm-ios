#include "loop.h"

#include <SDL3/SDL.h>

#include "../network/arena_persona.h"
#include "../network/arena_taint.h"
#include "../network/ntl_net.h"
#include "../platform/android_home.h"
#include "../network/server.h"
#include "../network/arena_protocol.h"
#include "../user.h"
#include "input.h"
#include "oef.h"
#include "redraw.h"
#include "ui_overlay.h"
#include "ai_mode.h"
#include "../mobile/mobile_controls.h"

/**
 * The screen between pressing Play and the arena existing.
 *
 * Drawn rather than loaded: the same coiled W as the launcher icon, stroked as
 * one continuous path, over Wyrm's paper. The shine says nothing about
 * how far along the connection is — nothing here knows that — so it is a
 * travelling segment rather than a fill that would be lying.
 */
static void draw_connecting(tenv* env) {
  tuser_data* usr = env->usr;
  tcontext* ctx = env->ctx;
  ImDrawList* draw = igGetWindowDrawList();

  const ImU32 paper = igColorConvertFloat4ToU32((ImVec4){0.969f, 0.965f, 0.953f, 1});
  const ImU32 ink = igColorConvertFloat4ToU32((ImVec4){0.216f, 0.208f, 0.184f, 1});
  const ImU32 rule = igColorConvertFloat4ToU32((ImVec4){0.216f, 0.208f, 0.184f, .08f});
  const ImU32 faint = igColorConvertFloat4ToU32((ImVec4){0.471f, 0.467f, 0.455f, 1});

  float shorter = ctx->size[0] < ctx->size[1] ? ctx->size[0] : ctx->size[1];
  float cx = ctx->size[0] * 0.5f;

  ImDrawList_AddRectFilled(draw, (ImVec2){0, 0},
                           (ImVec2){ctx->size[0], ctx->size[1]}, paper, 0, 0);
  ImDrawList_AddLine(draw, (ImVec2){ctx->size[0] * .08f, ctx->size[1] * .18f},
                     (ImVec2){ctx->size[0] * .92f, ctx->size[1] * .18f},
                     rule, 1.0f);

  /* No mark here — the wordmark carries it. h drives the spacing that the
   * mark used to occupy, so the block stays optically centred without it. */
  float h = shorter * 0.13f;
  float top = ctx->size[1] * 0.5f - h * 0.55f;

  ImFont* wordmark = usr->imgui_data.regular_font_bold[FONT_SIZE_LARGE];
  ImVec2 wordmark_size;
  igPushFont(wordmark, wordmark->LegacySize);
  igCalcTextSize(&wordmark_size, "WYRM", NULL, false, -1);
  igPopFont();
  float wordmark_y = top + h + h * 0.30f;
  const ImU32 dim = igColorConvertFloat4ToU32((ImVec4){0.216f, 0.208f, 0.184f, 0.20f});
  ImDrawList_AddText_FontPtr(draw, wordmark, wordmark->LegacySize,
                             (ImVec2){cx - wordmark_size.x * 0.5f, wordmark_y},
                             dim, "WYRM", NULL, 0.0f, NULL);

  ImFont* caption = usr->imgui_data.mono_font[FONT_SIZE_SMALL];
  const char* label = "ENTERING THE ARENA";
  ImVec2 caption_size;
  igPushFont(caption, caption->LegacySize);
  igCalcTextSize(&caption_size, label, NULL, false, -1);
  igPopFont();
  float caption_y = wordmark_y + wordmark_size.y + h * 0.10f;
  ImDrawList_AddText_FontPtr(draw, caption, caption->LegacySize,
                             (ImVec2){cx - caption_size.x * 0.5f, caption_y},
                             faint, label, NULL, 0.0f, NULL);

  /*
   * One screen, and the wordmark is the whole of it.
   *
   * There were two: this, and a Compose card carrying the mark. They belong to
   * different halves of the app and neither knew about the other, so entering
   * an arena showed both in turn. The travelling bar underneath was the second
   * thing pretending to report progress, and nothing here knows any.
   *
   * So the wordmark does it. The letters are drawn dim, then drawn again bright
   * through a narrow window that sweeps across them and starts over — a shine
   * passing over metal rather than a measurement of anything.
   */
  float sweep = fmodf((float)glfwGetTime() * 0.6f, 1.6f);
  float band = wordmark_size.x * 0.42f;
  float shine_x =
      (cx - wordmark_size.x * 0.5f) - band + (wordmark_size.x + band * 2) *
                                                 (sweep > 1.0f ? 1.0f : sweep);

  ImDrawList_PushClipRect(draw, (ImVec2){shine_x, wordmark_y},
                          (ImVec2){shine_x + band,
                                   wordmark_y + wordmark_size.y},
                          true);
  ImDrawList_AddText_FontPtr(draw, wordmark, wordmark->LegacySize,
                             (ImVec2){cx - wordmark_size.x * 0.5f, wordmark_y},
                             ink, "WYRM", NULL, 0.0f, NULL);
  ImDrawList_PopClipRect(draw);
  (void)rule;
  (void)shorter;
}

/* Paint-only wrapper. The caller still owns cancel, keyboard and exit state. */
static bool draw_connecting_back_button(tcontext* ctx) {
  igSetCursorPos((ImVec2){ctx->size[0] * .5f - 80, ctx->size[1] * .72f});
  igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, 11.0f);
  igPushStyleVar_Float(ImGuiStyleVar_FrameBorderSize, 1.0f);
  igPushStyleColor_Vec4(ImGuiCol_Text, (ImVec4){.216f, .208f, .184f, 1});
  igPushStyleColor_Vec4(ImGuiCol_Button, (ImVec4){1, 1, 1, 1});
  igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, (ImVec4){.941f, .933f, .914f, 1});
  igPushStyleColor_Vec4(ImGuiCol_ButtonActive, (ImVec4){.910f, .898f, .871f, 1});
  igPushStyleColor_Vec4(ImGuiCol_Border, (ImVec4){.216f, .208f, .184f, .10f});
  bool pressed = igButton("Back to lobby", (ImVec2){160, 40});
  igPopStyleColor(5);
  igPopStyleVar(2);
  return pressed;
}

void game_loop(tenv* env) {
  tuser_data* usr = env->usr;
  tcontext* ctx = env->ctx;
  game_data* gdata = &usr->gdata;
  user_settings* usrs = &usr->usrs;

  if (!env->config.running) gdata->conn = DISCONNECTED;

  /* The offline arena owns this frame completely. In particular, branching
     here makes it impossible to fall through to input(), ntl_net_tick() or
     server_poll() while AI Mode is active. */
  if (gdata->ai_mode) {
    ai_mode_tick(env);
    return;
  }

  switch (gdata->conn) {
    case AI_CONNECTED:
      /* Consumed by the isolated branch above. This case exists so compiler
         exhaustiveness checks also encode that it cannot reach networking. */
      break;
    case CONNECTING: {
      usr->r->global.bg_opacity = 0;
      usr->r->global.bd_opacity = 0;
      usr->r->global.minimap_opacity = 0;
      time_step(env);

      /* Retries stay on the chosen endpoint: directory selection is outside
         this parity pass. Never replace a socket which has not finished closing. */
      if (gdata->rejoin_at_ms) {
        server_poll(env);
        if (!gdata->connection && SDL_GetTicks() >= gdata->rejoin_at_ms) {
          game_data_reset(env);
          gdata->data.ltm = gdata->data.ctm = glfwGetTime() * 1000;
          gdata->join_requires_stability = true;
          gdata->closed = false;
          gdata->rejoin_at_ms = 0;
          if (!server_connect(env)) gdata->rejoin_at_ms = SDL_GetTicks() + 50;
        } else if (!gdata->connection) gdata->closed = false;
      } else {
        /* 'a' ends connecting in the reference, even before our snake exists.
           Keep the loading presentation separate, but start keepalives now. */
        if (!gdata->arena_ready && gdata->connection &&
            !gdata->connection->is_closing &&
            SDL_GetTicks() - gdata->attempt_started_ms > ARENA_RETRY_MS) {
          arena_taint_mark(usrs->ipv4);
          android_home_arena_refused(
              usrs->ipv4, (int)(arena_taint_remaining(usrs->ipv4) / 1000));
          game_fail_connection(gdata, "configuration timeout");
        }
        if (gdata->arena_ready) input_team_protected(env);
        server_poll(env);
      }

      if (gdata->closed) {
        gdata->closed = false;
        if (gdata->leaving) gdata->conn = DISCONNECTED;
        else if (android_home_death_pending()) gdata->conn = CONNECTED;
        else {
          /* Slither taints a refused arena and chooses another one. Retrying
             the same endpoint forever both hid the actual failure and caused
             the fleet to throttle the phone. Compose owns the live directory,
             so hand the refusal back to it and let it pick the next reachable
             endpoint after the lobby has settled. */
          arena_taint_mark(usrs->ipv4);
          android_home_arena_refused(
              usrs->ipv4, (int)(arena_taint_remaining(usrs->ipv4) / 1000));
          game_data_reset(env);
          gdata->conn = DISCONNECTED;
          gdata->curr_screen = LOBBY;
        }
      }
      if (gdata->conn == CONNECTING) {
        draw_connecting(env);
        /* An unbounded reference retry must still have an explicit way out. */
        if (draw_connecting_back_button(ctx) ||
            usr->mobile_controls.exit_requested ||
            igIsKeyPressed_Bool(ImGuiKey_Escape, false)) {
          usr->mobile_controls.exit_requested = false;
          gdata->leaving = true;
          gdata->rejoin_at_ms = 0;
          game_close_connection(gdata, "cancelled connecting");
          gdata->conn = DISCONNECTED;
          gdata->curr_screen = gdata->stay_in_lobby ? LOBBY : TITLE_SCREEN;
        }
      }
      break;
    }
    case CONNECTED:
      time_step(env);
      android_home_advance_death(env, gdata->data.vfr);
      if (gdata->curr_screen != PLAYING) break;
      if (gdata->data.want_close_socket && !android_home_death_pending()) {
        gdata->leaving = true;
        game_close_connection(gdata, "victory exchange finished");
        gdata->data.want_close_socket = false;
      }
      input(env);
      /* Before the poll, so an announcement written this frame goes out on it.
         This is a second socket on the same manager — the arena knows nothing
         about tags, so everyone else's arrive from somewhere else entirely. */
      ntl_net_tick(env);
      server_poll(env);
      oef(env);
      redraw(env);
      ui_overlay(env);
      mobile_controls_draw_gameplay(env);

      // special hotkeys
      if (usr->mobile_controls.exit_requested) {
        usr->mobile_controls.exit_requested = false;
        gdata->leaving = true;
        game_close_connection(gdata, "the player went back");
      } else if (usrs->hotkeys[HOTKEY_QUIT].active ||
          (usrs->quit_mc &&
           tmouse_button_pressed(env->ms, GLFW_MOUSE_BUTTON_MIDDLE))) {
        gdata->leaving = true;
        game_close_connection(gdata, "the player quit");
      } else if (usrs->hotkeys[HOTKEY_RESTART].active ||
                 (usrs->restart_rc &&
                  tmouse_button_pressed(env->ms, GLFW_MOUSE_BUTTON_RIGHT))) {
        /* Spent the moment it is read. The restart key is a tap, and a tap
           that stays down would ask for a second restart on the next frame —
           which is what a latched button looks like from the outside. */
        usrs->hotkeys[HOTKEY_RESTART].active = false;
        game_close_connection(gdata, "restart");
        gdata->restart_req = true;
      }

      if (gdata->closed) {
        if (android_home_death_pending()) {
          /* Original slither keeps drawing the world after `'v'`. If the
             arena hangs up during that watch, leave the last snakes on
             screen until the timer ends. */
          gdata->closed = false;
        } else if (gdata->join_spawned && !gdata->leaving &&
                   !gdata->restart_req) {
          /* Slither `ws.onclose` while playing: `dead_mtm = now`, then login
             after the death wait. Instant lobby here was the mid-match eject. */
          android_home_notify_death(env);
          gdata->closed = false;
        } else {
          if (gdata->last_life > SHORT_LIFE &&
              usrs->arena_persona != gdata->persona) {
            usrs->arena_persona = gdata->persona;
            save_user_settings(usrs);
            SDL_Log("Wyrm arena: '%s' played a full match — joining as it from "
                    "now on",
                    arena_persona_get(gdata->persona)->name);
          }

          bool restarting = gdata->restart_req;
          game_data_reset(env);

          if (restarting) {
            bool loop_risk = gdata->respawn_after_short_life;
            gdata->respawn_after_short_life = false;
            arena_request_join(env, loop_risk ? ARENA_RESPAWN_LOOP_COOLDOWN_MS
                                              : ARENA_CONNECT_COOLDOWN_MS);
          } else {
            usr->gdata.conn = DISCONNECTED;
            if (gdata->stay_in_lobby) gdata->curr_screen = LOBBY;
          }
          gdata->closed = false;
        }
      }

      break;
    case DISCONNECTED:
      gdata->rejoin_at_ms = 0;
      ntl_net_close(env);
      usr->r->global.bg_opacity = 0;
      usr->r->global.bd_opacity = 0;
      usr->r->global.minimap_opacity = 0;

      if (android_home_death_pending()) {
        server_poll(env);
        break;
      }

      /* Native lobby owns the return from a match. Compose Home is only for
         an explicit Home press. */
      if (gdata->stay_in_lobby)
        gdata->curr_screen = LOBBY;
      else
        gdata->curr_screen = TITLE_SCREEN;

      game_data_reset(env);
      server_poll(env);

      break;
  }
}
