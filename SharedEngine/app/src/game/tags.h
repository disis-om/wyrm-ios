#ifndef TAGS_H
#define TAGS_H

#include <stdbool.h>

typedef struct tenv tenv;
typedef struct snake snake;

/**
 * Tags, drawn the way NTL draws them.
 *
 * A tag is not a label above a snake. It is a bobble hanging from the head on
 * a rope, and the rope is the whole character of it: it lags behind a turn,
 * swings past, and settles. Players arriving from the mod know that movement
 * better than they know the artwork, so it is reproduced rather than
 * approximated — see ntl-tags.md for where each number came from.
 */

/** How many tags the app carries. */
int tags_count(void);

/** Whether an index names a tag this build can draw. */
bool tags_valid(int index);

/**
 * Wyrm's own numbering and the mod's, in both directions.
 *
 * Wyrm packs every tag into one run of indices; the mod keeps its bundled and
 * free tags in two ranges two hundred apart. The mod's number is what travels
 * over the wire, so it has to survive the translation — see ntl-tags.md.
 */
int tags_ntl_id(int index);
int tags_from_ntl_id(int ntl);

/** Sets the tag another snake is wearing. */
void tags_set(int snake_id, int tag);

/** Drops every rope. Called when the arena is left. */
void tags_forget_all(void);

/**
 * Draws one snake's tag, if it has one and the settings allow it.
 *
 * Called once per visible snake per frame, after the snake itself. `mine` says
 * whether this is the player's own snake, which some of the settings care
 * about.
 */
void tags_draw(tenv* env, snake* o, bool mine, bool teammate);

/**
 * Draws the player's own tag on the skin editor's preview snake.
 *
 * `head_x`/`head_y` are the centre of the preview head in framebuffer pixels
 * and `head_size` is how wide it is drawn. The same rope and the same bobble as
 * the arena, at the same proportions — a preview that only approximated the
 * thing would be worse than no preview, because it would be believed.
 */
void tags_draw_preview(tenv* env, float head_x, float head_y, float head_size);

/** Advances the swing. Once a frame, before anything is drawn. */
void tags_tick(tenv* env);

#endif
