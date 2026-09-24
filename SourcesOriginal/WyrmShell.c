#include "WyrmOriginalAdapter.h"
#include "user.h"
#include "network/server.h"
#include "game/arena_theme.h"
#include <stdio.h>
#include <math.h>

static ImU32 apple_rgba(unsigned char r, unsigned char g, unsigned char b,
                        unsigned char a) {
  return (ImU32)r | ((ImU32)g << 8) | ((ImU32)b << 16) | ((ImU32)a << 24);
}

static bool apple_button(tuser_data* usr, const char* id, const char* label,
                         ImVec2 size, float scale, bool primary, bool enabled) {
  igPushID_Str(id);
  igBeginDisabled(!enabled);
  igPushFont(usr->imgui_data.body_font[FONT_SIZE_REGULAR], 13.0f * scale);
  igPushStyleVar_Float(ImGuiStyleVar_FrameRounding,
                       (primary ? 31.0f : 11.0f) * scale);
  igPushStyleVar_Float(ImGuiStyleVar_FrameBorderSize, 1.0f * scale);
  igPushStyleColor_Vec4(ImGuiCol_Text,
      primary ? (ImVec4){.97f,.96f,.93f,1} : (ImVec4){.12f,.12f,.11f,1});
  igPushStyleColor_Vec4(ImGuiCol_Button,
      primary ? (ImVec4){.07f,.07f,.065f,1} : (ImVec4){.94f,.93f,.90f,1});
  igPushStyleColor_Vec4(ImGuiCol_ButtonHovered,
      primary ? (ImVec4){.15f,.15f,.14f,1} : (ImVec4){.88f,.87f,.84f,1});
  igPushStyleColor_Vec4(ImGuiCol_ButtonActive,
      primary ? (ImVec4){.02f,.02f,.02f,1} : (ImVec4){.82f,.81f,.78f,1});
  igPushStyleColor_Vec4(ImGuiCol_Border, (ImVec4){.74f,.72f,.68f,1});
  bool pressed = igButton(label, size);
  igPopStyleColor(5);
  igPopStyleVar(2);
  igPopFont();
  igEndDisabled();
  igPopID();
  return pressed && enabled;
}

static void apple_open_lobby(tenv* env, const char* name,
                             const char* address) {
  snprintf(env->usr->usrs.nickname, sizeof(env->usr->usrs.nickname), "%s", name);
  snprintf(env->usr->usrs.ipv4, sizeof(env->usr->usrs.ipv4), "%s", address);
  save_user_settings(&env->usr->usrs);
  env->usr->gdata.stay_in_lobby = true;
  env->usr->gdata.curr_screen = LOBBY;
  WyrmIOSSetEnginePresentation(true);
}

