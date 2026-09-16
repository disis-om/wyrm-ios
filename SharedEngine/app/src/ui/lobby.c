#include "lobby.h"

#include <stdio.h>
#include <string.h>

#include "../constants.h"
#include "../game/game_data.h"
#include "../game/input.h"
#include "../game/oef.h"
#include "../network/server.h"
#include "../platform/android_home.h"
#include "../user.h"
#include "ui_theme.h"

#ifdef VLITHER_ANDROID
#include <SDL3/SDL.h>
#endif

static bool s_quick_settings;

static ImU32 lobby_rgba(unsigned char r, unsigned char g, unsigned char b,
                        unsigned char a) {
  return (ImU32)r | ((ImU32)g << 8) | ((ImU32)b << 16) | ((ImU32)a << 24);
}

/* 6.1.1 Compose is in dp/sp. ImGui is pixels. One dp on this phone is ~2.75px. */
static float lobby_dp(tenv* env) {
#ifdef VLITHER_ANDROID
  if (env->wnd && env->wnd->handle) {
    float s = SDL_GetWindowDisplayScale(env->wnd->handle);
    if (s >= 1.0f) return s;
  }
#endif
  float short_side = env->ctx->size[0] < env->ctx->size[1] ? (float)env->ctx->size[0]
                                                           : (float)env->ctx->size[1];
  return short_side / 400.0f;
}

static void lobby_backdrop(tcontext* ctx) {
  ImGuiViewport* vp = igGetMainViewport();
  ImDrawList* dl = igGetBackgroundDrawList(vp);
  ImVec2 p0 = vp->Pos;
  ImVec2 p1 = {vp->Pos.x + vp->Size.x, vp->Pos.y + vp->Size.y};
  ImDrawList_AddRectFilled(dl, p0, p1, lobby_rgba(8, 8, 8, 255), 0.0f, 0);
  (void)ctx;
}

static void lobby_label(tuser_data* usr, const char* text, float dp) {
  ImFont* font = usr->imgui_data.body_font[FONT_SIZE_SMALL];
  igPushFont(font, 11.0f * dp);
  igTextColored((ImVec4){0.66f, 0.65f, 0.62f, 1.0f}, "%s", text);
  igPopFont();
}

static bool lobby_glass_button(tuser_data* usr, const char* id, const char* label,
                               ImVec2 size, float dp) {
  ImFont* font = usr->imgui_data.body_font[FONT_SIZE_SMALL];
  float rounding = size.y * 0.5f;
  igPushID_Str(id);
  igPushFont(font, 13.0f * dp);
  igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, rounding);
  igPushStyleVar_Float(ImGuiStyleVar_FrameBorderSize, 1.0f * dp);
  igPushStyleVar_Vec2(ImGuiStyleVar_FramePadding, (ImVec2){14.0f * dp, 0});
  igPushStyleColor_Vec4(ImGuiCol_Text, (ImVec4){0.91f, 0.90f, 0.87f, 1.0f});
  igPushStyleColor_Vec4(ImGuiCol_Button, (ImVec4){0.22f, 0.22f, 0.21f, 0.68f});
  igPushStyleColor_Vec4(ImGuiCol_ButtonHovered,
                        (ImVec4){0.31f, 0.31f, 0.29f, 0.82f});
  igPushStyleColor_Vec4(ImGuiCol_ButtonActive,
                        (ImVec4){0.15f, 0.15f, 0.14f, 0.90f});
  igPushStyleColor_Vec4(ImGuiCol_Border, (ImVec4){0.84f, 0.82f, 0.78f, 0.38f});
  bool pressed = igButton(label, size);
  igPopStyleColor(5);
  igPopStyleVar(3);
  igPopFont();
  igPopID();
  return pressed;
}

