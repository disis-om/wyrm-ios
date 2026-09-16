#include <stdio.h>
#include <stdlib.h>

#include "../core/tenv.h"
#include "../util/tdarray.h"

#ifdef VLITHER_ANDROID
#include <SDL3/SDL.h>
#include "platform/android_startup.h"

static double android_time_origin;
static int android_surface_recovery_attempts;
static int android_swapchain_recovery_attempts;
static const int ANDROID_MAX_GRAPHICS_RECOVERY_ATTEMPTS = 3;

double glfwGetTime(void) {
  return (double)SDL_GetTicksNS() / 1000000000.0 - android_time_origin;
}

void glfwSetTime(double value) {
  android_time_origin = (double)SDL_GetTicksNS() / 1000000000.0 - value;
}

static SDL_Scancode sdl_scancode_from_key(int key) {
  if (key >= 'A' && key <= 'Z')
    return (SDL_Scancode)(SDL_SCANCODE_A + key - 'A');
  if (key >= '1' && key <= '9')
    return (SDL_Scancode)(SDL_SCANCODE_1 + key - '1');
  if (key == '0')
    return SDL_SCANCODE_0;
  switch (key) {
    case GLFW_KEY_SPACE: return SDL_SCANCODE_SPACE;
    case GLFW_KEY_LEFT: return SDL_SCANCODE_LEFT;
    case GLFW_KEY_RIGHT: return SDL_SCANCODE_RIGHT;
    case GLFW_KEY_UP: return SDL_SCANCODE_UP;
    case GLFW_KEY_F11: return SDL_SCANCODE_F11;
    default: return SDL_SCANCODE_UNKNOWN;
  }
}

static int desktop_key_from_scancode(SDL_Scancode scancode) {
  if (scancode >= SDL_SCANCODE_A && scancode <= SDL_SCANCODE_Z)
    return 'A' + (int)(scancode - SDL_SCANCODE_A);
  if (scancode >= SDL_SCANCODE_1 && scancode <= SDL_SCANCODE_9)
    return '1' + (int)(scancode - SDL_SCANCODE_1);
  if (scancode == SDL_SCANCODE_0)
    return '0';
  switch (scancode) {
    case SDL_SCANCODE_SPACE: return GLFW_KEY_SPACE;
    case SDL_SCANCODE_LEFT: return GLFW_KEY_LEFT;
    case SDL_SCANCODE_RIGHT: return GLFW_KEY_RIGHT;
    case SDL_SCANCODE_UP: return GLFW_KEY_UP;
    case SDL_SCANCODE_F11: return GLFW_KEY_F11;
    default: return -1;
  }
}

static int desktop_mouse_button(Uint8 button) {
  switch (button) {
    case SDL_BUTTON_LEFT: return GLFW_MOUSE_BUTTON_LEFT;
    case SDL_BUTTON_RIGHT: return GLFW_MOUSE_BUTTON_RIGHT;
    case SDL_BUTTON_MIDDLE: return GLFW_MOUSE_BUTTON_MIDDLE;
    default: return -1;
  }
}

static void process_android_event(twindow* window, const SDL_Event* event) {
  tenv* env = window->env;
  if (window->_event_func)
    window->_event_func(event);

  switch (event->type) {
    case SDL_EVENT_QUIT:
      window->_closed = true;
      break;
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
    case SDL_EVENT_WINDOW_RESIZED: {
      int width = 0;
      int height = 0;
      SDL_GetWindowSizeInPixels(window->handle, &width, &height);
      window->size[0] = width;
      window->size[1] = height;
      window->_refresh = true;
      break;
    }
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP:
      if (env->kb && !event->key.repeat) {
        int key = desktop_key_from_scancode(event->key.scancode);
        if (key >= 0) {
          if (event->type == SDL_EVENT_KEY_DOWN)
            tdarray_push(&env->kb->keys_pressed, &key);
          else
            tdarray_push(&env->kb->keys_released, &key);
        }
      }
      break;
    case SDL_EVENT_TEXT_INPUT:
      if (env->kb && event->text.text[0])
        env->kb->char_pressed = event->text.text[0];
      break;
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP:
      if (env->ms) {
        int button = desktop_mouse_button(event->button.button);
        if (button >= 0) {
          if (event->type == SDL_EVENT_MOUSE_BUTTON_DOWN)
            tdarray_push(&env->ms->buttons_pressed, &button);
          else
            tdarray_push(&env->ms->buttons_released, &button);
        }
      }
      break;
    case SDL_EVENT_MOUSE_MOTION:
      if (env->ms) {
        env->ms->pos[0] = event->motion.x;
        env->ms->pos[1] = event->motion.y;
      }
      break;
    case SDL_EVENT_MOUSE_WHEEL:
      if (env->ms)
        env->ms->dwheel += event->wheel.y;
      break;
    default:
      break;
  }
}
#endif

void twindow_request_refresh(twindow* twindow) {
  twindow->_refresh = true;
}

