#define SDL_MAIN_HANDLED 1
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <SDL3/SDL_system.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
#import <dispatch/dispatch.h>
#include <TargetConditionals.h>
#include <math.h>
#include <unistd.h>
#include "user.h"
#include "network/server.h"
#include "WyrmOriginalAdapter.h"
/* The theme's paper (OM, 2026-10-30): the orientation cover and the hosts
   behind a rotation show it instead of black, so a turn reads as one soft
   dissolve. SwiftUI sets it (WyrmIOSSetCoverPaper); main thread. */
static UIColor* wyrm_cover_paper;
static UIColor* wyrm_paper_colour(void) {
  return wyrm_cover_paper ?: [UIColor colorWithRed:0.957 green:0.949 blue:0.925 alpha:1];
}
static bool internal_rotation;
#import "WyrmOrientationHost.inc"
#include "WyrmViewportGeometry.h"

static tenv engine;
static bool ready;
static unsigned frame_count;
static bool online_proven;
static int reported_width;
static int reported_height;
static int reported_screen = -1;
static bool engine_presentation;
/* Account-linked native game orientation. Both modes use identity-transformed
   content; the app root always returns to portrait (WyrmIOSSetPortraitPlay). */
static bool portrait_play;
static bool leaderboard_proven;
static bool canvas_proven;
static unsigned gameplay_frames;
static NSString* wyrm_engine_log_path;

/*
 * The display at its fastest, always, as the reference client (OM,
 * 2026-10-18; Settings › Performance is gone). The engine is driven by SDL's
 * display link, which SDL 3.4 runs at the screen's maximumFramesPerSecond
 * divided by the interval. With CADisableMinimumFrameDurationOnPhone in
 * Info.plist that maximum is 120 on a ProMotion iPhone, so a match draws at
 * interval 1. Under the opaque SwiftUI pages (Home, not the Skin postcard)
 * the engine draws nothing (main.c's render gate), so the link drops to 30
 * there and only the mailboxes tick.
 */
static int frame_interval = 1;
static bool frame_idle;
static void apply_frame_interval(void);
static int display_max_fps(void);
extern bool ui_skin_editor_postcard(void);
/* game/oef.c (engine_frame_timing_2026_11_07.py): the display period seeds
   the game's display-locked frame time. */
extern void wyrm_frame_period_hint_ms(double ms);

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
@interface WyrmRainHost : NSObject
+ (UIViewController*)makeViewController;
+ (BOOL)handleKey:(NSString*)key;
+ (void)placePanelLeft:(double)left top:(double)top width:(double)width height:(double)height;
@end

// A stationary stage owns only touches that begin inside the panel. Empty
// space falls through to the engine; UIKit keeps a captured pan until release.
@interface WyrmRainStageView : UIView
@property(nonatomic, assign) CGRect panelRect;
@end
@implementation WyrmRainStageView
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
  if (self.hidden || !CGRectContainsPoint(self.panelRect, point)) return nil;
  return [super hitTest:point withEvent:event];
}
@end

// One persistent SDL/SwiftUI/Rain content controller. UIKit rotates the real
// full-screen game host; every child uses its actual untransformed bounds.
@interface WyrmEngineContainerController : UIViewController
@property(nonatomic, strong) UIViewController* engineController;
@property(nonatomic, strong) UIViewController* shellController;
@property(nonatomic, strong) UIViewController* rainController;
@property(nonatomic, strong) WyrmRainStageView* rainStage;
@property(nonatomic, assign) BOOL rainVisible;
@property(nonatomic, assign) BOOL rainExpanded;
@property(nonatomic, assign) CGPoint rainOrigin;
@property(nonatomic, assign) CGPoint rainOffset;
@property(nonatomic, assign) CGFloat keyboardBottomInset;
@property(nonatomic, assign) CGPoint rainOffsetBeforeKeyboard;
@property(nonatomic, assign) BOOL rainDraggedWithKeyboard;
- (void)installEngineController:(UIViewController*)controller;
- (void)installShellControllerIfNeeded;
- (BOOL)engineGeometryIsStable;
- (void)layoutRainPanel;
@end

@implementation WyrmEngineContainerController

- (void)loadView {
  self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.view.backgroundColor = wyrm_paper_colour(); /* never a black frame on a turn (2026-10-30) */
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
  UIViewController* rain = [WyrmRainHost makeViewController];
  self.rainController = rain;
  [self addChildViewController:rain];
  rain.view.backgroundColor = UIColor.clearColor;
  WyrmRainStageView* stage = [[WyrmRainStageView alloc] initWithFrame:self.view.bounds];
  self.rainStage = stage;
  stage.backgroundColor = UIColor.clearColor; stage.hidden = YES;
  rain.view.frame = stage.bounds;
  [stage addSubview:rain.view];
  [self.view addSubview:stage];
  [rain didMoveToParentViewController:self];
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
  return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscape;
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  UIView* surface = self.engineController.view;
  if (!surface) return;
  CGRect bounds = self.view.bounds;
  surface.transform = CGAffineTransformIdentity;
  surface.frame = bounds;
  self.shellController.view.frame = bounds;
  [self layoutRainPanel];
}