static void apple_draw_lobby(tenv* env) {
  static bool reported;
  ImGuiViewport* vp = igGetMainViewport();
  ImDrawList* dl = igGetWindowDrawList();
  float w = vp->Size.x;
  float h = vp->Size.y;
  float sx = w / 874.0f;
  float sy = h / 402.0f;
  float s = fminf(sx, sy);
  float ox = (w - 874.0f * s) * .5f;
  float oy = (h - 402.0f * s) * .5f;
  tuser_data* usr = env->usr;
  user_settings* usrs = &usr->usrs;
  ImFont* body = usr->imgui_data.body_font[FONT_SIZE_REGULAR];
  ImFont* display = usr->imgui_data.display_font[FONT_SIZE_LARGE];

  ImDrawList_AddRectFilled(dl, vp->Pos,
      (ImVec2){vp->Pos.x + w, vp->Pos.y + h}, apple_rgba(247,246,243,255), 0, 0);
  ImDrawList_AddCircleFilled(dl, (ImVec2){ox + 815*s, oy + 34*s}, 48*s,
                            apple_rgba(35,34,31,12), 48);

  igSetCursorPos((ImVec2){ox + 40*s, oy + 22*s});
  igPushFont(body, 10*s);
  igTextColored((ImVec4){.42f,.41f,.38f,1}, "READY ROOM");
  igPopFont();
  igSetCursorPos((ImVec2){ox + 40*s, oy + 40*s});
  igPushFont(body, 29*s);
  igTextColored((ImVec4){.10f,.10f,.09f,1}, "Enter the arena");
  igPopFont();
  ImDrawList_AddLine(dl, (ImVec2){ox + 40*s, oy + 83*s},
                     (ImVec2){ox + 834*s, oy + 83*s},
                     apple_rgba(198,195,188,255), s);

  ImVec2 card_a = {ox + 40*s, oy + 118*s};
  ImVec2 card_b = {ox + 500*s, oy + 270*s};
  ImDrawList_AddRectFilled(dl, card_a, card_b, apple_rgba(239,238,234,255),
                           16*s, 0);
  ImDrawList_AddRect(dl, card_a, card_b, apple_rgba(205,202,194,255),
                     16*s, 0, s);
  igSetCursorPos((ImVec2){ox + 62*s, oy + 138*s});
  igPushFont(body, 9*s);
  igTextColored((ImVec4){.42f,.41f,.38f,1}, "SELECTED ARENA");
  igPopFont();
  igSetCursorPos((ImVec2){ox + 62*s, oy + 160*s});
  igPushFont(display, 30*s);
  igTextColored(usrs->ipv4[0] ? (ImVec4){.10f,.10f,.09f,1}
                              : (ImVec4){.48f,.47f,.44f,1},
                "%s", usrs->ipv4[0] ? usrs->ipv4 : "No arena selected");
  igPopFont();
  igSetCursorPos((ImVec2){ox + 62*s, oy + 219*s});
  igPushFont(body, 10*s);
  igTextColored((ImVec4){.42f,.41f,.38f,1}, "SERVER CODE   CUSTOM");
  igPopFont();

  igSetCursorPos((ImVec2){ox + 535*s, oy + 138*s});
  igPushFont(body, 9*s);
  igTextColored((ImVec4){.42f,.41f,.38f,1}, "PLAYING AS");
  igPopFont();
  igSetCursorPos((ImVec2){ox + 535*s, oy + 164*s});
  igPushFont(display, 40*s);
  igPushItemWidth(295*s);
  igPushStyleVar_Float(ImGuiStyleVar_FrameBorderSize, 0);
  igPushStyleVar_Vec2(ImGuiStyleVar_FramePadding, (ImVec2){0, 0});
  igPushStyleColor_Vec4(ImGuiCol_FrameBg, (ImVec4){0,0,0,0});
  igPushStyleColor_Vec4(ImGuiCol_Text, (ImVec4){.10f,.10f,.09f,1});
  if (igInputTextWithHint("##apple_lobby_name", "Wyrm Player",
                          usrs->nickname, sizeof(usrs->nickname), 0, NULL, NULL))
    save_user_settings(usrs);
  igPopStyleColor(2);
  igPopStyleVar(2);
  igPopItemWidth();
  igPopFont();
  ImDrawList_AddLine(dl, (ImVec2){ox + 535*s, oy + 224*s},
                     (ImVec2){ox + 830*s, oy + 224*s},
                     apple_rgba(100,98,92,100), s);

  float by = oy + 319*s;
  igSetCursorPos((ImVec2){ox + 40*s, by});
  apple_button(usr, "quick", "Quick settings", (ImVec2){150*s,49*s}, s,
               false, true);
  igSetCursorPos((ImVec2){ox + 342*s, by});
  if (apple_button(usr, "home", "Home", (ImVec2){104*s,49*s}, s, false,
                   true)) {
    env->usr->gdata.stay_in_lobby = false;
    env->usr->gdata.curr_screen = TITLE_SCREEN;
    WyrmIOSSetEnginePresentation(false);
  }
  igSetCursorPos((ImVec2){ox + 456*s, by});
  if (apple_button(usr, "ai", "Play with AI", (ImVec2){142*s,49*s}, s,
                   false, usrs->nickname[0]))
    WyrmIOSRequestPlay(usrs->nickname, "", true);
  igSetCursorPos((ImVec2){ox + 608*s, oy + 312*s});
  bool can_play = usrs->nickname[0] && server_address_is_valid(usrs->ipv4);
  if (apple_button(usr, "play", "PLAY", (ImVec2){226*s,62*s}, s, true,
                   can_play))
    WyrmIOSRequestPlay(usrs->nickname, usrs->ipv4, false);

  if (!reported) {
    reported = true;
    SDL_Log("Wyrm iOS lobby shell presented at %.0fx%.0f logical points", w, h);
  }
}

