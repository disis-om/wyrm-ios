#define SDL_MAIN_HANDLED 1
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <SDL3/SDL_system.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#include <TargetConditionals.h>
#include <math.h>
#include <unistd.h>
#include "user.h"
#include "network/server.h"
#include "WyrmOriginalAdapter.h"

static tenv engine;
static bool ready;
static unsigned frame_count;
static bool online_proven;
static int reported_width;
static int reported_height;
static int reported_screen = -1;
static bool engine_presentation;
static bool leaderboard_proven;

static const char* screen_name(int screen) {
  switch (screen) {
    case TITLE_SCREEN: return "HOME";
    case LOBBY: return "LOBBY";
    case PLAYING: return "PLAYING";
    case SKIN_EDITOR: return "SKIN_EDITOR";
    default: return "UNKNOWN";
  }
}

void WyrmIOSSetEnginePresentation(bool enabled) {
  if (engine_presentation == enabled) return;
  engine_presentation = enabled;
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow* window = nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
      if ([scene isKindOfClass:UIWindowScene.class] &&
          scene.activationState != UISceneActivationStateUnattached) {
        for (UIWindow* candidate in ((UIWindowScene*)scene).windows) {
          if (candidate.rootViewController) {
            window = candidate;
            if (candidate.isKeyWindow) break;
          }
        }
        break;
      }
    }
    if (!window) {
      engine_presentation = !enabled;
      NSLog(@"Wyrm presentation deferred: no connected window");
      return;
    }
    UIView* surface = window.rootViewController.view;
    CGRect portrait = window.bounds;
    CGFloat width = CGRectGetWidth(portrait);
    CGFloat height = CGRectGetHeight(portrait);
    [UIView performWithoutAnimation:^{
      surface.transform = CGAffineTransformIdentity;
      surface.bounds = enabled
          ? CGRectMake(0, 0, height, width)
          : CGRectMake(0, 0, width, height);
      surface.center = CGPointMake(CGRectGetMidX(portrait), CGRectGetMidY(portrait));
      if (enabled) surface.transform = CGAffineTransformMakeRotation((CGFloat)M_PI_2);
      [surface setNeedsLayout];
      [surface layoutIfNeeded];
    }];
    SDL_Log("Wyrm iOS presentation=%s os=portrait logical=%.0fx%.0f rotation=%d",
            enabled ? "rotated-landscape" : "portrait",
            enabled ? height : width, enabled ? width : height,
            enabled ? 90 : 0);
  });
}

static void frame(void* unused) {
  (void)unused;
  if (!ready) return;
  twindow_poll_input(engine.wnd);
  tinput(&engine);
  if (engine.ctx->swapchain_ok) trender(&engine);
  else if (engine.usr->gdata.connection) server_poll(&engine);
  if (reported_screen != (int)engine.usr->gdata.curr_screen) {
    reported_screen = (int)engine.usr->gdata.curr_screen;
    WyrmIOSSetEnginePresentation(reported_screen != TITLE_SCREEN &&
                                 reported_screen != SKIN_EDITOR);
    SDL_Log("Wyrm original engine: screen=%s (%d)",
            screen_name(reported_screen), reported_screen);
  }
  tkeyboard_update(engine.kb);
  tmouse_update(engine.ms);
  if (engine.ctx->last_present_succeeded && frame_count++ == 0)
    SDL_Log("Wyrm original engine: first Thermite frame presented");
  if (engine.ctx->last_present_succeeded) {
    int width = 0;
    int height = 0;
    SDL_GetWindowSizeInPixels(engine.wnd->handle, &width, &height);
    if (width != reported_width || height != reported_height) {
      SDL_DisplayOrientation orientation = SDL_GetCurrentDisplayOrientation(
          SDL_GetDisplayForWindow(engine.wnd->handle));
      reported_width = width;
      reported_height = height;
      SDL_Log("Wyrm original engine: orientation=%d drawable=%dx%d",
              (int)orientation, width, height);
    }
  }
  if (frame_count == 120)
    SDL_Log("Wyrm original engine: 120 frames; ai=%d arena_ready=%d spawned=%d",
            engine.usr->gdata.ai_mode, engine.usr->gdata.arena_ready,
            engine.usr->gdata.join_spawned);
  if (!online_proven && !engine.usr->gdata.ai_mode &&
      engine.usr->gdata.arena_ready && engine.usr->gdata.join_spawned &&
      get_snake(&engine.usr->gdata, engine.usr->gdata.data.snake_id) &&
      engine.ctx->last_present_succeeded) {
    online_proven = true;
    snake* own = get_snake(&engine.usr->gdata,
                           engine.usr->gdata.data.snake_id);
    SDL_Log("Wyrm original engine: online arena admitted, own snake spawned, frame presented id=%d segments=%d",
            own->id, own->sct);
  }
  if (!leaderboard_proven && engine.usr->gdata.curr_screen == PLAYING &&
      engine.usr->gdata.data.gotlb) {
    leaderboard_proven = true;
    SDL_Log("Wyrm original engine: leaderboard ready rank=%d players=%d leader=%s score=%d",
            engine.usr->gdata.data.rank,
            engine.usr->gdata.data.slither_count,
            engine.usr->gdata.data.lb.entries[0].nickname,
            engine.usr->gdata.data.lb.entries[0].score);
  }
}

