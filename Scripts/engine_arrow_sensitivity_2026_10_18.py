"""Arrow Sensitivity in place of Arrow lag (OM, 2026-10-18).

With Controls > Customise arrow movement on, the arrow's own lag slider is gone
and a Sensitivity slider (0..1) multiplies how far the arrow moves for a finger
move: 0 = 1x, exactly the original's; full = ARROW_SENS_MAX times (a tiny move
sends the arrow across the screen); the gain grows exponentially in between so
the slider feels even. Steering follows the arrow itself, as before, so a
higher sensitivity also turns faster. The drawn arrow follows at the
original's 0.6 a frame, made frame-rate free. With Customise off nothing
changes (the original motion). Start distance stays.

Stored as `ext.arrow_sens`, appended to user_settings_ext (missing = 0); id
`arrow.sensitivity`. `arrow.smoothness` leaves the settings table (its field
stays in the file, unread), so an old account document's value is skipped.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

PAIRS = {
    "app/src/game/user_settings.h": [
        ("  bool boost_own[2];\n} user_settings_ext;",
         "  bool boost_own[2];\n"
         "  /* Arrow sensitivity 0..1 (OM, 2026-10-18): 0 = the original 1x. Append\n"
         "     only. */\n"
         "  float arrow_sens;\n"
         "} user_settings_ext;"),
    ],
    "app/src/game/user_settings.c": [
        ("  /* A longer tail belongs to a newer build. Do not shrink it just to rewrite\n",
         "  {\n"
         "    /* Arrow sensitivity (OM, 2026-10-18): missing = 0, the original 1x. */\n"
         "    size_t sens_at = offsetof(user_settings_ext, arrow_sens);\n"
         "    fixed |= ext_take_float(&ext->arrow_sens, written >= sens_at + 4, 0.0f,\n"
         "                            1.0f, 0.0f);\n"
         "  }\n"
         "  /* A longer tail belongs to a newer build. Do not shrink it just to rewrite\n"),
    ],
    "app/src/platform/android_settings.c": [
        ("""    {"arrow.smoothness", "controls.arrow", "Arrow lag",
     "How lazily the arrow follows your thumb. Steering is never smoothed — "
     "only the arrow you are looking at.",
     SETTING_FLOAT, 0.0f, 0.85f, NULL, OWNER_ARROW, ARROW_FIELD(smoothness)},
""", """    /* Sensitivity replaced Arrow lag (OM, 2026-10-18); `smoothness` stays in
       the file, unread. */
    {"arrow.sensitivity", "controls.arrow", "Sensitivity",
     "How far the arrow moves for a finger move. 0 moves like the original; "
     "full sends it across the screen with a tiny move.",
     SETTING_FLOAT, 0.0f, 1.0f, NULL, OWNER_SETTINGS,
     SETTINGS_FIELD(ext.arrow_sens)},
"""),
    ],
    "app/src/mobile/mobile_controls.c": [
        ("""static void update_arrow(tenv* env, float x, float y) {
  mobile_controls_state* state = &env->usr->mobile_controls;
  state->arrow_vec[0] += x - state->arrow_last[0];
  state->arrow_vec[1] += y - state->arrow_last[1];
""", """/* Sensitivity (OM, 2026-10-18): the finger's move times this. 0 on the
   slider = 1x, the original; full = ARROW_SENS_MAX; exponential between. */
#define ARROW_SENS_MAX 12.0f
static float arrow_gain(tenv* env) {
  if (arrow_original_motion()) return 1.0f;
  float s = clampf(env->usr->usrs.ext.arrow_sens, 0.0f, 1.0f);
  return powf(ARROW_SENS_MAX, s);
}

static void update_arrow(tenv* env, float x, float y) {
  mobile_controls_state* state = &env->usr->mobile_controls;
  float gain = arrow_gain(env);
  state->arrow_vec[0] += (x - state->arrow_last[0]) * gain;
  state->arrow_vec[1] += (y - state->arrow_last[1]) * gain;
"""),
        ("""    float ease;
    if (arrow_original_motion()) {
      ease = 0.6f;
    } else {
      ease = clampf(1.0f - arrow->smoothness, 0.05f, 0.95f);
      ease = 1.0f - powf(1.0f - ease, vfr);
    }
""", """    /* With Customise on it is the same 0.6, frame-rate free (Sensitivity
       replaced the lag slider, OM 2026-10-18). */
    float ease;
    if (arrow_original_motion()) {
      ease = 0.6f;
    } else {
      ease = 1.0f - powf(0.4f, vfr);
    }
"""),
        ("""  {
    mobile_arrow_settings* arrow = &env->usr->usrs.arrow_controls;
    game_data* gdata = &env->usr->gdata;
    float vfr = gdata->data.vfr;
""", """  {
    game_data* gdata = &env->usr->gdata;
    float vfr = gdata->data.vfr;
"""),
    ],
}


def apply(root, label="arrow sensitivity 2026-10-18", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        text = path.read_text(encoding="utf-8")
        for old, new in pairs:
            if skip_applied and new in text:
                continue
            if text.count(old) != 1:
                raise SystemExit(f"{label}: anchor x{text.count(old)} in {relative}: {old[:80]!r}")
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8", newline="")


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
