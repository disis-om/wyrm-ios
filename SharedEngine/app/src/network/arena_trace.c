#include "arena_trace.h"

#include <stdio.h>
#include <string.h>

#include <SDL3/SDL.h>

/*
 * Everything here is per-connection and single-threaded: Mongoose is polled from
 * the game loop, and `input` sends from the same loop. No locking is needed and
 * none is pretended.
 */

enum { TRACE_RING = 256 };

typedef struct trace_entry {
  uint32_t ms;
  uint8_t op;
  uint16_t len;
  bool outbound;
} trace_entry;

static struct {
  trace_entry ring[TRACE_RING];
  int ring_pos;
  int ring_count;

  /* Counts per opcode, so the summary can name what was used without carrying
     the whole ring into the log line. */
  uint16_t out_count[256];
  uint32_t out_total;
  uint32_t in_total;

  uint32_t first_ms;
  uint32_t last_out_ms;
  uint32_t last_in_ms;
  /* The number this whole file exists for: the longest the client went without
     saying anything while a match was live. */
  uint32_t max_out_gap;
  uint8_t last_in_op;
  bool started;
} trace;

void arena_trace_reset(void) {
  memset(&trace, 0, sizeof(trace));
}

static void record(uint8_t op, size_t len, bool outbound) {
  uint32_t now = (uint32_t)SDL_GetTicks();

  if (!trace.started) {
    trace.started = true;
    trace.first_ms = now;
    /* Without this the first packet of the connection reads as a gap of the
       whole uptime, which is the sort of number that sends someone hunting a
       stall that never happened. */
    trace.last_out_ms = now;
  }

  if (outbound) {
    uint32_t gap = now - trace.last_out_ms;
    if (gap > trace.max_out_gap) trace.max_out_gap = gap;
    trace.last_out_ms = now;
    trace.out_count[op]++;
    trace.out_total++;
  } else {
    trace.last_in_ms = now;
    trace.last_in_op = op;
    trace.in_total++;
  }

#if WYRM_ARENA_TRACE
  trace.ring[trace.ring_pos] = (trace_entry){.ms = now - trace.first_ms,
                                             .op = op,
                                             .len = (uint16_t)len,
                                             .outbound = outbound};
  trace.ring_pos = (trace.ring_pos + 1) % TRACE_RING;
  if (trace.ring_count < TRACE_RING) trace.ring_count++;
#else
  (void)len;
#endif
}

void arena_trace_out(uint8_t op, size_t len) { record(op, len, true); }

void arena_trace_in(uint8_t op, size_t len) { record(op, len, false); }

void arena_trace_summary(char* out, size_t out_len) {
  if (!out || out_len == 0) return;
  if (!trace.started) {
    snprintf(out, out_len, "nothing was sent or received");
    return;
  }

  uint32_t now = (uint32_t)SDL_GetTicks();
  int n = snprintf(out, out_len,
                   "out %u in %u, widest send gap %ums, ",
                   trace.out_total, trace.in_total, trace.max_out_gap);
  if (n < 0 || (size_t)n >= out_len) return;
  size_t used = (size_t)n;

  if (trace.in_total)
    n = snprintf(out + used, out_len - used, "last heard 0x%02X %ums ago",
                 trace.last_in_op, now - trace.last_in_ms);
  else
    n = snprintf(out + used, out_len - used, "the arena never spoke");
  if (n < 0 || (size_t)n >= out_len - used) return;
  used += (size_t)n;

  /* Which opcodes we used, and how many of each. Six at most in practice —
     handshake, join, angle, ping, turn, boost — so this stays one line. */
  const char* separator = ", sent";
  for (int op = 0; op < 256; op++) {
    if (!trace.out_count[op]) continue;
    n = snprintf(out + used, out_len - used, "%s 0x%02X x%u", separator, op,
                 trace.out_count[op]);
    if (n < 0 || (size_t)n >= out_len - used) return;
    used += (size_t)n;
    separator = "";
  }
}
