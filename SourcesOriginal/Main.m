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
static bool canvas_proven;
static unsigned gameplay_frames;
static NSString* wyrm_engine_log_path;

static const char* wyrm_log_priority_name(SDL_LogPriority priority) {
  switch (priority) {
    case SDL_LOG_PRIORITY_TRACE: return "TRACE";
    case SDL_LOG_PRIORITY_VERBOSE: return "VERBOSE";
    case SDL_LOG_PRIORITY_DEBUG: return "DEBUG";
    case SDL_LOG_PRIORITY_INFO: return "INFO";
    case SDL_LOG_PRIORITY_WARN: return "WARN";
    case SDL_LOG_PRIORITY_ERROR: return "ERROR";
    case SDL_LOG_PRIORITY_CRITICAL: return "CRITICAL";
    default: return "UNKNOWN";
  }
}

static void wyrm_log_output(void* userdata, int category,
                            SDL_LogPriority priority, const char* message) {
  (void)userdata;
  @autoreleasepool {
    NSLog(@"Wyrm SDL [%s] %s", wyrm_log_priority_name(priority), message ?: "");
    if (!wyrm_engine_log_path) return;
    NSString* stamp = [NSISO8601DateFormatter stringFromDate:NSDate.date
                                                   timeZone:NSTimeZone.localTimeZone
                                              formatOptions:NSISO8601DateFormatWithInternetDateTime];
    NSString* line = [NSString stringWithFormat:@"[%@][ENGINE/%s/%d] %s\n",
                      stamp, wyrm_log_priority_name(priority), category,
                      message ?: ""];
    NSData* payload = [line dataUsingEncoding:NSUTF8StringEncoding];
    @synchronized(NSFileManager.class) {
      NSFileManager* files = NSFileManager.defaultManager;
      if (![files fileExistsAtPath:wyrm_engine_log_path])
        [files createFileAtPath:wyrm_engine_log_path contents:nil attributes:nil];
      NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:wyrm_engine_log_path];
      [handle seekToEndOfFile];
      [handle writeData:payload];
      [handle closeFile];
      NSNumber* size = [[files attributesOfItemAtPath:wyrm_engine_log_path error:nil]
          objectForKey:NSFileSize];
      if (size.unsignedLongLongValue > 1048576) {
        NSData* data = [NSData dataWithContentsOfFile:wyrm_engine_log_path];
        NSUInteger keep = MIN((NSUInteger)786432, data.length);
        NSData* tail = [data subdataWithRange:NSMakeRange(data.length - keep, keep)];
        [tail writeToFile:wyrm_engine_log_path atomically:YES];
      }
    }
  }
}

@interface WyrmShellHost : NSObject
+ (UIViewController*)makeViewController;
@end

// UIWindow owns the root controller's geometry and is allowed to lay it out
// again at any time.  Rotating that managed root view directly was therefore
// temporary: a later UIKit/Appetize layout restored portrait bounds while the
// 90-degree transform survived, producing the giant minimap/top-left crop.
// Keep the SDL controller as a child whose geometry we own instead.
@interface WyrmEngineContainerController : UIViewController
@property(nonatomic, strong) UIViewController* engineController;
@property(nonatomic, strong) UIViewController* shellController;
@property(nonatomic, assign) BOOL landscapePresentation;
- (void)installEngineController:(UIViewController*)controller;
- (void)installShellControllerIfNeeded;
- (BOOL)engineGeometryIsStable;
@end

@implementation WyrmEngineContainerController

- (void)loadView {
  self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.view.backgroundColor = UIColor.blackColor;
  self.view.clipsToBounds = YES;
}

- (void)installShellControllerIfNeeded {
  if (self.shellController) return;
  UIViewController* shell = [WyrmShellHost makeViewController];
  self.shellController = shell;
  [self addChildViewController:shell];
  shell.view.frame = self.view.bounds;
  shell.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:shell.view];
  [shell didMoveToParentViewController:self];
}

- (void)installEngineController:(UIViewController*)controller {
  self.engineController = controller;
  [self addChildViewController:controller];
  controller.view.autoresizingMask = UIViewAutoresizingNone;
  [self.view addSubview:controller.view];
  [controller didMoveToParentViewController:self];
  [self.view setNeedsLayout];
  [self.view layoutIfNeeded];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
  return UIInterfaceOrientationPortrait;
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  UIView* surface = self.engineController.view;
  if (!surface) return;
  CGRect portrait = self.view.bounds;
  CGFloat width = CGRectGetWidth(portrait);
  CGFloat height = CGRectGetHeight(portrait);
  surface.transform = CGAffineTransformIdentity;
  surface.bounds = self.landscapePresentation
      ? CGRectMake(0, 0, height, width)
      : CGRectMake(0, 0, width, height);
  surface.center = CGPointMake(CGRectGetMidX(portrait), CGRectGetMidY(portrait));
  if (self.landscapePresentation)
    surface.transform = CGAffineTransformMakeRotation((CGFloat)M_PI_2);
  self.shellController.view.frame = portrait;
}

