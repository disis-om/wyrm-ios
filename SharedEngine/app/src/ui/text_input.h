#ifndef UI_TEXT_INPUT_H
#define UI_TEXT_INPUT_H

#include <stddef.h>

#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS
#include "../cimgui/cimgui.h"

/* Mobile-friendly text input. Holding a field opens a native-looking Paste
   action backed by the Android system clipboard. */
bool ui_input_text_with_paste(const char* label, const char* hint, char* buffer,
                              size_t buffer_size, ImGuiInputTextFlags flags,
                              ImGuiInputTextCallback callback, void* user_data);

#endif