#ifndef VLITHER_ANDROID
void window_resize_callback(GLFWwindow* window, int width, int height) {
  tenv* env = glfwGetWindowUserPointer(window);
  env->wnd->size[0] = width;
  env->wnd->size[1] = height;

  if (width > 0 && height > 0) {
    tcontext_resize(env->ctx, env->wnd->size, env->config.vsync);
    env->wnd->_resize_func(env);
    env->wnd->_render_func(env);
  }
}
#endif

twindow* twindow_create(tenv* env, trender_func render_func,
                        tresize_func resize_func) {
  twindow* window = malloc(sizeof(twindow));
  window->_render_func = render_func;
  window->_resize_func = resize_func;
  window->_refresh = false;
  window->_closed = false;
  window->_event_func = NULL;
  window->env = env;
#ifdef VLITHER_ANDROID
  if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
    SDL_Log("Vlither: SDL_Init failed: %s", SDL_GetError());
    free(window);
    return NULL;
  }

  SDL_SetAppMetadata(env->config.title, APP_VERSION, "com.wyrm.omrajput");
  window->handle = SDL_CreateWindow(
      env->config.title, 1280, 720,
      SDL_WINDOW_VULKAN | SDL_WINDOW_FULLSCREEN | SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if (!window->handle) {
    SDL_Log("Vlither: SDL_CreateWindow failed: %s", SDL_GetError());
    free(window);
    return NULL;
  }
  SDL_GetWindowSizeInPixels(window->handle, &window->size[0], &window->size[1]);
  glm_ivec2_copy(window->size, window->lsize);
  glm_ivec2_zero(window->lpos);
  env->config.fullscreen = true;
  return window;
#else
  if (glfwInit() == GLFW_FALSE) {
    printf("Error initializing window\n");
    return NULL;
  }

  glfwWindowHint(GLFW_RESIZABLE,
                 env->config.resizable ? GLFW_TRUE : GLFW_FALSE);
  glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);

  GLFWmonitor* primary = glfwGetPrimaryMonitor();
  const GLFWvidmode* vidmode = glfwGetVideoMode(primary);

  float padding = 0.8f;
  int mw = vidmode->width * padding;
  int mh = mw / env->config.aspect_ratio;
  if (mh > vidmode->height * padding) {
    mh = vidmode->height * padding;
    mw = mh * env->config.aspect_ratio;
  }
  int mx = (vidmode->width - mw) / 2;
  int my = (vidmode->height - mh) / 2;

  if (env->config.fullscreen) {
    window->size[0] = vidmode->width;
    window->size[1] = vidmode->height;
    window->lsize[0] = mw;
    window->lsize[1] = mh;
    window->lpos[0] = mx;
    window->lpos[1] = my;

    window->handle =
        glfwCreateWindow(window->size[0], window->size[1], env->config.title,
                         glfwGetPrimaryMonitor(), NULL);
  } else {
    window->size[0] = mw;
    window->size[1] = mh;
    window->lpos[0] = 0;
    window->lpos[1] = 0;
    window->lsize[0] = vidmode->width;
    window->lsize[1] = vidmode->height;

    glfwWindowHint(GLFW_POSITION_X, mx);
    glfwWindowHint(GLFW_POSITION_Y, my);

    window->handle = glfwCreateWindow(window->size[0], window->size[1],
                                      env->config.title, NULL, NULL);
  }

  if (!window->handle) {
    printf("Error creating window\n");
    return NULL;
  }

  glfwSetWindowUserPointer(window->handle, env);
  glfwSetFramebufferSizeCallback(window->handle, window_resize_callback);

  return window;
#endif
}

