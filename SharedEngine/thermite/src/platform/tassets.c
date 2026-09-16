#include "tassets.h"

#ifdef VLITHER_ANDROID

#include <SDL3/SDL.h>
#include <stdio.h>
#include <unistd.h>

/*
 * Every packaged file, by name.
 *
 * Android serves assets out of the APK, which is not a filesystem the engine
 * can read from, so each one is copied to writable storage once and the
 * process then runs from there. The list is written by hand and must be
 * updated whenever a file is added to app/res — anything missing from it is
 * simply never copied, and the first thing to ask for it dies on a file that
 * is plainly sitting in the source tree.
 */
static const char* packaged_assets[] = {
    "fonts/iconfont.ttf",
    "fonts/mono_bold.ttf",
    "fonts/mono_italic.ttf",
    "fonts/mono_regular.ttf",
    "fonts/regular_bold.ttf",
    "fonts/regular_italic.ttf",
    "fonts/regular_regular.ttf",
    "fonts/wyrm_body.ttf",
    "fonts/wyrm_display.ttf",
    "shaders/bin/bdf.spv",
    "shaders/bin/bdv.spv",
    "shaders/bin/bgf.spv",
    "shaders/bin/bgv.spv",
    "shaders/bin/bpf.spv",
    "shaders/bin/bpv.spv",
    "shaders/bin/bstf.spv",
    "shaders/bin/bstv.spv",
    "shaders/bin/fdf.spv",
    "shaders/bin/fdrf.spv",
    "shaders/bin/fdrv.spv",
    "shaders/bin/fdv.spv",
    "shaders/bin/mmf.spv",
    "shaders/bin/mmv.spv",
    "shaders/bin/sprf.spv",
    "shaders/bin/sprv.spv",
    "textures/background_4k.png",
    "textures/backgrounds/bg_asanoha.png",
    "textures/backgrounds/bg_bluecube.png",
    "textures/backgrounds/bg_circuits.png",
    "textures/backgrounds/bg_circuits2.png",
    "textures/backgrounds/bg_graygrid.png",
    "textures/backgrounds/bg_hearts.png",
    "textures/backgrounds/bg_hexB.png",
    "textures/backgrounds/bg_hexice.png",
    "textures/backgrounds/bg_kitties.png",
    "textures/backgrounds/bg_leaves.png",
    "textures/backgrounds/bg_paint.png",
    "textures/backgrounds/bg_purplecube.png",
    "textures/backgrounds/bg_redcube.png",
    "textures/backgrounds/bg_rizz.png",
    "textures/backgrounds/bg_seigaiha.png",
    "textures/backgrounds/bg_snakey.png",
    "textures/backgrounds/bg_stainedglass.png",
    "textures/backgrounds/bg_usastar.png",
    "textures/backgrounds/bgee2.png",
    "textures/backgrounds/bgee_classic.png",
    "textures/home_navigation_icons.png",
    "textures/wyrm_tags.png",
    "textures/tex_atlas_8k.png",
    "textures/vlither_enhanced_logo.png",
};

static bool copy_packaged_asset(const char* pref_path, const char* asset) {
  char destination[1024];
  char directory[1024];
  SDL_snprintf(destination, sizeof(destination), "%sapp/res/%s", pref_path,
               asset);
  SDL_strlcpy(directory, destination, sizeof(directory));
  char* separator = SDL_strrchr(directory, '/');
  if (separator) {
    *separator = '\0';
    if (!SDL_CreateDirectory(directory)) {
      SDL_Log("Vlither: cannot create asset directory %s: %s", directory,
              SDL_GetError());
      return false;
    }
  }

  SDL_IOStream* source = SDL_IOFromFile(asset, "rb");
  if (!source) {
    SDL_Log("Vlither: packaged asset is missing: %s (%s)", asset,
            SDL_GetError());
    return false;
  }

  const Sint64 source_size = SDL_GetIOSize(source);
  SDL_PathInfo current_info;
  if (source_size >= 0 && SDL_GetPathInfo(destination, &current_info) &&
      current_info.type == SDL_PATHTYPE_FILE &&
      (Sint64)current_info.size == source_size) {
    SDL_CloseIO(source);
    return true;
  }

  SDL_IOStream* target = SDL_IOFromFile(destination, "wb");
  if (!target) {
    SDL_Log("Vlither: cannot write asset %s: %s", destination, SDL_GetError());
    SDL_CloseIO(source);
    return false;
  }

  bool ok = true;
  unsigned char buffer[64 * 1024];
  size_t count;
  while ((count = SDL_ReadIO(source, buffer, sizeof(buffer))) > 0) {
    if (SDL_WriteIO(target, buffer, count) != count) {
      ok = false;
      break;
    }
  }

  if (!SDL_CloseIO(target))
    ok = false;
  SDL_CloseIO(source);
  if (!ok)
    SDL_Log("Vlither: failed while copying asset %s: %s", asset,
            SDL_GetError());
  return ok;
}

bool tassets_prepare_android(void) {
  char* pref_path = SDL_GetPrefPath("Vlither", "VlitherEnhanced");
  if (!pref_path) {
    SDL_Log("Vlither: SDL_GetPrefPath failed: %s", SDL_GetError());
    return false;
  }

  bool ok = true;
  for (size_t i = 0; i < SDL_arraysize(packaged_assets); ++i) {
    if (!copy_packaged_asset(pref_path, packaged_assets[i])) {
      ok = false;
      break;
    }
  }

  if (ok && chdir(pref_path) != 0) {
    SDL_Log("Vlither: cannot switch to internal storage path %s", pref_path);
    ok = false;
  }
  SDL_free(pref_path);
  return ok;
}

#else

bool tassets_prepare_android(void) { return true; }

#endif