- (void)setLandscapePresentation:(BOOL)enabled {
  _landscapePresentation = enabled;
  [self.view setNeedsLayout];
  [self.view layoutIfNeeded];
}

- (BOOL)engineGeometryIsStable {
  UIView* surface = self.engineController.view;
  if (!surface) return NO;
  CGRect portrait = self.view.bounds;
  CGSize expected = self.landscapePresentation
      ? CGSizeMake(CGRectGetHeight(portrait), CGRectGetWidth(portrait))
      : portrait.size;
  const CGFloat epsilon = 0.5;
  BOOL sizeOK = fabs(CGRectGetWidth(surface.bounds) - expected.width) < epsilon &&
                fabs(CGRectGetHeight(surface.bounds) - expected.height) < epsilon;
  BOOL rotationOK = self.landscapePresentation
      ? fabs(surface.transform.b - 1.0) < 0.01 &&
        fabs(surface.transform.c + 1.0) < 0.01
      : CGAffineTransformIsIdentity(surface.transform);
  return sizeOK && rotationOK;
}

@end


static WyrmEngineContainerController* engine_container;
static bool shell_overlay;

/* The SwiftUI shell stays visible above the rotated engine while it draws the
   Ready Room (LOBBY) or the layout editor; its hosting view turns clear so the
   engine shows wherever SwiftUI paints nothing. Main thread only. */
static void apply_shell_visibility(void) {
  UIView* shell = engine_container.shellController.view;
  if (!shell) return;
  static UIColor* original_background;
  static bool captured;
  if (!captured) { original_background = shell.backgroundColor; captured = true; }
  bool overlay = engine_presentation && (reported_screen == LOBBY || shell_overlay);
  shell.hidden = engine_presentation && !overlay;
  shell.backgroundColor = overlay ? UIColor.clearColor : original_background;
}

void WyrmIOSSetShellOverlay(bool enabled) {
  dispatch_async(dispatch_get_main_queue(), ^{
    shell_overlay = enabled;
    apply_shell_visibility();
  });
}

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
  if (engine_presentation == enabled && engine_container &&
      engine_container.shellController) return;
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
    if (![window.rootViewController isKindOfClass:WyrmEngineContainerController.class]) {
      UIViewController* sdlController = window.rootViewController;
      engine_container = [[WyrmEngineContainerController alloc] init];
      [engine_container loadViewIfNeeded];
      window.rootViewController = engine_container;
      [engine_container installEngineController:sdlController];
    } else {
      engine_container = (WyrmEngineContainerController*)window.rootViewController;
    }
    [engine_container installShellControllerIfNeeded];
    [UIView performWithoutAnimation:^{
      engine_container.landscapePresentation = enabled;
      apply_shell_visibility();
    }];
    CGRect portrait = engine_container.view.bounds;
    CGFloat width = CGRectGetWidth(portrait);
    CGFloat height = CGRectGetHeight(portrait);
    SDL_Log("Wyrm iOS presentation=%s os=portrait container=stable-child logical=%.0fx%.0f rotation=%d geometry_ok=%d",
            enabled ? "rotated-landscape" : "portrait",
            enabled ? height : width, enabled ? width : height,
            enabled ? 90 : 0,
            engine_container.engineGeometryIsStable ? 1 : 0);
  });
}

