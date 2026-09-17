#include "WyrmOriginalAdapter.h"
#include "user.h"
#include "network/server.h"
#include <stdio.h>
#include <math.h>

/* This is only the Apple shell. Every Play action enters the original mailbox;
 * simulation, rendering, input and protocol remain original engine functions. */
void WyrmIOSDrawShell(tenv* env) {
  // Android's product Home is portrait, but LOBBY belongs to the original
  // landscape engine. Never paint this temporary Home shell over ui_lobby().
  if (env->usr->gdata.curr_screen != TITLE_SCREEN) return;
  static char name[MAX_NICKNAME_LEN + 1];
  static char arena[MAX_IPV4_LEN + 1];
  static bool loaded;
  if (!loaded) {
    snprintf(name, sizeof(name), "%s", env->usr->usrs.nickname);
    snprintf(arena, sizeof(arena), "%s", env->usr->usrs.ipv4);
    loaded = true;
  }
  // ImGui positions are logical points. ctx->size is the Retina Vulkan
  // drawable in pixels (3x on the CI iPhone), which previously made the form
  // three times too wide and clipped it off-screen.
  ImGuiViewport* viewport = igGetMainViewport();
  float width = fminf(viewport->Size.x - 32.0f, 360.0f);
  ImDrawList_AddRectFilled(igGetWindowDrawList(), (ImVec2){0, 0},
      viewport->Size,
      igColorConvertFloat4ToU32((ImVec4){.969f,.965f,.953f,1}), 0, 0);
  igSetCursorPos((ImVec2){(viewport->Size.x - width) * .5f, 72.0f});
  igBeginGroup();
  ImFont* font = env->usr->imgui_data.body_font[FONT_SIZE_REGULAR];
  igPushFont(font, 20.0f);
  igPushStyleColor_Vec4(ImGuiCol_Text, (ImVec4){.22f,.21f,.18f,1});
  igPushStyleColor_Vec4(ImGuiCol_FrameBg, (ImVec4){.91f,.90f,.87f,1});
  igPushStyleColor_Vec4(ImGuiCol_Button, (ImVec4){.72f,.80f,.72f,1});
  igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, 10.0f);
  igPushStyleVar_Vec2(ImGuiStyleVar_FramePadding, (ImVec2){14.0f, 12.0f});
  igPushItemWidth(width);
  igText("WYRM / PLAY");
  igText("Original engine · Apple test");
  igSpacing();
  igInputTextWithHint("##name", "Your name", name, sizeof(name), 0, NULL, NULL);
  igInputTextWithHint("##arena", "Arena IPv4:port", arena, sizeof(arena), 0, NULL, NULL);
  bool allowed = name[0] && server_address_is_valid(arena);
  igBeginDisabled(!allowed);
  if (igButton("JOIN ARENA", (ImVec2){width, 48.0f}))
    WyrmIOSRequestPlay(name, arena, false);
  igEndDisabled();
  igBeginDisabled(!name[0]);
  if (igButton("OFFLINE AI", (ImVec2){width, 48.0f}))
    WyrmIOSRequestPlay(name, arena, true);
  igEndDisabled();
  igPopItemWidth();
  igPopStyleVar(2);
  igPopStyleColor(3);
  igPopFont();
  igEndGroup();
}
