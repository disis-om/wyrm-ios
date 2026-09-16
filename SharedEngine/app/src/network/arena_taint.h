#ifndef ARENA_TAINT_H
#define ARENA_TAINT_H

#include <stdbool.h>
#include <stdint.h>

/*
 * Arenas that would not take us, and how long to remember that for.
 *
 * Both originals do exactly this and nothing more: when a connect attempt runs
 * past 3333ms the server is marked, and the mark lapses after two minutes. In
 * the originals it feeds an automatic server pick, which Wyrm does not have —
 * the player chooses the arena — so here it feeds the picker instead, and the
 * player gets to see that the machine they are about to choose refused them a
 * minute ago.
 *
 * It deliberately does not change the retry policy. Refusing to re-dial a
 * tainted arena would be Wyrm inventing a rule neither original has, and the
 * 14000ms entry budget already bounds how hard a refusing server is knocked on.
 */
enum { ARENA_TAINT_MS = 120000, ARENA_TAINT_SLOTS = 32 };

/** Records that `endpoint` did not answer in time. Ignores empty input. */
void arena_taint_mark(const char* endpoint);

/** Whether `endpoint` refused inside the last `ARENA_TAINT_MS`. */
bool arena_taint_active(const char* endpoint);

/** Milliseconds until `endpoint`'s mark lapses, or 0 if it carries none. */
uint32_t arena_taint_remaining(const char* endpoint);

#endif
