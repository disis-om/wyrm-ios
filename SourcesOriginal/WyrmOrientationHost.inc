/* UIKit owns orientation. One persistent SDL/SwiftUI/Rain content controller
   moves between a portrait root and a real full-screen game presentation.
   Full-screen preferred orientation also supports iOS 15 without UIDevice KVC.
   Included by Main.m; every entry and completion runs on the main thread. */
#include "WyrmOrientationPolicy.h"
/* The orientation cover's view tag: the container keeps it above Rain and the shell. */
#define WYRM_ORIENTATION_COVER_TAG 0x57594F52
/* Which way sideways the player holds the phone (OM, 2026-11-01): +1 home
   button / flat side right (interface LandscapeRight), -1 the other way. The
   game enters on that side, and internal rotation turns its content that way. */
static int internal_turn = 1;
static void wyrm_note_device_side(void) {
  UIDeviceOrientation device = UIDevice.currentDevice.orientation;
  if (device == UIDeviceOrientationLandscapeLeft) internal_turn = 1;
  else if (device == UIDeviceOrientationLandscapeRight) internal_turn = -1;
}
static UIInterfaceOrientation wyrm_held_landscape(void) {
  return internal_turn < 0 ? UIInterfaceOrientationLandscapeLeft : UIInterfaceOrientationLandscapeRight;
}
@interface WyrmOrientationHostController : UIViewController
@property(nonatomic, assign) BOOL landscape;
@property(nonatomic, copy) void (^becameVisible)(void);
- (void)adoptContent:(UIViewController*)content;
- (void)layoutContent:(UIViewController*)content;
@end

@implementation WyrmOrientationHostController
- (void)loadView {
  self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
  /* Paper, not black: the corners a rotation uncovers match the app. */
  self.view.backgroundColor = wyrm_paper_colour();
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  return self.landscape && !internal_rotation ? UIInterfaceOrientationMaskLandscape : UIInterfaceOrientationMaskPortrait;
}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
  return self.landscape && !internal_rotation ? wyrm_held_landscape() : UIInterfaceOrientationPortrait;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (void)adoptContent:(UIViewController*)content {
  if (content.parentViewController == self) return;
  if (content.parentViewController) [content willMoveToParentViewController:nil];
  [content.view removeFromSuperview];
  [content removeFromParentViewController];
  [self addChildViewController:content];
  content.view.transform = CGAffineTransformIdentity;
  content.view.frame = self.view.bounds;
  [self layoutContent:content];
  content.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:content.view];
  [content didMoveToParentViewController:self];
  [content.view setNeedsLayout];
}
- (void)layoutContent:(UIViewController*)child {
  CGRect bounds = self.view.bounds;
  BOOL turn = self.landscape && internal_rotation;
  child.view.transform = CGAffineTransformIdentity;
  child.view.bounds = turn ? CGRectMake(0,0,bounds.size.height,bounds.size.width) : bounds;
  child.view.center = CGPointMake(CGRectGetMidX(bounds),CGRectGetMidY(bounds));
  if (turn) {
    child.view.transform = CGAffineTransformMakeRotation((CGFloat)(internal_turn * M_PI_2));
    if (self.view.bounds.size.height > self.view.bounds.size.width && child.view.bounds.size.width > child.view.bounds.size.height)
      NSLog(@"Wyrm internal rotation portrait_window=1 landscape_content=1");
  }
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  for (UIViewController* child in self.childViewControllers) [self layoutContent:child];
}
- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if (self.becameVisible) self.becameVisible();
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
  [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
  [self.view endEditing:YES];
  self.view.userInteractionEnabled = NO;
  [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    (void)context; self.view.userInteractionEnabled = YES; [self.view setNeedsLayout];
    if (self.becameVisible) self.becameVisible();
  }];
}
@end