- (void)layoutRainPanel {
  WyrmRainStageView* rain = self.rainStage;
  if (!rain) return;
  CGRect bounds = self.view.bounds;
  CGFloat stageWidth = CGRectGetWidth(bounds);
  CGFloat stageHeight = CGRectGetHeight(bounds);
  UIEdgeInsets safe = self.view.safeAreaInsets;
  WyrmPanelGeometry panel = wyrm_panel_geometry(stageWidth, stageHeight,
      self.rainOrigin.x, self.rainOrigin.y, self.rainOffset.x, self.rainOffset.y,
      safe.left, safe.top, safe.right, MAX(safe.bottom, self.keyboardBottomInset));
  CGFloat width = panel.width, height = panel.height;
  CGFloat left = panel.left, top = panel.top;
  rain.clipsToBounds = NO; rain.layer.masksToBounds = NO;
  self.rainOffset = CGPointMake(panel.offset_x, panel.offset_y);
  // Never translate/resize the SwiftUI render root to the small panel's box:
  // its cached root clip otherwise remains at the old rectangle while dragging.
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  CGSize stageSize = CGSizeMake(stageWidth, stageHeight);
  if (!CGSizeEqualToSize(rain.bounds.size, stageSize)) rain.bounds = (CGRect){CGPointZero, stageSize};
  CGPoint centre = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
  if (!CGPointEqualToPoint(rain.center, centre)) rain.center = centre;
  CGAffineTransform turn = CGAffineTransformIdentity;
  if (!CGAffineTransformEqualToTransform(rain.transform, turn)) rain.transform = turn;
  UIView* content = self.rainController.view;
  if (!CGSizeEqualToSize(content.bounds.size, stageSize)) content.bounds = (CGRect){CGPointZero, stageSize};
  // Full-stage content host: changing only layer position during a pan cannot
  // re-layout SwiftUI or restart its recognizer. Its panel stays at local zero.
  content.center = CGPointMake(left + stageWidth / 2, top + stageHeight / 2);
  rain.panelRect = CGRectMake(left, top, width, height);
  [WyrmRainHost placePanelLeft:0 top:0 width:width height:height];
  [CATransaction commit];
  rain.hidden = !self.rainVisible || !self.rainExpanded || !engine_presentation || reported_screen != PLAYING;
  [self.view bringSubviewToFront:rain];
  UIView* cover = [self.view viewWithTag:WYRM_ORIENTATION_COVER_TAG];
  if (cover.superview == self.view) [self.view bringSubviewToFront:cover];
}

- (void)pressesBegan:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event {
  NSMutableSet<UIPress*>* remaining = [NSMutableSet setWithSet:presses];
  if (engine_presentation && reported_screen == PLAYING) for (UIPress* press in presses) {
    UIKey* key = press.key;
    NSString* name = key.charactersIgnoringModifiers;
    if (key.keyCode >= UIKeyboardHIDUsageKeyboardF1 && key.keyCode <= UIKeyboardHIDUsageKeyboardF12)
      name = [NSString stringWithFormat:@"F%ld", (long)(key.keyCode-UIKeyboardHIDUsageKeyboardF1+1)];
    if (name.length && [WyrmRainHost handleKey:name]) [remaining removeObject:press];
  }
  if (remaining.count) [super pressesBegan:remaining withEvent:event];
}

- (BOOL)engineGeometryIsStable {
  UIView* surface = self.engineController.view;
  if (!surface) return NO;
  CGSize expected = self.view.bounds.size;
  const CGFloat epsilon = 0.5;
  BOOL sizeOK = fabs(CGRectGetWidth(surface.bounds) - expected.width) < epsilon &&
                fabs(CGRectGetHeight(surface.bounds) - expected.height) < epsilon;
  return sizeOK && CGAffineTransformIsIdentity(surface.transform);

}

@end


static WyrmEngineContainerController* engine_container;
static WyrmOrientationCoordinator* orientation_coordinator;
static bool shell_overlay;

// Separate small hosting view: the rest of the screen still belongs to SDL.
// In sideways play, coordinates and bounds are in the engine's logical stage.
void WyrmIOSSetRainPanel(bool visible, bool expanded, double x, double y) {
  dispatch_async(dispatch_get_main_queue(), ^{
    engine_container.rainVisible = visible; engine_container.rainExpanded = expanded;
    engine_container.rainOrigin = CGPointMake(isfinite(x) ? x:380,isfinite(y) ? y:340);
    [engine_container layoutRainPanel];
  });
}

