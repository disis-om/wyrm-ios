"""Eyes Back locked arenas (OM, 2026-10-13).

One source for both apps (the engine_sync_2026_10_12.py pattern): Wyrm
Android's tree gets these pairs once
(`python engine_eyes_back_lock_2026_10_13.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree.

As NTL VANCED does it (main-mt.js, Eyes Back "fair use": `lim.arenas`,
`LOCK_MSG`, `locked()`, `say()`): some arenas ban players who use Eyes Back,
so there it never runs. Pressing the key in such an arena does not turn it
on; if it is on when the player reaches one, it turns off. Either way a
message sits at the top centre of the screen for 5 s (dark pill, orange
text, as NTL VANCED's `#eb-hud`). The list is NTL VANCED's,
"139.84.170.60:444", compared as "ip:port" in lower case. NTL VANCED's 2-min
run / 30-s cooldown is not part of this (OM asked for the locked arenas only).
Revert: drop these pairs.
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


LOCK_BLOCK = r'''/*
 * Eyes Back locked arenas (OM, 2026-10-13, as NTL VANCED): arenas that ban
 * players for Eyes Back. There it never runs, and the player is told for 5 s
 * at the top of the screen (ui_overlay.c, eyes_back_lock_message).
 */
static const char* const EB_LOCKED_ARENAS[] = {"139.84.170.60:444"};
#define EB_LOCK_MESSAGE_MS 5000
static Uint64 eb_lock_until;

static bool eyes_back_locked_here(const user_settings* usrs) {
  const char* arena = user_settings_arena(usrs);
  if (!arena || !arena[0]) return false;
  for (size_t i = 0; i < sizeof(EB_LOCKED_ARENAS) / sizeof(*EB_LOCKED_ARENAS);
       i++) {
    const char* a = arena;
    const char* b = EB_LOCKED_ARENAS[i];
    while (*a && *b &&
           (*a == *b || (*a >= 'A' && *a <= 'Z' && *a + 32 == *b))) {
      a++;
      b++;
    }
    if (!*a && !*b) return true;
  }
  return false;
}

static void eyes_back_say_locked(void) {
  eb_lock_until = SDL_GetTicks() + EB_LOCK_MESSAGE_MS;
}

/* The message while it shows, else NULL. */
const char* eyes_back_lock_message(void) {
  if (eb_lock_until == 0 || SDL_GetTicks() >= eb_lock_until) return NULL;
  return "Eyes Back is disabled in this arena, so this server does not ban you";
}

static void eyes_back_toggle(game_data* gdata, const user_settings* usrs) {
  if (!eb.on && eyes_back_locked_here(usrs)) {
    eyes_back_say_locked();
    return;
  }
  eb.on = !eb.on;
'''

pairs("app/src/game/input.c",
      ("static void eyes_back_toggle(game_data* gdata) {\n  eb.on = !eb.on;\n",
       LOCK_BLOCK),
      ("    bool eyes_back = eb.on && gdata->data.protocol_version >= 5;\n",
       "    /* A locked arena turns it off, and says why (OM, 2026-10-13). */\n"
       "    if (eb.on && eyes_back_locked_here(usrs)) {\n"
       "      eyes_back_toggle(gdata, usrs);\n"
       "      eyes_back_say_locked();\n"
       "    }\n"
       "    bool eyes_back = eb.on && gdata->data.protocol_version >= 5;\n"),
      ("(env, MOBILE_HOTKEY_EYES_BACK))\n    eyes_back_toggle(gdata);\n",
       "(env, MOBILE_HOTKEY_EYES_BACK))\n    eyes_back_toggle(gdata, usrs);\n"))

# Wyrm Desktop's bound key (Android tree only; the iOS tree has no such block).
OPTIONAL = {
    ("app/src/game/input.c",
     "MOBILE_HOTKEY_EYES_BACK)))\n    eyes_back_toggle(gdata);\n"):
        "MOBILE_HOTKEY_EYES_BACK)))\n    eyes_back_toggle(gdata, usrs);\n",
}

DRAW_OLD = '''    ImDrawList* draw = igGetWindowDrawList();
    const float edge = 16.0f;
    const float pad = 14.0f;
'''

DRAW_NEW = DRAW_OLD + '''
    /* Eyes Back locked here (OM, 2026-10-13, as NTL VANCED): 5 s at the
       top centre, a dark pill with orange text (input.c). */
    {
      extern const char* eyes_back_lock_message(void);
      const char* lock = eyes_back_lock_message();
      if (lock) {
        ImFont* lock_font = usr->imgui_data.regular_font_bold[0];
        float lock_w = measure(lock_font, lock);
        float lock_h = lock_font->LegacySize;
        float lock_pad_x = 12.0f, lock_pad_y = 5.0f;
        ImVec2 lock_min = {mww2 - lock_w * 0.5f - lock_pad_x, 8.0f};
        ImVec2 lock_max = {mww2 + lock_w * 0.5f + lock_pad_x,
                           8.0f + lock_h + 2.0f * lock_pad_y};
        ImDrawList_AddRectFilled(draw, lock_min, lock_max, 0x8C000000u, 6.0f, 0);
        ImDrawList_AddText_FontPtr(
            draw, lock_font, lock_h,
            (ImVec2){lock_min.x + lock_pad_x, lock_min.y + lock_pad_y},
            0xFF4AB1FFu, lock, NULL, 0, NULL);
      }
    }
'''

pairs("app/src/game/ui_overlay.c", (DRAW_OLD, DRAW_NEW))


def apply(root, label="engine eyes back lock 2026-10-13", skip_applied=False):
    root = Path(root)
    touched = {relative for relative, _ in OPTIONAL} | set(PAIRS)
    for relative in touched:
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        for old, new in PAIRS.get(relative, []):
            if skip_applied and new in text:
                continue
            count = text.count(old)
            if count != 1:
                raise SystemExit(f"{label}: anchor x{count} in {relative}: {old[:70]!r}")
            text = text.replace(old, new)
        for (path, old), new in OPTIONAL.items():
            if path == relative and text.count(old) == 1:
                text = text.replace(old, new)
        if text != original:
            target.write_text(text, encoding="utf-8", newline="")
    return len(touched)


if __name__ == "__main__":
    print(apply(sys.argv[1], skip_applied=True), "files written")
