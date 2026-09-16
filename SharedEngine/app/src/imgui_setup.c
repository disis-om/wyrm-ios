#include "imgui_setup.h"

#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS

#include "cimgui/cimgui.h"
#include "cimgui/cimgui_impl.h"

#include "user.h"
#include "mobile/mobile_controls.h"
#include "ui/ui_theme.h"

#ifdef VLITHER_ANDROID
#include <SDL3/SDL.h>

static tenv* android_env;
static bool ui_touch_active;
static SDL_FingerID ui_touch_finger;

static bool is_touch_mouse_event(const SDL_Event* event) {
  switch (event->type) {
    case SDL_EVENT_MOUSE_MOTION:
      return event->motion.which == SDL_TOUCH_MOUSEID;
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP:
      return event->button.which == SDL_TOUCH_MOUSEID;
    case SDL_EVENT_MOUSE_WHEEL:
      return event->wheel.which == SDL_TOUCH_MOUSEID;
    default:
      return false;
  }
}

/* Dear ImGui names its generic pointer queue "Mouse", but the source marker
   below is TouchScreen and the data comes straight from SDL finger events.
   This deliberately bypasses SDL's touch-to-mouse compatibility layer. */
static bool imgui_process_direct_touch(const SDL_Event* event,
                                       bool gameplay_owned) {
  if (event->type == SDL_EVENT_WILL_ENTER_BACKGROUND ||
      event->type == SDL_EVENT_WINDOW_FOCUS_LOST) {
    if (ui_touch_active) {
      ImGuiIO* io = igGetIO_Nil();
      ImGuiIO_AddMouseSourceEvent(io, ImGuiMouseSource_TouchScreen);
      ImGuiIO_AddMouseButtonEvent(io, 0, false);
      ui_touch_active = false;
    }
    return false;
  }

  if (event->type != SDL_EVENT_FINGER_DOWN &&
      event->type != SDL_EVENT_FINGER_MOTION &&
      event->type != SDL_EVENT_FINGER_UP &&
      event->type != SDL_EVENT_FINGER_CANCELED)
    return false;

  const SDL_FingerID finger = event->tfinger.fingerID;
  if (event->type == SDL_EVENT_FINGER_DOWN) {
    if (gameplay_owned || ui_touch_active) return false;
    ui_touch_active = true;
    ui_touch_finger = finger;
  } else if (!ui_touch_active || ui_touch_finger != finger) {
    return false;
  }

  ImGuiIO* io = igGetIO_Nil();
  float width = io->DisplaySize.x;
  float height = io->DisplaySize.y;
  if (width <= 0.0f || height <= 0.0f) {
    int window_width = 0;
    int window_height = 0;
    SDL_GetWindowSize(android_env->wnd->handle, &window_width, &window_height);
    width = (float)window_width;
    height = (float)window_height;
  }

  ImGuiIO_AddMouseSourceEvent(io, ImGuiMouseSource_TouchScreen);
  ImGuiIO_AddMousePosEvent(io, event->tfinger.x * width,
                          event->tfinger.y * height);

  if (event->type == SDL_EVENT_FINGER_DOWN) {
    ImGuiIO_AddMouseButtonEvent(io, 0, true);
  } else if (event->type == SDL_EVENT_FINGER_UP ||
             event->type == SDL_EVENT_FINGER_CANCELED) {
    ImGuiIO_AddMouseButtonEvent(io, 0, false);
    ui_touch_active = false;
  }
  return true;
}

static bool imgui_process_android_event(const void* event) {
  const SDL_Event* sdl_event = event;
  bool gameplay_owned = mobile_controls_process_event(android_env, event);
  bool touch_handled =
      imgui_process_direct_touch(sdl_event, gameplay_owned);

  /* SDL_TOUCH_MOUSEID events are compatibility duplicates of the raw finger
     stream above. Never queue them a second time. Physical mouse, keyboard,
     text and controller events still use the official SDL ImGui backend. */
  bool backend_handled = false;
  if (!is_touch_mouse_event(sdl_event) &&
      sdl_event->type != SDL_EVENT_FINGER_DOWN &&
      sdl_event->type != SDL_EVENT_FINGER_MOTION &&
      sdl_event->type != SDL_EVENT_FINGER_UP &&
      sdl_event->type != SDL_EVENT_FINGER_CANCELED)
    backend_handled = igImplSDL3_ProcessEvent(event);

  return gameplay_owned || touch_handled || backend_handled;
}
#endif

