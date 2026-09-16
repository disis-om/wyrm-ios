#include "game/loop.h"
#include "network/server.h"
#include "platform/android_home.h"
#include "platform/android_settings.h"
#include "platform/android_team.h"
#include "platform/android_skin.h"
#include "platform/android_update.h"
#include "ui/lobby.h"
#include "ui/skin_editor.h"
#include "ui/ui_theme.h"
#include "ui/viewport.h"
#include "mobile/mobile_controls.h"
#include "mobile/mobile_hotkeys.h"
#include "user.h"

void tinput(tenv* env) {
  tuser_data* usr = env->usr;
  user_settings* usrs = &usr->usrs;

  if (twindow_closed(env->wnd)) {
    env->config.running = false;
    save_user_settings(usrs);
  }
  if (tkeyboard_key_pressed(
          env->kb,
          mobile_hotkey_get_key(usrs, MOBILE_HOTKEY_FULLSCREEN)) ||
      mobile_hotkeys_pressed(env, MOBILE_HOTKEY_FULLSCREEN)) {
    twindow_toggle_fullscreen(env->wnd);
  }
  mobile_controls_update(env);
}

void tlaunch(tenv* env) {
  tuser_data* usr = env->usr;
  user_settings* usrs = &usr->usrs;
  srand(time(NULL));

  memset(usrs, 0, sizeof(user_settings));
  strcpy(usrs->ipv4, "15.204.212.200:444");
  strcpy(usrs->nickname, "");

  usrs->custom_skin = false;
  usrs->default_skin = rand() % 9;
  usrs->accessory = NO_ACCESSORY;

  read_user_settings(usrs);

  env->config.vsync = usrs->vsync;
  env->config.fullscreen = false;
  env->config.title = "Vlither";
}

void tinit(tenv* env) {
  tuser_data* usr = env->usr;

  imgui_init(env);
  mobile_controls_init(env);
  mobile_hotkeys_init(env);
  env->usr->r = renderer_create(env);
  ui_viewport_init(env);
  android_update_bind_env(env);
  android_home_bind_env(env);
  android_settings_bind_env(env);
  android_team_bind_env(env);
  android_skin_bind_env(env);
  ui_skin_editor_init(env);
  game_data_init(env);
}

void tdestroy(tenv* env) {
  game_data_destroy(env);
  save_user_settings(&env->usr->usrs);
  ui_skin_editor_destroy(env);
  ui_viewport_destroy(env);
  renderer_destroy(env->usr->r, env->ctx);
  imgui_destroy();
}

/*
 * Tells Java which screen the engine is on, so Compose can show the matching
 * one. Reported on change only. Each Compose-owned screen is seeded with the
 * state it needs just before it appears, and the first arrival at Home releases
 * the startup gate that the native title screen used to release.
 */
static void sync_screen(tenv* env) {
  static int reported = -1;
  static bool title_ready_reported = false;
  static bool skin_tables_published = false;

  int screen = (int)env->usr->gdata.curr_screen;
  if (screen == TITLE_SCREEN && !title_ready_reported) {
    title_ready_reported = true;
    android_update_notify_title_ready(&env->usr->usrs,
                                      sizeof(env->usr->usrs));
  }
  if (reported == screen) return;
  reported = screen;

  if (screen == TITLE_SCREEN) {
    android_home_publish_state(env);
  } else if (screen == SKIN_EDITOR) {
    // The palette and the preset sequences never change, so they cross the
    // bridge once, the first time the editor is opened.
    if (!skin_tables_published) {
      skin_tables_published = true;
      android_skin_publish_tables(env);
    }
    android_skin_publish_state(env);
  }
  android_home_set_screen(screen);
}

