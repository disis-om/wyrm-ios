#include "WyrmOriginalAdapter.h"
#include "user.h"
#include "network/server.h"
#include "game/arena_theme.h"
#include <stdatomic.h>

/* This is only the Apple shell. Every Play action enters the original mailbox;
 * simulation, rendering, input and protocol remain original engine functions.
 *
 * The old ImGui screens that lived here (the "WYRM / PLAY" test title and an
 * ImGui copy of the Ready Room) are gone (OM, 2026-10-01): SwiftUI owns Home
 * and the lobby, and those copies drew under it and flickered through. */
static atomic_bool apple_home_requested;

/* Main thread (SwiftUI) asks; the engine thread leaves the lobby next frame. */
void WyrmIOSLobbyHome(void) { atomic_store(&apple_home_requested, true); }

void WyrmIOSDrawShell(tenv* env) {
  if (atomic_exchange(&apple_home_requested, false) &&
      env->usr->gdata.curr_screen == LOBBY) {
    save_user_settings(&env->usr->usrs);
    env->usr->gdata.stay_in_lobby = false;
    env->usr->gdata.curr_screen = TITLE_SCREEN;
    WyrmIOSSetEnginePresentation(false);
    return;
  }
  static bool reported;
  if (!reported && env->usr->gdata.curr_screen == LOBBY) {
    reported = true;
    ImGuiViewport* vp = igGetMainViewport();
    /* The CI lobby smoke test looks for this line. */
    SDL_Log("Wyrm iOS lobby shell presented at %.0fx%.0f logical points (SwiftUI lobby, engine backdrop)",
            vp->Size.x, vp->Size.y);
  }
}

/* SwiftUI owns the theme choice; the engine only reads the colours. The store
   is atomic in arena_theme.c, so this may be called from the main thread while
   the renderer draws. */
void WyrmIOSSetArenaTheme(const uint32_t* colours, int count, bool dark) {
  if (!colours || count < ARENA_THEME_ROLE_COUNT) return;
  uint32_t next[ARENA_THEME_ROLE_COUNT];
  for (int i = 0; i < ARENA_THEME_ROLE_COUNT; ++i) next[i] = colours[i];
  arena_theme_set(next, dark);
}
