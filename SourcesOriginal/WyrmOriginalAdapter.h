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
void WyrmIOSSetEnginePresentation(bool enabled);
/* SwiftUI draws the landscape Ready Room and the layout editor above the
   rotated engine surface; these let it drive the original home mailbox. */
void WyrmIOSSetShellOverlay(bool enabled);
void WyrmIOSSaveNickname(const char* name);
void WyrmIOSLobbyHome(void);
void WyrmIOSEnterLayoutEditor(const char* name);
void WyrmIOSExitLayoutEditor(void);
void WyrmIOSToggleEditorLeaderboard(void);
/* Finished-run receipts and arena skin sync (HomeMailbox.inc). */
void WyrmIOSRecordFinishedRun(int score, int kills);
const char* WyrmIOSDrainFinishedRuns(void);
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