static void apply_pending_window_change(twindow* window) {
#ifdef VLITHER_ANDROID
  /* Android destroys and replaces the native SurfaceView while the SDL
     window object survives. Rebuild only Vulkan's surface-facing resources;
     ImGui and the raw-finger input backend remain bound to the same SDL
     window, which preserves live touch ownership after resume. */
  if (window->env->ctx && window->env->ctx->surface_lost) {
    if (android_surface_recovery_attempts >=
        ANDROID_MAX_GRAPHICS_RECOVERY_ATTEMPTS) {
      android_startup_failure(
          7, "Vulkan surface recovery exhausted",
          "VK_ERROR_SURFACE_LOST_KHR remained after 3 bounded retries");
      return;
    }
    android_surface_recovery_attempts++;
    char recovery_detail[128];
    snprintf(recovery_detail, sizeof(recovery_detail),
             "Recreating Android Vulkan surface · attempt %d / %d",
             android_surface_recovery_attempts,
             ANDROID_MAX_GRAPHICS_RECOVERY_ATTEMPTS);
    android_startup_stage(7, "Recovering Vulkan surface", recovery_detail);
    int width = 0;
    int height = 0;
    SDL_GetWindowSizeInPixels(window->handle, &width, &height);
    if (width > 0 && height > 0) {
      window->size[0] = width;
      window->size[1] = height;
      if (tcontext_recreate_surface(window->env->ctx, window,
                                    window->env->config.vsync)) {
        android_surface_recovery_attempts = 0;
        window->_refresh = false;
        window->_resize_func(window->env);
      }
    }
    return;
  }
  if (window->env->ctx && !window->env->ctx->swapchain_ok) {
    if (android_swapchain_recovery_attempts >=
        ANDROID_MAX_GRAPHICS_RECOVERY_ATTEMPTS) {
      android_startup_failure(
          7, "Swapchain recovery exhausted",
          "VK_ERROR_OUT_OF_DATE_KHR remained after 3 bounded retries");
      return;
    }
    android_swapchain_recovery_attempts++;
    char recovery_detail[128];
    snprintf(recovery_detail, sizeof(recovery_detail),
             "Recreating Vulkan swapchain · attempt %d / %d",
             android_swapchain_recovery_attempts,
             ANDROID_MAX_GRAPHICS_RECOVERY_ATTEMPTS);
    android_startup_stage(7, "Recovering swapchain", recovery_detail);
    tcontext_resize(window->env->ctx, window->size,
                    window->env->config.vsync);
    if (window->env->ctx->swapchain_ok) {
      android_swapchain_recovery_attempts = 0;
      window->_resize_func(window->env);
    }
    return;
  }
#endif
  if (window->_refresh) {
    if (window->env->ctx) {
      tcontext_resize(window->env->ctx, window->env->wnd->size,
                      window->env->config.vsync);
      window->_resize_func(window->env);
      /* A swapchain that came back the wrong shape is asked for again next
         frame: the driver was describing the display as it was before the
         rotation, and it only needs a moment to catch up. */
      window->_refresh = window->env->ctx->extent_stale;
      return;
    }
    window->_refresh = false;
  }
}

void twindow_poll_input(twindow* window) {
#ifdef VLITHER_ANDROID
  SDL_Event event;
  while (SDL_PollEvent(&event))
    process_android_event(window, &event);
#else
  glfwPollEvents();
#endif
  apply_pending_window_change(window);
}
void twindow_wait_input(twindow* window) {
#ifdef VLITHER_ANDROID
  SDL_Event event;
  /* A timeout guarantees that surface recovery is retried after Android has
     created the replacement SurfaceView even if no later input event arrives. */
  if (SDL_WaitEventTimeout(&event, 250))
    process_android_event(window, &event);
#else
  glfwWaitEvents();
#endif
  apply_pending_window_change(window);
}

void twindow_toggle_fullscreen(twindow* window) {
#ifdef VLITHER_ANDROID
  SDL_SetWindowFullscreen(window->handle, true);
  window->env->config.fullscreen = true;
#else
  GLFWmonitor* monitor = glfwGetPrimaryMonitor();
  const GLFWvidmode* mode = glfwGetVideoMode(monitor);

  if (!window->env->config.fullscreen) {
    glfwGetWindowPos(window->handle, &window->lpos[0], &window->lpos[1]);
    glfwGetWindowSize(window->handle, &window->lsize[0], &window->lsize[1]);

    glfwSetWindowMonitor(window->handle, monitor, 0, 0, mode->width,
                         mode->height, mode->refreshRate);

    window->env->config.fullscreen = true;
  } else {
    glfwRestoreWindow(window->handle);
    glfwSetWindowMonitor(window->handle, NULL, window->lpos[0], window->lpos[1],
                         window->lsize[0], window->lsize[1], mode->refreshRate);
    window->env->config.fullscreen = false;
  }
#endif
}

bool twindow_key_down(twindow* window, int key) {
#ifdef VLITHER_ANDROID
  SDL_Scancode scancode = sdl_scancode_from_key(key);
  const bool* state = SDL_GetKeyboardState(NULL);
  return scancode != SDL_SCANCODE_UNKNOWN && state[scancode];
#else
  return glfwGetKey(window->handle, key) == GLFW_PRESS;
#endif
}

bool twindow_button_down(twindow* window, int button) {
#ifdef VLITHER_ANDROID
  SDL_MouseButtonFlags state = SDL_GetMouseState(NULL, NULL);
  Uint8 sdl_button = button == GLFW_MOUSE_BUTTON_LEFT
                         ? SDL_BUTTON_LEFT
                         : (button == GLFW_MOUSE_BUTTON_RIGHT ? SDL_BUTTON_RIGHT
                                                              : SDL_BUTTON_MIDDLE);
  return (state & SDL_BUTTON_MASK(sdl_button)) != 0;
#else
  return glfwGetMouseButton(window->handle, button) == GLFW_PRESS;
#endif
}

bool twindow_closed(twindow* window) {
#ifdef VLITHER_ANDROID
  return window->_closed;
#else
  return glfwWindowShouldClose(window->handle);
#endif
}

void twindow_set_event_handler(twindow* window, tevent_func event_func) {
  window->_event_func = event_func;
}

void twindow_destroy(twindow* window) {
#ifdef VLITHER_ANDROID
  SDL_DestroyWindow(window->handle);
  SDL_Quit();
#else
  glfwTerminate();
#endif
  free(window);
}
