#ifndef BATTLEDOME_H
#define BATTLEDOME_H

#include <stdbool.h>

#include <thermite.h>

/**
 * Battledome arenas (OM, 2026-10-24). Android only for now.
 *
 * The Battledome servers write their words into the arena as food: one pellet
 * for each pixel of a 5 x 7 font, on a grid `cell` world units apart, with the
 * pellet's size byte set to the text's `dot`. Drawn as food they glow, wobble
 * and grow into blobs, so the words cannot be read.
 *
 * Each of those servers also answers `http://ip:port/live.json` with the texts
 * (where, how big a cell, which dot) and the dome (a green ring of `dome` world
 * units around `center`). This module fetches it every few seconds while the
 * player is on one of those servers, and the renderer then draws the text
 * pellets as solid pixels of `cell` size, above the food and under the snakes,
 * plus the dome ring. Positions always come from the arena's own pellets, so
 * the words sit exactly where the server put them.
 */

/** Fetches live.json while connected to a Battledome server. Every frame. */
void battledome_tick(tenv* env);

/** Leaves the arena: stops fetching and forgets the texts and the dome. */
void battledome_close(tenv* env);

/**
 * Whether a pellet at world (x, y) with size `sz` (the wire byte / 5) is a
 * letter pixel. If so, `cell` is its pixel size in world units and `square`
 * says it can be drawn as an upright square (straight text); arc text gets a
 * round pixel, since its pixels are turned.
 */
bool battledome_text_pixel(float x, float y, float sz, float* cell, bool* square);

/** The dome ring, when the server has one: centre and radius, world units. */
bool battledome_dome(float* cx, float* cy, float* radius);

#endif
