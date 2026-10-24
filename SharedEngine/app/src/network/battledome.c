#include "battledome.h"

#include <SDL3/SDL.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "../user.h"

/*
 * Battledome texts and dome (battledome.h). The servers below are the
 * Battledome network's own list (`:447/full/bdinfo.json`, `serverlist`,
 * 2026-10-24): IN, EU (also the 1vs1 arena on 446), BR, US, JP, KR, SG, AE.
 * Every port on those machines is asked, so a new arena there works at once.
 * No other arena is ever asked for anything.
 *
 * live.json (public, read only):
 *   center   arena middle (both axes)
 *   dome     ring radius, 0 when there is none
 *   texts[]  { text, cell, dot, cv, box[x0,y0,x1,y1], x, y }   straight
 *            { text, cell, dot, cv, box, arc{cx,cy,r,mid} }     on a circle
 *
 * A pellet is a letter pixel when its size byte is a text's `dot` * 5 and it
 * lies in that text's box (straight) or on its ring (arc). Checked against the
 * live stream on 81.169.165.225:446, 2026-10-24: every pixel of "0" (19
 * pellets) sat on x + col * cell, y + row * cell, cols 0-4, rows 0-6.
 */

static const char* const BD_HOSTS[] = {
  "139.84.170.60",  "81.169.165.225", "216.128.169.33", "45.77.5.207",
  "45.76.102.107",  "141.164.36.225", "5.223.78.163",   "130.94.45.154",
};

/* The words change with the match (counters, the clock). Three seconds keeps
   them close without leaning on the server; a miss waits longer. */
#define BD_POLL_MS 3000
#define BD_RETRY_MS 15000
#define BD_TIMEOUT_MS 6000
#define BD_MAX_TEXTS 48

typedef struct bd_text {
  bool arc;
  float cx, cy, r;   /* arc */
  float box[4];      /* x0, y0, x1, y1 */
  float cell;
  int dot_byte;      /* the pellet's size byte: dot * 5 */
} bd_text;

static bool on_bd = false;            /* the arena is a Battledome server */
static char arena[96] = "";           /* host:port the state belongs to */
static char host[64] = "";
static struct mg_connection* conn = NULL;
static Uint64 conn_started_ms = 0;
static Uint64 next_fetch_ms = 0;

static bd_text texts[BD_MAX_TEXTS];
static int text_count = 0;
static float dome_center = 0, dome_radius = 0;

static void forget(void) {
  text_count = 0;
  dome_radius = 0;
}

static bool host_listed(const char* h) {
  for (size_t i = 0; i < sizeof(BD_HOSTS) / sizeof(BD_HOSTS[0]); i++)
    if (strcmp(h, BD_HOSTS[i]) == 0) return true;
  return false;
}

static float num(struct mg_str json, const char* path, double dflt) {
  double v = dflt;
  if (!mg_json_get_num(json, path, &v) || !isfinite(v)) v = dflt;
  return (float)v;
}

static void parse(struct mg_str body) {
  forget();
  dome_center = num(body, "$.center", 32550);
  float dome = num(body, "$.dome", 0);
  dome_radius = dome > 0 && dome < 100000 ? dome : 0;

  char path[64];
  for (int i = 0; i < BD_MAX_TEXTS; i++) {
    int len = 0;
    snprintf(path, sizeof(path), "$.texts[%d]", i);
    int at = mg_json_get(body, path, &len);
    if (at < 0 || len <= 0) break;
    struct mg_str t = mg_str_n(body.buf + at, (size_t)len);

    bd_text x = {0};
    x.cell = num(t, "$.cell", 0);
    float dot = num(t, "$.dot", 0);
    if (!(x.cell > 1 && x.cell < 2000 && dot > 0 && dot < 51)) continue;
    x.dot_byte = (int)lroundf(dot * 5);
    for (int k = 0; k < 4; k++) {
      snprintf(path, sizeof(path), "$.box[%d]", k);
      x.box[k] = num(t, path, 0);
    }
    double r = 0;
    x.arc = mg_json_get_num(t, "$.arc.r", &r) && r > 0;
    if (x.arc) {
      x.r = (float)r;
      x.cx = num(t, "$.arc.cx", dome_center);
      x.cy = num(t, "$.arc.cy", dome_center);
    }
    texts[text_count++] = x;
  }
}

