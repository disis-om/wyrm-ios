#include "ui_theme.h"

#include <math.h>
#include <stdio.h>

#include "../constants.h"
#include "../user.h"

#ifdef VLITHER_ANDROID
#include <SDL3/SDL.h>
#endif

const ImVec4 UI_COLOR_ACCENT = {0.055f, 0.765f, 0.515f, 1.0f};
const ImVec4 UI_COLOR_TEXT = {0.925f, 0.937f, 0.953f, 1.0f};
const ImVec4 UI_COLOR_MUTED = {0.545f, 0.576f, 0.620f, 1.0f};
const ImVec4 UI_COLOR_PANEL = {0.055f, 0.071f, 0.094f, 0.98f};
const ImVec4 UI_COLOR_BORDER = {0.165f, 0.192f, 0.231f, 1.0f};

static ImU32 ui_u32(ImVec4 color) { return igColorConvertFloat4ToU32(color); }

typedef enum ui_transition_phase {
  UI_TRANSITION_ENTER,
  UI_TRANSITION_STABLE,
  UI_TRANSITION_EXIT
} ui_transition_phase;

static struct {
  bool initialized;
  bool input_blocked;
  int shown_screen;
  int pending_screen;
  double started_at;
  float alpha;
  float veil;
  ui_transition_phase phase;
} transition;

static float smoothstep01(float value) {
  value = value < 0.0f ? 0.0f : (value > 1.0f ? 1.0f : value);
  return value * value * (3.0f - 2.0f * value);
}

void ui_theme_transition_begin(tenv* env) {
  int requested = env->usr->gdata.curr_screen;
  double now = igGetTime();
  /* Lobby <-> Play must not fade. Original slither connects on the same
     frame Play is pressed; a 160ms veil here is extra latency on that path. */
  if (requested == PLAYING || requested == LOBBY || requested == TITLE_SCREEN ||
      transition.shown_screen == PLAYING || transition.shown_screen == LOBBY ||
      transition.shown_screen == TITLE_SCREEN) {
    transition.initialized = true;
    transition.shown_screen = requested;
    transition.pending_screen = requested;
    transition.phase = UI_TRANSITION_STABLE;
    transition.alpha = 1.0f;
    transition.veil = 0.0f;
    transition.input_blocked = false;
    igPushStyleVar_Float(ImGuiStyleVar_Alpha, 1.0f);
    return;
  }
  if (!transition.initialized) {
    transition.initialized = true;
    transition.shown_screen = requested;
    transition.pending_screen = requested;
    transition.started_at = now;
    transition.phase = UI_TRANSITION_ENTER;
  }

  if (transition.phase == UI_TRANSITION_STABLE &&
      requested != transition.shown_screen) {
    transition.pending_screen = requested;
    env->usr->gdata.curr_screen = transition.shown_screen;
    transition.phase = UI_TRANSITION_EXIT;
    transition.started_at = now;
  } else if (transition.phase == UI_TRANSITION_EXIT) {
    env->usr->gdata.curr_screen = transition.shown_screen;
    float progress = (float)((now - transition.started_at) / 0.16);
    if (progress >= 1.0f) {
      transition.shown_screen = transition.pending_screen;
      env->usr->gdata.curr_screen = transition.shown_screen;
      transition.phase = UI_TRANSITION_ENTER;
      transition.started_at = now;
    }
  } else if (transition.phase == UI_TRANSITION_ENTER) {
    env->usr->gdata.curr_screen = transition.shown_screen;
    if (now - transition.started_at >= 0.30)
      transition.phase = UI_TRANSITION_STABLE;
  }

  if (transition.phase == UI_TRANSITION_EXIT) {
    float progress = smoothstep01((float)((now - transition.started_at) / 0.16));
    transition.alpha = 1.0f - progress;
    transition.veil = progress * 0.52f;
  } else if (transition.phase == UI_TRANSITION_ENTER) {
    float progress = smoothstep01((float)((now - transition.started_at) / 0.30));
    transition.alpha = progress;
    transition.veil = (1.0f - progress) * 0.52f;
  } else {
    transition.alpha = 1.0f;
    transition.veil = 0.0f;
  }

  transition.input_blocked = transition.phase != UI_TRANSITION_STABLE;
  igPushStyleVar_Float(ImGuiStyleVar_Alpha,
                       transition.alpha < 0.02f ? 0.02f : transition.alpha);
  if (transition.input_blocked) igBeginDisabled(true);
}

