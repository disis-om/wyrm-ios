#include "WyrmOriginalAdapter.h"

#include <SDL3/SDL.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "game/backgrounds.h"
#include "game/tag_count.h"
#include "game/user_settings.h"
#include "rendering/renderer.h"
#include "user.h"

typedef struct apple_skin_selection {
  bool pending;
  int preset;
  int accessory;
  int tag;
  int background;
  char code[MAX_SKIN_CODE_LEN + 1];
} apple_skin_selection;

static SDL_Mutex* skin_mutex;
static apple_skin_selection queued;

bool WyrmIOSQueueSkinSelection(int preset, const char* code, int accessory,
                               int tag, int background) {
  if (!skin_mutex || preset < 0 || preset >= NUM_DEFAULT_SKINS ||
      accessory < -1 || accessory >= NUM_ACCESSORIES ||
      tag < -1 || tag >= TAG_COUNT ||
      background < 0 || background >= NUM_BACKGROUNDS)
    return false;
  SDL_LockMutex(skin_mutex);
  queued.pending = true;
  queued.preset = preset;
  queued.accessory = accessory;
  queued.tag = tag;
  queued.background = background;
  snprintf(queued.code, sizeof(queued.code), "%s", code ? code : "");
  SDL_UnlockMutex(skin_mutex);
  return true;
}

void WyrmIOSApplySkinSelection(tenv* env) {
  if (!skin_mutex) skin_mutex = SDL_CreateMutex();
  if (!skin_mutex || !env) return;

  apple_skin_selection next = {0};
  SDL_LockMutex(skin_mutex);
  if (queued.pending) {
    next = queued;
    queued.pending = false;
  }
  SDL_UnlockMutex(skin_mutex);
  if (!next.pending) return;

  user_settings* settings = &env->usr->usrs;
  settings->default_skin = (uint8_t)next.preset;
  settings->accessory = next.accessory < 0 ? NO_ACCESSORY : (uint8_t)next.accessory;
  settings->tag_index = next.tag;
  settings->arena_background = background_clamp(next.background);
  snprintf(settings->skin_code, sizeof(settings->skin_code), "%s", next.code);
  settings->custom_skin = settings->skin_code[0] != '\0';
  memset(settings->skin_rgba, 0, sizeof(settings->skin_rgba));
  renderer_set_background(env->usr->r, env->ctx, settings->arena_background);
  save_user_settings(settings);
  SDL_Log("Wyrm Apple skin applied preset=%d custom=%d accessory=%d tag=%d background=%d",
          next.preset, settings->custom_skin, next.accessory, next.tag,
          next.background);
}