/* This is only the Apple shell. Every Play action enters the original mailbox;
 * simulation, rendering, input and protocol remain original engine functions. */
void WyrmIOSDrawShell(tenv* env) {
  // Android owns this Ready Room in Compose; Apple draws the same bridge over
  // the original engine's intentionally black LOBBY clear.
  if (env->usr->gdata.curr_screen == LOBBY) {
    apple_draw_lobby(env);
    return;
  }
  if (env->usr->gdata.curr_screen != TITLE_SCREEN) return;
  static char name[MAX_NICKNAME_LEN + 1];
  static char arena[MAX_IPV4_LEN + 1];
  static bool loaded;
  if (!loaded) {
    snprintf(name, sizeof(name), "%s", env->usr->usrs.nickname);
    snprintf(arena, sizeof(arena), "%s", env->usr->usrs.ipv4);
    loaded = true;
  }
  // The original engine intentionally runs ImGui in Android-style drawable
  // pixels. Scale this Apple-only portrait shell from its 440x956 point design
  // so it keeps the same apparent size on a Retina canvas.
  ImGuiViewport* viewport = igGetMainViewport();
  float shell_scale = fminf(viewport->Size.x / 440.0f,
                            viewport->Size.y / 956.0f);
  float width = fminf(viewport->Size.x - 32.0f * shell_scale,
                      360.0f * shell_scale);
  ImDrawList_AddRectFilled(igGetWindowDrawList(), (ImVec2){0, 0},
      viewport->Size,
      igColorConvertFloat4ToU32((ImVec4){.969f,.965f,.953f,1}), 0, 0);
  igSetCursorPos((ImVec2){(viewport->Size.x - width) * .5f,
                           72.0f * shell_scale});
  igBeginGroup();
  ImFont* font = env->usr->imgui_data.body_font[FONT_SIZE_REGULAR];
  igPushFont(font, 20.0f * shell_scale);
  igPushStyleColor_Vec4(ImGuiCol_Text, (ImVec4){.22f,.21f,.18f,1});
  igPushStyleColor_Vec4(ImGuiCol_FrameBg, (ImVec4){.91f,.90f,.87f,1});
  igPushStyleColor_Vec4(ImGuiCol_Button, (ImVec4){.72f,.80f,.72f,1});
  igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, 10.0f * shell_scale);
  igPushStyleVar_Vec2(ImGuiStyleVar_FramePadding,
                      (ImVec2){14.0f * shell_scale, 12.0f * shell_scale});
  igPushItemWidth(width);
  igText("WYRM / PLAY");
  igText("Original engine · Apple test");
  igSpacing();
  igInputTextWithHint("##name", "Your name", name, sizeof(name), 0, NULL, NULL);
  igInputTextWithHint("##arena", "Arena IPv4:port", arena, sizeof(arena), 0, NULL, NULL);
  bool allowed = name[0] && server_address_is_valid(arena);
  igBeginDisabled(!allowed);
  if (igButton("JOIN ARENA", (ImVec2){width, 48.0f * shell_scale}))
    apple_open_lobby(env, name, arena);
  igEndDisabled();
  igBeginDisabled(!name[0]);
  if (igButton("OFFLINE AI", (ImVec2){width, 48.0f * shell_scale}))
    WyrmIOSRequestPlay(name, arena, true);
  igEndDisabled();
  igPopItemWidth();
  igPopStyleVar(2);
  igPopStyleColor(3);
  igPopFont();
  igEndGroup();
}

/* SwiftUI owns the theme choice; the engine only reads the colours. The store
   is atomic in arena_theme.c, so this may be called from the main thread while
   the renderer draws. */
void WyrmIOSSetArenaTheme(const uint32_t* colours, int count, bool dark) {
  if (!colours || count < ARENA_THEME_ROLE_COUNT) return;
  uint32_t next[ARENA_THEME_ROLE_COUNT];
  for (int i = 0; i < ARENA_THEME_ROLE_COUNT; ++i) next[i] = colours[i];
  arena_theme_set(next, dark);
}