void trender(tenv* env) {
  tuser_data* usr = env->usr;
  tcontext* ctx = env->ctx;
  game_data* gdata = &usr->gdata;

  android_update_apply_pending_settings(env);
  android_home_poll(env);
  android_settings_poll(env);
  android_team_poll(env);
  android_skin_poll(env);
  sync_screen(env);

  imgui_prerender();
  // render begin
  ImGuiStyle* style = igGetStyle();
  ui_viewport(env);

  igSetNextWindowPos(igGetMainViewport()->Pos, ImGuiCond_None, (ImVec2){});
  igSetNextWindowSize(igGetMainViewport()->Size, ImGuiCond_None);
  igPushStyleVar_Float(ImGuiStyleVar_WindowBorderSize, 0);
  igBegin("##fullscreen_holder", NULL,
          ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoTitleBar |
              ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoDocking |
              ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
  igPopStyleVar(1);
  ui_theme_transition_begin(env);
  if (usr->gdata.curr_screen != PLAYING &&
      usr->gdata.curr_screen != SKIN_EDITOR &&
      usr->gdata.curr_screen != TITLE_SCREEN &&
      usr->gdata.curr_screen != LOBBY) {
    ui_theme_draw_background(env);
    ui_theme_draw_version(env);
  }
  switch (usr->gdata.curr_screen) {
    case TITLE_SCREEN:
      // Home/Social are fully opaque Compose. Paper Skin punches a hole in
      // the preview card and asks for the two-row snake here, without
      // switching to SKIN_EDITOR (that path is the dark nested editor).
      if (ui_skin_editor_postcard()) ui_skin_editor(env);
      break;
    case LOBBY:
      ui_lobby(env);
      break;
    case SKIN_EDITOR:
      ui_skin_editor(env);
      break;
    case PLAYING:
      game_loop(env);
      break;
  }
  ui_theme_transition_end(env);
  if (gdata->curr_screen == PLAYING && android_home_death_pending()) {
    ImGuiViewport* viewport = igGetMainViewport();
    ImVec2 end = {viewport->Pos.x + viewport->Size.x,
                  viewport->Pos.y + viewport->Size.y};
    unsigned alpha = (unsigned)(255 * (1 - android_home_death_opacity()));
    ImDrawList_AddRectFilled(igGetForegroundDrawList_ViewportPtr(viewport),
        viewport->Pos, end, alpha << 24, 0, 0);
  }
  igEnd();
  // render end

  igRender();
  if (tcontext_begin(ctx)) {
    // On the Compose-owned screens this clear *is* the background the player
    // sees: the interface above it is transparent so the skin preview and the
    // accessory sprites can show through, so it has to be Wyrm's black rather
    // than the engine's old slate.
    // Also while connecting: the loading screen is Wyrm's, not the arena's.
    bool compose_owns = usr->gdata.curr_screen == TITLE_SCREEN ||
                        usr->gdata.curr_screen == SKIN_EDITOR;
    bool title = usr->gdata.curr_screen == TITLE_SCREEN;
    bool wyrm_black = (compose_owns && !title) ||
                      usr->gdata.curr_screen == LOBBY ||
                      usr->gdata.conn == CONNECTING;
    vec4 clear_color = {0.086f, 0.109f, 0.133f, 1};
    if (title) {
      /* Paper #F7F6F3 under Compose Home/Auth and the Skin postcard hole. */
      clear_color[0] = 0.969f;
      clear_color[1] = 0.965f;
      clear_color[2] = 0.953f;
    } else if (wyrm_black) {
      clear_color[0] = 0.035f;
      clear_color[1] = 0.035f;
      clear_color[2] = 0.035f;
    }
    renderer_render(usr->r, ctx, clear_color);
    tcontext_clear(ctx, (vec4){0, 0, 0, 1.0f});
    imgui_render(ctx->frames[ctx->current_frame].cmd);
    renderer_render_cursor(usr->r, ctx);
    tcontext_end(ctx);
  }
  renderer_clear_instances(usr->r);
}

/**
 * Called for every frame the window gives up on drawing.
 *
 * Rotating into a match is not one skipped frame. `twindow` returns early for
 * each swapchain rebuild, and asks for another whenever the driver hands back
 * an extent that still describes the display as it was before the rotation —
 * which is exactly what happens on the way from portrait Home into a landscape
 * arena. `trender` does not run on any of those frames, and `server_poll` lives
 * inside it, so for the whole rotation the arena socket is not read, not
 * written, and not answered.
 *
 * Everything that looked like three separate faults came from that one gap: the
 * arena's ping reply sat unread so the keepalive stalled and the arena closed
 * an idle snake at around 0.7s; the updates that queued up in the meantime all
 * arrived at once, so the snake appeared mid-flight as though the match had
 * started without us; and the reply that was finally read had been waiting the
 * length of the rotation, which is the 200ms-odd that settles by itself a
 * moment later.
 *
 * So the socket is pumped here. This is the one place that knows a frame is
 * being skipped rather than merely running slowly.
 */
void tresize(tenv* env) {
  ui_viewport_resize(env);
  /* Only once an arena socket exists: the manager is initialised with the game
   * and these callbacks also run during startup. */
  if (env->usr && env->usr->gdata.connection) server_poll(env);
}

TDEF_ENTRY();