void ui_theme_transition_end(tenv* env) {
  if (transition.input_blocked) igEndDisabled();
  igPopStyleVar(1);
  if (transition.veil <= 0.001f) return;

  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(igGetMainViewport());
  ImVec2 min = {0, 0};
  ImVec2 max = {(float)env->ctx->size[0], (float)env->ctx->size[1]};
  ImDrawList_AddRectFilled(
      draw, min, max,
      ui_u32((ImVec4){0.012f, 0.018f, 0.025f, transition.veil}), 0, 0);
  // Layered translucent frames create a deliberate defocus/materialisation
  // impression without introducing an off-screen blur pass into Vulkan.
  for (int i = 0; i < 4; ++i) {
    float inset = 8.0f + i * 9.0f;
    ImDrawList_AddRect(
        draw, (ImVec2){inset, inset},
        (ImVec2){max.x - inset, max.y - inset},
        ui_u32((ImVec4){0.10f, 0.72f, 0.52f,
                        transition.veil * (0.20f - i * 0.035f)}),
        24.0f + i * 2.0f, 0, 1.0f + i * 1.2f);
  }
}

void ui_theme_apply(void) {
  ImGuiStyle* style = igGetStyle();
  igStyleColorsDark(style);

  style->WindowPadding = (ImVec2){24, 22};
  style->FramePadding = (ImVec2){14, 11};
  style->ItemSpacing = (ImVec2){10, 10};
  style->ItemInnerSpacing = (ImVec2){8, 6};
  style->IndentSpacing = 20;
  style->ScrollbarSize = 12;
  style->GrabMinSize = 22;
  style->WindowBorderSize = 1;
  style->ChildBorderSize = 1;
  style->PopupBorderSize = 1;
  style->FrameBorderSize = 1;
  style->TabBorderSize = 1;
  style->WindowRounding = 22;
  style->ChildRounding = 22;
  style->FrameRounding = 13;
  style->PopupRounding = 16;
  style->ScrollbarRounding = 10;
  style->GrabRounding = 10;
  style->TabRounding = 12;
  style->DockingNodeHasCloseButton = false;
  style->WindowMenuButtonPosition = ImGuiDir_None;
  style->TabCloseButtonMinWidthUnselected = -1;

  style->Colors[ImGuiCol_Text] = UI_COLOR_TEXT;
  style->Colors[ImGuiCol_TextDisabled] =
      (ImVec4){UI_COLOR_MUTED.x, UI_COLOR_MUTED.y, UI_COLOR_MUTED.z, 0.58f};
  style->Colors[ImGuiCol_WindowBg] = (ImVec4){0.026f, 0.035f, 0.047f, 1.0f};
  style->Colors[ImGuiCol_ChildBg] = UI_COLOR_PANEL;
  style->Colors[ImGuiCol_PopupBg] = (ImVec4){0.045f, 0.059f, 0.078f, 0.99f};
  style->Colors[ImGuiCol_Border] = UI_COLOR_BORDER;
  style->Colors[ImGuiCol_BorderShadow] = (ImVec4){0, 0, 0, 0};
  style->Colors[ImGuiCol_FrameBg] = (ImVec4){0.025f, 0.033f, 0.044f, 1.0f};
  style->Colors[ImGuiCol_FrameBgHovered] =
      (ImVec4){0.070f, 0.095f, 0.118f, 1.0f};
  style->Colors[ImGuiCol_FrameBgActive] =
      (ImVec4){0.052f, 0.078f, 0.094f, 1.0f};
  style->Colors[ImGuiCol_TitleBg] = UI_COLOR_PANEL;
  style->Colors[ImGuiCol_TitleBgActive] = UI_COLOR_PANEL;
  style->Colors[ImGuiCol_Button] = (ImVec4){0.071f, 0.090f, 0.118f, 1.0f};
  style->Colors[ImGuiCol_ButtonHovered] =
      (ImVec4){0.105f, 0.137f, 0.169f, 1.0f};
  style->Colors[ImGuiCol_ButtonActive] =
      (ImVec4){0.042f, 0.061f, 0.075f, 1.0f};
  style->Colors[ImGuiCol_Header] = (ImVec4){0.055f, 0.235f, 0.178f, 0.72f};
  style->Colors[ImGuiCol_HeaderHovered] =
      (ImVec4){0.068f, 0.355f, 0.255f, 0.84f};
  style->Colors[ImGuiCol_HeaderActive] =
      (ImVec4){0.045f, 0.275f, 0.195f, 1.0f};
  style->Colors[ImGuiCol_CheckMark] = UI_COLOR_ACCENT;
  style->Colors[ImGuiCol_SliderGrab] = UI_COLOR_ACCENT;
  style->Colors[ImGuiCol_SliderGrabActive] =
      (ImVec4){0.20f, 0.92f, 0.68f, 1.0f};
  style->Colors[ImGuiCol_Separator] =
      (ImVec4){UI_COLOR_BORDER.x, UI_COLOR_BORDER.y, UI_COLOR_BORDER.z, 0.78f};
  style->Colors[ImGuiCol_SeparatorHovered] = UI_COLOR_ACCENT;
  style->Colors[ImGuiCol_SeparatorActive] = UI_COLOR_ACCENT;
  style->Colors[ImGuiCol_ScrollbarBg] = (ImVec4){0.018f, 0.025f, 0.034f, 0.72f};
  style->Colors[ImGuiCol_ScrollbarGrab] =
      (ImVec4){0.145f, 0.176f, 0.208f, 1.0f};
  style->Colors[ImGuiCol_ScrollbarGrabHovered] =
      (ImVec4){0.205f, 0.245f, 0.282f, 1.0f};
  style->Colors[ImGuiCol_ScrollbarGrabActive] = UI_COLOR_ACCENT;
  style->Colors[ImGuiCol_Tab] = (ImVec4){0.055f, 0.071f, 0.094f, 1.0f};
  style->Colors[ImGuiCol_TabHovered] =
      (ImVec4){0.075f, 0.165f, 0.142f, 1.0f};
  style->Colors[ImGuiCol_TabSelected] =
      (ImVec4){0.055f, 0.235f, 0.178f, 1.0f};
  style->Colors[ImGuiCol_TabSelectedOverline] = UI_COLOR_ACCENT;
  style->Colors[ImGuiCol_TableHeaderBg] =
      (ImVec4){0.060f, 0.078f, 0.102f, 1.0f};
  style->Colors[ImGuiCol_TableBorderStrong] = UI_COLOR_BORDER;
  style->Colors[ImGuiCol_TableBorderLight] =
      (ImVec4){UI_COLOR_BORDER.x, UI_COLOR_BORDER.y, UI_COLOR_BORDER.z, 0.5f};
  style->Colors[ImGuiCol_ModalWindowDimBg] = (ImVec4){0, 0, 0, 0.78f};
}