static bool lobby_play_button(tuser_data* usr, const char* label, ImVec2 size,
                              bool enabled, float dp) {
  ImFont* font = usr->imgui_data.body_font[FONT_SIZE_REGULAR];
  float rounding = size.y * 0.5f;
  igBeginDisabled(!enabled);
  igPushFont(font, 16.0f * dp);
  igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, rounding);
  igPushStyleVar_Float(ImGuiStyleVar_FrameBorderSize, 1.0f * dp);
  igPushStyleColor_Vec4(ImGuiCol_Text, (ImVec4){0.10f, 0.10f, 0.10f, 1.0f});
  igPushStyleColor_Vec4(ImGuiCol_Button, (ImVec4){0.96f, 0.95f, 0.92f, 1.0f});
  igPushStyleColor_Vec4(ImGuiCol_ButtonHovered,
                        (ImVec4){1.0f, 0.99f, 0.97f, 1.0f});
  igPushStyleColor_Vec4(ImGuiCol_ButtonActive,
                        (ImVec4){0.84f, 0.83f, 0.80f, 1.0f});
  igPushStyleColor_Vec4(ImGuiCol_Border, (ImVec4){1.0f, 1.0f, 1.0f, 0.62f});
  bool pressed = igButton(label, size);
  igPopStyleColor(5);
  igPopStyleVar(2);
  igPopFont();
  igEndDisabled();
  return pressed && enabled;
}

static void lobby_pill(tuser_data* usr, const char* label, const char* value,
                       float dp) {
  ImDrawList* dl = igGetWindowDrawList();
  ImVec2 p;
  igGetCursorScreenPos(&p);
  ImFont* body = usr->imgui_data.body_font[FONT_SIZE_SMALL];
  float label_px = 11.0f * dp;
  float value_px = 15.0f * dp;
  igPushFont(body, label_px);
  ImVec2 label_sz, value_sz;
  igCalcTextSize(&label_sz, label, NULL, false, -1);
  igPopFont();
  igPushFont(body, value_px);
  igCalcTextSize(&value_sz, value, NULL, false, -1);
  igPopFont();
  float h = 36.0f * dp;
  float w = label_sz.x + value_sz.x + 36.0f * dp;
  ImVec2 a = p;
  ImVec2 b = {p.x + w, p.y + h};
  ImDrawList_AddRectFilled(dl, a, b, lobby_rgba(12, 12, 12, 90), h * 0.5f, 0);
  ImDrawList_AddRect(dl, a, b, lobby_rgba(214, 209, 199, 70), h * 0.5f, 0,
                     1.0f * dp);
  ImDrawList_AddText_FontPtr(
      dl, body, label_px,
      (ImVec2){p.x + 13.0f * dp, p.y + (h - label_sz.y) * 0.5f},
      lobby_rgba(168, 166, 158, 255), label, NULL, 0.0f, NULL);
  ImDrawList_AddText_FontPtr(
      dl, body, value_px,
      (ImVec2){p.x + 22.0f * dp + label_sz.x, p.y + (h - value_sz.y) * 0.5f},
      lobby_rgba(232, 230, 222, 255), value, NULL, 0.0f, NULL);
  igDummy((ImVec2){w, h});
}

void ui_lobby_play(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;

  save_user_settings(&usr->usrs);
  /* Slither only calls `connect()` once `dead_mtm == -1`. A leftover death
     watch must not yank this join back to the lobby. */
  android_home_reset_death();
  gdata->stay_in_lobby = true;
  gdata->leaving = false;
  /* Same door as every other join: 3333ms since the last dial, and wait if
     the previous socket is still closing. Lobby Play used to skip both and
     dial on the spot, which is the enter-exit loop after a drop. */
  arena_request_join(env, ARENA_CONNECT_COOLDOWN_MS);
}

static void lobby_go_home(tenv* env) {
  tuser_data* usr = env->usr;
  save_user_settings(&usr->usrs);
  s_quick_settings = false;
  usr->gdata.stay_in_lobby = false;
  usr->gdata.leaving = true;
  usr->gdata.curr_screen = TITLE_SCREEN;
  usr->gdata.conn = DISCONNECTED;
}