static int engine_main(int argc, char** argv) {
  @autoreleasepool {
#if TARGET_OS_SIMULATOR
    // SimMetalHost aborts while encoding the original ImGui texture descriptors.
    // Keep Vulkan bindings unchanged; use MoltenVK's direct-resource path here.
    setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "0", 1);
#endif
    NSFileManager* files = NSFileManager.defaultManager;
    NSURL* base = [files URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL* app = [base URLByAppendingPathComponent:@"OriginalEngine-23/app" isDirectory:YES];
    NSError* error = nil;
    if (![files createDirectoryAtURL:app withIntermediateDirectories:YES attributes:nil error:&error]) {
      NSLog(@"Wyrm storage failed: %@", error); return 1;
    }
    // Versioned immutable assets avoid reusing stale textures after an update.
    NSURL* working = [base URLByAppendingPathComponent:@"OriginalEngine-23" isDirectory:YES];
    NSURL* assets = [app URLByAppendingPathComponent:@"res" isDirectory:YES];
    NSURL* bundle = [NSBundle.mainBundle URLForResource:@"res" withExtension:nil];
    if (!bundle) { NSLog(@"Wyrm original assets missing"); return 1; }
    if (![files fileExistsAtPath:assets.path] && ![files copyItemAtURL:bundle toURL:assets error:&error]) {
      NSLog(@"Wyrm asset preparation failed: %@", error); return 1;
    }
    if (chdir(working.path.fileSystemRepresentation) != 0) return 1;
    // UIKit always remains portrait. Lobby/arena rotate only the SDL surface,
    // so Appetize and a physical iPhone never need to approve an orientation
    // change while the original engine still receives a landscape drawable.
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "Portrait");
    SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "1");
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) return 1;
    engine.config.argc = argc;
    engine.config.argv = argv;
    engine.config.running = true;
    engine.config.vsync = true;
    engine.config.fif = 3;
    engine.config.aspect_ratio = 16 / 9.0f;
    engine.config.title = "Wyrm";
    engine.usr = calloc(1, sizeof(tuser_data));
    if (!engine.usr) return 1;
    tlaunch(&engine);
    engine.wnd = twindow_create(&engine, trender, tresize);
    if (!engine.wnd) { SDL_Log("Wyrm window failed: %s", SDL_GetError()); return 1; }
    engine.kb = tkeyboard_create(engine.wnd);
    engine.ms = tmouse_create(engine.wnd);
    engine.ctx = tcontext_create(engine.wnd, engine.config.vsync, engine.config.fif);
    if (!engine.ctx) { SDL_Log("Wyrm original context failed"); return 1; }
    tinit(&engine);
    ready = true;
    for (int i = 1; i < argc; ++i) {
      if (!strcmp(argv[i], "--smoke-ai")) WyrmIOSRequestPlay("Apple test", "", true);
      if (!strcmp(argv[i], "--smoke-lobby")) {
        WyrmIOSSetEnginePresentation(true);
        snprintf(engine.usr->usrs.nickname,
                 sizeof(engine.usr->usrs.nickname), "Apple test");
        engine.usr->gdata.curr_screen = LOBBY;
      }
      if (!strcmp(argv[i], "--smoke-online"))
        WyrmIOSRequestPlay("Apple test", engine.usr->usrs.ipv4, false);
    }
    if (!SDL_SetiOSAnimationCallback(engine.wnd->handle, 1, frame, NULL)) return 1;
    SDL_Log("Wyrm original engine initialized; Apple animation callback installed");
    return 0;
  }
}

int main(int argc, char** argv) { return SDL_RunApp(argc, argv, engine_main, NULL); }
