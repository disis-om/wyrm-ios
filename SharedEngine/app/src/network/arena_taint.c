#include "arena_taint.h"

#include <stdio.h>
#include <string.h>

#include <SDL3/SDL.h>

#include "../constants.h"

typedef struct taint_slot {
  char endpoint[MAX_IPV4_LEN + 1];
  uint64_t at_ms;
} taint_slot;

/* Thirty-two is several times the number of arenas a player dials in a
   sitting, and the whole table is smaller than one of the packets it exists to
   explain. When it does fill, the oldest mark is the one worth losing. */
static taint_slot slots[ARENA_TAINT_SLOTS];

static taint_slot* find(const char* endpoint) {
  for (int i = 0; i < ARENA_TAINT_SLOTS; i++)
    if (slots[i].at_ms && strcmp(slots[i].endpoint, endpoint) == 0)
      return slots + i;
  return NULL;
}

void arena_taint_mark(const char* endpoint) {
  if (!endpoint || !endpoint[0]) return;

  uint64_t now = SDL_GetTicks();

  /* Re-marking an arena restarts its two minutes rather than adding a second
     row for the same address. */
  taint_slot* slot = find(endpoint);

  if (!slot) {
    for (int i = 0; i < ARENA_TAINT_SLOTS && !slot; i++)
      if (!slots[i].at_ms || now - slots[i].at_ms > ARENA_TAINT_MS)
        slot = slots + i;
  }
  if (!slot) {
    slot = slots;
    for (int i = 1; i < ARENA_TAINT_SLOTS; i++)
      if (slots[i].at_ms < slot->at_ms) slot = slots + i;
  }

  snprintf(slot->endpoint, sizeof(slot->endpoint), "%s", endpoint);
  slot->at_ms = now;
  /* SDL_GetTicks starts at zero, and a taint recorded in the first millisecond
     of the process would otherwise read as an empty slot for ever. */
  if (!slot->at_ms) slot->at_ms = 1;

  SDL_Log("Wyrm arena: '%s' would not take us — noted for %ds", endpoint,
          ARENA_TAINT_MS / 1000);
}

uint32_t arena_taint_remaining(const char* endpoint) {
  if (!endpoint || !endpoint[0]) return 0;
  taint_slot* slot = find(endpoint);
  if (!slot) return 0;
  uint64_t age = SDL_GetTicks() - slot->at_ms;
  if (age >= ARENA_TAINT_MS) return 0;
  return (uint32_t)(ARENA_TAINT_MS - age);
}

bool arena_taint_active(const char* endpoint) {
  return arena_taint_remaining(endpoint) > 0;
}