static void draw_quick_settings(tenv* env, ui_safe_area safe, float dp) {
  tuser_data* usr = env->usr;
  ImFont* display = usr->imgui_data.display_font[FONT_SIZE_LARGE];
  ImFont* body = usr->imgui_data.body_font[FONT_SIZE_SMALL];

  igSetCursorPos((ImVec2){safe.x + 34.0f * dp, safe.y + 22.0f * dp});
  if (lobby_glass_button(usr, "qs_back", "Back",
                         (ImVec2){106.0f * dp, 49.0f * dp}, dp))
    s_quick_settings = false;

  float card_w = 520.0f * dp;
  float card_h = 140.0f * dp;
  igSetCursorPos((ImVec2){safe.x + (safe.width - card_w) * 0.5f,
                          safe.y + (safe.height - card_h) * 0.5f});
  ImVec2 card_min;
  igGetCursorScreenPos(&card_min);
  ImVec2 card_max = {card_min.x + card_w, card_min.y + card_h};
  ImDrawList* dl = igGetWindowDrawList();
  ImDrawList_AddRectFilled(dl, card_min, card_max, lobby_rgba(18, 18, 17, 180),
                           28.0f * dp, 0);
  ImDrawList_AddRect(dl, card_min, card_max, lobby_rgba(214, 209, 199, 50),
                     28.0f * dp, 0, 1.0f * dp);
  igSetCursorPos((ImVec2){safe.x + (safe.width - card_w) * 0.5f + 30.0f * dp,
                          safe.y + (safe.height - card_h) * 0.5f + 28.0f * dp});
  igBeginGroup();
  lobby_label(usr, "QUICK SETTINGS", dp);
  igPushFont(display, 28.0f * dp);
  igPushTextWrapPos(card_min.x + card_w - 30.0f * dp);
  igTextColored((ImVec4){0.96f, 0.96f, 0.94f, 1.0f},
                "This area of Wyrm is in development.");
  igPopTextWrapPos();
  igPopFont();
  igPushFont(body, 14.0f * dp);
  igTextColored((ImVec4){0.55f, 0.55f, 0.52f, 1.0f},
                "The controls you reach for between rounds will live here.");
  igPopFont();
  igEndGroup();
}

