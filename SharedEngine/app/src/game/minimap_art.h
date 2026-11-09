#ifndef WYRM_MINIMAP_ART_H
#define WYRM_MINIMAP_ART_H
/*
 * The original minimap's own bitmap per floor (OM, 2026-11-01): Main.as
 * setMinimapSize baked offline by Wyrm iOS/Scripts/generate-minimap-floors.py
 * (the floor blurred into the disc, x0.75 or x1.35 + 12, two quarters lifted
 * by #202020, the drop shadow) and its "server N" line. Why it reads on every
 * floor: the disc is the floor itself, darkened or lifted, never a fixed
 * colour. Drawn as ImGui images with the disc centred on `centre` at `scale`
 * bitmap pixels per pixel.
 */
#include <stdio.h>
#include "../user.h"
#include "backgrounds.h"
#include "minimap_art_data.h"

extern VkDescriptorSet wyrm_minimap_set;

static inline ImVec2 minimap_art_origin(ImVec2 centre, float scale) {
  return (ImVec2){centre.x - MINIMAP_ART_CX * scale, centre.y - MINIMAP_ART_CY * scale};
}

static inline bool minimap_art_draw(ImDrawList* draw, int floor, ImVec2 centre,
                                    float scale, float alpha) {
  int count = (int)(sizeof(MINIMAP_FLOOR_XY) / sizeof(MINIMAP_FLOOR_XY[0]));
  int f = background_clamp(floor);
  if (!wyrm_minimap_set || !draw || f >= count || alpha <= 0.0f) return false;
  ImTextureRef tex = {NULL, (ImTextureID)(uintptr_t)wyrm_minimap_set};
  ImVec2 tl = minimap_art_origin(centre, scale);
  const float* xy = MINIMAP_FLOOR_XY[f];
  ImDrawList_AddImage(draw, tex, tl,
                      (ImVec2){tl.x + MINIMAP_ART_W * scale, tl.y + MINIMAP_ART_H * scale},
                      (ImVec2){xy[0] / 1024.0f, xy[1] / 1024.0f},
                      (ImVec2){(xy[0] + MINIMAP_ART_W) / 1024.0f, (xy[1] + MINIMAP_ART_H) / 1024.0f},
                      igColorConvertFloat4ToU32((ImVec4){1, 1, 1, alpha}));
  return true;
}

/* "server N": Main.as's TextField, 104 wide, centred, 6 down, alpha 0.75,
   under the bitmap's shadow; baseline 2 px gutter + Nunito's 1.011 em. */
static inline void minimap_art_server(ImDrawList* draw, int server, ImVec2 centre,
                                      float scale, float alpha) {
  if (!wyrm_minimap_set || !draw || server <= 0) return;
  char digits[16];
  snprintf(digits, sizeof(digits), "%d", server);
  int pieces[17], n = 0;
  pieces[n++] = 0;
  for (const char* d = digits; *d && n < 17; ++d) pieces[n++] = 1 + (*d - '0');
  float width = 0;
  for (int i = 0; i < n; ++i) width += MINIMAP_LABEL[pieces[i]][6];
  ImVec2 tl = minimap_art_origin(centre, scale);
  float pen = 2.0f + (MINIMAP_ART_W - 4.0f - width) * 0.5f;
  float base = 6.0f + 2.0f + 18.0f * 1.011f;
  ImTextureRef tex = {NULL, (ImTextureID)(uintptr_t)wyrm_minimap_set};
  ImU32 tint = igColorConvertFloat4ToU32((ImVec4){1, 1, 1, alpha});
  for (int i = 0; i < n; ++i) {
    const float* p = MINIMAP_LABEL[pieces[i]];
    ImVec2 a = {tl.x + (pen - p[4]) * scale, tl.y + (base - p[5]) * scale};
    ImDrawList_AddImage(draw, tex, a, (ImVec2){a.x + p[2] * scale, a.y + p[3] * scale},
                        (ImVec2){p[0] / 1024.0f, p[1] / 1024.0f},
                        (ImVec2){(p[0] + p[2]) / 1024.0f, (p[1] + p[3]) / 1024.0f}, tint);
    pen += p[6];
  }
}

#endif