void ui_theme_draw_background(tenv* env) {
  tcontext* ctx = env->ctx;
  ImDrawList* dl = igGetWindowDrawList();
  ImVec2 p0 = {0, 0};
  ImVec2 p1 = {(float)ctx->size[0], (float)ctx->size[1]};
  ImDrawList_AddRectFilled(dl, p0, p1, ui_u32((ImVec4){0.020f, 0.027f, 0.037f, 1}),
                           0, 0);

  const float grid = 64.0f;
  ImU32 grid_color = ui_u32((ImVec4){0.115f, 0.140f, 0.165f, 0.16f});
  for (float x = 0; x <= p1.x; x += grid)
    ImDrawList_AddLine(dl, (ImVec2){x, 0}, (ImVec2){x, p1.y}, grid_color, 1);
  for (float y = 0; y <= p1.y; y += grid)
    ImDrawList_AddLine(dl, (ImVec2){0, y}, (ImVec2){p1.x, y}, grid_color, 1);

  float short_edge = p1.x < p1.y ? p1.x : p1.y;
  ImVec2 orb = {p1.x * 0.77f, p1.y * 0.18f};
  ImDrawList_AddCircleFilled(
      dl, orb, short_edge * 0.17f,
      ui_u32((ImVec4){0.020f, 0.345f, 0.260f, 0.075f}), 96);
}

void ui_theme_draw_version(tenv* env) {
  tuser_data* usr = env->usr;
  tcontext* ctx = env->ctx;
  char label[48] = {0};
  snprintf(label, sizeof(label), "V%s  \xE2\x80\xA2  OPTIMIZED", APP_VERSION);
  ImFont* font = usr->imgui_data.mono_font_bold[FONT_SIZE_SMALL];
  igPushFont(font, font->LegacySize);
  ImVec2 size;
  igCalcTextSize(&size, label, NULL, false, -1);
  igSetCursorPos((ImVec2){ctx->size[0] - size.x - 22, 16});
  igTextColored((ImVec4){UI_COLOR_ACCENT.x, UI_COLOR_ACCENT.y,
                         UI_COLOR_ACCENT.z, 0.80f},
                "%s", label);
  igPopFont();
}