static void draw_ready_room(tenv* env, ui_safe_area safe, float dp) {
  tuser_data* usr = env->usr;
  user_settings* usrs = &usr->usrs;
  ImDrawList* dl = igGetWindowDrawList();
  ImFont* display = usr->imgui_data.display_font[FONT_SIZE_LARGE];

  float pad_x = 34.0f * dp;
  float pad_y = 22.0f * dp;
  float left = safe.x + pad_x;
  float col_gap = 54.0f * dp;
  float left_w = (safe.width - pad_x * 2.0f - col_gap) * 0.58f;
  float right_x = left + left_w + col_gap;
  float mid_y = safe.y + safe.height * 0.34f;

  igSetCursorPos((ImVec2){left, mid_y});
  igBeginGroup();
  lobby_label(usr, "SELECTED ARENA", dp);
  igDummy((ImVec2){0, 7.0f * dp});
  const char* arena = usrs->ipv4[0] ? usrs->ipv4 : "No arena selected";
  igPushFont(display, 38.0f * dp);
  igPushTextWrapPos(left + left_w);
  igTextColored(usrs->ipv4[0] ? (ImVec4){0.96f, 0.96f, 0.94f, 1.0f}
                              : (ImVec4){0.45f, 0.45f, 0.42f, 1.0f},
                "%s", arena);
  igPopTextWrapPos();
  igPopFont();
  igDummy((ImVec2){0, 14.0f * dp});
  igBeginGroup();
  lobby_pill(usr, "SERVER CODE", usrs->ipv4[0] ? "CUSTOM" : "\xe2\x80\x94", dp);
  igSameLine(0, 9.0f * dp);
  lobby_pill(usr, "CLUSTER", "\xe2\x80\x94", dp);
  igEndGroup();
  igEndGroup();

  igSetCursorPos((ImVec2){right_x, mid_y});
  igBeginGroup();
  lobby_label(usr, "PLAYING AS", dp);
  igDummy((ImVec2){0, 7.0f * dp});
  igPushFont(display, 48.0f * dp);
  igPushItemWidth((safe.x + safe.width) - right_x - pad_x);
  igPushStyleColor_Vec4(ImGuiCol_FrameBg, (ImVec4){0, 0, 0, 0});
  igPushStyleColor_Vec4(ImGuiCol_FrameBgHovered, (ImVec4){0, 0, 0, 0});
  igPushStyleColor_Vec4(ImGuiCol_FrameBgActive, (ImVec4){0, 0, 0, 0});
  igPushStyleColor_Vec4(ImGuiCol_Border, (ImVec4){0, 0, 0, 0});
  igPushStyleColor_Vec4(ImGuiCol_Text, (ImVec4){0.96f, 0.96f, 0.94f, 1.0f});
  igPushStyleVar_Float(ImGuiStyleVar_FrameBorderSize, 0);
  igPushStyleVar_Vec2(ImGuiStyleVar_FramePadding, (ImVec2){0, 0});
  if (igInputTextWithHint("##lobby_nick", "Unnamed", usrs->nickname,
                          MAX_NICKNAME_LEN + 1, ImGuiInputTextFlags_None, NULL,
                          NULL)) {
    save_user_settings(usrs);
  }
  igPopStyleVar(2);
  igPopStyleColor(5);
  igPopItemWidth();
  igPopFont();
  ImVec2 line_a;
  igGetCursorScreenPos(&line_a);
  float rule_w = (safe.x + safe.width) - right_x - pad_x;
  ImDrawList_AddRectFilledMultiColor(
      dl, line_a, (ImVec2){line_a.x + rule_w, line_a.y + 1.0f * dp},
      lobby_rgba(232, 230, 222, 158), lobby_rgba(232, 230, 222, 0),
      lobby_rgba(232, 230, 222, 0), lobby_rgba(232, 230, 222, 158));
  igDummy((ImVec2){rule_w, 8.0f * dp});
  igEndGroup();

  float play_w = 206.0f * dp;
  float play_h = 62.0f * dp;
  float home_w = 112.0f * dp;
  float glass_h = 49.0f * dp;
  float qs_w = 176.0f * dp;
  float gap = 10.0f * dp;
  float btn_y = safe.y + safe.height - pad_y - play_h;
  float right_edge = safe.x + safe.width - pad_x;

  igSetCursorPos((ImVec2){left, btn_y + (play_h - glass_h) * 0.5f});
  if (lobby_glass_button(usr, "qs", "Quick settings", (ImVec2){qs_w, glass_h},
                         dp))
    s_quick_settings = true;

  igSetCursorPos((ImVec2){right_edge - play_w - gap - home_w,
                          btn_y + (play_h - glass_h) * 0.5f});
  if (lobby_glass_button(usr, "home", "Home", (ImVec2){home_w, glass_h}, dp))
    lobby_go_home(env);
  igSameLine(0, gap);
  bool can_play = usrs->nickname[0] && server_address_is_valid(usrs->ipv4);
  igSetCursorPosY(btn_y);
  if (lobby_play_button(usr, "PLAY", (ImVec2){play_w, play_h}, can_play, dp))
    ui_lobby_play(env);
}

void ui_lobby(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  usr->r->global.bg_opacity = 0;
  usr->r->global.bd_opacity = 0;
  usr->r->global.minimap_opacity = 0;
  gdata->stay_in_lobby = true;

  if (gdata->connection || gdata->conn != DISCONNECTED) {
    if (gdata->data.victory_message_requested && gdata->connection) {
      time_step(env);
      input_team_protected(env);
    }
    server_poll(env);
    if (gdata->data.want_close_socket) {
      gdata->leaving = true;
      game_close_connection(gdata, "victory exchange finished");
      gdata->data.want_close_socket = false;
    }
    if (gdata->closed) {
      game_data_reset(env);
      gdata->conn = DISCONNECTED;
      gdata->closed = false;
      gdata->curr_screen = LOBBY;
    }
  }

  /* Compose draws the 6.1.1 lobby. Native only keeps a black clear so the
     glass sits on the same near-black as Home, with no extra orbs. */
  lobby_backdrop(env->ctx);
}