static void callback(struct mg_connection* c, int ev, void* ev_data) {
  if (c != conn && ev != MG_EV_OPEN) return;
  if (ev == MG_EV_CONNECT) {
    mg_printf(c,
              "GET /live.json HTTP/1.1\r\nHost: %s\r\n"
              "Accept: application/json\r\nConnection: close\r\n\r\n",
              arena);
  } else if (ev == MG_EV_HTTP_MSG) {
    struct mg_http_message* hm = (struct mg_http_message*)ev_data;
    bool ok = mg_http_status(hm) == 200;
    if (ok) parse(hm->body);
    next_fetch_ms = SDL_GetTicks() + (ok ? BD_POLL_MS : BD_RETRY_MS);
    c->is_draining = 1;
    conn = NULL;
  } else if (ev == MG_EV_ERROR || ev == MG_EV_CLOSE) {
    if (c == conn) {
      next_fetch_ms = SDL_GetTicks() + BD_RETRY_MS;
      conn = NULL;
    }
  }
}

static void drop_conn(void) {
  if (conn) conn->is_closing = 1;
  conn = NULL;
}

void battledome_tick(tenv* env) {
  game_data* gdata = &env->usr->gdata;
  const char* now_arena = user_settings_arena(&env->usr->usrs);
  if (!now_arena) now_arena = "";

  if (strcmp(now_arena, arena) != 0) {
    drop_conn();
    forget();
    snprintf(arena, sizeof(arena), "%s", now_arena);
    /* host = everything before the last ':' (no IPv6 Battledome servers). */
    snprintf(host, sizeof(host), "%s", arena);
    char* colon = strrchr(host, ':');
    if (colon) *colon = '\0';
    on_bd = colon && host_listed(host);
    next_fetch_ms = 0;
  }
  if (!on_bd) return;

  Uint64 ms = SDL_GetTicks();
  if (conn && ms - conn_started_ms > BD_TIMEOUT_MS) {
    drop_conn();
    next_fetch_ms = ms + BD_RETRY_MS;
  }
  if (conn || ms < next_fetch_ms) return;

  char url[160];
  snprintf(url, sizeof(url), "http://%s/live.json", arena);
  conn_started_ms = ms;
  next_fetch_ms = ms + BD_RETRY_MS;
  conn = mg_http_connect(&gdata->network_manager, url, callback, env);
}

void battledome_close(tenv* env) {
  (void)env;
  drop_conn();
  forget();
  arena[0] = '\0';
  on_bd = false;
}

/* How far off the grid a pixel may sit, in cells. The wire places pellets
   to 300/256 of a unit (about 0.03 of the smallest cell); death food that
   merely shares a text's dot byte (68-76 are common in a Battledome) lands on
   the grid in both axes far less often. */
#define BD_GRID_SLACK 0.12f

static bool on_grid(float v) { return fabsf(v - roundf(v)) <= BD_GRID_SLACK; }

bool battledome_text_pixel(float x, float y, float sz, float* cell, bool* square) {
  if (!text_count) return false;
  int byte = (int)lroundf(sz * 5);
  for (int i = 0; i < text_count; i++) {
    const bd_text* t = texts + i;
    if (t->dot_byte != byte) continue;
    if (t->arc) {
      /* Seven rows straddle the ring, one cell apart (-3..3). The words turn,
         so only the ring is tested, never the box (a snapshot of a moving
         text). */
      float k = (hypotf(x - t->cx, y - t->cy) - t->r) / t->cell;
      if (fabsf(k) <= 3.0f + BD_GRID_SLACK && on_grid(k)) {
        *cell = t->cell;
        *square = false;
        return true;
      }
    } else {
      /* Pixels sit at box origin + (col, row) * cell. */
      float pad = t->cell * 0.5f;
      if (x >= t->box[0] - pad && x <= t->box[2] + pad &&
          y >= t->box[1] - pad && y <= t->box[3] + pad &&
          on_grid((x - t->box[0]) / t->cell) && on_grid((y - t->box[1]) / t->cell)) {
        *cell = t->cell;
        *square = true;
        return true;
      }
    }
  }
  return false;
}

bool battledome_dome(float* cx, float* cy, float* radius) {
  if (!on_bd || dome_radius <= 0) return false;
  *cx = dome_center;
  *cy = dome_center;
  *radius = dome_radius;
  return true;
}
