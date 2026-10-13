"""Joystick knob (OM, 2026-10-13).

One source for both apps (the engine_sync_2026_10_12.py pattern): Wyrm
Android's tree gets these pairs once
(`python engine_joystick_knob_2026_10_13.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree.

Controls › Joystick knob, two kinds:
  - Follows the snake (as since 2026-10-01): at rest the knob sits on the
    side the snake heads, and a dynamic joystick starts there under the finger.
  - Back to the centre: at rest the knob returns to the middle, and a dynamic
    joystick starts with the knob under the finger, in the middle.
Fixed and dynamic joysticks both; Near Original keeps slither's own joystick.
Steering is unchanged. The choice is the apps' (Android PlayFeel, iOS
WyrmPlayFeelStore); they hand it over with `mobile_controls_set_knob_centre`
(Android JNI nativeSetJoystickKnob, iOS WyrmIOSSetJoystickKnob).
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


pairs("app/src/mobile/mobile_controls.h",
      ("void mobile_controls_set_play_feel(bool original_arrow, bool look_ahead,\n"
       "                                   int zoom_style);\n",
       "void mobile_controls_set_play_feel(bool original_arrow, bool look_ahead,\n"
       "                                   int zoom_style);\n"
       "/* Controls › Joystick knob (OM, 2026-10-13): true = back to the centre,\n"
       "   false = follows the snake. */\n"
       "void mobile_controls_set_knob_centre(bool centre);\n"))

pairs("app/src/mobile/mobile_controls.c",
      ("static bool joystick_heading(tenv* env, float* hx, float* hy) {\n",
       """/* Controls › Joystick knob (OM, 2026-10-13): back to the centre instead of
   following the snake. Any thread; read each frame. Near Original draws
   slither's own joystick and is not touched. */
static volatile int knob_centre = 0;

void mobile_controls_set_knob_centre(bool centre) { knob_centre = centre ? 1 : 0; }

static bool knob_follows_snake(void) {
  return !knob_centre || android_home_near_original();
}

#ifdef WYRM_SDL_JNI
#include <jni.h>
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetJoystickKnob(JNIEnv* jenv,
                                                          jclass clazz,
                                                          jboolean centre) {
  (void)jenv;
  (void)clazz;
  mobile_controls_set_knob_centre(centre == JNI_TRUE);
}
#endif

static bool joystick_heading(tenv* env, float* hx, float* hy) {
"""),
      ("      if (joystick_heading(env, &hx, &hy)) {\n",
       "      if (knob_follows_snake() && joystick_heading(env, &hx, &hy)) {\n"),
      ("  if (!editor && (!active || (fabsf(ax) < 0.08f && fabsf(ay) < 0.08f)) &&\n",
       "  if (!editor && knob_follows_snake() &&\n"
       "      (!active || (fabsf(ax) < 0.08f && fabsf(ay) < 0.08f)) &&\n"))


def apply(root, label="engine joystick knob 2026-10-13", skip_applied=False):
    root = Path(root)
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        crlf = "\r\n" in text
        for old, new in items:
            if crlf:
                old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
            if skip_applied and new in text:
                continue
            count = text.count(old)
            if count != 1:
                raise SystemExit(f"{label}: anchor x{count} in {relative}: {old[:70]!r}")
            text = text.replace(old, new)
        if text != original:
            target.write_text(text, encoding="utf-8", newline="")
    return len(PAIRS)


if __name__ == "__main__":
    print(apply(sys.argv[1], skip_applied=True), "files written")