ui_panel_layout ui_theme_panel_layout(tenv* env, float desired_width,
                                      float desired_height) {
  float max_width = env->ctx->size[0] - 56.0f;
  float max_height = env->ctx->size[1] - 86.0f;
  ui_panel_layout panel = {
      .width = desired_width < max_width ? desired_width : max_width,
      .height = desired_height < max_height ? desired_height : max_height};
  panel.x = (env->ctx->size[0] - panel.width) * 0.5f;
  panel.y = (env->ctx->size[1] - panel.height) * 0.5f;
  return panel;
}

ui_safe_area ui_theme_safe_area(tenv* env) {
  ui_safe_area safe = {0, 0, (float)env->ctx->size[0],
                       (float)env->ctx->size[1]};
#ifdef VLITHER_ANDROID
  SDL_Rect area;
  if (env->wnd && env->wnd->handle &&
      SDL_GetWindowSafeArea(env->wnd->handle, &area)) {
    safe.x = (float)area.x;
    safe.y = (float)area.y;
    safe.width = (float)area.w;
    safe.height = (float)area.h;
  }
#endif
  return safe;
}

ui_panel_layout ui_theme_fullscreen_layout(tenv* env, float inset_x,
                                           float inset_y) {
  ui_safe_area safe = ui_theme_safe_area(env);
  ui_panel_layout panel = {
      .x = safe.x + inset_x,
      .y = safe.y + inset_y,
      .width = safe.width - inset_x * 2.0f,
      .height = safe.height - inset_y * 2.0f};
  if (panel.width < 320.0f) {
    panel.x = safe.x;
    panel.width = safe.width;
  }
  if (panel.height < 240.0f) {
    panel.y = safe.y;
    panel.height = safe.height;
  }
  return panel;
}

void ui_theme_begin_panel(const char* id, ui_panel_layout panel,
                          ImGuiWindowFlags flags) {
  igSetCursorPos((ImVec2){panel.x, panel.y});
  igBeginChild_Str(id, (ImVec2){panel.width, panel.height},
                   ImGuiChildFlags_Borders, flags);
}

void ui_theme_end_panel(void) { igEndChild(); }

void ui_theme_centered_text(const char* text, ImVec4 color) {
  ImVec2 text_size;
  ImVec2 avail;
  igCalcTextSize(&text_size, text, NULL, false, -1);
  igGetContentRegionAvail(&avail);
  if (avail.x > text_size.x)
    igSetCursorPosX(igGetCursorPosX() + (avail.x - text_size.x) * 0.5f);
  igTextColored(color, "%s", text);
}

void ui_theme_section_label(const char* label) {
  igSpacing();
  igTextColored((ImVec4){UI_COLOR_ACCENT.x, UI_COLOR_ACCENT.y,
                         UI_COLOR_ACCENT.z, 0.92f},
                "%s", label);
  igSeparator();
}

bool ui_theme_back_button(const char* id) {
  char label[96] = {0};
  snprintf(label, sizeof(label), "\xE2\x86\x90  BACK##%s", id);
  return ui_theme_secondary_button(label, (ImVec2){142, 52});
}

bool ui_theme_primary_button(const char* label, ImVec2 size) {
  igPushStyleColor_Vec4(ImGuiCol_Text, (ImVec4){0.025f, 0.033f, 0.044f, 1});
  igPushStyleColor_Vec4(ImGuiCol_Button, (ImVec4){0.925f, 0.937f, 0.953f, 1});
  igPushStyleColor_Vec4(ImGuiCol_ButtonHovered,
                        (ImVec4){1.0f, 1.0f, 1.0f, 1});
  igPushStyleColor_Vec4(ImGuiCol_ButtonActive,
                        (ImVec4){0.76f, 0.80f, 0.84f, 1});
  bool pressed = igButton(label, size);
  igPopStyleColor(4);
  return pressed;
}

