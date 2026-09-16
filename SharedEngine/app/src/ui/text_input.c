#include "text_input.h"

#include <string.h>

#ifdef VLITHER_ANDROID
#include <SDL3/SDL.h>
#endif

static bool paste_clipboard_text(char* buffer, size_t buffer_size,
                                 ImGuiInputTextFlags flags,
                                 ImGuiInputTextCallback callback,
                                 void* user_data) {
  if (!buffer || buffer_size == 0) return false;

#ifdef VLITHER_ANDROID
  char* clipboard = SDL_GetClipboardText();
  if (!clipboard || !clipboard[0]) {
    if (clipboard) SDL_free(clipboard);
    return false;
  }
#else
  const char* clipboard = igGetClipboardText();
  if (!clipboard || !clipboard[0]) return false;
#endif

  size_t written = 0;
  if ((flags & ImGuiInputTextFlags_CallbackCharFilter) && callback) {
    for (const unsigned char* p = (const unsigned char*)clipboard;
         *p && written + 1 < buffer_size; ++p) {
      ImGuiInputTextCallbackData data = {0};
      data.EventFlag = ImGuiInputTextFlags_CallbackCharFilter;
      data.Flags = flags;
      data.UserData = user_data;
      data.EventChar = (ImWchar)*p;
      if (callback(&data) == 0 && data.EventChar != 0 && data.EventChar < 128)
        buffer[written++] = (char)data.EventChar;
    }
    buffer[written] = '\0';
  } else {
    size_t length = strlen(clipboard);
    if (length >= buffer_size) length = buffer_size - 1;
    memcpy(buffer, clipboard, length);
    buffer[length] = '\0';
    written = length;
  }

#ifdef VLITHER_ANDROID
  SDL_free(clipboard);
#endif
  return written > 0;
}

bool ui_input_text_with_paste(const char* label, const char* hint, char* buffer,
                              size_t buffer_size, ImGuiInputTextFlags flags,
                              ImGuiInputTextCallback callback, void* user_data) {
  bool changed = igInputTextWithHint(label, hint, buffer, buffer_size, flags,
                                     callback, user_data);
  bool hovered = igIsItemHovered(ImGuiHoveredFlags_None);
  ImGuiIO* io = igGetIO_Nil();

  igPushID_Str(label);
  if (hovered && io->MouseDown[ImGuiMouseButton_Left] &&
      io->MouseDownDuration[ImGuiMouseButton_Left] >= 0.55f &&
      io->MouseDownDurationPrev[ImGuiMouseButton_Left] < 0.55f) {
    igOpenPopup_Str("##paste_menu", ImGuiPopupFlags_None);
  }

  if (igBeginPopup("##paste_menu", ImGuiWindowFlags_AlwaysAutoResize)) {
    igTextDisabled("CLIPBOARD");
    if (igMenuItem_Bool("PASTE", NULL, false, true)) {
      igClearActiveID();
      changed |= paste_clipboard_text(buffer, buffer_size, flags, callback,
                                      user_data);
      igCloseCurrentPopup();
    }
    igEndPopup();
  }
  igPopID();
  return changed;
}