static void log_engine_geometry(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!engine_container) {
      SDL_Log("Wyrm iOS persistent geometry: container=missing geometry_ok=0");
      return;
    }
    UIView* surface = engine_container.engineController.view;
    SDL_Log("Wyrm iOS persistent geometry: container=stable-child child_bounds=%.0fx%.0f geometry_ok=%d",
            CGRectGetWidth(surface.bounds), CGRectGetHeight(surface.bounds),
            engine_container.engineGeometryIsStable ? 1 : 0);
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
    int screen = reported_screen;
    dispatch_async(dispatch_get_main_queue(), ^{
      apply_shell_visibility();
      [NSNotificationCenter.defaultCenter postNotificationName:@"WyrmEngineScreenChanged"
                                                        object:nil
                                                      userInfo:@{@"screen": @(screen)}];
    });
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
    if (!canvas_proven && engine.usr->gdata.curr_screen == PLAYING &&
        width > height) {
      ImGuiIO* io = igGetIO_Nil();
      canvas_proven = true;
      SDL_Log("Wyrm iOS pixel canvas: imgui=%.0fx%.0f framebuffer=%.2fx%.2f drawable=%dx%d",
              io->DisplaySize.x, io->DisplaySize.y,
              io->DisplayFramebufferScale.x, io->DisplayFramebufferScale.y,
              width, height);
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
  if (engine.ctx->last_present_succeeded &&
      engine.usr->gdata.curr_screen == PLAYING) {
    gameplay_frames++;
    if (gameplay_frames % 120 == 0) {
      snake* own = get_snake(&engine.usr->gdata,
                             engine.usr->gdata.data.snake_id);
      SDL_Log("Wyrm arena frame progress=%u own=%d segments=%d fps=%d",
              gameplay_frames, own ? own->id : -1, own ? own->sct : 0,
              engine.usr->gdata.data.fps);
    }
    if (gameplay_frames % 600 == 0) log_engine_geometry();
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
    NSURL* diagnostics = [base URLByAppendingPathComponent:@"WyrmDiagnostics" isDirectory:YES];
    [files createDirectoryAtURL:diagnostics withIntermediateDirectories:YES attributes:nil error:nil];
    wyrm_engine_log_path = [diagnostics.path stringByAppendingPathComponent:@"engine.log"];
    SDL_SetLogOutputFunction(wyrm_log_output, NULL);
    NSURL* app = [base URLByAppendingPathComponent:@"OriginalEngine-27/app" isDirectory:YES];
    NSError* error = nil;
    if (![files createDirectoryAtURL:app withIntermediateDirectories:YES attributes:nil error:&error]) {
      NSLog(@"Wyrm storage failed: %@", error); return 1;
    }
    // Versioned immutable assets avoid reusing stale textures after an update.
    NSURL* working = [base URLByAppendingPathComponent:@"OriginalEngine-27" isDirectory:YES];
    NSURL* assets = [app URLByAppendingPathComponent:@"res" isDirectory:YES];
    NSURL* bundle = [NSBundle.mainBundle URLForResource:@"res" withExtension:nil];
    if (!bundle) { NSLog(@"Wyrm original assets missing"); return 1; }
    // The copy is made once per asset revision. Bump the revision whenever a
    // bundled engine asset changes (56: the Android Build-a-Slither cells in
    // the atlas); user.dat lives beside app/, not in it, and is kept.
    NSString* assetRevision = @"56-air-skin";
    NSURL* stamp = [assets URLByAppendingPathComponent:@".wyrm-assets"];
    NSString* installed = [NSString stringWithContentsOfURL:stamp encoding:NSUTF8StringEncoding error:nil];
    if ([files fileExistsAtPath:assets.path] && ![installed isEqualToString:assetRevision] &&
        ![files removeItemAtURL:assets error:&error]) {
      NSLog(@"Wyrm stale assets kept: %@", error);
    }
    if (![files fileExistsAtPath:assets.path]) {
      if (![files copyItemAtURL:bundle toURL:assets error:&error]) {
        NSLog(@"Wyrm asset preparation failed: %@", error); return 1;
      }
      [assetRevision writeToURL:stamp atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
    bool smoke_ai = false, smoke_lobby = false, smoke_online = false;
    for (int i = 1; i < argc; ++i) {
      if (!strcmp(argv[i], "--smoke-ai")) smoke_ai = true;
      if (!strcmp(argv[i], "--smoke-lobby")) smoke_lobby = true;
      if (!strcmp(argv[i], "--smoke-online")) smoke_online = true;
    }
    // The physical-device hang report showed UIKit's launch runloop spending
    // 552 ms in tinit -> renderer_create -> stbi_load/vkQueueSubmit. Install
    // the responsive SwiftUI shell first, then perform that immutable renderer
    // bootstrap away from UIKit's main runloop. The animation callback and all
    // later engine mutation remain on main after initialization completes.
    WyrmIOSSetEnginePresentation(false);
    SDL_Log("Wyrm engine bootstrap scheduled off main thread");
    // Register before returning from SDL's main callback. Frames are harmless
    // no-ops until `ready` flips on main, and UIKit gets its runloop back now.
    if (!SDL_SetiOSAnimationCallback(engine.wnd->handle, 1, frame, NULL)) {
      SDL_Log("Wyrm animation callback failed: %s", SDL_GetError());
      return 1;
    }
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      @autoreleasepool {
        tinit(&engine);
        CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - started;
        dispatch_async(dispatch_get_main_queue(), ^{
          ready = true;
          if (smoke_ai) WyrmIOSRequestPlay("Apple test", "", true);
          if (smoke_lobby) {
            WyrmIOSSetEnginePresentation(true);
            snprintf(engine.usr->usrs.nickname,
                     sizeof(engine.usr->usrs.nickname), "Apple test");
            engine.usr->gdata.curr_screen = LOBBY;
          }
          if (smoke_online)
            WyrmIOSRequestPlay("Apple test", engine.usr->usrs.ipv4, false);
          SDL_Log("Wyrm engine bootstrap completed off main thread in %.0f ms; Apple animation callback installed",
                  elapsed * 1000.0);
        });
      }
    });
    return 0;
  }
}

int main(int argc, char** argv) { return SDL_RunApp(argc, argv, engine_main, NULL); }
