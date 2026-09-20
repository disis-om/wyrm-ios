#include <stddef.h>
#include <stdio.h>

#include "game/user_settings.h"

#define ASSERT_OFFSET(field, expected) \
  _Static_assert(offsetof(user_settings, field) == (expected), \
                 "user_settings." #field " ABI offset changed")

_Static_assert(sizeof(user_settings) == 2720,
               "user_settings ABI size changed");
ASSERT_OFFSET(version, 0);
ASSERT_OFFSET(nickname, 4);
ASSERT_OFFSET(ipv4, 29);
ASSERT_OFFSET(modes, 436);
ASSERT_OFFSET(mobile_controls, 540);
ASSERT_OFFSET(hotkeys, 600);
ASSERT_OFFSET(arrow_controls, 1240);
ASSERT_OFFSET(mobile_hotkeys, 1272);
ASSERT_OFFSET(auto_respawn, 1436);
ASSERT_OFFSET(rope_mode_key, 1440);
ASSERT_OFFSET(arrow_style, 1456);
ASSERT_OFFSET(skin_rgba, 1460);
ASSERT_OFFSET(arena_background, 2484);
ASSERT_OFFSET(arena_persona, 2488);
ASSERT_OFFSET(death_hold_s, 2492);
ASSERT_OFFSET(head_dot_size, 2496);
ASSERT_OFFSET(hud_minimap_x, 2528);
ASSERT_OFFSET(joystick_opacity, 2568);
ASSERT_OFFSET(hotkey_scale, 2580);
ASSERT_OFFSET(hud_chat_opacity, 2712);

#define PRINT_FIELD(field) \
  printf("%-28s %4zu %4zu\n", #field, offsetof(user_settings, field), \
         sizeof(((user_settings *)0)->field))

int main(void) {
  printf("user_settings size %zu\n", sizeof(user_settings));
  printf("field                        off size\n");
  PRINT_FIELD(version);
  PRINT_FIELD(nickname);
  PRINT_FIELD(ipv4);
  PRINT_FIELD(modes);
  PRINT_FIELD(mobile_controls);
  PRINT_FIELD(hotkeys);
  PRINT_FIELD(arrow_controls);
  PRINT_FIELD(mobile_hotkeys);
  PRINT_FIELD(auto_respawn);
  PRINT_FIELD(rope_mode_key);
  PRINT_FIELD(arrow_style);
  PRINT_FIELD(skin_rgba);
  PRINT_FIELD(arena_background);
  PRINT_FIELD(arena_persona);
  PRINT_FIELD(death_hold_s);
  PRINT_FIELD(head_dot_size);
  PRINT_FIELD(hud_minimap_x);
  PRINT_FIELD(joystick_opacity);
  PRINT_FIELD(hotkey_scale);
  PRINT_FIELD(hud_chat_opacity);
  return 0;
}
