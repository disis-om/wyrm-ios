#include "server.h"

#include <stdio.h>
#include <string.h>

#include "../user.h"
#include "arena_trace.h"
#include "callback.h"

void arena_send(struct mg_connection* c, const void* data, size_t len) {
  /* A match can end inside the frame that reads the controls: the poll which
     delivers the close runs after `input`. Sending to an arena that has already
     hung up is what turns a finished match into a crash, so the check lives
     here rather than being remembered at every call site. */
  if (!c || !data || len == 0) return;
  arena_trace_out(((const uint8_t*)data)[0], len);
  mg_ws_send(c, data, len, WEBSOCKET_OP_BINARY);
}

void server_init(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  user_settings* usrs = &usr->usrs;
  mg_log_set(MG_LL_NONE);
  mg_mgr_init(&gdata->network_manager);
}

bool server_connect(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  user_settings* usrs = &usr->usrs;

  /*
   * A second request must never replace a live pointer. The old socket would
   * keep running inside Mongoose but every event from it would be ignored as
   * stale.
   *
   * This used to return without saying so, and the caller had already put the
   * game into CONNECTING — so the player watched a loading screen with no
   * socket behind it at all, against a timeout measured from the *previous*
   * attempt's stamp, which had already expired. That is the whole of "fresh
   * app start works, joining again does not": a fresh start has no old socket
   * to collide with, and every join after a match does.
   *
   * Now it says no, and the caller waits for the old socket to finish rather
   * than pretending it dialled.
   */
  if (gdata->connection) {
    SDL_Log("Wyrm arena: '%s' still has a socket closing — waiting for it",
            usrs->ipv4);
    return false;
  }

  /*
   * Slither.txt: `new WebSocket("ws://"+ip+":"+port+"/slither")`.
   *
   * `wss://` on this fleet was closing with `nothing was sent or received`
   * before a protocol byte — Play never spawned. Plain `ws://` is what the
   * original client dials.
   */
  char url[256] = {};
  snprintf(url, sizeof(url), "ws://%s/slither", usrs->ipv4);

  /* Cleared first, so that nothing in the window below is holding the last
     arena's socket. Mongoose raises MG_EV_OPEN from inside the call, and the
     callback decides what to ignore by comparing against this. */
  gdata->closed = false;
  /* One record per attempt. A retry that inherited the previous attempt's
     counts would report a send gap that spans the gap between sockets. */
  arena_trace_reset();
  /* The silence watchdog counts from here. Left at whatever the last match
     ended on, a fresh socket would be judged against a clock that had already
     run out and the join would be killed before the arena got a word in. */
  gdata->last_packet_ms = SDL_GetTicks();
  /* This attempt's own clock: what it is allowed to spend, and what the next
     attempt is scheduled off. */
  gdata->attempt_started_ms = gdata->last_packet_ms;
  /* Deliberately not cleared by `game_data_reset`: it paces the next entry
     against this one, so it has to outlive the world it belongs to. */
  gdata->last_connect_ms = gdata->last_packet_ms;
  gdata->persona_tested = false;
  /* A browser keeps Host equal to the arena URL and sends the page origin.
     Mongoose already writes Host; adding a second slither.com Host and using
     slither.com (rather than slither.io) made some live arenas reject the HTTP
     upgrade before they could send challenge 0x36. */
  gdata->connection =
    mg_ws_connect(&gdata->network_manager, url, server_callback, env,
                  "Origin: https://slither.io\r\n");
  if (!gdata->connection) {
    SDL_Log("Wyrm arena: could not open a socket to '%s'", usrs->ipv4);
    gdata->closed_by_us = false;
    gdata->closed = true;
    return true;
  }

  /* Two immediate polls, from Vlither. A TLS handshake needs poll cycles
     before the game loop's own first poll comes round, and the connect
     otherwise spends a frame doing nothing. */
#ifdef VLITHER_ANDROID
  mg_mgr_poll(&gdata->network_manager, 5);
  mg_mgr_poll(&gdata->network_manager, 5);
#endif
  return true;
}

void server_poll(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;

  /* Vlither blocks 5ms here on Android and 0ms elsewhere. A non-blocking poll
     is fine over plaintext, where a frame's worth of bytes is already sitting
     in the socket; a TLS record has to be assembled before there is anything to
     hand up, and starving that is how a working connection reads as a dead
     one. */
#ifdef VLITHER_ANDROID
  mg_mgr_poll(&gdata->network_manager, 5);
#else
  mg_mgr_poll(&gdata->network_manager, 0);
#endif
}

void server_destroy(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;

  mg_mgr_free(&gdata->network_manager);
}

bool server_address_is_valid(const char* address) {
  if (!address || !address[0] || strlen(address) > MAX_IPV4_LEN) return false;
  unsigned int a, b, c, d, port;
  char tail = 0;
  int matched = sscanf(address, "%u.%u.%u.%u:%u%c", &a, &b, &c, &d, &port,
                       &tail);
  return matched == 5 && a <= 255 && b <= 255 && c <= 255 && d <= 255 &&
         port > 0 && port <= 65535;
}