@interface WyrmOrientationCoordinator : NSObject
@property(nonatomic, weak) UIWindow* window;
@property(nonatomic, strong) UIViewController* content;
@property(nonatomic, strong) WyrmOrientationHostController* home;
@property(nonatomic, strong) WyrmOrientationHostController* game;
@property(nonatomic, assign) NSInteger wanted; // 0 Home, 1 upright game, 2 landscape game
@property(nonatomic, assign) NSInteger current;
@property(nonatomic, assign) BOOL transitioning;
@property(nonatomic, assign) NSUInteger geometryGeneration;
@property(nonatomic, assign) BOOL geometryRequestSent;
@property(nonatomic, assign) BOOL geometryRefreshQueued;
@property(nonatomic, assign) CFTimeInterval geometryRefreshUntil;
@property(nonatomic, copy) NSString* geometryWaitReason;
@property(nonatomic, strong) id foregroundObserver;
@property(nonatomic, strong) id deviceObserver;
@property(nonatomic, strong) UIView* cover;
@property(nonatomic, assign) BOOL coverReady;
@property(nonatomic, assign) BOOL coverExpectsEngine;
@property(nonatomic, assign) CFTimeInterval coverRaisedAt;
@property(nonatomic, assign) CFTimeInterval coverSettledAt;
@property(nonatomic, strong) NSTimer* coverTimer;
/* Main.m: the engine reports the screen this cover waits for and stable geometry. */
@property(nonatomic, copy) BOOL (^coverSettled)(BOOL engineVisible);
- (instancetype)initWithWindow:(UIWindow*)window content:(UIViewController*)content;
- (void)setEngineVisible:(BOOL)visible portrait:(BOOL)portrait;
- (void)raiseCoverExpectingEngine:(BOOL)engineVisible;
- (void)reconcile;
- (void)refreshGeometry;
- (void)rearmGeometryObservation;
- (void)deferGeometryRefresh:(NSString*)reason;
- (void)deviceTurned;
@end

@implementation WyrmOrientationCoordinator
- (instancetype)initWithWindow:(UIWindow*)window content:(UIViewController*)content {
  if ((self = [super init])) {
    _window = window; _content = content;
    [self rearmGeometryObservation];
    _home = [[WyrmOrientationHostController alloc] init];
    __weak WyrmOrientationCoordinator* weakSelf = self;
    _home.becameVisible = ^{ [weakSelf reconcile]; [weakSelf refreshGeometry]; };
    window.rootViewController = _home;
    [_home adoptContent:content];
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reconcile]; [weakSelf refreshGeometry]; });
    /* The side the phone is held (OM, 2026-11-01): native play enters on it;
       internal play turns its content to it whenever the phone is turned over. */
    [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
    wyrm_note_device_side();
    _deviceObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:UIDeviceOrientationDidChangeNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note) {
      (void)note; [weakSelf deviceTurned];
    }];
    _foregroundObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note) {
      (void)note; [weakSelf rearmGeometryObservation]; [weakSelf reconcile]; [weakSelf refreshGeometry];
    }];
  }
  return self;
}
- (void)dealloc {
  if (_foregroundObserver) [NSNotificationCenter.defaultCenter removeObserver:_foregroundObserver];
  if (_deviceObserver) [NSNotificationCenter.defaultCenter removeObserver:_deviceObserver];
  [_coverTimer invalidate];
}
/* Orientation cover (OM, 2026-10-29). Home <-> Ready Room, the arena background
   and arena UI editors flickered: the lobby drew upright, then Home, then the
   rotated lobby, while the content moved between hosts and the scene turned.
   The outgoing screen is frozen as a snapshot that fades to the theme's paper
   (2026-10-30: it was black, OM wanted no black screen); the move and rotation
   happen under the paper; the cover fades away once the orientation, the
   engine's geometry and the expected screen have held for 0.06 s (1.0 s at
   most), so the turn reads as one quick dissolve. SwiftUI raises it before it changes its own route (WyrmIOSHoldOrientationCover). */