// Native keyboard overlap is transient and never written to account defaults.
void WyrmIOSSetKeyboardOcclusion(double bottom) {
  dispatch_async(dispatch_get_main_queue(), ^{
    WyrmEngineContainerController* c = engine_container;
    if (!c) return;
    CGFloat next = isfinite(bottom) ? MAX(0, bottom) : 0;
    if (next > 0 && c.keyboardBottomInset == 0) {
      c.rainOffsetBeforeKeyboard = c.rainOffset;
      c.rainDraggedWithKeyboard = NO;
    } else if (next == 0 && c.keyboardBottomInset > 0 && !c.rainDraggedWithKeyboard) {
      c.rainOffset = c.rainOffsetBeforeKeyboard;
    }
    c.keyboardBottomInset = next;
    [c layoutRainPanel];
  });
}

// The panel's knob moved the finger by (dx, dy) stage points from where it grabbed.
// Main thread (the gesture's own), so the next touch already sees the new place.
void WyrmIOSMoveRainPanel(double dx, double dy) {
  void (^move)(void) = ^{
    if (!engine_container || !isfinite(dx) || !isfinite(dy)) return;
    if (engine_container.keyboardBottomInset > 0) engine_container.rainDraggedWithKeyboard = YES;
    CGPoint o = engine_container.rainOffset;
    // Native landscape: window, stage and drag deltas share the same axes.
    CGFloat stageDX = dx;
    CGFloat stageDY = dy;
    engine_container.rainOffset = CGPointMake(o.x + stageDX, o.y + stageDY);
    [engine_container layoutRainPanel];
  };
  if (NSThread.isMainThread) move(); else dispatch_async(dispatch_get_main_queue(), move);
}

// CI-only runtime regression: exercise the actual native layout across 100
// displayed positions, including repeated engine layout calls between moves.
static void smoke_rain_drag(void) {
  if (![NSProcessInfo.processInfo.arguments containsObject:@"--smoke-rain-drag"]) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    WyrmEngineContainerController* c = engine_container;
    c.rainVisible = YES; c.rainExpanded = YES;
    c.rainOrigin = CGPointMake(428 * 0.7, 388 * 0.7);
    [c layoutRainPanel];
    CGRect stage = c.rainStage.bounds;
    CGPoint centre = c.rainStage.center;
    CGAffineTransform turn = c.rainStage.transform;
    __block int moves = 0;
    [NSTimer scheduledTimerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer* timer) {
      // Test reachable positions. The real layout clamps to the safe area;
      // a destination inside the landscape notch was never a valid drag.
      UIEdgeInsets safe = c.view.safeAreaInsets;
      CGFloat minX = safe.left, minY = safe.top;
      CGFloat maxX = CGRectGetWidth(stage) - safe.right - c.rainStage.panelRect.size.width;
      CGFloat maxY = CGRectGetHeight(stage) - MAX(safe.bottom, c.keyboardBottomInset) - c.rainStage.panelRect.size.height;
      CGFloat x = minX + MAX(0, maxX-minX) * (0.05 + 0.9 * (moves + 1) / 100.0);
      CGFloat y = minY + MAX(0, maxY-minY) * (0.1 + 0.8 * (moves + 1) / 100.0);
      CGFloat dx = x - c.rainStage.panelRect.origin.x;
      CGFloat dy = y - c.rainStage.panelRect.origin.y;
      WyrmIOSMoveRainPanel(dx, dy);
      [c layoutRainPanel]; [c layoutRainPanel];
      BOOL ok = CGRectEqualToRect(stage, c.rainStage.bounds) && CGPointEqualToPoint(centre, c.rainStage.center) &&
          CGAffineTransformEqualToTransform(turn, c.rainStage.transform) &&
          fabs(c.rainStage.panelRect.origin.x - x) < 0.01 && fabs(c.rainStage.panelRect.origin.y - y) < 0.01;
      if (!ok) {
        NSLog(@"Rain drag geometry FAIL move=%d target=(%.3f,%.3f) actual=%@ stage=%@ original=%@ safe=%@",
              moves, x, y, NSStringFromCGRect(c.rainStage.panelRect),
              NSStringFromCGRect(c.rainStage.bounds), NSStringFromCGRect(stage), NSStringFromUIEdgeInsets(safe));
        [timer invalidate]; return;
      }
      if (++moves == 100) {
        NSLog(@"Rain drag geometry passed moves=100 stable_stage=1 position_held=1");
        [timer invalidate];
      }
    }];
  });
}

/* Future Apple CI runtime probe: use the real lobby/Home mailbox and UIKit
   scene geometry, not the physical screenshot buffer's orientation metadata. */
