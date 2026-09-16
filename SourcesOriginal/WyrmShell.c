#include "WyrmOriginalAdapter.h"
#include "user.h"
#include "network/server.h"
#include <stdio.h>
#include <math.h>

/* This is only the Apple shell. Every Play action enters the original mailbox;
 * simulation, rendering, input and protocol remain original engine functions. */
void WyrmIOSDrawShell(tenv* env) {
  if (env->usr->gdata.curr_screen != TITLE_SCREEN &&
      env->usr->gdata.curr_screen != LOBBY) return;
  static char name[MAX_NICKNAME_LEN + 1];
  static char arena[MAX_IPV4_LEN + 1];
  static bool loaded;
  if (!loaded) {
    snprintf(name, sizeof(name), "%s", env->usr->usrs.nickname);
    snprintf(arena, sizeof(arena), "%s", env->usr->usrs.ipv4);
    loaded = true;
  }
  float scale = SDL_GetWindowDisplayScale(env->wnd->handle);
  if (scale < 1) scale = 1;
  float width = fminf(env->ctx->size[0] - 48 * scale, 440 * scale);
  ImDrawList_AddRectFilled(igGetWindowDrawList(), (ImVec2){0, 0},
      (ImVec2){env->ctx->size[0], env->ctx->size[1]},
      igColorConvertFloat4ToU32((ImVec4){.969f,.965f,.953f,1}), 0, 0);
  igSetCursorPos((ImVec2){(env->ctx->size[0] - width) * .5f, 30 * scale});
  igBeginGroup();
  ImFont* font = env->usr->imgui_data.body_font[FONT_SIZE_REGULAR];
  igPushFont(font, 17 * scale);
  igPushStyleColor_Vec4(ImGuiCol_Text, (ImVec4){.22f,.21f,.18f,1});
  igPushStyleColor_Vec4(ImGuiCol_FrameBg, (ImVec4){.91f,.90f,.87f,1});
  igPushStyleColor_Vec4(ImGuiCol_Button, (ImVec4){.72f,.80f,.72f,1});
  igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, 8 * scale);
  igPushStyleVar_Vec2(ImGuiStyleVar_FramePadding, (ImVec2){12*scale, 9*scale});
  igPushItemWidth(width);
  igText("WYRM / PLAY");
  igText("Original engine · Apple test");
  igSpacing();
  igInputTextWithHint("##name", "Your name", name, sizeof(name), 0, NULL, NULL);
  igInputTextWithHint("##arena", "Arena IPv4:port", arena, sizeof(arena), 0, NULL, NULL);
  bool allowed = name[0] && server_address_is_valid(arena);
  igBeginDisabled(!allowed);
  if (igButton("JOIN ARENA", (ImVec2){width, 43*scale}))
    WyrmIOSRequestPlay(name, arena, false);
  igEndDisabled();
  igBeginDisabled(!name[0]);
  if (igButton("OFFLINE AI", (ImVec2){width, 43*scale}))
    WyrmIOSRequestPlay(name, arena, true);
  igEndDisabled();
  igPopItemWidth();
  igPopStyleVar(2);
  igPopStyleColor(3);
  igPopFont();
  igEndGroup();
}
