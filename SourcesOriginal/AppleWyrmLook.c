/* Wyrm looks: hair, ears and glasses (OM, 2026-09-28), the Apple build.
 *
 * The same drawing as Wyrm Android's platform/android_look.c: only over the
 * player's own snake, only on this phone; nothing touches the join packet or
 * the arena socket. The art is Resources/WyrmAccessories.png (8 x 8 cells,
 * painted by Scripts/generate-wyrm-accessories.py). The choice comes from
 * SwiftUI through atomics (WyrmIOSSetLook).
 *
 * Frames (R = head radius, +x = the way the head points):
 *   hair cap   cell 0..11, 4.4 R square, centred 0.6 R behind the head
 *   ears       cell 16..27, 4 R square on the head
 *   glasses    cell 28..39, 4 R square on the head
 *   hair flow  cell 12..15, 3.4 R long, laid along a chain that trails the
 *              head so a ponytail or pigtails swing as the snake turns.
 */
#include "WyrmOriginalAdapter.h"
#include "user.h"

#include <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <stdatomic.h>
#include <SDL3/SDL.h>

#define LOOK_GRID 8
#define LOOK_STYLES 12
#define FLOW_POINTS 9
#define FLOW_SPAN 3.4f
#define CAP_SIDE 4.4f
#define CAP_BACK 0.6f

static texture* look_texture;
static VkDescriptorSet look_descriptor;
static atomic_int look_hair = -1;
static atomic_int look_hair_rgb = 0x96603A;
static atomic_int look_ears = -1;
static atomic_int look_glasses = -1;

void WyrmIOSSetLook(int hair, int hair_rgb, int ears, int glasses) {
  atomic_store(&look_hair, hair >= 0 && hair < LOOK_STYLES ? hair : -1);
  atomic_store(&look_hair_rgb, hair_rgb & 0xFFFFFF);
  atomic_store(&look_ears, ears >= 0 && ears < LOOK_STYLES ? ears : -1);
  atomic_store(&look_glasses, glasses >= 0 && glasses < LOOK_STYLES ? glasses : -1);
}