bool ui_theme_play_button(const char* id, ImVec2 size) {
  ImVec2 min;
  igGetCursorScreenPos(&min);
  bool pressed = igInvisibleButton(id, size, ImGuiButtonFlags_None);
  bool held = igIsItemActive();
  bool hovered = igIsItemHovered(ImGuiHoveredFlags_None);
  ImDrawList* draw = igGetWindowDrawList();
  ImVec2 max = {min.x + size.x, min.y + size.y};
  ImVec4 fill = held ? (ImVec4){0.76f, 0.80f, 0.84f, 1.0f}
                     : hovered ? (ImVec4){1.0f, 1.0f, 1.0f, 1.0f}
                               : (ImVec4){0.925f, 0.937f, 0.953f, 1.0f};
  ImDrawList_AddRectFilled(draw, min, max, ui_u32(fill),
                           igGetStyle()->FrameRounding, 0);
  ImDrawList_AddRect(draw, min, max, ui_u32(UI_COLOR_BORDER),
                     igGetStyle()->FrameRounding, 0, 1.0f);

  const char* text = "PLAY";
  ImVec2 text_size;
  igCalcTextSize(&text_size, text, NULL, false, -1);
  float group_width = 22.0f + 15.0f + text_size.x;
  float start_x = min.x + (size.x - group_width) * 0.5f;
  float center_y = min.y + size.y * 0.5f;
  ImVec2 tip = {start_x + 20.0f, center_y};
  ImVec2 upper = {start_x, center_y - 11.0f};
  ImVec2 lower = {start_x, center_y + 11.0f};
  ImU32 ink = ui_u32((ImVec4){0.025f, 0.033f, 0.044f, 1.0f});
  ImDrawList_AddTriangleFilled(draw, tip, upper, lower, ink);
  ImDrawList_AddText_Vec2(
      draw, (ImVec2){start_x + 37.0f, center_y - text_size.y * 0.5f}, ink,
      text, NULL);
  return pressed;
}

bool ui_theme_secondary_button(const char* label, ImVec2 size) {
  return igButton(label, size);
}

bool ui_theme_tab_button(const char* label, bool active, ImVec2 size) {
  if (active) {
    igPushStyleColor_Vec4(ImGuiCol_Button,
                          (ImVec4){0.045f, 0.235f, 0.172f, 1});
    igPushStyleColor_Vec4(ImGuiCol_ButtonHovered,
                          (ImVec4){0.060f, 0.310f, 0.220f, 1});
    igPushStyleColor_Vec4(ImGuiCol_ButtonActive,
                          (ImVec4){0.035f, 0.190f, 0.140f, 1});
  }
  bool pressed = igButton(label, size);
  if (active) igPopStyleColor(3);
  return pressed;
}

bool ui_theme_toggle(const char* id, bool* value, ImVec2 size) {
  if (!value) return false;
  if (size.x < 62.0f) size.x = 62.0f;
  if (size.y < 34.0f) size.y = 34.0f;
  ImVec2 min;
  igGetCursorScreenPos(&min);
  bool pressed = igInvisibleButton(id, size, ImGuiButtonFlags_None);
  if (pressed) *value = !*value;

  ImDrawList* draw = igGetWindowDrawList();
  ImVec2 max = {min.x + size.x, min.y + size.y};
  bool hovered = igIsItemHovered(ImGuiHoveredFlags_None);
  ImVec4 track = *value ? (ImVec4){0.045f, 0.42f, 0.30f, 0.96f}
                        : (ImVec4){0.070f, 0.083f, 0.105f, 0.98f};
  if (hovered) {
    track.x += 0.025f;
    track.y += 0.025f;
    track.z += 0.025f;
  }
  float radius = size.y * 0.5f;
  ImDrawList_AddRectFilled(draw, min, max, ui_u32(track), radius, 0);
  ImDrawList_AddRect(draw, min, max,
                     ui_u32(*value ? UI_COLOR_ACCENT : UI_COLOR_BORDER),
                     radius, 0, 1.2f);
  float knob_radius = radius - 5.0f;
  float knob_x = *value ? max.x - radius : min.x + radius;
  ImDrawList_AddCircleFilled(
      draw, (ImVec2){knob_x, min.y + radius}, knob_radius,
      ui_u32(*value ? UI_COLOR_TEXT
                    : (ImVec4){0.52f, 0.55f, 0.60f, 1.0f}),
      32);
  return pressed;
}

void ui_theme_draw_card(ImDrawList* draw_list, ImVec2 min, ImVec2 max,
                        float rounding, float alpha) {
  ImVec4 fill = UI_COLOR_PANEL;
  fill.w = alpha;
  ImDrawList_AddRectFilled(draw_list, min, max, ui_u32(fill), rounding, 0);
  ImDrawList_AddRect(draw_list, min, max, ui_u32(UI_COLOR_BORDER), rounding, 0,
                     1.0f);
}