static void smoke_native_orientation_cycle(void) {
  if (![NSProcessInfo.processInfo.arguments containsObject:@"--smoke-native-orientation-cycle"]) return;
  __block unsigned ticks = 0;
  __block BOOL saw_landscape = NO;
  __block UIViewController* expected_engine = nil;
  __block UIViewController* expected_shell = nil;
  SDL_Window* expected_window = engine.wnd->handle;
  [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer* timer) {
    if (++ticks > 160) {
      SDL_Log("Native orientation cycle FAILED timeout landscape=%d", saw_landscape);
      [timer invalidate]; return;
    }
    if (!orientation_coordinator || orientation_coordinator.transitioning) return;
    UIWindowScene* scene = orientation_coordinator.window.windowScene;
    CGSize size = engine_container.view.bounds.size;
    if (!saw_landscape && orientation_coordinator.current == 2 &&
        UIInterfaceOrientationIsLandscape(scene.interfaceOrientation) && size.width > size.height &&
        reported_screen == LOBBY && engine_container.engineGeometryIsStable) {
      saw_landscape = YES;
      expected_engine = engine_container.engineController;
      expected_shell = engine_container.shellController;
      WyrmIOSLobbyHome();
    } else if (saw_landscape && orientation_coordinator.current == 0 &&
               scene.interfaceOrientation == UIInterfaceOrientationPortrait && size.height > size.width &&
               reported_screen == TITLE_SCREEN && engine_container.engineGeometryIsStable) {
      BOOL preserved = expected_engine == engine_container.engineController &&
                       expected_shell == engine_container.shellController && expected_window == engine.wnd->handle;
      SDL_Log("Native orientation cycle %s preserved_engine_shell_window=%d landscape=1 portrait=1",
              preserved ? "passed" : "FAILED", preserved);
      [timer invalidate];
    }
  }];
}

/* The SwiftUI shell stays visible above the native engine while it draws the
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

/* Existing account-linked Play orientation selects native game orientation.
   Home always stays portrait. Applies to the same persistent content/engine. */
void WyrmIOSSetCoverPaper(double r, double g, double b) {
  void (^apply)(void) = ^{ wyrm_cover_paper = [UIColor colorWithRed:r green:g blue:b alpha:1]; };
  if (NSThread.isMainThread) apply(); else dispatch_async(dispatch_get_main_queue(), apply);
}

void WyrmIOSHoldOrientationCover(bool engine_visible) {
  void (^raise)(void) = ^{ [orientation_coordinator raiseCoverExpectingEngine:engine_visible]; };
  if (NSThread.isMainThread) raise(); else dispatch_async(dispatch_get_main_queue(), raise);
}

bool WyrmIOSInternalRotationActive(void) {
  // A system modal above the game owns a genuine portrait keyboard.
  return internal_rotation && engine_presentation && !portrait_play &&
      !orientation_coordinator.game.presentedViewController;
}
void WyrmIOSSetInternalRotation(bool internal) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (internal_rotation == internal) return;
    [engine_container.view endEditing:YES];
    internal_rotation = internal;
    [orientation_coordinator rearmGeometryObservation];
    [orientation_coordinator.game.view setNeedsLayout];
    [orientation_coordinator refreshGeometry];
  });
}

void WyrmIOSSetPortraitPlay(bool portrait) {
  dispatch_async(dispatch_get_main_queue(), ^{
    portrait_play = portrait;
    if (!engine_container) return;
    [orientation_coordinator setEngineVisible:engine_presentation portrait:portrait_play];
    apply_shell_visibility();
  });
}

/* The shell over a match (the arena composer, the layout editor) comes and
   goes with a short fade (OM, 2026-10-09: the lobby flickered when the arena
   chat opened and again after Send). Un-hidden, SwiftUI's first frame can be
   the last one it drew before the match (the Ready Room), so the view starts
   invisible and fades in after two frames; going away it fades out before it
   is hidden. A later call wins over a fade still running. Over the Ready Room
   (LOBBY) the shell is needed anyway and changes at once. */
static unsigned shell_overlay_generation;