void WyrmIOSLookCreate(renderer* r, tcontext* ctx) {
  if (!r || !ctx || look_texture) return;
  CFURLRef url = CFBundleCopyResourceURL(CFBundleGetMainBundle(), CFSTR("WyrmAccessories"),
                                         CFSTR("png"), NULL);
  if (!url) {
    SDL_Log("Wyrm looks: WyrmAccessories.png is not in the bundle; looks off");
    return;
  }
  char path[1024];
  bool ok = CFURLGetFileSystemRepresentation(url, true, (UInt8*)path, sizeof(path));
  CFRelease(url);
  if (!ok) return;
  /* A loose PNG may have been rewritten by Xcode as CgBI (see AppleArrowSkins.c). */
  extern void stbi_convert_iphone_png_to_rgb(int flag);
  extern void stbi_set_unpremultiply_on_load(int flag);
  stbi_convert_iphone_png_to_rgb(1);
  stbi_set_unpremultiply_on_load(1);
  look_texture = create_mipmap_texture(ctx, path);
  stbi_convert_iphone_png_to_rgb(0);
  stbi_set_unpremultiply_on_load(0);
  if (!look_texture || look_texture->size[0] < 64) {
    SDL_Log("Wyrm looks: atlas unreadable; looks off");
    return;
  }
  look_descriptor = igImplVulkan_AddTexture(r->linear_sampler, look_texture->view,
                                            VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
  SDL_Log("Wyrm looks: atlas ready (%dx%d)", look_texture->size[0], look_texture->size[1]);
}

void WyrmIOSLookDestroy(tcontext* ctx) {
  if (look_descriptor) igImplVulkan_RemoveTexture(look_descriptor);
  look_descriptor = VK_NULL_HANDLE;
  if (look_texture && ctx) destroy_texture(ctx, look_texture);
  look_texture = NULL;
}

/* ---------------------------------------------------------------- drawing */

typedef struct {
  float x[FLOW_POINTS], y[FLOW_POINTS];
  bool live;
} flow_chain;

static flow_chain chains[2];
static uint64_t last_ticks;

static void cell_uv(int cell, float* u0, float* v0, float* u1, float* v1) {
  *u0 = (float)(cell % LOOK_GRID) / LOOK_GRID;
  *v0 = (float)(cell / LOOK_GRID) / LOOK_GRID;
  *u1 = *u0 + 1.0f / LOOK_GRID;
  *v1 = *v0 + 1.0f / LOOK_GRID;
}

static void draw_cell(ImDrawList* dl, int cell, float cx, float cy, float dx,
                      float dy, float half, ImU32 colour) {
  float px = -dy, py = dx;
  ImVec2 c[4] = {
      {cx - dx * half - px * half, cy - dy * half - py * half},
      {cx + dx * half - px * half, cy + dy * half - py * half},
      {cx + dx * half + px * half, cy + dy * half + py * half},
      {cx - dx * half + px * half, cy - dy * half + py * half},
  };
  float u0, v0, u1, v1;
  cell_uv(cell, &u0, &v0, &u1, &v1);
  ImTextureRef tex = {NULL, (ImTextureID)(uintptr_t)look_descriptor};
  ImDrawList_AddImageQuad(dl, tex, c[0], c[1], c[2], c[3], (ImVec2){u0, v0},
                          (ImVec2){u1, v0}, (ImVec2){u1, v1}, (ImVec2){u0, v1},
                          colour);
}

static int flow_roots(int style, int* cell, float rx[2], float ry[2]) {
  switch (style) {
    case 5: *cell = 12; rx[0] = -0.9f; ry[0] = 0.0f; return 1;
    case 6: *cell = 13; rx[0] = rx[1] = -0.55f; ry[0] = -0.8f; ry[1] = 0.8f; return 2;
    case 7: *cell = 14; rx[0] = -0.95f; ry[0] = 0.0f; return 1;
    case 8: *cell = 15; rx[0] = -0.6f; ry[0] = 0.0f; return 1;
    default: return 0;
  }
}

static void flow_update(flow_chain* ch, float rootx, float rooty, float backx,
                        float backy, float seg, float dt, float t, int index) {
  float dx0 = ch->x[0] - rootx, dy0 = ch->y[0] - rooty;
  if (!ch->live || dx0 * dx0 + dy0 * dy0 > (seg * 12) * (seg * 12)) {
    for (int i = 0; i < FLOW_POINTS; ++i) {
      ch->x[i] = rootx + backx * seg * i;
      ch->y[i] = rooty + backy * seg * i;
    }
    ch->live = true;
    return;
  }
  ch->x[0] = rootx;
  ch->y[0] = rooty;
  float ease = 1.0f - powf(1.0f - 0.085f, dt * 60.0f);
  for (int i = 1; i < FLOW_POINTS; ++i) {
    float dx = ch->x[i] - ch->x[i - 1], dy = ch->y[i] - ch->y[i - 1];
    float len = sqrtf(dx * dx + dy * dy);
    if (len < 1e-4f) { dx = backx; dy = backy; len = 1.0f; }
    dx /= len;
    dy /= len;
    float sway = 0.1f * sinf(t * 2.3f + i * 0.55f + index * 1.7f) * ((float)i / (FLOW_POINTS - 1));
    float cs = cosf(sway), sn = sinf(sway);
    float rx = backx * cs - backy * sn, ry = backx * sn + backy * cs;
    dx += (rx - dx) * ease;
    dy += (ry - dy) * ease;
    len = sqrtf(dx * dx + dy * dy);
    if (len < 1e-4f) len = 1.0f;
    ch->x[i] = ch->x[i - 1] + dx / len * seg;
    ch->y[i] = ch->y[i - 1] + dy / len * seg;
  }
}

static void flow_draw(ImDrawList* dl, flow_chain* ch, int cell, game_data* gdata,
                      float mww2, float mhh2, float half, ImU32 colour) {
  float gsc = gdata->data.gsc;
  ImVec2 s[FLOW_POINTS], n[FLOW_POINTS];
  for (int i = 0; i < FLOW_POINTS; ++i)
    s[i] = (ImVec2){mww2 + (ch->x[i] - gdata->data.view_xx) * gsc,
                    mhh2 + (ch->y[i] - gdata->data.view_yy) * gsc};
  for (int i = 0; i < FLOW_POINTS; ++i) {
    ImVec2 a = s[i > 0 ? i - 1 : 0], b = s[i < FLOW_POINTS - 1 ? i + 1 : FLOW_POINTS - 1];
    float dx = b.x - a.x, dy = b.y - a.y;
    float len = sqrtf(dx * dx + dy * dy);
    if (len < 1e-4f) len = 1.0f;
    n[i] = (ImVec2){-dy / len * half, dx / len * half};
  }
  float u0, v0, u1, v1;
  cell_uv(cell, &u0, &v0, &u1, &v1);
  ImTextureRef tex = {NULL, (ImTextureID)(uintptr_t)look_descriptor};
  for (int i = 0; i < FLOW_POINTS - 1; ++i) {
    float ua = u0 + (u1 - u0) * i / (FLOW_POINTS - 1);
    float ub = u0 + (u1 - u0) * (i + 1) / (FLOW_POINTS - 1);
    ImDrawList_AddImageQuad(
        dl, tex, (ImVec2){s[i].x - n[i].x, s[i].y - n[i].y},
        (ImVec2){s[i + 1].x - n[i + 1].x, s[i + 1].y - n[i + 1].y},
        (ImVec2){s[i + 1].x + n[i + 1].x, s[i + 1].y + n[i + 1].y},
        (ImVec2){s[i].x + n[i].x, s[i].y + n[i].y}, (ImVec2){ua, v0},
        (ImVec2){ub, v0}, (ImVec2){ub, v1}, (ImVec2){ua, v1}, colour);
  }
}

void wyrm_look_draw(tenv* env, float hx, float hy, float fang, float lsz,
                    float alpha, float mww2, float mhh2) {
  if (!look_descriptor || !env || !env->usr) return;
  int hair = atomic_load(&look_hair);
  int ears = atomic_load(&look_ears);
  int glasses = atomic_load(&look_glasses);
  if (hair < 0 && ears < 0 && glasses < 0) {
    chains[0].live = chains[1].live = false;
    return;
  }
  game_data* gdata = &env->usr->gdata;
  ImDrawList* dl = igGetForegroundDrawList_ViewportPtr(NULL);
  if (!dl) return;
  if (alpha > 1.0f) alpha = 1.0f;
  if (alpha <= 0.0f) return;

  uint64_t now = SDL_GetTicks();
  float dt = last_ticks ? (float)(now - last_ticks) / 1000.0f : 1.0f / 60.0f;
  if (dt > 0.1f) dt = 0.1f;
  last_ticks = now;
  float t = (float)(now % 600000) / 1000.0f;

  float gsc = gdata->data.gsc;
  float R = lsz * gsc;
  float dx = cosf(fang), dy = sinf(fang);
  float cx = mww2 + (hx - gdata->data.view_xx) * gsc;
  float cy = mhh2 + (hy - gdata->data.view_yy) * gsc;
  ImU32 white = igColorConvertFloat4ToU32((ImVec4){1, 1, 1, alpha});

  if (hair >= 0) {
    int rgb = atomic_load(&look_hair_rgb);
    ImU32 tint = igColorConvertFloat4ToU32((ImVec4){((rgb >> 16) & 0xFF) / 255.0f,
                                                   ((rgb >> 8) & 0xFF) / 255.0f,
                                                   (rgb & 0xFF) / 255.0f, alpha});
    int cell = 0;
    float rx[2], ry[2];
    int flows = flow_roots(hair, &cell, rx, ry);
    for (int k = 0; k < 2; ++k) {
      if (k >= flows) {
        chains[k].live = false;
        continue;
      }
      float wx = hx + (dx * rx[k] - dy * ry[k]) * lsz;
      float wy = hy + (dy * rx[k] + dx * ry[k]) * lsz;
      flow_update(&chains[k], wx, wy, -dx, -dy, FLOW_SPAN * lsz / (FLOW_POINTS - 1), dt, t, k);
      flow_draw(dl, &chains[k], cell, gdata, mww2, mhh2, FLOW_SPAN * 0.5f * R, tint);
    }
    draw_cell(dl, hair, cx - dx * CAP_BACK * R, cy - dy * CAP_BACK * R, dx, dy,
              CAP_SIDE * 0.5f * R, tint);
  } else {
    chains[0].live = chains[1].live = false;
  }
  if (ears >= 0) draw_cell(dl, 16 + ears, cx, cy, dx, dy, 2.0f * R, white);
  if (glasses >= 0) draw_cell(dl, 28 + glasses, cx, cy, dx, dy, 2.0f * R, white);
}