void imgui_init(tenv* env) {
  tuser_data* usr = env->usr;

  igCreateContext(NULL);
  igImplVulkan_Init(&(ImGui_ImplVulkan_InitInfo){
      .ApiVersion = VK_API_VERSION_1_0,
      .Instance = env->ctx->instance,
      .PhysicalDevice = env->ctx->ph_device,
      .Device = env->ctx->device,
      .QueueFamily = env->ctx->queue_family,
      .Queue = env->ctx->queue,
      .DescriptorPool = env->ctx->descriptor_pool,
      .DescriptorPoolSize = 0,
      .MinImageCount = env->ctx->min_image_count,
      .ImageCount = env->ctx->fif,
      .PipelineCache = NULL,
      .PipelineInfoMain = {.RenderPass = env->ctx->renderpass,
                           .Subpass = 0,
                           .MSAASamples = VK_SAMPLE_COUNT_1_BIT},
      .UseDynamicRendering = false});
#ifdef VLITHER_ANDROID
  android_env = env;
  ui_touch_active = false;
  SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
  igImplSDL3_InitForVulkan(env->wnd->handle);
  twindow_set_event_handler(env->wnd, imgui_process_android_event);
#else
  igImplGlfw_InitForVulkan(env->wnd->handle, true);
#endif
  ImGuiIO* io = igGetIO_Nil();
  // io->MouseDrawCursor = true;

  for (int i = 0; i < NUM_FONT_SIZES; i++) {
    ImFontConfig icons_config = {.FontDataOwnedByAtlas = true,
                                 .OversampleH = 0,
                                 .OversampleV = 0,
                                 .GlyphMaxAdvanceX = FLT_MAX,
                                 .RasterizerDensity = 1,
                                 .RasterizerMultiply = 1,
                                 .EllipsisChar = 0,
                                 .MergeMode = true,
                                 .GlyphOffset = (ImVec2){0, 2 + i},
                                 .GlyphMinAdvanceX = 26.0f + i * 6};

    usr->imgui_data.mono_font[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/mono_regular.ttf", 20 + i * 4, NULL, NULL);

    ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/iconfont.ttf", 20 + i * 4, &icons_config,
        (const ImWchar[]){0xe900, 0xeaea, 0});

    usr->imgui_data.regular_font[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/regular_regular.ttf", 20 + i * 4, NULL, NULL);

    ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/iconfont.ttf", 20 + i * 4, &icons_config,
        (const ImWchar[]){0xe900, 0xeaea, 0});

    usr->imgui_data.mono_font_bold[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/mono_bold.ttf", 20 + i * 4, NULL, NULL);

    ImFontAtlas_AddFontFromFileTTF(io->Fonts, "app/res/fonts/iconfont.ttf",
                                   20 + i * 4, &icons_config,
                                   (const ImWchar[]){0xe900, 0xeaea, 0});

    usr->imgui_data.regular_font_bold[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/regular_bold.ttf", 20 + i * 4, NULL, NULL);

    ImFontAtlas_AddFontFromFileTTF(io->Fonts, "app/res/fonts/iconfont.ttf",
                                   20 + i * 4, &icons_config,
                                   (const ImWchar[]){0xe900, 0xeaea, 0});

    /* The two faces the app itself is set in, loaded from the same files
       Compose loads, so the arena's overlay and the app's screens speak with
       one voice. The display serif carries numbers and is loaded a size larger
       at every step, because a serif at a body size reads as decoration. */
    usr->imgui_data.display_font[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/wyrm_display.ttf", 24 + i * 5, NULL, NULL);

    usr->imgui_data.body_font[i] = ImFontAtlas_AddFontFromFileTTF(
        io->Fonts, "app/res/fonts/wyrm_body.ttf", 18 + i * 4, NULL, NULL);
  }
  
  io->ConfigFlags |= ImGuiConfigFlags_DockingEnable;
  io->IniFilename = NULL;

  ui_theme_apply();
}

void imgui_prerender() {
  igImplVulkan_NewFrame();
#ifdef VLITHER_ANDROID
  igImplSDL3_NewFrame();
#else
  igImplGlfw_NewFrame();
#endif
  igNewFrame();
}

void imgui_render(VkCommandBuffer cmd) {
  igImplVulkan_RenderDrawData(igGetDrawData(), cmd, NULL);
}

void imgui_destroy() {
#ifdef VLITHER_ANDROID
  igImplSDL3_Shutdown();
#else
  igImplGlfw_Shutdown();
#endif
  igImplVulkan_Shutdown();
  igDestroyContext(NULL);
}