- (void)raiseCoverExpectingEngine:(BOOL)engineVisible {
  NSAssert(NSThread.isMainThread, @"Orientation cover is main-thread only");
  self.coverExpectsEngine = engineVisible;
  self.coverRaisedAt = CACurrentMediaTime(); self.coverSettledAt = 0;
  if (self.cover) return;
  UIView* host = self.content.view;
  if (!host.window) { self.coverReady = YES; return; }
  UIView* cover = [[UIView alloc] initWithFrame:host.bounds];
  cover.tag = WYRM_ORIENTATION_COVER_TAG;
  cover.backgroundColor = wyrm_paper_colour();
  if (self.home.isViewLoaded) self.home.view.backgroundColor = cover.backgroundColor;
  if (self.game.isViewLoaded) self.game.view.backgroundColor = cover.backgroundColor;
  cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  UIView* still = [host snapshotViewAfterScreenUpdates:NO];
  if (still) { still.frame = cover.bounds; still.autoresizingMask = UIViewAutoresizingNone; [cover addSubview:still]; }
  [host addSubview:cover];
  self.cover = cover; self.coverReady = NO;
  __weak WyrmOrientationCoordinator* weakSelf = self;
  if (still && !UIAccessibilityIsReduceMotionEnabled()) {
    [UIView animateWithDuration:0.1 delay:0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{ still.alpha = 0; } completion:^(BOOL finished) {
      (void)finished;
      WyrmOrientationCoordinator* owner = weakSelf;
      if (!owner || owner.cover != cover) return;
      [still removeFromSuperview];
      owner.coverReady = YES; [owner reconcile];
    }];
  } else {
    [still removeFromSuperview];
    self.coverReady = YES;
  }
  [self.coverTimer invalidate];
  self.coverTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer* timer) {
    (void)timer; [weakSelf checkCover];
  }];
}
- (void)checkCover {
  UIView* cover = self.cover;
  if (!cover) { [self.coverTimer invalidate]; self.coverTimer = nil; return; }
  [cover.superview bringSubviewToFront:cover];
  CFTimeInterval now = CACurrentMediaTime();
  BOOL landscape = self.wanted == 2;
  CGSize size = self.content.view.bounds.size;
  UIWindowScene* scene = self.window.windowScene;
  /* Internal rotation turns the content, never the scene (OM, 2026-11-01): the
     scene stays portrait, so waiting for a landscape scene held the paper
     cover for the whole timeout on every turn. */
  BOOL sceneLandscape = landscape && !internal_rotation;
  BOOL settled = self.coverReady && !self.transitioning && self.current == self.wanted &&
      (self.wanted != 0) == self.coverExpectsEngine &&
      UIInterfaceOrientationIsLandscape(scene.interfaceOrientation) == sceneLandscape &&
      (size.width > size.height) == landscape &&
      (!self.coverSettled || self.coverSettled(self.coverExpectsEngine));
  if (!settled) self.coverSettledAt = 0;
  else if (self.coverSettledAt == 0) self.coverSettledAt = now;
  if ((settled && now - self.coverSettledAt >= 0.06) || now - self.coverRaisedAt > 1.0) [self dropCover];
}
- (void)dropCover {
  [self.coverTimer invalidate]; self.coverTimer = nil;
  UIView* cover = self.cover;
  self.cover = nil; self.coverReady = NO;
  if (!cover) return;
  cover.userInteractionEnabled = NO;
  [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.08 : 0.18 delay:0
                      options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                   animations:^{ cover.alpha = 0; } completion:^(BOOL finished) {
    (void)finished; [cover removeFromSuperview];
  }];
}
/* Internal rotation follows the phone over (OM, 2026-11-01): the window stays
   portrait; only the content's quarter turn flips, so the engine's surface
   keeps its size and nothing reconnects. Native play is turned by iOS itself. */
