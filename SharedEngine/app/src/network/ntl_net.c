#include "ntl_net.h"

#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>

#include "../game/tags.h"
#include "../user.h"

/*
 * Everybody else's tags.
 *
 * The arena carries no cosmetics at all — as far as slither is concerned a tag
 * does not exist. The mod solves that with a network of its own: one websocket
 * that every player is on, which collects who is wearing what and hands the
 * whole table back to everyone, several times a second.
 *
 * Outbound is JSON and is announced once per connection:
 *
 *     [nick, server, tagpass, tagid, skin, x, y, snakeid]
 *
 * and after that only `[x, y]`. `tagid` is `-1` and `tagpass` empty unless the
 * player has *claimed* a private tag — the free and bundled ones travel on the
 * team endpoint's `tg` instead, which Wyrm already sends. So this connection is
 * here to listen, and it announces mostly so that it is allowed to.
 *
 * Inbound is a flat array of four-byte records, big-endian throughout:
 *
 *     [ NTL id hi, NTL id lo, tag hi, tag lo ]
 *
 * `NTL id` is the packet-S session composite, `tag` is what it is wearing,
 * and 65535 means nothing. The whole table arrives each time; there is no
 * delta. The composite is resolved to the renderer's raw arena id before the
 * tag table is touched.
 */

#define NTL_NET_URL "ws://ws.ntl-slither.com:9000"

/* How often the position goes out. The mod reports on its one-second tick and
   there is nothing here worth sending faster — the tags are the point, and they
   arrive when they arrive. */
#define NTL_REPORT_MS 1000

/* Long enough that a service which is simply down is not hammered, short enough
   that a player who was disconnected mid-match gets their tags back. */
#define NTL_RETRY_MS 15000

static struct mg_connection* ntl_conn = NULL;
static bool announced = false;
static Uint64 last_report_ms = 0;
static Uint64 retry_after_ms = 0;

/** Escapes what little of a nickname JSON cares about. */
static void json_string(char* out, size_t cap, const char* in) {
  size_t o = 0;
  if (cap < 3) return;
  out[o++] = '"';
  for (const char* p = in; *p && o + 3 < cap; ++p) {
    unsigned char ch = (unsigned char)*p;
    if (ch == '"' || ch == '\\') {
      out[o++] = '\\';
      out[o++] = (char)ch;
    } else if (ch >= 0x20) {
      out[o++] = (char)ch;
    }
  }
  out[o++] = '"';
  out[o] = '\0';
}

static void send_text(struct mg_connection* c, const char* text) {
  mg_ws_send(c, text, strlen(text), WEBSOCKET_OP_TEXT);
}

/**
 * One inbound table, applied to every snake it names.
 *
 * The ids on the wire are the mod's own tag numbers, not Wyrm's indices into
 * its sheet, so each one is looked up. A number Wyrm has no artwork for — a
 * private tag, most often — resolves to nothing and that snake simply goes
 * without, which is the honest outcome and not a reason to drop the rest.
 */
static void apply_table(tenv* env, const uint8_t* data, size_t len) {
  game_data* gdata = &env->usr->gdata;
  int count = tdarray_length(gdata->data.snakes);
  for (size_t i = 0; i + 3 < len; i += 4) {
    int ntl_id = data[i] << 8 | data[i + 1];
    int ntl = data[i + 2] << 8 | data[i + 3];
    snake* target = snake_find_by_ntl_id(gdata->data.snakes, count, ntl_id);
    if (target)
      tags_set(target->id, ntl == 65535 ? -1 : tags_from_ntl_id(ntl));
  }
}

static void ntl_callback(struct mg_connection* c, int ev, void* ev_data) {
  tenv* env = c->fn_data;
  if (c != ntl_conn && ev != MG_EV_OPEN) return;

  if (ev == MG_EV_WS_MSG) {
    struct mg_ws_message* msg = (struct mg_ws_message*)ev_data;
    apply_table(env, (const uint8_t*)msg->data.buf, msg->data.len);
  } else if (ev == MG_EV_ERROR) {
    SDL_Log("Wyrm NTL: %s", (char*)ev_data);
  } else if (ev == MG_EV_CLOSE) {
    /* Mongoose frees this on the way out of here — see the arena's own callback
       for what holding on to it costs. */
    ntl_conn = NULL;
    announced = false;
    retry_after_ms = SDL_GetTicks() + NTL_RETRY_MS;
    tags_forget_all();
    (void)env;
  }
}

void ntl_net_close(tenv* env) {
  if (ntl_conn) {
    ntl_conn->is_closing = true;
    ntl_conn = NULL;
  }
  announced = false;
  retry_after_ms = 0;
  tags_forget_all();
  (void)env;
}

void ntl_net_tick(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  user_settings* usrs = &usr->usrs;

  /* Only while actually in a match. Off the map there is nobody to be seen by
     and nobody to see. */
  if (gdata->curr_screen != PLAYING || gdata->conn != CONNECTED) {
    if (ntl_conn) ntl_net_close(env);
    return;
  }

  Uint64 now = SDL_GetTicks();
  if (!ntl_conn) {
    if (now < retry_after_ms) return;
    ntl_conn = mg_ws_connect(&gdata->network_manager, NTL_NET_URL, ntl_callback,
                             env, NULL);
    if (!ntl_conn) retry_after_ms = now + NTL_RETRY_MS;
    announced = false;
    return;
  }

  int x = 0, y = 0;
  int sid = gdata->data.snake_id;
  int snakes = tdarray_length(gdata->data.snakes);
  if (snakes > 0) {
    snake* me = gdata->data.snakes + (snakes - 1);
    if (me->id == gdata->data.snake_id) {
      x = (int)(me->xx + me->fx);
      y = (int)(me->yy + me->fy);
      sid = me->ntl_id;
    }
  }

  if (!announced) {
    char nick[MAX_NICKNAME_LEN * 2 + 4];
    char srv[MAX_IPV4_LEN * 2 + 4];
    json_string(nick, sizeof(nick), usrs->nickname);
    json_string(srv, sizeof(srv), usrs->ipv4);

    /* The tag and its password stay empty. Wyrm never claims a private tag on
       this socket — the one it wears travels on the team endpoint — and saying
       otherwise here would be claiming an entitlement it has not been given. */
    char line[sizeof(nick) + sizeof(srv) + 96];
    snprintf(line, sizeof(line), "[%s,%s,\"\",-1,%d,%d,%d,%d]", nick, srv,
             usrs->default_skin, x, y, sid);
    send_text(ntl_conn, line);
    announced = true;
    last_report_ms = now;
    return;
  }

  if (now - last_report_ms < NTL_REPORT_MS) return;
  last_report_ms = now;
  char line[64];
  snprintf(line, sizeof(line), "[%d,%d]", x, y);
  send_text(ntl_conn, line);
}
