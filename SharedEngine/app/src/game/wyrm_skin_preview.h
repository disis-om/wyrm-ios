#ifndef WYRM_SKIN_PREVIEW_H
#define WYRM_SKIN_PREVIEW_H

#include <stdint.h>

/*
 * Live Wyrm skin preview (OM, 2026-10-25; wyrm_skin_preview.c). One frame of a
 * snake wearing `skin` swimming in a w x h box, as triangles in box pixels:
 * out_xy (x, y per vertex), out_argb (0xAARRGGBB per vertex), out_idx (three
 * per triangle). `now` in seconds. Returns the vertex count; *out_ni gets the
 * index count. Not thread safe: call from one thread (the app's UI thread).
 */
int wyrm_skin_preview_frame(int skin, float w, float h, double now, float red, float green,
                            float blue, float* out_xy, uint32_t* out_argb, int max_v,
                            uint16_t* out_idx, int max_i, int* out_ni);

#endif
