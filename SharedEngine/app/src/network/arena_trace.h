#ifndef ARENA_TRACE_H
#define ARENA_TRACE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/*
 * What actually went down the arena socket, so a drop stops being a guess.
 *
 * Five things end a match early and from the outside they are indistinguishable:
 * a stale challenge answer, our own packet rate, our own connect timeout, an
 * arena that never spoke, and a genuine server-side drop. This records enough to
 * tell them apart in one match, and the summary it produces is one line.
 *
 * Set `WYRM_ARENA_TRACE` to 0 once the wire persona is settled. The per-packet
 * ring goes with it; `arena_trace_summary` keeps working either way, because the
 * counts it reports are the part worth keeping in a shipping build.
 */
#define WYRM_ARENA_TRACE 1

/** Starts a fresh record. Called once per connection attempt. */
void arena_trace_reset(void);

/** One outbound packet. `op` is its first byte. */
void arena_trace_out(uint8_t op, size_t len);

/** One inbound protocol packet, after frame splitting. `op` is its command. */
void arena_trace_in(uint8_t op, size_t len);

/**
 * The whole connection in one line, written into `out`.
 *
 * Reports both directions' packet counts, the outbound opcodes that were used
 * and how many of each, the largest gap between two outbound packets, and how
 * long the arena had been silent when this was asked. Truncates rather than
 * overruns.
 */
void arena_trace_summary(char* out, size_t out_len);

#endif