void WyrmIOSSetShellOverlay(bool enabled) {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIView* shell = engine_container.shellController.view;
    unsigned generation = ++shell_overlay_generation;
    if (!shell || !engine_presentation || reported_screen == LOBBY) {
      shell_overlay = enabled;
      apply_shell_visibility();
      if (shell) shell.alpha = 1;
      return;
    }
    if (enabled) {
      bool was_hidden = shell.hidden;
      shell_overlay = true;
      apply_shell_visibility();
      if (was_hidden) {
        shell.alpha = 0;
        [UIView animateWithDuration:0.12 delay:0.05
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{ shell.alpha = 1; } completion:nil];
      } else {
        shell.alpha = 1;
      }
      return;
    }
    if (!shell_overlay) return;
    [UIView animateWithDuration:0.1 delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ shell.alpha = 0; }
                     completion:^(BOOL finished) {
      (void)finished;
      if (generation != shell_overlay_generation) return;
      shell_overlay = false;
      apply_shell_visibility();
      shell.alpha = 1;
    }];
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
  // Last main-thread intent wins; do not let queued stale Play/Back events
  // short-circuit one another against a prematurely updated global flag.
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow* window = orientation_coordinator.window;
    UIWindow* connected_window = nil;
    if (!window) for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
      if (![scene isKindOfClass:UIWindowScene.class] ||
          scene.activationState == UISceneActivationStateUnattached) continue;
      for (UIWindow* candidate in ((UIWindowScene*)scene).windows) {
        if (!connected_window && candidate.rootViewController && candidate.windowLevel == UIWindowLevelNormal)
          connected_window = candidate;
        if (candidate.isKeyWindow) { window = candidate; break; }
      }
      if (window) break;
    }
    if (!window) window = connected_window;
    if (!window || !window.rootViewController) {
      NSLog(@"Wyrm presentation deferred: no connected key window"); return;
    }
    if (!orientation_coordinator) {
      UIViewController* sdlController = window.rootViewController;
      engine_container = [[WyrmEngineContainerController alloc] init];
      orientation_coordinator = [[WyrmOrientationCoordinator alloc] initWithWindow:window content:engine_container];
      orientation_coordinator.coverSettled = ^BOOL(BOOL engineVisible) {
        if (!engine_container.engineGeometryIsStable) return NO;
        bool home = reported_screen == TITLE_SCREEN || reported_screen == SKIN_EDITOR;
        return engineVisible ? (reported_screen >= 0 && !home) : home;
      };
      [engine_container installEngineController:sdlController];
      [engine_container installShellControllerIfNeeded];
    }
    BOOL changed = engine_presentation != enabled;
    engine_presentation = enabled;
    [orientation_coordinator setEngineVisible:enabled portrait:portrait_play];
    apply_shell_visibility();
    if (changed) SDL_Log("Wyrm iOS native presentation=%s container=persistent rotation=0 geometry_ok=%d",
        enabled ? (portrait_play ? "game-portrait" : "game-landscape") : "home-portrait",
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

static void publish_arena_port_availability(void) {
  static int reported_arena_port_available = -1;
  game_data* gdata = &engine.usr->gdata;
  int arena_port_available = gdata->curr_screen != PLAYING &&
      gdata->conn == DISCONNECTED && !gdata->connection;
  if (reported_arena_port_available != arena_port_available) {
    reported_arena_port_available = arena_port_available;
    BOOL available = arena_port_available != 0;
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSNotificationCenter.defaultCenter postNotificationName:@"WyrmEngineArenaPortAvailable"
                                                    object:nil
                                                  userInfo:@{@"available": @(available)}];
    });
  }
}

/* VK_ERROR_DEVICE_LOST was seen (tcontext_device_lost, 2026-10-06): the
   engine draws nothing more this run, and the shell asks the player to
   reopen Wyrm instead of leaving a frozen screen. Main thread. */
bool WyrmIOSGraphicsLost(void) {
  return ready && engine.ctx && engine.ctx->device_lost;
}

/* SDL 3 adds its CADisplayLink to NSDefaultRunLoopMode only. While a SwiftUI
   ScrollView scrolls, a slider drags or any UIKit gesture tracks (the Snakey
   Rain panel above the arena), the main run loop is in UITrackingRunLoopMode,
   the link does not fire and the whole game stood still until the finger
   lifted (OM, 2026-10-14; Android runs the engine on its own thread and never
   had this). The link is added to the common modes too, which include the
   tracking mode. SDL makes a new link whenever the frame interval changes or
   the app returns, so the current one is checked again every 30 frames.

   It is added every time (OM, 2026-10-18: the Rain panel still froze the
   match). The old check skipped a link whose address equalled the last one,
   but SDL frees the old link and the new one is often allocated at the same
   address, so the match's new link (interval 2 -> 1 on entering the arena)
   stayed in the default mode only. Adding a link to a mode it is already in
   changes nothing; the address is kept only to log a new link once. */
