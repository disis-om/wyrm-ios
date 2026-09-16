#ifndef UI_THEME_H
#define UI_THEME_H

#include <thermite.h>

#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS
#include "../cimgui/cimgui.h"

typedef struct ui_panel_layout {
  float x;
  float y;
  float width;
  float height;
} ui_panel_layout;

typedef struct ui_safe_area {
  float x;
  float y;
  float width;
  float height;
} ui_safe_area;

extern const ImVec4 UI_COLOR_ACCENT;
extern const ImVec4 UI_COLOR_TEXT;
extern const ImVec4 UI_COLOR_MUTED;
extern const ImVec4 UI_COLOR_PANEL;
extern const ImVec4 UI_COLOR_BORDER;

void ui_theme_apply(void);
void ui_theme_draw_background(tenv* env);
void ui_theme_draw_version(tenv* env);
void ui_theme_transition_begin(tenv* env);
void ui_theme_transition_end(tenv* env);

ui_panel_layout ui_theme_panel_layout(tenv* env, float desired_width,
                                      float desired_height);
ui_panel_layout ui_theme_fullscreen_layout(tenv* env, float inset_x,
                                           float inset_y);
ui_safe_area ui_theme_safe_area(tenv* env);
void ui_theme_begin_panel(const char* id, ui_panel_layout panel,
                          ImGuiWindowFlags flags);
void ui_theme_end_panel(void);

void ui_theme_centered_text(const char* text, ImVec4 color);
void ui_theme_section_label(const char* label);
bool ui_theme_back_button(const char* id);
bool ui_theme_primary_button(const char* label, ImVec2 size);
bool ui_theme_play_button(const char* id, ImVec2 size);
bool ui_theme_secondary_button(const char* label, ImVec2 size);
bool ui_theme_tab_button(const char* label, bool active, ImVec2 size);
bool ui_theme_toggle(const char* id, bool* value, ImVec2 size);
void ui_theme_draw_card(ImDrawList* draw_list, ImVec2 min, ImVec2 max,
                        float rounding, float alpha);

#endif
