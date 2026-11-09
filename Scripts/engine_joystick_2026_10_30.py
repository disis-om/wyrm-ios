"""Near Original joystick and boost placed as Main.as places them (OM, 2026-10-30).

Players said the original's joystick sits nearer the corner than Wyrm's. Wyrm
used only the original's phone numbers. Main.as picks them by screen size
(`isPhone()`: the long side in inches, long side / screen DPI, under 7):

  phone:  joystick 150 in, 130 up; boost 140 in, 140 up (map top left)
  larger: joystick 100 in, 100 up; boost 100 in, 100 up

The unit stays the original's (short side / 480, `force_game_scale`). The DPI
is the display's own: SDL's display scale x 160 on Android (densityDpi), x 163
on iOS (points per inch), the same figure the original read. Display and
touch only; nothing is sent differently.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

OLD_CENTRES = """static void original_joystick_centre(tenv* env, float* x, float* y) {
  float u = original_unit(env);
  *x = original_joystick_right(env) ? env->wnd->size[0] - 150.0f * u
                                    : 150.0f * u;
  *y = env->wnd->size[1] - 130.0f * u;
}

static void original_boost_centre(tenv* env, float* x, float* y) {
  float u = original_unit(env);
  *x = original_joystick_right(env) ? 140.0f * u
                                    : env->wnd->size[0] - 140.0f * u;
  *y = env->wnd->size[1] - 140.0f * u;
}
"""

NEW_CENTRES = """/* Main.as `isPhone()` (OM, 2026-10-30): the long side in inches under 7.
   Phones get the original's 150/130 joystick and 140/140 boost, larger
   screens its 100/100 and 100/100 (map top left). Inches = long side in
   pixels / (display scale x 160 on Android, x 163 on iOS). Unknown scale =
   phone, the original's case for every handset. */
static bool original_is_phone(tenv* env) {
  int long_side = env->wnd->size[0] > env->wnd->size[1] ? env->wnd->size[0]
                                                        : env->wnd->size[1];
  float scale = env->wnd->handle ? SDL_GetWindowDisplayScale(env->wnd->handle)
                                 : 0.0f;
  if (!(scale > 0.0f) || long_side <= 0) return true;
#ifdef __APPLE__
  const float dpi = scale * 163.0f;
#else
  const float dpi = scale * 160.0f;
#endif
  return (float)long_side / dpi < 7.0f;
}

static void original_joystick_centre(tenv* env, float* x, float* y) {
  float u = original_unit(env);
  bool phone = original_is_phone(env);
  float in = phone ? 150.0f : 100.0f, up = phone ? 130.0f : 100.0f;
  *x = original_joystick_right(env) ? env->wnd->size[0] - in * u : in * u;
  *y = env->wnd->size[1] - up * u;
}

static void original_boost_centre(tenv* env, float* x, float* y) {
  float u = original_unit(env);
  float in = original_is_phone(env) ? 140.0f : 100.0f;
  *x = original_joystick_right(env) ? in * u : env->wnd->size[0] - in * u;
  *y = env->wnd->size[1] - in * u;
}
"""

PAIRS = {
    "app/src/mobile/mobile_controls.c": [
        (" * Fixed joystick at (150u, H - 130u), boost at (W - 140u, H - 140u), both\n",
         " * Fixed joystick at (150u, H - 130u), boost at (W - 140u, H - 140u) on a\n"
         " * phone, (100u, H - 100u) and (W - 100u, H - 100u) on a larger screen\n"
         " * (Main.as isPhone, 2026-10-30), both\n"),
        (OLD_CENTRES, NEW_CENTRES),
    ],
}


def apply(root, label="Near Original joystick 2026-10-30", skip_applied=False):
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
