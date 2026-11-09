#ifndef WYRM_EXTRAS_H
#define WYRM_EXTRAS_H

/* Wyrm extras (OM, 2026-11-07): one atlas, app/res/textures/wyrm_extras.png
 * (tools/wyrm-extras/make.py), for
 *   1. AIR's special skins, drawn exactly as Main.as `setSkin` / the snake
 *      loop does: one eye (27), slug stalks (41), closed eyes + mouth (40),
 *      double beads (60), eye shapes, and the antenna + bulb skins (24, 25,
 *      37, 39, 42, 45-49, 59, 62, 65). Only on a preset with no custom skin
 *      block (`!cusk`), as AIR, and never on a Wyrm skin. Nothing is sent.
 *   2. Minimap marks: NTL teammates show their NTL dot icon (`di`, NTL's
 *      F[0..741] and F[996..1000]); Wyrm friends (mutual follows, from the
 *      Wyrm backend) show their Wyrm icon. Your own place keeps its arrow. */

#include <stdbool.h>
#include "../user.h"

void wyrm_extras_create(renderer* r, tcontext* ctx);
void wyrm_extras_destroy(tcontext* ctx);
/* The bead pass's binding 6 (renderer.c): the extras atlas. */
VkImageView wyrm_extras_view(renderer* r);

/* --- AIR special skins --- */
bool air_looks_on(const snake* o);
/* Main.as `pma`: how far the pupils look (2.3 unless the skin says). */
float air_looks_pma(const snake* o);
/* Main.as auto zoom (game/oef.c); kept across deaths and resets. */
extern float wyrm_air_zoom;
/* Settings > Display > Auto zoom (OM, 2026-11-09): false keeps the
   player's own zoom. Android JNI nativeSetAutoZoom, iOS WyrmIOSSetAutoZoom. */
void wyrm_extras_set_auto_zoom(bool on);
bool wyrm_extras_auto_zoom(void);
/* Main.as `swell`: the first four beads from the head grow (skin 27). */
float air_looks_swell(const snake* o, int bead_from_head);
/* Main.as `drez`: twice the beads (skin 60). */
float air_looks_density(const snake* o);
/* Eye shape (Main.as ed / esp / er, world units at sc 1). */
void air_looks_eye_params(const snake* o, float* ed, float* esp, float* er);
/* Main.as `eo`: a dark rim this much wider than the eye (slug). */
float air_looks_eye_rim(const snake* o);
/* True when slither's two round eyes are not drawn (one eye, closed eyes). */
bool air_looks_hide_eyes(const snake* o);
/* Everything drawn with the atlas: one eye, closed eyes, mouth, slug stalks,
   antenna and bulb. hx/hy the head's world centre, fang the eye angle. */
void air_looks_draw(tenv* env, snake* o, float hx, float hy, float fang,
                    float ssc, float alpha, float mww2, float mhh2, float lsz,
                    float ed, bool accessory);
/* True when air_looks_draw draws this snake's accessory (after its art). */
bool air_looks_owns_accessory(const snake* o);
void air_looks_forget(int snake_id);

/* --- Minimap marks --- */
/* NTL teammate mark: its `di` icon (1000 = NTL's plain dot). False when the
   icon is unknown, so the caller keeps its own dot. */
bool wyrm_extras_ntl_mark(ImDrawList* draw, ImVec2 at, float radius, int di);
/* Wyrm friends: one line each, "x\ty\ticon\tname". */
void wyrm_extras_set_friends(const char* packed);
void wyrm_extras_draw_friends(tenv* env, float left, float top, float diameter);
/* Gallery floors (OM, 2026-11-08): the player's own photo as the arena
   floor, stored as background index BACKGROUND_CUSTOM (backgrounds.h). An
   empty path forgets it. */
void wyrm_custom_floor_set(const char* path, int width, int height);

#ifdef WYRM_IOS
void WyrmIOSSetFriendMarks(const char* packed);
void WyrmIOSSetCustomFloor(const char* path, int width, int height);
#endif

#endif
