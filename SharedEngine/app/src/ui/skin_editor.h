#ifndef SKIN_EDITOR_H
#define SKIN_EDITOR_H

#include <stdbool.h>
#include <thermite.h>

void ui_skin_editor_init(tenv* env);

/*
 * Draws the skin preview, and nothing else.
 *
 * The editor's controls are Compose now; the engine keeps only the parts that
 * are genuinely its own — the snake itself and the accessory sprites, both of
 * which live in the game's texture atlas and cannot be reproduced faithfully
 * anywhere else. Compose leaves transparent holes where these land and reports
 * their geometry through ui_skin_editor_set_layout.
 */
void ui_skin_editor(tenv* env);

/**
 * Where Compose has reserved room, in framebuffer pixels.
 *
 * preview_cy is the vertical centre of the two-row snake. The accessory grid is
 * laid out from its top-left corner across seven columns. Zero cell size hides
 * the accessory grid entirely.
 */
void ui_skin_editor_set_layout(float preview_cy, float preview_scale,
                               float accessory_x, float accessory_y,
                               float accessory_cell, float accessory_gap);

/**
 * Paper Skin tab: draw the two-row snake on TITLE_SCREEN, no floor, no
 * accessory grid. The full SKIN_EDITOR path is unchanged.
 */
void ui_skin_editor_set_postcard(bool on);
bool ui_skin_editor_postcard(void);

void ui_skin_editor_destroy(tenv* env);

#endif