- (void)deviceTurned {
  if (!internal_rotation) return; /* UIKit handles native physical turns. */
  int before = internal_turn;
  wyrm_note_device_side();
  if (internal_turn == before) return;
  WyrmOrientationHostController* host = self.game ?: self.home;
  if (!host.landscape || self.transitioning) return;
  [self.window endEditing:YES];
  [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.3 delay:0
                      options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                   animations:^{ for (UIViewController* child in host.childViewControllers) [host layoutContent:child]; }
                   completion:nil];
}
- (void)setEngineVisible:(BOOL)visible portrait:(BOOL)portrait {
  NSAssert(NSThread.isMainThread, @"Orientation is main-thread only");
  NSInteger next = !visible ? 0 : (portrait ? 1 : 2);
  if (next == 2) wyrm_note_device_side(); /* Sample the held side on native entry too. */
  if (_wanted == next) { [self reconcile]; return; }
  _wanted = next; [self rearmGeometryObservation];
  // End the old responder/gesture before its window geometry changes. The same
  // content/SDL controller, engine, socket and SwiftUI stores remain alive.
  [self.window endEditing:YES];
  [self reconcile];
  [self refreshGeometry];
}
- (void)rearmGeometryObservation {
  ++_geometryGeneration;
  self.geometryRequestSent = NO;
  self.geometryRefreshUntil = CACurrentMediaTime() + 20.0;
  self.geometryWaitReason = nil;
}
/* Geometry requests have an error callback, no success callback. Appearance
   callbacks can also run while the presentation is still marked transitioning.
   Observe the latest intent independently of the one-second visual cover. */
