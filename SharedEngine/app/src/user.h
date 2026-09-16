#ifndef USER_H
#define USER_H

#include "imgui_setup.h"
#include "rendering/renderer.h"

#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS
#include "cimgui/cimgui.h"
#include "cimgui/cimgui_impl.h"
#include "constants.h"

#include "game/game_data.h"
#include "game/user_settings.h"
#include "mobile/mobile_controls.h"
#include "mobile/mobile_hotkeys.h"

TDEF_USER_DATA({
  renderer* r;

  struct {
    ImFont* mono_font[NUM_FONT_SIZES];
    ImFont* regular_font[NUM_FONT_SIZES];
    ImFont* mono_font_bold[NUM_FONT_SIZES];
    ImFont* regular_font_bold[NUM_FONT_SIZES];
    /* Wyrm's own two faces, the same files Compose uses: the display serif for
       numbers, the body face for anything read as words. */
    ImFont* display_font[NUM_FONT_SIZES];
    ImFont* body_font[NUM_FONT_SIZES];
  } imgui_data;

  struct {
    VkDescriptorSet* scene;
  } viewport_widget;

  game_data gdata;
  user_settings usrs;
  mobile_controls_state mobile_controls;
  mobile_hotkeys_state mobile_hotkeys;
});

#endif
