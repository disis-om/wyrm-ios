#define SDL_MAIN_HANDLED 1
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <SDL3/SDL_system.h>
#import <Foundation/Foundation.h>
#include <TargetConditionals.h>
#include <unistd.h>
#include "user.h"
#include "network/server.h"
#include "WyrmOriginalAdapter.h"

static tenv engine;
static bool ready;
static unsigned frame_count;
static bool online_proven;

static void frame(void* unused) {
  (void)unused;
  if (!ready) return;
  twindow_poll_input(engine.wnd);
  tinput(&engine);
  if (engine.ctx->swapchain_ok) trender(&engine);
  else if (engine.usr->gdata.connection) server_poll(&engine);
  tkeyboard_update(engine.kb);
  tmouse_update(engine.ms);
  if (engine.ctx->last_present_succeeded && frame_count++ == 0)
    SDL_Log("Wyrm original engine: first Thermite frame presented");
  if (frame_count == 120)
    SDL_Log("Wyrm original engine: 120 frames; ai=%d arena_ready=%d spawned=%d",
            engine.usr->gdata.ai_mode, engine.usr->gdata.arena_ready,
            engine.usr->gdata.join_spawned);
  if (!online_proven && engine.usr->gdata.arena_ready && engine.usr->gdata.join_spawned &&
      engine.ctx->last_present_succeeded) {
    online_proven = true;
    SDL_Log("Wyrm original engine: online arena admitted, own snake spawned, frame presented");
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
    NSURL* app = [base URLByAppendingPathComponent:@"OriginalEngine-19/app" isDirectory:YES];
    NSError* error = nil;
    if (![files createDirectoryAtURL:app withIntermediateDirectories:YES attributes:nil error:&error]) {
      NSLog(@"Wyrm storage failed: %@", error); return 1;
    }
    // Versioned immutable assets avoid reusing stale textures after an update.
    NSURL* working = [base URLByAppendingPathComponent:@"OriginalEngine-19" isDirectory:YES];
    NSURL* assets = [app URLByAppendingPathComponent:@"res" isDirectory:YES];
    NSURL* bundle = [NSBundle.mainBundle URLForResource:@"res" withExtension:nil];
    if (!bundle) { NSLog(@"Wyrm original assets missing"); return 1; }
    if (![files fileExistsAtPath:assets.path] && ![files copyItemAtURL:bundle toURL:assets error:&error]) {
      NSLog(@"Wyrm asset preparation failed: %@", error); return 1;
    }
    if (chdir(working.path.fileSystemRepresentation) != 0) return 1;
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
      if (!strcmp(argv[i], "--smoke-online"))
        WyrmIOSRequestPlay("Apple test", engine.usr->usrs.ipv4, false);
    }
    if (!SDL_SetiOSAnimationCallback(engine.wnd->handle, 1, frame, NULL)) return 1;
    SDL_Log("Wyrm original engine initialized; Apple animation callback installed");
    return 0;
  }
}

int main(int argc, char** argv) { return SDL_RunApp(argc, argv, engine_main, NULL); }
