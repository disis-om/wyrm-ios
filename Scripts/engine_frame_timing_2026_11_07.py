"""Display-locked frame time (OM, 2026-11-07: "FPS/jitter: fix it from the
official docs", Android and iOS).

Two faults in time_step (game/oef.c), the one place every moving thing gets
its step (`vfr`, frames of 8 ms):

1. Precision. `ctm` / `ltm` are float milliseconds counted from the last
   arena dial (glfwSetTime(0)), or from app start in the lobby / AI arena. A
   float has 24 bits: after 35 minutes a millisecond step is 0.25 ms, after
   70 minutes 0.5 ms, after 140 minutes 1 ms. A 144 Hz frame (6.94 ms) then
   reads as 6.5 / 7.0 ms or 6 / 7 / 8 ms, so the snake moved up to 14 % too
   far or too short on alternate frames. The step is now taken from a double.

2. Wake-up noise. The step was the wall time between two CPU wake-ups. With
   vsync (FIFO + Swappy on Android, CADisplayLink on iOS) every frame is
   shown exactly one display period after the last, but the CPU wakes a
   little early or late each time, so equal on-screen intervals got unequal
   steps: visible judder at 120/144 Hz. Android's own game-loop guide: "Since
   your game state advances according to the time between buffer swaps, your
   animation won't update at a consistent rate"; the fix it gives is the
   vsync time rather than the current time
   (developer.android.com/games/develop/gameloops). Apple says the same for
   CADisplayLink (drive animation from the display link's timestamps, not
   the clock at wake-up). The engine is shared and SDL / Swappy hide those
   timestamps, so the step is snapped to whole display periods instead:
   - the period is learnt from the frames themselves (a running average of
     frame / n), seeded by the platform (Swappy's interval, iOS's display
     link rate) through wyrm_frame_period_hint_ms; when 20 frames in a row
     fit no whole number of periods (the display changed rate), it is
     learnt again from the new frames;
   - a frame of about n periods (n >= 1, within 35 %) steps exactly n
     periods, so a missed vsync still steps two;
   - the difference from the real clock is kept and paid back 10 % a frame,
     so over any stretch the game advances by the real elapsed time (the
     snake stays where the server expects it); if it ever exceeds four
     periods it is paid at once. A frame that fits no period takes the
     plain step plus anything owed, so no time is ever dropped.
   Pauses (> 250 ms) and clock rewinds use the plain step, as before. The 5-frame cap, the lag multiplier and every
   other rule after this are unchanged. No packet, setting or save change.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

TIMING_CODE = r'''/* Display-locked frame time (OM, 2026-11-07;
   Wyrm iOS/Scripts/engine_frame_timing_2026_11_07.py). The step is taken
   from a double clock and snapped to whole display periods, with the
   difference from real time paid back gradually. */
static double ft_period_ms;  /* learnt display period, 0 = not yet */
static double ft_hint_ms;    /* from the platform (Swappy / display link) */
static double ft_debt_ms;    /* real time not yet given to the game */
static int ft_off_frames;    /* frames in a row that fit no period */
static double ft_prev_ms = -1;
static float ft_prev_ltm = -1;

/* Any thread; read on the engine thread. */
void wyrm_frame_period_hint_ms(double ms) {
  if (ms < 2.0 || ms > 50.0) return;
  ft_hint_ms = ms;
  ft_period_ms = ms;
  ft_off_frames = 0;
}

static double ft_step_ms(double raw) {
  if (raw <= 0.0 || raw > 250.0) {
    ft_debt_ms = 0;
    return raw;
  }
  if (ft_period_ms <= 0.0) ft_period_ms = ft_hint_ms > 0.0 ? ft_hint_ms : raw;
  double ratio = raw / ft_period_ms;
  long n = lround(ratio);
  if (n < 1 || fabs(ratio - (double)n) > 0.35) {
    if (++ft_off_frames >= 20) {
      ft_period_ms = raw; /* the display changed rate: learn it again */
      ft_off_frames = 0;
    }
    /* Not a whole number of periods: the plain step, plus anything still
       owed, so no real time is ever lost. */
    double plain = raw + ft_debt_ms;
    ft_debt_ms = 0;
    return plain > 0.0 ? plain : 0.0;
  }
  ft_off_frames = 0;
  /* Learn the period from every frame (a frame of two vsyncs counts as two);
     faster while it is far off, as after a refresh-rate change. */
  double one = raw / (double)n;
  ft_period_ms += (one - ft_period_ms) *
                  (fabs(one - ft_period_ms) > 0.1 * ft_period_ms ? 0.1 : 0.02);
  double step = (double)n * ft_period_ms;
  ft_debt_ms += raw - step;
  double pay = fabs(ft_debt_ms) > 4.0 * ft_period_ms ? ft_debt_ms
                                                     : ft_debt_ms * 0.1;
  ft_debt_ms -= pay;
  return step + pay;
}

void time_step(tenv* env) {'''

STEP_OLD = """  gdata->data.fps_etm = (gdata->data.ctm - gdata->data.fps_ltm);
  gdata->data.vfr = (gdata->data.ctm - gdata->data.ltm) / 8.0f;"""

STEP_NEW = """  gdata->data.fps_etm = (gdata->data.ctm - gdata->data.fps_ltm);
  {
    /* The float ctm/ltm stay for everything else; the step comes from the
       double clock unless ltm was reset elsewhere (a new dial, a reset). */
    double now_ms = time_sec * 1000.0;
    double raw = gdata->data.ltm == ft_prev_ltm && ft_prev_ms >= 0.0
                     ? now_ms - ft_prev_ms
                     : (double)(gdata->data.ctm - gdata->data.ltm);
    ft_prev_ms = now_ms;
    ft_prev_ltm = gdata->data.ctm;
    gdata->data.vfr = (float)(ft_step_ms(raw) / 8.0);
  }"""

PAIRS = {
    "app/src/game/oef.c": [
        ("""#include "oef.h"
""", """#include "oef.h"

#include <math.h>
"""),
        ("void time_step(tenv* env) {", TIMING_CODE),
        (STEP_OLD, STEP_NEW),
    ],
    "app/src/game/oef.h": [
        ("""void time_step(tenv* env);""", """void time_step(tenv* env);
/* The display's period in ms, from the platform (Swappy's interval, iOS's
   display link rate): a seed for time_step's display-locked frame time. */
void wyrm_frame_period_hint_ms(double ms);"""),
    ],
}


def apply(root, label="frame timing 2026-11-07", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        text = path.read_text(encoding="utf-8")
        for old, new in pairs:
            if skip_applied and new in text:
                continue
            if text.count(old) != 1:
                raise SystemExit(f"{label}: anchor x{text.count(old)} in {relative}: {old[:80]!r}")
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8", newline="\n" if "build-original-source" in str(root) else "")


def revert(root, label="frame timing 2026-11-07"):
    """Takes this pass back out of a tree (for checks of earlier passes)."""
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for old, new in reversed(pairs):
            if text.count(new) != 1:
                raise SystemExit(f"{label}: revert x{text.count(new)} in {relative}: {new[:80]!r}")
            text = text.replace(new, old)
        path.write_text(text, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
