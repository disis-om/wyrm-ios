#include "input.h"

#include "../mobile/mobile_controls.h"
#include "../mobile/mobile_hotkeys.h"
#include "../network/server.h"
#include "../network/arena_protocol.h"
#include "../user.h"

static void input_with_policy(tenv* env, bool team_protected,
                              bool force_heading) {
  tuser_data* usr = env->usr;
  tcontext* ctx = env->ctx;
  game_data* gdata = &usr->gdata;
  user_settings* usrs = &usr->usrs;
  struct mg_connection* connection = gdata->connection;

  /* Every send below goes down this socket, and a match can end inside the
     same frame that reads the controls — the poll that delivers the close runs
     after this. There is nothing useful to send to an arena that has already
     hung up, and sending it is what turns a finished match into a crash. */
  if (!connection || !gdata->arena_ready || connection->is_closing) return;

  /*
   * One ping outstanding at a time, and never faster than one per 250ms.
   *
   * Slither.txt: `if(!wfpr)if(ctm-last_ping_mtm>250)`. Wyrm used to abandon
   * `wfpr` after 500ms; that let it ping faster than any real client, which
   * is its own way of being asked to leave. A late reply is marked at 750ms
   * in `oef`; a dead socket is the silence watchdog in `loop.c`.
   */
  if (!gdata->data.wfpr) {
    if (gdata->data.ctm - gdata->data.last_ping_mtm > ARENA_PING_MS) {
      gdata->data.last_ping_mtm = gdata->data.ctm;
      gdata->data.wfpr = true;
      arena_send(connection, (uint8_t[]){gdata->data.protocol_version >= 5 ? 251 : 112}, 1);
    }
  }

  /* Following a snake that has already been taken off the list is the same
     read one element before the array that crashed got_packet — the window is
     small, between the snake leaving and the death packet arriving, but it is
     a window a player sits in every time they die. */
  if (gdata->data.follow_view && tdarray_length(gdata->data.snakes) > 0) {
    int xm;
    int ym;

    int snakes_len = tdarray_length(gdata->data.snakes);
    snake* me = gdata->data.snakes + (snakes_len - 1);

    if (usrs->hotkeys[HOTKEY_BOT].active) {
      xm = gdata->bot.output.xm;
      ym = gdata->bot.output.ym;
    } else if (!team_protected) {
      if (twindow_key_down(
              env->wnd, mobile_hotkey_get_key(usrs, MOBILE_HOTKEY_TURN_LEFT)) ||
          mobile_hotkeys_down(env, MOBILE_HOTKEY_TURN_LEFT))
        gdata->data.kd_l_frb += gdata->data.vfrb;
      if (twindow_key_down(env->wnd, mobile_hotkey_get_key(
                                         usrs, MOBILE_HOTKEY_TURN_RIGHT)) ||
          mobile_hotkeys_down(env, MOBILE_HOTKEY_TURN_RIGHT))
        gdata->data.kd_r_frb += gdata->data.vfrb;

      if (gdata->data.kd_l_frb > 0 || gdata->data.kd_r_frb > 0)
        if (gdata->data.ctm - gdata->data.lkstm > ARENA_TURN_MS) {
          gdata->data.lkstm = gdata->data.ctm;
          if (gdata->data.kd_r_frb > 0)
            if (gdata->data.kd_l_frb > gdata->data.kd_r_frb) {
              gdata->data.kd_l_frb -= gdata->data.kd_r_frb;
              gdata->data.kd_r_frb = 0;
            }
          if (gdata->data.kd_l_frb > 0)
            if (gdata->data.kd_r_frb > gdata->data.kd_l_frb) {
              gdata->data.kd_r_frb -= gdata->data.kd_l_frb;
              gdata->data.kd_l_frb = 0;
            }
          if (gdata->data.kd_l_frb > 0) {
            int v = gdata->data.kd_l_frb;
            if (v > 127) v = 127;
            gdata->data.kd_l_frb -= v;
            me->eang -= gdata->data.mamu * v * me->scang * me->spang;
            arena_send(connection, (uint8_t[]){gdata->data.protocol_version >= 5 ? 252 : 108, (uint8_t)v}, 2);
          } else if (gdata->data.kd_r_frb > 0) {
            int v = gdata->data.kd_r_frb;
            if (v > 127) v = 127;
            gdata->data.kd_r_frb -= v;
            me->eang += gdata->data.mamu * v * me->scang * me->spang;
            if (gdata->data.protocol_version >= 5) v += 128;
            arena_send(connection, (uint8_t[]){gdata->data.protocol_version >= 5 ? 252 : 114, (uint8_t)v}, 2);
          }
        }

      if (!mobile_controls_get_aim(env, &xm, &ym)) {
        xm = (int)env->ms->pos[0] - ctx->size[0] / 2;
        ym = (int)env->ms->pos[1] - ctx->size[1] / 2;
      }
    } else {
      // The Team panel owns all manual input. If bot protection is disabled,
      // keep the last heading instead of leaking chat/touch input into arena
      // controls while the panel is open.
      xm = gdata->data.lsxm;
      ym = gdata->data.lsym;
    }
    // SDL turns Android touches into compatibility mouse events so ImGui stays
    // touchable. Never treat that synthetic left mouse as gameplay boost: the
    // mobile controls layer owns boost using an explicit finger ID.
#ifdef VLITHER_ANDROID
    gdata->data.wmd =
        team_protected
            ? (usrs->hotkeys[HOTKEY_BOT].active && gdata->bot.output.accel)
            : (twindow_key_down(env->wnd, mobile_hotkey_get_key(
                                              usrs, MOBILE_HOTKEY_BOOST)) ||
#else
    gdata->data.wmd =
        team_protected
            ? (usrs->hotkeys[HOTKEY_BOT].active && gdata->bot.output.accel)
            : (twindow_button_down(env->wnd, GLFW_MOUSE_BUTTON_LEFT) ||
               twindow_key_down(env->wnd, mobile_hotkey_get_key(
                                              usrs, MOBILE_HOTKEY_BOOST)) ||
#endif
               twindow_key_down(env->wnd, GLFW_KEY_UP) ||
               mobile_controls_boost_down(env) ||
               mobile_hotkeys_down(env, MOBILE_HOTKEY_BOOST) ||
               gdata->bot.output.accel);

    if (gdata->data.md != gdata->data.wmd &&
        gdata->data.ctm - gdata->data.last_accel_mtm > ARENA_BOOST_MS) {
      gdata->data.md = gdata->data.wmd;
      gdata->data.last_accel_mtm = gdata->data.ctm;
      if (gdata->data.protocol_version >= 5)
        arena_send(connection, (uint8_t[]){gdata->data.md ? 253 : 254}, 1);
      else
        arena_send(connection, (uint8_t[]){109, gdata->data.md ? 1 : 0}, 2);
    }

    /* A newly admitted snake has not sent a direction on this socket yet.

     * Protected input normally holds the last vector still, so its (0, 0)

     * compares equal to the reset vector and suppresses the packet entirely.

     * Some arenas accept a ping-only join; others close that silent snake.
 The
     * join path forces this first comparison, while lsang keeps every
 later
     * frame deduplicated in the ordinary way. */
    if (force_heading || xm != gdata->data.lsxm || ym != gdata->data.lsym)
      gdata->data.want_e = true;
    me->eang = atan2f(ym, xm);
    float ang;
    if (gdata->data.want_e && gdata->data.ctm - gdata->data.last_e_mtm > ARENA_AIM_MS) {
      gdata->data.want_e = false;
      gdata->data.last_e_mtm = gdata->data.ctm;
      gdata->data.lsxm = xm;
      gdata->data.lsym = ym;
      float d2 = xm * xm + ym * ym;
      if (d2 > 256) {
        ang = atan2f(ym, xm);
        me->eang = ang;
      } else
        ang = me->wang;
      ang = fmodf(ang, PI2);
      if (ang < 0) ang += PI2;
      int sang = (int)floorf((gdata->data.protocol_version >= 5 ? 251 : 16777215) * ang / PI2);
      if (sang != gdata->data.lsang) {
        gdata->data.lsang = sang;
        if (gdata->data.protocol_version >= 5)
          arena_send(connection, (uint8_t[]){sang & 255}, 1);
        else
          arena_send(connection, (uint8_t[]){101, (sang >> 16) & 255,
                                           (sang >> 8) & 255, sang & 255}, 4);
      }
    }
  }

  // Bot aim/acceleration and network packets above must continue while Team
  // Mode owns the UI. Everything below is manual zoom/hotkey processing and
  // remains blocked so chat text can never toggle gameplay state.
  if (team_protected) return;

  gdata->data.ms_zoom *= expf(env->ms->dwheel * usrs->zoom_step);

  if (tkeyboard_key_pressed(
          env->kb, mobile_hotkey_get_key(usrs, MOBILE_HOTKEY_ZOOM_IN)) ||
      mobile_hotkeys_pressed(env, MOBILE_HOTKEY_ZOOM_IN))
    gdata->data.ms_zoom *= expf(1 * usrs->zoom_step);
  else if (tkeyboard_key_pressed(
               env->kb, mobile_hotkey_get_key(usrs, MOBILE_HOTKEY_ZOOM_OUT)) ||
           mobile_hotkeys_pressed(env, MOBILE_HOTKEY_ZOOM_OUT))
    gdata->data.ms_zoom *= expf(-1 * usrs->zoom_step);

  gdata->data.ms_zoom =
      GLM_MAX(MAX_ZOOM_OUT, GLM_MIN(gdata->data.ms_zoom, MAX_ZOOM_IN));

  // hotkeys
  for (int i = 0; i < NUM_HOTKEYS; i++) {
    hotkey* hk = usrs->hotkeys + i;
    bool virtual_pressed = mobile_hotkeys_pressed(env, i);
    if (i == HOTKEY_RESTART || i == HOTKEY_QUIT)
      hk->active = tkeyboard_key_pressed(env->kb, hk->key) || virtual_pressed;
    else if (hk->mode)
      hk->active =
          twindow_key_down(env->wnd, hk->key) || mobile_hotkeys_down(env, i);
    else
      hk->active ^= tkeyboard_key_pressed(env->kb, hk->key) || virtual_pressed;
  }

  if (WYRM_EXPERIMENTAL_ROPE_MODE &&
      (tkeyboard_key_pressed(
           env->kb, mobile_hotkey_get_key(usrs, MOBILE_HOTKEY_ROPE_MODE)) ||
       mobile_hotkeys_pressed(env, MOBILE_HOTKEY_ROPE_MODE)))
    env->usr->mobile_hotkeys.rope_mode = !env->usr->mobile_hotkeys.rope_mode;

  /* A restart used to be thrown away once the snake was worth more than a
     thousand — a guard against losing a good run to a stray key. On a phone
     that reads as a broken button: the one time you most want out is when the
     snake is big, and the tap simply did nothing. The button is a tap now, and
     a tap does what it says. (It also indexed the last snake without checking
     there was one, which is the same crash that was fixed in got_packet.) */

}

void input(tenv* env) { input_with_policy(env, false, false); }

void input_team_protected(tenv* env) { input_with_policy(env, true, false); }

void input_join_alive(tenv* env) { input_with_policy(env, true, true); }