static const void* common_mode_link;
static void keep_frames_while_tracking(void) {
  UIViewController* sdl = engine_container.engineController;
  if (!sdl) return;
  id link = nil;
  @try {
    link = [sdl valueForKey:@"displayLink"];
  } @catch (NSException* error) {
    return;
  }
  if (![link isKindOfClass:CADisplayLink.class]) return;
  [(CADisplayLink*)link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
  /* SDL 3.4 sets only the old preferredFramesPerSecond. From iOS 15 Apple's
     API for ProMotion is preferredFrameRateRange (OM, 2026-11-07, official
     docs): a fixed range at the rate we draw at, so the system does not
     vary the rate under a match. The idle 30 Hz pass gets its own range. */
  if (@available(iOS 15.0, *)) {
    float fps = (float)display_max_fps() / (float)(frame_interval > 0 ? frame_interval : 1);
    CAFrameRateRange range = CAFrameRateRangeMake(fps, fps, fps);
    CADisplayLink* display = (CADisplayLink*)link;
    if (!CAFrameRateRangeIsEqualToRange(display.preferredFrameRateRange, range))
      display.preferredFrameRateRange = range;
  }
  if ((__bridge const void*)link == common_mode_link) return;
  common_mode_link = (__bridge const void*)link;
  SDL_Log("Wyrm frames: display link also runs while UIKit tracks touches");
}

static void frame(void* unused) {
  (void)unused;
  static unsigned frames_since_link_check;
  if (frames_since_link_check++ % 30 == 0) keep_frames_while_tracking();
  if (!ready) return;
  twindow_poll_input(engine.wnd);
  if (!wyrm_background()) tinput(&engine);
  /* A failed join can enter and leave PLAYING in one render call. Publish
   * both edges so the Swift gate still observes this attempt's busy state. */
  publish_arena_port_availability();
  /* Background play (OM, 2026-10-13): not active, the match keeps running
     and nothing is drawn; GPU work sent from the background is what made
     the device "lost" after coming back. */
  if (wyrm_background_tick(&engine)) {
  } else if (engine.ctx->swapchain_ok) trender(&engine);
  else if (engine.usr->gdata.connection) server_poll(&engine);
  bool idle = engine.usr->gdata.curr_screen == TITLE_SCREEN &&
              !ui_skin_editor_postcard();
  if (idle != frame_idle) {
    frame_idle = idle;
    /* After this callback returns: the change replaces the display link. */
    dispatch_async(dispatch_get_main_queue(), ^{ apply_frame_interval(); });
  }
  publish_arena_port_availability();
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
    if (gameplay_frames == 120) smoke_rain_drag();
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

/* Background play (OM, 2026-10-13). The display link stops in the
   background, so a 30 Hz timer on the main queue keeps the frames coming
   (the app is kept awake by WyrmBackgroundPlay.swift's silent audio). Not
   active (a call, Control Centre, the app switcher) nothing is drawn. */
static dispatch_source_t background_timer;

static void start_background_timer(void) {
  if (background_timer) return;
  background_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                            dispatch_get_main_queue());
  dispatch_source_set_timer(background_timer, dispatch_time(DISPATCH_TIME_NOW, 0),
                            NSEC_PER_SEC / 30, NSEC_PER_MSEC * 5);
  dispatch_source_set_event_handler(background_timer, ^{ frame(NULL); });
  dispatch_resume(background_timer);
  SDL_Log("Wyrm background: timer on");
}

static void stop_background_timer(void) {
  if (!background_timer) return;
  dispatch_source_cancel(background_timer);
  background_timer = nil;
  SDL_Log("Wyrm background: timer off");
}

static void install_background_play(void) {
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  NSOperationQueue* main = NSOperationQueue.mainQueue;
  [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:main
                  usingBlock:^(NSNotification* note) { (void)note; wyrm_set_background(true); }];
  [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:main
                  usingBlock:^(NSNotification* note) {
                    (void)note;
                    wyrm_set_background(true);
                    start_background_timer();
                  }];
  [center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:main
                  usingBlock:^(NSNotification* note) { (void)note; stop_background_timer(); }];
  [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:main
                  usingBlock:^(NSNotification* note) {
                    (void)note;
                    stop_background_timer();
                    wyrm_set_background(false);
                  }];
}

static int display_max_fps(void) {
  NSInteger max = UIScreen.mainScreen.maximumFramesPerSecond;
  return max > 0 ? (int)max : 60;
}

/* Main thread. */
static void apply_frame_interval(void) {
  if (!engine.wnd) return;
  int max = display_max_fps();
  int target = frame_idle ? 30 : max;
  if (target > max) target = max;
  if (target < 1) target = 1;
  int interval = (int)lround((double)max / (double)target);
  if (interval < 1) interval = 1;
  if (interval == frame_interval) return;
  frame_interval = interval;
  if (!SDL_SetiOSAnimationCallback(engine.wnd->handle, interval, frame, NULL)) {
    SDL_Log("Wyrm performance: interval %d refused: %s", interval, SDL_GetError());
    return;
  }
  keep_frames_while_tracking();
  wyrm_frame_period_hint_ms(1000.0 * (double)interval / (double)max);
  SDL_Log("Wyrm performance: display %d Hz, %s, interval %d = %d FPS", max,
          frame_idle ? "idle under SwiftUI" : "drawing", interval, max / interval);
}

int WyrmIOSDisplayMaxFPS(void) { return display_max_fps(); }

/*
 * Arena text fallbacks (OM, 2026-11-07; engine_arena_fonts_2026_11_07.py).
 * The engine draws its text in Manrope with Liberation Sans behind it; names
 * and messages in other scripts need the system's own fonts. CoreText names
 * each one's file; a font CoreText had to substitute (not on this iOS) or a
 * file the app may not read is left out. For a .ttc the face is found by its
 * PostScript name. Engine thread (imgui_init), once.
 */
static uint32_t wyrm_font_be32(const unsigned char* p) {
  return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

static bool wyrm_font_face_named(NSData* data, uint32_t face, NSString* want) {
  const unsigned char* d = data.bytes;
  NSUInteger size = data.length;
  if ((NSUInteger)face + 12 > size) return false;
  unsigned tables = (unsigned)d[face + 4] << 8 | d[face + 5];
  for (unsigned i = 0; i < tables; ++i) {
    NSUInteger at = (NSUInteger)face + 12 + 16 * i;
    if (at + 16 > size) return false;
    if (memcmp(d + at, "name", 4) != 0) continue;
    NSUInteger off = wyrm_font_be32(d + at + 8);
    if (off + 6 > size) return false;
    unsigned count = (unsigned)d[off + 2] << 8 | d[off + 3];
    NSUInteger strings = off + ((unsigned)d[off + 4] << 8 | d[off + 5]);
    for (unsigned r = 0; r < count; ++r) {
      NSUInteger rec = off + 6 + 12 * r;
      if (rec + 12 > size) return false;
      unsigned platform = (unsigned)d[rec] << 8 | d[rec + 1];
      unsigned name_id = (unsigned)d[rec + 6] << 8 | d[rec + 7];
      unsigned length = (unsigned)d[rec + 8] << 8 | d[rec + 9];
      NSUInteger start = strings + ((unsigned)d[rec + 10] << 8 | d[rec + 11]);
      if (name_id != 6 || start + length > size) continue;
      NSString* text = nil;
      if (platform == 3 || platform == 0)
        text = [[NSString alloc] initWithBytes:d + start length:length
                                      encoding:NSUTF16BigEndianStringEncoding];
      else if (platform == 1)
        text = [[NSString alloc] initWithBytes:d + start length:length
                                      encoding:NSMacOSRomanStringEncoding];
      if ([text isEqualToString:want]) return true;
    }
    return false;
  }
  return false;
}

static int wyrm_font_ttc_index(NSString* path, NSString* postscript) {
  NSData* data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
  if (data.length < 16 || memcmp(data.bytes, "ttcf", 4) != 0) return data.length ? 0 : -1;
  const unsigned char* d = data.bytes;
  uint32_t faces = wyrm_font_be32(d + 8);
  if (faces > 64 || 12 + 4 * (NSUInteger)faces > data.length) return -1;
  for (uint32_t i = 0; i < faces; ++i)
    if (wyrm_font_face_named(data, wyrm_font_be32(d + 12 + 4 * i), postscript)) return (int)i;
  return -1;
}

int wyrm_ios_fallback_fonts(char (*paths)[1024], int* indices, int max) {
  /* One per script, in the engine's order (Indic, Arabic, Thai, Hebrew,
     Chinese/Japanese, Korean, symbols, maths letters). */
  static NSString* const wanted[] = {
      @"KohinoorDevanagari-Regular", @"KohinoorBangla-Regular",
      @"GurmukhiMN", @"KohinoorGujarati-Regular", @"TamilSangamMN",
      @"KohinoorTelugu-Regular", @"KannadaSangamMN", @"MalayalamSangamMN",
      @"OriyaSangamMN", @"GeezaPro", @"Thonburi", @"ArialHebrew",
      // PingFang and Apple SD Gothic Neo are tens of MB each: left out
      // (2026-11-07, the build 155 Simulator failure); Hiragino carries kanji/kana.
      @"HiraginoSans-W3", @"AppleSymbols", @"STIXTwoMath-Regular"};
  int found = 0;
  @autoreleasepool {
    for (size_t i = 0; i < sizeof(wanted) / sizeof(wanted[0]) && found < max; ++i) {
      CTFontRef font = CTFontCreateWithName((__bridge CFStringRef)wanted[i], 16.0, NULL);
      if (!font) continue;
      NSString* postscript = CFBridgingRelease(CTFontCopyPostScriptName(font));
      NSURL* url = CFBridgingRelease(CTFontCopyAttribute(font, kCTFontURLAttribute));
      CFRelease(font);
      if (![postscript isEqualToString:wanted[i]] || !url.isFileURL) continue;
      NSString* path = url.path;
      if (path.length == 0 || path.length >= 1024 ||
          access(path.fileSystemRepresentation, R_OK) != 0) continue;
      int index = wyrm_font_ttc_index(path, postscript);
      if (index < 0) continue;
      bool seen = false;
      for (int j = 0; j < found; ++j)
        if (indices[j] == index && strcmp(paths[j], path.fileSystemRepresentation) == 0) seen = true;
      if (seen) continue;
      strlcpy(paths[found], path.fileSystemRepresentation, 1024);
      indices[found] = index;
      ++found;
    }
  }
  SDL_Log("Wyrm arena text: %d iOS script fonts", found);
  return found;
}

static int engine_main(int argc, char** argv) {
  @autoreleasepool {
#if TARGET_OS_SIMULATOR
    // SimMetalHost aborts while encoding the original ImGui texture descriptors.
    // Keep Vulkan bindings unchanged; use MoltenVK's direct-resource path here.
    setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "0", 1);
    // The Simulator can report zero-sized Metal placement-heap buffer
    // requirements. Use MoltenVK's ordinary-buffer path on this platform.
    setenv("MVK_CONFIG_USE_MTLHEAP", "0", 1);
    SDL_Log("Wyrm Simulator compatibility: Metal placement heaps disabled");
#endif
    NSFileManager* files = NSFileManager.defaultManager;
    NSURL* base = [files URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL* diagnostics = [base URLByAppendingPathComponent:@"WyrmDiagnostics" isDirectory:YES];
    [files createDirectoryAtURL:diagnostics withIntermediateDirectories:YES attributes:nil error:nil];
    wyrm_engine_log_path = [diagnostics.path stringByAppendingPathComponent:@"engine.log"];
    /* The last launch's engine log, kept before this launch writes a line, for
       a crash report (2026-10-09: an iPhone XR report carried only the
       relaunch's startup lines, which crowded the crash out of the tail). */
    NSString* previous_engine_log = [diagnostics.path stringByAppendingPathComponent:@"engine.previous.log"];
    [files removeItemAtPath:previous_engine_log error:nil];
    if ([files fileExistsAtPath:wyrm_engine_log_path])
      [files copyItemAtPath:wyrm_engine_log_path toPath:previous_engine_log error:nil];
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
    // The copy is made once per build: the revision is the app's build number,
    // so a changed atlas can never be left stale (it was, from 56 until 74:
    // the Wyrm bead cells were missing and bead snakes drew blank). user.dat
    // lives beside app/, not in it, and is kept.
    NSString* build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"0";
    NSString* assetRevision = [NSString stringWithFormat:@"build-%@", build];
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
    // Permit native UIKit orientation. Portrait root / full-screen game hosts
    // enforce the current screen policy; SDL gets actual window pixel sizes.
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "Portrait LandscapeLeft LandscapeRight");
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
    bool smoke_ai = false, smoke_lobby = false, smoke_online = false, smoke_original_art = false;
    for (int i = 1; i < argc; ++i) {
      if (!strcmp(argv[i], "--smoke-ai")) smoke_ai = true;
      if (!strcmp(argv[i], "--smoke-original-art")) smoke_original_art = true;
      if (!strcmp(argv[i], "--smoke-lobby") || !strcmp(argv[i], "--smoke-native-orientation-cycle")) smoke_lobby = true;
      if (!strcmp(argv[i], "--smoke-online")) smoke_online = true;
    }
    // The physical-device hang report showed UIKit's launch runloop spending
    // 552 ms in tinit -> renderer_create -> stbi_load/vkQueueSubmit. Install
    // the responsive SwiftUI shell first, then perform that immutable renderer
    // bootstrap away from UIKit's main runloop. The animation callback and all
    // later engine mutation remain on main after initialization completes.
    WyrmIOSSetEnginePresentation(false);
    install_background_play();
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
        /* Log here, on the worker, before hopping back to main. The Simulator
           smoke test reads this line after a fixed wait, and the main queue can
           still be inside the first SwiftUI layout. */
        SDL_Log("Wyrm engine bootstrap completed off main thread in %.0f ms; Apple animation callback installed",
                elapsed * 1000.0);
        dispatch_async(dispatch_get_main_queue(), ^{
          ready = true;
          if (smoke_original_art) {
            WyrmIOSSetNearOriginal(true,0);
            engine.usr->usrs.ext.food_tex[0]=engine.usr->usrs.ext.food_tex[1]=1;
            engine.usr->usrs.hotkeys[HOTKEY_SHOW_NAMES].active=true;
            engine.usr->usrs.show_own_name=true;
            SDL_Log("Wyrm smoke original art enabled baked_glyphs=570 baked_food=11");
          }
          if (smoke_ai) WyrmIOSRequestPlay("Apple test", "", true);
          if (smoke_lobby) {
            WyrmIOSSetEnginePresentation(true);
            snprintf(engine.usr->usrs.nickname,
                     sizeof(engine.usr->usrs.nickname), "Apple test");
            engine.usr->gdata.curr_screen = LOBBY;
          }
          if (smoke_online)
            WyrmIOSRequestPlay("Apple test", engine.usr->usrs.ipv4, false);
          smoke_native_orientation_cycle();
        });
      }
    });
    return 0;
  }
}

int main(int argc, char** argv) {
#if TARGET_OS_SIMULATOR
  // Test-only, before any Swift store reads defaults; normal runs never write it.
  BOOL internalSmoke=NO, nativeSmoke=NO;
  for(int i=1;i<argc;++i) {
    if(!strcmp(argv[i],"--smoke-internal-rotation")) internalSmoke=YES;
    if(!strcmp(argv[i],"--smoke-lobby") || !strcmp(argv[i],"--smoke-native-orientation-cycle")) nativeSmoke=YES;
  }
  if(internalSmoke || nativeSmoke) {
    [NSUserDefaults.standardUserDefaults setBool:internalSmoke forKey:@"wyrm.ios.orientation.internal"];
    /* Internal rotation is a Developer Mode option (2026-11-01): the smoke turns it on with it. */
    [NSUserDefaults.standardUserDefaults setBool:internalSmoke forKey:@"wyrm.ios.developer-mode"];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"wyrm.ios.orientation.portrait"];
  }
#endif
  return SDL_RunApp(argc, argv, engine_main, NULL);
}
