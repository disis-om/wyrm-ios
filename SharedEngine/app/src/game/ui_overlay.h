#ifndef UI_OVERLAY_H
#define UI_OVERLAY_H

#include <stdbool.h>
#include <thermite.h>

void ui_overlay(tenv* env);

/** The leaderboard is the only interactive HUD block; it owns only its bounds. */
bool ui_overlay_leaderboard_hit(tenv* env, float x, float y);
void ui_overlay_toggle_leaderboard(tenv* env);

#endif
