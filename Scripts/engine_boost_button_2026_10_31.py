"""Boost button on or off, never under the finger (OM, 2026-10-31).

`controls.boost_mode` keeps its two values, now read as a switch:
  1 (MOBILE_BOOST_FIXED)      "Show boost button": the fixed button is drawn
                              where the player placed it and boosts when held;
  0 (MOBILE_BOOST_TOUCH_ZONE) no button at all.
Either way boost works from anywhere it did before, plus more: in joystick
modes any finger on the other half boosts (it used to need mode 0), in arrow
mode a second finger anywhere or a double tap (engine_arrow_boost_2026_10_31).
No button is ever drawn under a finger. Applies after
engine_arrow_boost_2026_10_31.py. Near Original is untouched.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

C = "app/src/mobile/mobile_controls.c"

PAIRS = {
    C: [
        ("""    /* Arrow mode always has the fixed button (OM, 2026-10-31). */
    bool fixed_boost_hit =
        (cfg->boost_mode == MOBILE_BOOST_FIXED || wyrm_arrow_mode(env)) &&
        inside_circle(x, y, bx, by, 112.0f * scale * cfg->boost_size);""",
         """    /* The fixed button only while "Show boost button" is on (OM, 2026-10-31). */
    bool fixed_boost_hit =
        cfg->boost_mode == MOBILE_BOOST_FIXED &&
        inside_circle(x, y, bx, by, 112.0f * scale * cfg->boost_size);"""),
        ("""    bool can_take_boost = cfg->boost_mode == MOBILE_BOOST_TOUCH_ZONE &&
                          !in_joystick_half;""",
         """    /* Any finger on the other half boosts, button shown or not (OM, 2026-10-31). */
    bool can_take_boost = !in_joystick_half;"""),
        ("""  /* Arrow mode: the fixed button only, lit while any boost is on (OM,
     2026-10-31); no button follows a finger. */
  bool arrow_boost = mobile_controls_steering_mode(env) == MOBILE_STEERING_ARROW;
  bool boosting = state->boost_down || (arrow_boost && arrow_tap_boost && state->joystick_down);
  if (cfg->boost_mode == MOBILE_BOOST_FIXED || arrow_boost || state->boost_down) {
    if (cfg->boost_mode == MOBILE_BOOST_TOUCH_ZONE && !arrow_boost) {
      bx = state->boost_origin[0];
      by = state->boost_origin[1];
    }
    draw_boost(env, dl, bx, by, boosting, false);
  }""",
         """  /* The fixed button only, and only while "Show boost button" is on (OM,
     2026-10-31); it lights while any boost is on. No button follows a finger. */
  bool arrow_boost = mobile_controls_steering_mode(env) == MOBILE_STEERING_ARROW;
  bool boosting = state->boost_down || (arrow_boost && arrow_tap_boost && state->joystick_down);
  if (cfg->boost_mode == MOBILE_BOOST_FIXED)
    draw_boost(env, dl, bx, by, boosting, false);"""),
    ],
}


def apply(root, label="boost button 2026-10-31", skip_applied=False):
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
