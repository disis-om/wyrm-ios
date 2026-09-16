#ifndef WYRM_ARENA_THEME_H
#define WYRM_ARENA_THEME_H

#include <stdbool.h>
#include <stdint.h>

typedef enum arena_theme_role {
  ARENA_THEME_PAPER,
  ARENA_THEME_CARD,
  ARENA_THEME_INK,
  ARENA_THEME_ON_INK,
  ARENA_THEME_QUIET,
  ARENA_THEME_MUTE,
  ARENA_THEME_RULE,
  ARENA_THEME_LIVE,
  ARENA_THEME_LINK,
  ARENA_THEME_WELL,
  ARENA_THEME_TRACK,
  ARENA_THEME_BADGE,
  ARENA_THEME_ROLE_COUNT,
} arena_theme_role;

/** ImGui-packed ABGR colour with the semantic colour's alpha preserved. */
uint32_t arena_theme_colour(arena_theme_role role, float alpha);

/** Readable foreground over the arena: paper for light themes, ink for dark. */
uint32_t arena_theme_overlay_text(float alpha);

void arena_theme_set(const uint32_t colours[ARENA_THEME_ROLE_COUNT],
                     bool dark);

#endif
