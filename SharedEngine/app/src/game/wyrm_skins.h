#ifndef WYRM_SKINS_H
#define WYRM_SKINS_H

/*
 * Wyrm skins (OM, 2026-10-13): creatures and strip looks drawn over a snake
 * instead of its beads, eyes and boost glow.
 *
 * Numbers never change, only append: creatures 1..23, strip looks 101..115.
 * A creature also has the nearest slither preset, which is what the arena
 * (and every client without these skins) shows; a strip look keeps the
 * snake's own skin and colour.
 *
 * On the wire the number rides in the join's skin-block corner, the way
 * Wyrm's own tags do (network/callback.c):
 *   254, 86 ('V'), preset or 255, 0, 0, 0, n, n ^ 0x5C
 * Byte 1 = 86 is a kind every other reader takes as "no tag", so they draw
 * the snake from its runs (the preset) as before.
 */

#include <stdbool.h>
#include <stdint.h>

#define WYRM_SKIN_MARK 254
#define WYRM_SKIN_KIND 86
#define WYRM_SKIN_CHECK 0x5C
#define WYRM_SKIN_CREATURES 23
#define WYRM_SKIN_STRIP_BASE 100
#define WYRM_SKIN_STRIPS 15

/* A skin number this build knows (creature or strip look). */
bool wyrm_skin_valid(int skin);
/* The preset the arena gets for a creature; -1 for a strip look (the snake
   keeps its own skin) or an unknown number. */
int wyrm_skin_preset(int skin);
/* The skin number a received block's corner names, or 0. */
int wyrm_skin_from_corner(const uint8_t* corner);

/*
 * Draws one snake wearing `skin` on the current ImGui window list.
 * px/py: the body's points in world units, head first; vis[i] >= 1 when the
 * point is on screen. view_x/view_y/zoom/cx/cy map world to screen as the
 * renderer does (cx + (x - view_x) * zoom). radius: half the body's width in
 * world units. head: the head's drawn angle; want: where the snake steers.
 * look: per-snake eased eye state (start at NAN). rgb: the snake's colour.
 */
void wyrm_skin_draw(int skin, const float* px, const float* py,
                    const uint8_t* vis, int n, float view_x, float view_y,
                    float zoom, float cx, float cy, float radius, float head,
                    float want, float* look, bool boosting, float alpha,
                    float red, float green, float blue);

#endif
