"""Arrow mode boosts like slither's own (OM, 2026-10-31; Main.as, control mode 2).

Wyrm's arrow steering only (Near Original is left exactly as it is):
- no boost under the finger: the boost button is the fixed one, always drawn
  where the player placed it (whatever "Boost" says, that setting is for the
  joystick modes);
- the first finger is the arrow; a second finger anywhere boosts while it is
  down (Main.as portrait: multi_finger_accel);
- a double tap with one finger (the second touch within 400 ms of the last
  one and within 92 units of it, nothing else down) boosts while that same
  finger keeps steering, until it lifts (Main.as double_tap_accel, the
  "Double tap to boost" rule: getTimer() - last_touch_mtm < 400, |dx|,|dy| < 92).
Units are Main.as's (short side / 480). The state is three statics in
mobile_controls.c (nothing in a saved struct changes). Only which finger does
what changes; boost is sent the way it always was.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

C = "app/src/mobile/mobile_controls.c"

PAIRS = {
    C: [
        ("""static float original_boost_alpha = 0.3f;""",
         """static float original_boost_alpha = 0.3f;

/* Arrow mode boosts like slither's own (OM, 2026-10-31; Main.as control mode 2;
   Wyrm iOS/Scripts/engine_arrow_boost_2026_10_31.py): a double tap boosts while
   that finger keeps steering. When and where the last finger came down. */
static bool arrow_tap_boost;
static Uint64 arrow_last_down_ms;
static float arrow_last_down[2];

/* Wyrm's arrow steering (not Near Original): boost by a second finger, a double
   tap, or the fixed button; never a button under the finger. */
static bool wyrm_arrow_mode(tenv* env) {
  return !android_home_near_original() &&
         mobile_controls_steering_mode(env) == MOBILE_STEERING_ARROW;
}

/* Main.as: a touch within 400 ms and 92 units of the last one, alone on the glass. */
static void arrow_note_down(tenv* env, float x, float y, bool alone) {
  Uint64 now = SDL_GetTicks();
  float reach = 92.0f * original_unit(env);
  arrow_tap_boost = alone && arrow_last_down_ms != 0 && now - arrow_last_down_ms < 400 &&
                    fabsf(x - arrow_last_down[0]) < reach &&
                    fabsf(y - arrow_last_down[1]) < reach;
  arrow_last_down_ms = now;
  arrow_last_down[0] = x;
  arrow_last_down[1] = y;
}"""),
        ("""static void reset_touches(mobile_controls_state* state) {
  state->joystick_down = false;""",
         """static void reset_touches(mobile_controls_state* state) {
  arrow_tap_boost = false;
  state->joystick_down = false;"""),
        ("""    bool fixed_boost_hit =
        cfg->boost_mode == MOBILE_BOOST_FIXED &&
        inside_circle(x, y, bx, by, 112.0f * scale * cfg->boost_size);""",
         """    /* Arrow mode always has the fixed button (OM, 2026-10-31). */
    bool fixed_boost_hit =
        (cfg->boost_mode == MOBILE_BOOST_FIXED || wyrm_arrow_mode(env)) &&
        inside_circle(x, y, bx, by, 112.0f * scale * cfg->boost_size);"""),
        ("""      if (cfg->boost_mode == MOBILE_BOOST_TOUCH_ZONE &&
          state->joystick_down && state->joystick_finger != finger &&
          !state->boost_down) {
        state->boost_down = true;
        state->boost_finger = finger;
        state->boost_origin[0] = x;
        state->boost_origin[1] = y;
        return true;
      }
      if (!state->joystick_down) {
        state->joystick_down = true;
        state->joystick_finger = finger;
        state->joystick_origin[0] = x;
        state->joystick_origin[1] = y;
        state->arrow_drag_distance = 0.0f;
        arrow_seed(env, x, y);
        return true;
      }""",
         """      /* Main.as (OM, 2026-10-31): a second finger anywhere boosts while it
         is down, whatever the Boost setting says. */
      if (state->joystick_down && state->joystick_finger != finger &&
          !state->boost_down) {
        state->boost_down = true;
        state->boost_finger = finger;
        state->boost_origin[0] = x;
        state->boost_origin[1] = y;
        arrow_note_down(env, x, y, false);
        return true;
      }
      if (!state->joystick_down) {
        state->joystick_down = true;
        state->joystick_finger = finger;
        state->joystick_origin[0] = x;
        state->joystick_origin[1] = y;
        state->arrow_drag_distance = 0.0f;
        arrow_seed(env, x, y);
        /* A double tap: boost while this finger keeps steering. */
        arrow_note_down(env, x, y, !state->boost_down && !state->zoom_down);
        return true;
      }"""),
        ("""    bool released_owned_touch = false;
    if (state->joystick_down && state->joystick_finger == finger) {
      state->joystick_down = false;
      released_owned_touch = true;
    }""",
         """    bool released_owned_touch = false;
    if (state->joystick_down && state->joystick_finger == finger) {
      state->joystick_down = false;
      arrow_tap_boost = false; /* the double tap's boost ends with its finger */
      released_owned_touch = true;
    }"""),
        ("""  return env->usr->mobile_controls.boost_down;
#else
  (void)env;
  return false;""",
         """  /* Arrow mode's double tap boosts while its finger is down (Main.as). */
  if (arrow_tap_boost && env->usr->mobile_controls.joystick_down && wyrm_arrow_mode(env))
    return true;
  return env->usr->mobile_controls.boost_down;
#else
  (void)env;
  return false;"""),
        ("""  if (cfg->boost_mode == MOBILE_BOOST_FIXED || state->boost_down) {
    if (cfg->boost_mode == MOBILE_BOOST_TOUCH_ZONE) {
      bx = state->boost_origin[0];
      by = state->boost_origin[1];
    }
    draw_boost(env, dl, bx, by, state->boost_down, false);
  }""",
         """  /* Arrow mode: the fixed button only, lit while any boost is on (OM,
     2026-10-31); no button follows a finger. */
  bool arrow_boost = mobile_controls_steering_mode(env) == MOBILE_STEERING_ARROW;
  bool boosting = state->boost_down || (arrow_boost && arrow_tap_boost && state->joystick_down);
  if (cfg->boost_mode == MOBILE_BOOST_FIXED || arrow_boost || state->boost_down) {
    if (cfg->boost_mode == MOBILE_BOOST_TOUCH_ZONE && !arrow_boost) {
      bx = state->boost_origin[0];
      by = state->boost_origin[1];
    }
    draw_boost(env, dl, bx, by, boosting, false);
  }"""),
    ],
}


def apply(root, label="arrow boost 2026-10-31", skip_applied=False):
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


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
