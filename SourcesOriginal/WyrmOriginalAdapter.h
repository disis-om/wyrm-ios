#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <vulkan/vulkan.h>
typedef struct tenv tenv;
void WyrmIOSDrawShell(tenv* env);
void WyrmIOSRequestPlay(const char* name, const char* address, bool offline);
void WyrmIOSRequestLobby(const char* name, const char* address);
const char* WyrmIOSHomeSnapshot(void);
void WyrmIOSPublishArenaRefusal(const char* endpoint, int seconds);
const char* WyrmIOSArenaRefusalSnapshot(void);
const char* WyrmIOSSettingsSnapshot(void);
const char* WyrmIOSSettingsVersion(void);
bool WyrmIOSQueueSetting(const char* id, float a, float b, float c, float d, int count);
void WyrmIOSSettingsAction(int action);
const char* WyrmIOSHotkeysSnapshot(void);
bool WyrmIOSQueueHotkey(int action, int key, int mode, bool visible, float x, float y);
bool WyrmIOSQueueSkinSelection(int preset, const char* code,
                               const uint32_t* colors, int color_count, int accessory,
                               int tag, int background);
void WyrmIOSApplySkinSelection(tenv* env);
const char* WyrmIOSTeamPresenceSnapshot(void);
void WyrmIOSSetTeamMembers(const char* packed);
/* Team HUD (2026-10-04): the team chat for the arena's chat window, the
   roster's and chat window's look, and taps on the window's message box. */
void WyrmIOSSetTeamChat(const char* packed);
void WyrmIOSSetTeamHudStyle(const float* values, int count);
int WyrmIOSTakeTeamComposerRequest(void);
void WyrmIOSSetEnginePresentation(bool enabled);
/* SwiftUI draws the landscape Ready Room and the layout editor above the
   rotated engine surface; these let it drive the original home mailbox. */
void WyrmIOSSetShellOverlay(bool enabled);
/* True once the Vulkan device is lost: nothing more can be drawn this run. */
bool WyrmIOSGraphicsLost(void);
/* Play orientation (OM, 2026-10-01): upright play keeps the engine surface
   unrotated in the lobby, the match and the layout editor. Main thread. */
void WyrmIOSSetPortraitPlay(bool portrait);
void WyrmIOSSaveNickname(const char* name);
void WyrmIOSLobbyHome(void);
void WyrmIOSEnterLayoutEditor(const char* name);
void WyrmIOSExitLayoutEditor(void);
void WyrmIOSToggleEditorLeaderboard(void);
void WyrmIOSSetEditorBare(bool bare);
/* Snake-look preview (OM, 2026-10-05): the bare editor's Normal or Assist. */
void WyrmIOSSetEditorAssist(bool on);
/* Settings › Performance (Main.m): the engine's frame cap (0 = the display's
   maximum) and that maximum (120 on ProMotion, else 60). Main thread. */
void WyrmIOSSetFrameCap(int fps);
/* Phase 3 H: the HUD performance chip, "" for none (HomeMailbox.inc). */
void WyrmIOSSetPerformanceChip(const char* text);
/* Settings > Modes > Assist: the assist laser in joystick mode (length is a
   share of the screen's short side, 0.1-1.0). */
void WyrmIOSSetJoystickLaser(bool on, float length);
/* Play feel (2026-10-05): slither's arrow motion, look ahead, spring zoom (0/1). */
void WyrmIOSSetPlayFeel(bool original_arrow, bool look_ahead, int zoom_style);
/* Near Original (Home): slither's own HUD and controls; `server` labels the
   minimap (0 = unknown). HomeMailbox.inc. */
void WyrmIOSSetNearOriginal(bool on, int server);
int WyrmIOSDisplayMaxFPS(void);
/* Finished-run receipts and arena skin sync (HomeMailbox.inc). A receipt
   carries the life's length in seconds (usrs.play_time); Swift drains
   "score\tkills\tseconds\n" lines. */
void WyrmIOSRecordFinishedRun(int score, int kills, double play_time);
const char* WyrmIOSDrainFinishedRuns(void);
/* Run screenshots (AppleRunCapture.inc, appended to thermite's tcontext.c).
   The run receipt requests one; the next frame's swapchain image is copied
   without waiting. Take hands over a malloc'd, tightly packed 8-bit picture
   (bgra 1 = B,G,R,A bytes, 0 = R,G,B,A; sRGB-encoded; alpha meaningless) and
   returns false when none is ready. Free it with WyrmIOSFreeRunScreenshot. */
void WyrmIOSRunCaptureRequest(void);
bool WyrmIOSTakeRunScreenshot(void** pixels, int* width, int* height,
                              int* stride, int* bgra);
void WyrmIOSFreeRunScreenshot(void* pixels);
void WyrmIOSArenaSyncPoll(tenv* env);
const char* WyrmIOSArenaIdentitySnapshot(void);
const char* WyrmIOSArenaVisibleSnapshot(void);
void WyrmIOSArenaSkinSet(int snake_id, const char* nickname, const uint32_t* colours, int count);
void WyrmIOSArenaSkinsClear(void);
/* Arena drops (HomeMailbox.inc). The engine thread stamps each dial, notes a
   CLOSE frame or transport error, and publishes one snapshot per dropped
   match; Swift polls "sequence\tkey=value\t…" ("0" before the first). */
void WyrmIOSArenaConnectStamp(void);
void WyrmIOSArenaCloseFrame(const uint8_t* data, size_t length);
void WyrmIOSArenaNoteError(const char* text);
void WyrmIOSArenaDropped(tenv* env);
/* A 'v' death packet within a moment of spawning is a drop too. */
void WyrmIOSArenaFastDeath(tenv* env, int death_code);
/* What the join carried, the configuration timeout, and a socket turned away
   before spawn (a pre-spawn drop report). */
void WyrmIOSArenaJoinFacts(int packet_bytes, int skin_bytes, int skin_runs,
                           int nick_bytes, int custom_skin);
void WyrmIOSArenaNoteTimeout(void);
void WyrmIOSArenaPrespawnClosed(tenv* env, const char* phase);
const char* WyrmIOSArenaDropSnapshot(void);
/* Image arrow skin (-1 = the engine's polygon style) and a 0.2-1.0 brightness
   applied to image and polygon arrows alike; AppleArrowSkins.c. */
void WyrmIOSSetArrowSkin(int skin, float brightness);
/* Wyrm looks (-1 = none): hair style 0-11 with a 0xRRGGBB tint, ears 0-11 and
   glasses 0-11; drawn on the player's snake only. AppleWyrmLook.c. */
void WyrmIOSSetLook(int hair, int hair_rgb, int ears, int glasses);
/* Twelve ARGB roles in arena_theme_role order; stored atomically. */
void WyrmIOSSetArenaTheme(const uint32_t* colours, int count, bool dark);
VkResult WyrmIOSCreateInstance(const VkInstanceCreateInfo*, const VkAllocationCallbacks*, VkInstance*);
VkResult WyrmIOSCreateDevice(VkPhysicalDevice, const VkDeviceCreateInfo*, const VkAllocationCallbacks*, VkDevice*);
