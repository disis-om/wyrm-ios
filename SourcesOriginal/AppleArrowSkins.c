/* Image arrow skins for the Apple build.
 *
 * The original engine draws its five arrow styles as polygons. The NTL VANCED
 * image skins live in one right-facing atlas (Resources/ArrowSkins.png, built
 * by Scripts/generate-arrow-skins.py) that is uploaded once, beside the tag
 * atlas, when the renderer is created. Drawing one is a single rotated ImGui
 * quad, so it costs nothing a frame. The selection and brightness come from
 * SwiftUI through atomics; nothing here touches steering, input or the arena.
 */
#include "WyrmOriginalAdapter.h"
#include "user.h"

#include <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <stdatomic.h>
#include <SDL3/SDL.h>

#define ARROW_ATLAS_COLUMNS 5
#define ARROW_ATLAS_ROWS 4
#define ARROW_SKIN_COUNT 20

static texture* arrow_texture;
static VkDescriptorSet arrow_descriptor;
static atomic_int arrow_skin = -1;           /* -1: the engine's own polygon */
static _Atomic float arrow_brightness = 1.0f; /* 0.2 … 1.0, multiplies colour */

void WyrmIOSSetArrowSkin(int skin, float brightness) {
  if (skin < -1 || skin >= ARROW_SKIN_COUNT) skin = -1;
  if (!(brightness >= 0.2f)) brightness = 0.2f;
  if (brightness > 1.0f) brightness = 1.0f;
  atomic_store(&arrow_skin, skin);
  atomic_store(&arrow_brightness, brightness);
}

float WyrmIOSArrowBrightness(void) { return atomic_load(&arrow_brightness); }

/* Renderer creation: the atlas is read from the app bundle, not app/res, so an
   existing install whose res copy predates this file still finds it. */
void WyrmIOSArrowSkinsCreate(renderer* r, tcontext* ctx) {
  if (!r || !ctx || arrow_texture) return;
  CFURLRef url = CFBundleCopyResourceURL(CFBundleGetMainBundle(), CFSTR("ArrowSkins"),
                                         CFSTR("png"), NULL);
  if (!url) {
    SDL_Log("Wyrm arrows: ArrowSkins.png is not in the bundle; image arrows off");
    return;
  }
  char path[1024];
  bool ok = CFURLGetFileSystemRepresentation(url, true, (UInt8*)path, sizeof(path));
  CFRelease(url);
  if (!ok) return;
  arrow_texture = create_mipmap_texture(ctx, path);
  /* A failed decode comes back as the engine's 2 x 2 fallback. */
  if (!arrow_texture || arrow_texture->size[0] < 64) {
    SDL_Log("Wyrm arrows: atlas unreadable; image arrows off");
    return;
  }
  arrow_descriptor = igImplVulkan_AddTexture(r->linear_sampler, arrow_texture->view,
                                             VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
  SDL_Log("Wyrm arrows: %d image skins ready (%dx%d)", ARROW_SKIN_COUNT,
          arrow_texture->size[0], arrow_texture->size[1]);
}

void WyrmIOSArrowSkinsDestroy(tcontext* ctx) {
  if (arrow_descriptor) igImplVulkan_RemoveTexture(arrow_descriptor);
  arrow_descriptor = VK_NULL_HANDLE;
  if (arrow_texture && ctx) destroy_texture(ctx, arrow_texture);
  arrow_texture = NULL;
}

/* Called from draw_arrow with the geometry it already computed. Returns true
   when an image skin was drawn in place of the polygon. The square is sized
   from the arrow's own length so the Arrow size slider governs both kinds. */
bool WyrmIOSDrawArrowImage(ImDrawList* dl, float ax, float ay, float dx, float dy,
                           float length, float alpha) {
  int skin = atomic_load(&arrow_skin);
  if (skin < 0 || !arrow_descriptor || !dl) return false;
  float half = length * 0.72f;
  float px = -dy, py = dx;
  ImVec2 corners[4] = {
      {ax - dx * half - px * half, ay - dy * half - py * half},
      {ax + dx * half - px * half, ay + dy * half - py * half},
      {ax + dx * half + px * half, ay + dy * half + py * half},
      {ax - dx * half + px * half, ay - dy * half + py * half},
  };
  float u0 = (float)(skin % ARROW_ATLAS_COLUMNS) / ARROW_ATLAS_COLUMNS;
  float v0 = (float)(skin / ARROW_ATLAS_COLUMNS) / ARROW_ATLAS_ROWS;
  float u1 = u0 + 1.0f / ARROW_ATLAS_COLUMNS;
  float v1 = v0 + 1.0f / ARROW_ATLAS_ROWS;
  float b = atomic_load(&arrow_brightness);
  ImTextureRef texture = {NULL, (ImTextureID)(uintptr_t)arrow_descriptor};
  ImDrawList_AddImageQuad(dl, texture, corners[0], corners[1], corners[2], corners[3],
                          (ImVec2){u0, v0}, (ImVec2){u1, v0}, (ImVec2){u1, v1},
                          (ImVec2){u0, v1},
                          igColorConvertFloat4ToU32((ImVec4){b, b, b, alpha}));
  return true;
}
