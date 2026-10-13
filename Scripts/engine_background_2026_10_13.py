"""Background play (OM, 2026-10-13).

One source for both apps (the engine_sync_2026_10_12.py pattern): Wyrm
Android's tree gets these pairs once
(`python engine_background_2026_10_13.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree.

With the app in the background (recents, screen off, a call) the match carries
on — the socket, the game, the bot — but nothing is drawn:
  - iOS kills GPU work sent from the background; the next acquire then
    reported VK_ERROR_DEVICE_LOST ("Wyrm needs a restart"). Not drawing there
    removes the cause.
  - Android has no surface in the background, so the old loop only waited:
    the match stopped and the snake died.
`wyrm_set_background(on)` is set by the apps (Android WyrmActivity onStop /
onStart through JNI, iOS Main.m on resign active / become active).
`wyrm_background_tick(env)` is one background pass: the match runs (trender
with no drawing), anything else sleeps; a finger left down when the app went
away is let go, so a held boost or joystick does not stay on.
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


BACKGROUND_BLOCK = r'''/*
 * Background play (OM, 2026-10-13): in the background the match carries on —
 * the socket, the game and the bot — but nothing is drawn. iOS kills GPU work
 * sent from the background (that was the "GPU lost" card after coming back);
 * Android has no surface there. Set by the apps: Android WyrmActivity onStop /
 * onStart, iOS Main.m on resign active / become active.
 */
#include <stdatomic.h>
static atomic_int wyrm_background_on = 0;
static bool wyrm_background_seen = false;

void wyrm_set_background(bool on) {
  atomic_store(&wyrm_background_on, on ? 1 : 0);
}

bool wyrm_background(void) { return atomic_load(&wyrm_background_on) != 0; }

/* Engine thread. One background pass; false when the app is in front. */
bool wyrm_background_tick(tenv* env) {
  if (!wyrm_background()) {
    wyrm_background_seen = false;
    return false;
  }
  if (!wyrm_background_seen) {
    wyrm_background_seen = true;
    /* A finger down when the app went away never comes up: let it go, so a
       held boost or joystick does not stay on in the background. */
    env->usr->mobile_controls.joystick_down = false;
    env->usr->mobile_controls.boost_down = false;
    env->usr->mobile_controls.zoom_down = false;
    env->usr->mobile_controls.aim_valid = false;
    SDL_Log("Wyrm background: %s", env->usr->gdata.curr_screen == PLAYING
                                       ? "the match keeps running"
                                       : "waiting");
  }
  game_data* gdata = &env->usr->gdata;
  if (gdata->curr_screen == PLAYING || gdata->connection) {
    trender(env);
  } else {
#ifdef WYRM_SDL_JNI
    /* Android's own loop: rest. iOS calls this from a timer on its main
       thread, which must never sleep. */
    SDL_Delay(100);
#endif
  }
  return true;
}

#ifdef WYRM_SDL_JNI
#include <jni.h>
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetBackgroundPlay(JNIEnv* jenv,
                                                            jclass clazz,
                                                            jboolean on) {
  (void)jenv;
  (void)clazz;
  wyrm_set_background(on);
}
#endif

void trender(tenv* env) {
'''

pairs("app/src/main.c",
      ("void trender(tenv* env) {\n", BACKGROUND_BLOCK),
      ("  bool draw = wyrm_engine_visible(env);\n",
       "  bool draw = !wyrm_background() && wyrm_engine_visible(env);\n"))


def apply(root, label="engine background 2026-10-13", skip_applied=False):
    root = Path(root)
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        for old, new in items:
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