- (void)deferGeometryRefresh:(NSString*)reason {
  if (CACurrentMediaTime() >= self.geometryRefreshUntil) {
    if (![self.geometryWaitReason isEqualToString:@"timeout"])
      NSLog(@"Wyrm native geometry observation timed out wanted=%ld reason=%@", (long)self.wanted, reason);
    self.geometryWaitReason = @"timeout";
    return;
  }
  if (![self.geometryWaitReason isEqualToString:reason]) {
    self.geometryWaitReason = reason;
    NSLog(@"Wyrm native geometry waiting=%@ wanted=%ld current=%ld", reason, (long)self.wanted, (long)self.current);
  }
  if (self.geometryRefreshQueued) return;
  self.geometryRefreshQueued = YES;
  __weak WyrmOrientationCoordinator* weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 100), dispatch_get_main_queue(), ^{
    WyrmOrientationCoordinator* owner = weakSelf;
    if (!owner) return;
    owner.geometryRefreshQueued = NO;
    [owner reconcile]; [owner refreshGeometry];
  });
}
- (void)refreshGeometry {
  if (self.transitioning) { [self deferGeometryRefresh:@"transitioning"]; return; }
  if (self.current != self.wanted) { [self deferGeometryRefresh:@"pending-intent"]; return; }
  WyrmOrientationHostController* host = self.game ?: self.home;
  UIWindowScene* scene = self.window.windowScene;
  if (!host.view.window) { [self deferGeometryRefresh:@"host-detached"]; return; }
  if (scene.activationState != UISceneActivationStateForegroundActive) {
    [self deferGeometryRefresh:@"scene-inactive"]; return;
  }
  UIInterfaceOrientationMask mask = host.supportedInterfaceOrientations;
  BOOL sceneAccepted = (mask & (1UL << scene.interfaceOrientation)) != 0;
  CGSize bounds = host.view.bounds.size, content = self.content.view.bounds.size;
  BOOL hostLandscape = self.current == 2 && !internal_rotation;
  BOOL contentLandscape = self.current == 2;
  BOOL boundsMatch = bounds.width > 0 && bounds.height > 0 && content.width > 0 && content.height > 0 &&
      ((bounds.width > bounds.height) == hostLandscape) &&
      ((content.width > content.height) == contentLandscape);
  if (sceneAccepted && boundsMatch) {
    NSLog(@"Wyrm native orientation=%@ bounds=%.0fx%.0f content=%.0fx%.0f",
        self.current == 2 ? @"game-landscape" : (self.current == 1 ? @"game-portrait" : @"home-portrait"),
        bounds.width, bounds.height, content.width, content.height);
    self.geometryWaitReason = nil;
    return;
  }
  if (@available(iOS 16.0, *)) {
    if (!sceneAccepted && !self.geometryRequestSent) {
      self.geometryRequestSent = YES;
      [host setNeedsUpdateOfSupportedInterfaceOrientations];
      NSUInteger generation = self.geometryGeneration;
      __weak WyrmOrientationCoordinator* weakSelf = self;
      UIWindowSceneGeometryPreferencesIOS* preference =
          [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
      [scene requestGeometryUpdateWithPreferences:preference errorHandler:^(NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          WyrmOrientationCoordinator* owner = weakSelf;
          if (!owner || generation != owner.geometryGeneration) return;
          NSLog(@"Wyrm native orientation request denied: %@", error.localizedDescription);
        });
      }];
    }
  } else {
    // iOS 15 enters the preferred orientation through a genuine full-screen
    // controller presentation; this refresh handles physical left/right turns.
    [UIViewController attemptRotationToDeviceOrientation];
  }
  [self deferGeometryRefresh:sceneAccepted ? @"bounds-pending" : @"scene-orientation-pending"];
}
- (void)reconcile {
  NSAssert(NSThread.isMainThread, @"Presentation is main-thread only");
  BOOL modern = NO;
  if (@available(iOS 16.0, *)) modern = YES;
  WyrmOrientationAction action = wyrm_orientation_action((int)self.wanted, (int)self.current,
      self.game != nil, self.transitioning,
      self.window.windowScene.activationState == UISceneActivationStateForegroundActive,
      self.home.view.window != nil, self.home.presentedViewController != nil, modern);
  if (action == WYRM_ORIENTATION_WAIT) return;
  // Every content move and rotation happens under the cover; its fade calls back here.
  if (!self.cover) [self raiseCoverExpectingEngine:self.wanted != 0];
  else self.coverExpectsEngine = self.wanted != 0;
  if (self.cover && !self.coverReady) return;
  BOOL animate = !self.cover && !UIAccessibilityIsReduceMotionEnabled();
  if (action == WYRM_ORIENTATION_CHANGE_MASK) {
    if (@available(iOS 16.0, *)) {
      self.game.landscape = self.wanted == 2;
      self.current = self.wanted;
      [self refreshGeometry];
      return;
    }
    // On iOS 15 a change between upright/sideways uses another supported
    // full-screen presentation, never a private UIDevice orientation setter.
  }
  if (action == WYRM_ORIENTATION_RETURN_HOME) {
    self.transitioning = YES;
    UIView* snapshot = [self.content.view snapshotViewAfterScreenUpdates:NO];
    if (snapshot) { snapshot.frame = self.game.view.bounds; [self.game.view addSubview:snapshot]; }
    // The portrait root receives its existing content before the game goes
    // away, so Back reveals the retained Home instead of an empty root.
    [self.home adoptContent:self.content];
    __weak WyrmOrientationCoordinator* weakSelf = self;
    [self.home dismissViewControllerAnimated:animate completion:^{
      WyrmOrientationCoordinator* owner = weakSelf;
      if (!owner) return;
      [snapshot removeFromSuperview]; owner.game = nil;
      owner.current = 0; owner.transitioning = NO;
      [owner reconcile]; [owner refreshGeometry];
    }];
    return;
  }
  // Defer while a document/photo/system controller is above the portrait
  // shell. Its dismissal invokes home.viewDidAppear and reconciles latest intent.
  self.transitioning = YES;
  NSInteger target = self.wanted;
  WyrmOrientationHostController* game = [[WyrmOrientationHostController alloc] init];
  game.landscape = target == 2;
  game.modalPresentationStyle = UIModalPresentationFullScreen;
  game.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
  game.modalInPresentation = YES;
  self.game = game;
  [game adoptContent:self.content];
  __weak WyrmOrientationCoordinator* weakSelf = self;
  game.becameVisible = ^{ [weakSelf reconcile]; [weakSelf refreshGeometry]; };
  [self.home presentViewController:game animated:animate completion:^{
    WyrmOrientationCoordinator* owner = weakSelf;
    if (!owner) return;
    owner.current = target; owner.transitioning = NO;
    [owner reconcile]; [owner refreshGeometry];
  }];
}
@end
