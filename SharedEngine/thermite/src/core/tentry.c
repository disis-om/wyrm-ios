#include "tentry.h"
#include <stdio.h>

#ifdef VLITHER_ANDROID
#include <SDL3/SDL.h>
#include "../platform/tassets.h"
#include "platform/android_startup.h"
#endif

int tentry(int argc, char** argv, size_t usr_size) {
  tenv env;

#ifdef VLITHER_ANDROID
  SDL_Log("Vlither: native startup begin");
  if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
    SDL_Log("Vlither: SDL initialization failed: %s", SDL_GetError());
    return 1;
  }
  android_startup_stage(1, "Native runtime online",
                        "SDL Android bootstrap and event runtime initialized");
  if (!tassets_prepare_android()) {
    SDL_Log("Vlither: required packaged assets could not be prepared");
    android_startup_failure(2, "Packaged assets unavailable",
                            "Required native assets could not be extracted");
    SDL_Quit();
    return 1;
  }
  SDL_Log("Vlither: packaged assets ready");
  android_startup_stage(2, "Packaged assets ready",
                        "Shaders, fonts and textures are available to native code");
#endif

  env.config.argc = argc;
  env.config.argv = argv;
  env.config.vsync = true;
  env.config.running = true;
  env.config.fullscreen = false;
  env.config.resizable = true;
  env.config.aspect_ratio = 16 / 9.0f;
  env.config.fif = 3;
  env.config.title = "app";
  env.usr = malloc(usr_size);

  tlaunch(&env);
#ifdef VLITHER_ANDROID
  SDL_Log("Vlither: user settings loaded");
#endif

  env.wnd = twindow_create(&env, trender, tresize);
#ifdef VLITHER_ANDROID
  if (!env.wnd) {
    android_startup_failure(3, "Android surface unavailable",
                            "SDL could not create the fullscreen Vulkan window");
    return 1;
  }
  SDL_Log("Vlither: SDL Vulkan window ready (%dx%d)", env.wnd->size[0],
          env.wnd->size[1]);
  char window_detail[128];
  snprintf(window_detail, sizeof(window_detail),
           "Fullscreen Vulkan surface requested at %d x %d", env.wnd->size[0],
           env.wnd->size[1]);
  android_startup_stage(3, "Android surface ready", window_detail);
#endif
  env.kb = tkeyboard_create(env.wnd);
  env.ms = tmouse_create(env.wnd);
#ifdef VLITHER_ANDROID
  SDL_Log("Vlither: creating Vulkan context");
#endif
  if ((env.ctx = tcontext_create(env.wnd, env.config.vsync, env.config.fif)) == NULL) {
    printf("Error creating context.\n");
#ifdef VLITHER_ANDROID
    android_startup_failure(7, "Vulkan context unavailable",
                            "Graphics initialization returned no usable context");
#endif
    return 1;
  }
#ifdef VLITHER_ANDROID
  SDL_Log("Vlither: Vulkan context ready");
#endif
  tinit(&env);
#ifdef VLITHER_ANDROID
  SDL_Log("Vlither: UI and renderer ready");
  android_startup_stage(9, "Graphics pipelines ready",
                        "Renderer, ImGui and mobile interface initialized");
  bool startup_ready_reported = false;
#endif

  while (env.config.running) {
    if (env.ctx->swapchain_ok) {
      twindow_poll_input(env.wnd);
    } else {
      twindow_wait_input(env.wnd);
      continue;
    }

    tinput(&env);
    trender(&env);
#ifdef VLITHER_ANDROID
    if (!startup_ready_reported && env.ctx->last_present_succeeded) {
      startup_ready_reported = true;
      android_startup_ready();
    }
#endif

    tkeyboard_update(env.kb);
    tmouse_update(env.ms);
  }
  tcontext_wait_idle(env.ctx);

  tdestroy(&env);
  tcontext_destroy(env.ctx);
  tmouse_destroy(env.ms);
  tkeyboard_destroy(env.kb);
  twindow_destroy(env.wnd);
  free(env.usr);

  return 0;
}
