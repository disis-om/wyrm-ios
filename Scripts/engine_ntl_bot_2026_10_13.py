"""Wyrm's bot = NTL 9.68's bot (OM, 2026-10-13).

One source for both apps (the engine_sync_2026_10_12.py pattern): Wyrm
Android's tree gets this once (`python engine_ntl_bot_2026_10_13.py
"<Wyrm Android>"`), and prepare-original-engine.py applies it to the generated
iOS tree, so the bot is the same text on Android, iOS and Wyrm Desktop.

  - app/src/game/sbot.c is replaced whole: NTL's `tf` bot (grow / tocircle /
    circle, its sectors, timers, coil and numbers), the Smart bot always on,
    surrounded = flee with boost always, and Wyrm's border guard kept.
  - "Bot radius" (NTL's `de`) defaults to NTL's 12 (was 20); "Circle after
    score" reaches NTL's 50000; both rows say what they do.
"""

import sys
from pathlib import Path

NEW_FILES = {}
PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


NEW_FILES["app/src/game/sbot.c"] = r'''#include "sbot.h"

#include <SDL3/SDL.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "../user.h"

/*
 * Wyrm's bot = NTL 9.68's bot, line for line (OM, 2026-10-13). NTL's object
 * `tf` in main-mt.js, with the Smart bot always on: below "Circle after
 * score" it eats (grow), above it turns until its head meets its own body
 * (tocircle), then it coils around itself (circle) and keeps the coil clear
 * of other snakes and the wall, tightening it on a snake caught inside.
 *
 * NTL's own numbers: 16 sectors of 22.5 degrees, danger circle = the "Bot
 * radius" setting (NTL's `de`, 12) x half the snake's width ahead of the head,
 * food picked every 200 ms and 1 s after a dodge (wall-clock timers, not
 * frames), snake width 29.2 x sc, NTL's fast atan2 (`xf`), the coil's
 * offsets .38 / .22 / -.8 / .16. NTL's code is quoted by its names in the
 * comments (`Ue`, `pe`, `Xe`, `Vf`, `fe`, `Re`...).
 *
 * Wyrm keeps three things of its own:
 *  - the border guard (`avoid_border_emergency`, OM 2026-10-12): it outranks
 *    every state and turns the snake back inward before it reaches the wall;
 *  - the wall is measured from the head, not the eased camera, and obeys the
 *    server's border while a shrink is still easing on screen;
 *  - surrounded = flee with boost, always (OM): NTL boosts only when the
 *    snake surrounding it is boosting. Coiled, NTL never looked; Wyrm checks
 *    for one snake wrapped round it (its points outside our own coil) and
 *    breaks out with boost too.
 *  And one fix: NTL's open-gap search (`Xe`) loses a gap that starts at
 *  sector 0 (JavaScript treats the index 0 as false); Wyrm keeps it.
 */

#define NTL_ARC ((double)M_PI / 8.0)       /* re */
#define NTL_ARCS 16                        /* Pe = 2 PI / re */
#define NTL_FOOD_MS 200                    /* 1000 / oe(25) * we(5) */
#define NTL_DANGER_MS 1000                 /* 1000 / oe(25) * ue(25) */
#define NTL_SPEED_BASE 5.78                /* le */
#define NTL_FRONT ((double)M_PI / 2.0)     /* Qe */
#define NTL_ENCIRCLE_ONE 0.5               /* be */
#define NTL_ENCIRCLE_ALL 0.5               /* Be */
#define NTL_ENCIRCLE_DIST 30.0             /* De */
#define NTL_VIEW_BOX 2400.0                /* Ie */
#define NTL_WALL_NEAR 3500.0
#define NTL_WALL_LEAN 1650.0
#define NTL_TOCIRCLE_TURN 25.0             /* I8 */
#define NTL_NECK_SHARE 0.85                /* h8 */
#define NTL_GT 0.38
#define NTL_NT 0.22
#define NTL_TT (-0.8)
#define NTL_ST 0.16
#define NTL_WIDTH 29.2                     /* Df: Math.round(29.2 * k) */

enum { BOT_GROW = 0, BOT_TOCIRCLE = 1, BOT_CIRCLE = 2 };

#define MAX_BODY_PTS 8192
#define MAX_SE 2048
#define MAX_HULL 16
#define MAX_INSIDE 4096

typedef struct {
  double x, y;
} v2;
typedef struct {
  double x, y, r;
} circ;
typedef struct {
  double x, y, ang;
} hit;

/* tf.ie: the nearest thing in each sector. */
typedef struct {
  double x, y, ang, d2, r;
  int si;
} sector;
/* tf.se: things close enough to touch the danger circle. */
typedef struct {
  double x, y, d2, r;
  int si;
  bool head;
} cpt;
/* tf.Wf: the food in each sector. */
typedef struct {
  double x, y, ang, da, d2, sz, score;
} fsector;
typedef struct {
  double x, y, len;
} bpt;
typedef struct {
  v2* pts;
  int n;
  double minx, maxx, miny, maxy;
} poly;

typedef struct {
  int id;
  int state;
  int dir;              /* tf.Hf.ee: which way the coil turns */
  uint64_t action_at;   /* tf.actionTimeout: 0 = none */
  v2 goal;              /* fA */
  bool boost;

  /* every(): this frame */
  double hx, hy, fx, fy, ang, aang, ca, sa;
  double speed_mult, radius, width, de;
  int len_score;
  double centre, pts_r, prox_r, gu, iu, he;
  v2 follow;
  circ ne, side_r, side_l;
  double box_x, box_y, box_w, box_h;

  sector ie[NTL_ARCS];
  bool ie_set[NTL_ARCS];
  cpt se[MAX_SE];
  int se_n;
  fsector wf[NTL_ARCS];
  bool wf_set[NTL_ARCS];

  bpt X[MAX_BODY_PTS];
  int xn;
  double xlen;
} bot_state;

static bot_state B;
static v2 inside_buf[MAX_INSIDE];
static v2 hull_buf[MAX_HULL];

/* What one bot remembers between frames (the rest is worked out each frame). */
typedef struct {
  int id, state, dir;
  uint64_t action_at;
  v2 goal;
} bot_mind;

typedef struct {
  bool used;
  int id;
  bot_mind mind;
} ai_bot_context;

static bot_mind mind_of(void) { return (bot_mind){B.id, B.state, B.dir, B.action_at, B.goal}; }
static void mind_to(bot_mind m) {
  B.id = m.id;
  B.state = m.state;
  B.dir = m.dir;
  B.action_at = m.action_at;
  B.goal = m.goal;
}

static ai_bot_context ai_contexts[15];

/* ------------------------------------------------------------ helpers */

static inline double js_round(double v) { return floor(v + 0.5); }

static inline double dist2(double ax, double ay, double bx, double by) {
  double dx = ax - bx, dy = ay - by;
  return dx * dx + dy * dy;
}

/* dA.xf: NTL's fast atan2(y, x). */
static double ntl_atan2(double y, double x) {
  double c = M_PI / 4.0;
  double g = fabs(y) + 1e-10;
  double r;
  if (x < 0) {
    r = (x + g) / (g - x);
    c = 3.0 * M_PI / 4.0;
  } else {
    r = (x - g) / (x + g);
  }
  c += (0.1963 * r * r - 0.9817) * r;
  return y < 0 ? -c : c;
}

/* tf.xe: the signed angle between two headings, NTL's way. */
static double ang_between(double a, double b) {
  double r1 = fmod(a - b, M_PI);
  double r2 = fmod(b - a, M_PI);
  return r1 < r2 ? -r1 : r2;
}

/* tf.ae: sector of an angle. */
static int sector_of(double a) {
  if (a < 0) a += 2.0 * M_PI;
  int i = (int)js_round(a / NTL_ARC);
  return i == NTL_ARCS ? 0 : i;
}

/* dA.Rf: a circle with rounded centre and radius. */
static inline circ rcirc(double x, double y, double r) {
  return (circ){js_round(x), js_round(y), js_round(r)};
}

/* dA.Yf: do two circles touch; where, and at what angle from the head. */
static bool circles_touch(circ a, circ b, hit* out) {
  double cb = a.r + b.r;
  if (!(a.x + cb > b.x && a.y + cb > b.y && a.x < b.x + cb && a.y < b.y + cb &&
        dist2(a.x, a.y, b.x, b.y) < cb * cb))
    return false;
  if (out) {
    out->x = (a.x * b.r + b.x * a.r) / cb;
    out->y = (a.y * b.r + b.y * a.r) / cb;
    out->ang = ntl_atan2(out->y - B.hy, out->x - B.hx);
  }
  return true;
}

static inline v2 unit_vec(v2 v) {
  double l = sqrt(v.x * v.x + v.y * v.y);
  return l > 0 ? (v2){v.x / l, v.y / l} : (v2){0, 0};
}

/* dA.Uf */
static inline double cross3(v2 o, v2 a, v2 b) {
  return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

static int hull_cmp(const void* pa, const void* pb) {
  const v2* a = pa;
  const v2* b = pb;
  double d = a->x == b->x ? a->y - b->y : a->x - b->x; /* dA.kf */
  return (d > 0) - (d < 0);
}

/* dA.If: Andrew's monotone chain. */
static int convex_hull(v2* pts, int n, v2* out) {
  qsort(pts, n, sizeof(v2), hull_cmp);
  v2 lo[MAX_HULL], up[MAX_HULL];
  int nl = 0, nu = 0;
  for (int i = 0; i < n; i++) {
    while (nl >= 2 && cross3(lo[nl - 2], lo[nl - 1], pts[i]) <= 0) nl--;
    lo[nl++] = pts[i];
  }
  for (int i = n - 1; i >= 0; i--) {
    while (nu >= 2 && cross3(up[nu - 2], up[nu - 1], pts[i]) <= 0) nu--;
    up[nu++] = pts[i];
  }
  nu--;
  nl--;
  int k = 0;
  for (int i = 0; i < nl; i++) out[k++] = lo[i];
  for (int i = 0; i < nu; i++) out[k++] = up[i];
  return k;
}

/* dA.yf: a polygon with its box. */
static void poly_box(poly* p) {
  p->minx = p->maxx = p->pts[0].x;
  p->miny = p->maxy = p->pts[0].y;
  for (int i = 1; i < p->n; i++) {
    if (p->pts[i].x < p->minx) p->minx = p->pts[i].x;
    if (p->pts[i].x > p->maxx) p->maxx = p->pts[i].x;
    if (p->pts[i].y < p->miny) p->miny = p->pts[i].y;
    if (p->pts[i].y > p->maxy) p->maxy = p->pts[i].y;
  }
}

/* dA.Gf: is the point inside the polygon. */
static bool in_poly(v2 p, const poly* pb) {
  if (pb->n < 1) return false;
  if (p.x < pb->minx || p.x > pb->maxx || p.y < pb->miny || p.y > pb->maxy)
    return false;
  bool c = false;
  for (int i = 0, j = pb->n - 1; i < pb->n; j = i++) {
    if ((pb->pts[i].y > p.y) != (pb->pts[j].y > p.y) &&
        p.x < (pb->pts[j].x - pb->pts[i].x) * (p.y - pb->pts[i].y) /
                      (pb->pts[j].y - pb->pts[i].y) +
                  pb->pts[i].x)
      c = !c;
  }
  return c;
}

static snake* find_me(game_data* gdata) {
  int ns = tdarray_length(gdata->data.snakes);
  for (int i = 0; i < ns; i++)
    if (gdata->data.snakes[i].id == B.id) return gdata->data.snakes + i;
  return NULL;
}

/* During a shrink the renderer eases flux_grd over several frames, but the
   server's border (real_flux_grd) has already moved: the bot obeys the smaller
   (OM, 2026-10-12, from the reference client). */
static inline double safe_border_radius(const game_data* gdata) {
  double smoothed = gdata->data.flux_grd;
  double server = gdata->data.real_flux_grd;
  if (server > 0.0 && (smoothed <= 0.0 || server < smoothed)) return server;
  return smoothed;
}

/* tf.Df: a snake's width. */
static inline double ntl_width(double sc) { return js_round(NTL_WIDTH * sc); }

static int snake_score(game_data* gdata, snake* sk) {
  if (sk->sct < 0 || sk->fam < 0 || sk->rsc < 0) return 0;
  int sct = sk->sct + sk->rsc;
  return (int)(15.0f * (gdata->data.fpsls[sct] +
                        sk->fam / gdata->data.fmlts[sct] - 1) -
               5);
}

/* ------------------------------------------------------------ steering */

/* tf.He: head for an absolute angle. */
static void head_for(double a) {
  B.goal = (v2){js_round(B.hx + B.ne.r * cos(a)), js_round(B.hy + B.ne.r * sin(a))};
}

/* tf.te: turn by an angle from where the snake heads. */
static void turn_by(double a) {
  double ex = B.hx + 500.0 * B.ca, ey = B.hy + 500.0 * B.sa;
  double c = cos(-a), s = sin(-a);
  B.goal = (v2){js_round(c * (ex - B.hx) - s * (ey - B.hy) + B.hx),
                js_round(s * (ex - B.hx) + c * (ey - B.hy) + B.hy)};
}

/* tf.Ce: away from a touch point, to the side it is not on. */
static void avoid(hit h) {
  v2 a = {B.hx, B.hy}, b = {B.hx + 2000.0 * B.ca, B.hy + 2000.0 * B.sa};
  v2 p = {h.x, h.y};
  if (cross3(a, b, p) > 0)
    head_for(h.ang - M_PI);
  else
    head_for(h.ang + M_PI);
}

/* tf.me: is the point in front of the head. */
static bool in_front(hit h) {
  double a = ntl_atan2(js_round(h.y - B.hy), js_round(h.x - B.hx));
  return fabs(ang_between(a, B.aang)) < NTL_FRONT;
}

/* ------------------------------------------------------------ every */

static bool every(game_data* gdata) {
  int ns = tdarray_length(gdata->data.snakes);
  if (ns == 0) return false;
  snake* me = find_me(gdata);
  if (!me) {
    /* A new life (or the first): NTL starts each game growing (U8). */
    me = gdata->data.snakes + (ns - 1);
    int keep_dir = B.dir ? B.dir : 1;
    B.id = me->id;
    B.state = BOT_GROW;
    B.action_at = 0;
    B.dir = keep_dir;
    B.goal = (v2){me->xx + cos(me->ang) * 500.0, me->yy + sin(me->ang) * 500.0};
  }

  B.centre = gdata->data.grd;
  B.he = 0.98 * gdata->data.grd;
  B.pts_r = safe_border_radius(gdata);
  if (B.pts_r <= 0) B.pts_r = B.he;
  /* H9: the server is shrinking the arena; then its radius (Xl) is the wall. */
  bool shrinking = gdata->data.real_flux_grd > 0 &&
                   gdata->data.real_flux_grd < gdata->data.grd * 0.98 - 1.0;
  B.prox_r = shrinking ? B.pts_r : B.centre;

  B.hx = me->xx;
  B.hy = me->yy;
  B.fx = me->fx;
  B.fy = me->fy;
  B.ang = me->ang;
  B.aang = me->ehang;
  B.ca = cos(B.ang);
  B.sa = sin(B.ang);
  /* gu / iu: from the head, not the eased camera (Wyrm). */
  B.gu = sqrt(dist2(B.hx, B.hy, B.centre, B.centre));
  B.iu = atan2(B.hy - B.centre, B.hx - B.centre);
  B.follow = fabs(B.centre - B.gu) < NTL_WALL_NEAR
                 ? (v2){B.centre + cos(B.iu + 64.0 * B.dir / B.centre) * B.he,
                        B.centre + sin(B.iu + 64.0 * B.dir / B.centre) * B.he}
                 : (v2){B.centre, B.centre};
  B.box_x = js_round(B.hx - NTL_VIEW_BOX / 2);
  B.box_y = js_round(B.hy - NTL_VIEW_BOX / 2);
  B.box_w = B.box_h = NTL_VIEW_BOX;
  B.speed_mult = me->sp / NTL_SPEED_BASE;
  B.width = ntl_width(me->sc);
  B.radius = B.width / 2.0;
  B.len_score = snake_score(gdata, me);
  double k = fmin(1.0, B.speed_mult - 1.0);
  B.ne = rcirc(B.hx + B.ca * k * B.de / 2.0 * B.radius,
               B.hy + B.sa * k * B.de / 2.0 * B.radius, B.de / 2.0 * B.radius);
  /* The side circles sit beside the neck (snake.Bf, the newest point). */
  int pn = tdarray_length(me->pts);
  double nx = B.hx, ny = B.hy;
  if (pn > 0) {
    nx = me->pts[pn - 1].xx;
    ny = me->pts[pn - 1].yy;
  }
  B.side_r = rcirc(nx - B.sa * B.width, ny + B.ca * B.width, B.width * B.speed_mult);
  B.side_l = rcirc(nx + B.sa * B.width, ny - B.ca * B.width, B.width * B.speed_mult);
  return !me->dead;
}

/* ------------------------------------------------------------ danger: Ye, Ue */

/* tf.je: the nearest thing per sector (NTL compares the new raw distance
   with the stored, already shortened one; kept). */
static void note_sector(double x, double y, double d2, double r, int si) {
  double a = ntl_atan2(js_round(y - B.hy), js_round(x - B.hx));
  int s = sector_of(a);
  double gap = sqrt(d2) - r;
  double adj = js_round(gap * gap);
  if (!B.ie_set[s] || B.ie[s].d2 > d2) {
    B.ie[s] = (sector){js_round(x), js_round(y), a, adj, r, si};
    B.ie_set[s] = true;
  }
}

static inline bool in_box(double x, double y) {
  return B.box_x <= x && B.box_y <= y && B.box_x + B.box_w >= x && B.box_y + B.box_h >= y;
}

static int se_cmp(const void* a, const void* b) {
  double da = ((const cpt*)a)->d2, db = ((const cpt*)b)->d2;
  return (da > db) - (da < db);
}

static void push_se(cpt p) {
  if (B.se_n < MAX_SE) B.se[B.se_n++] = p;
}

/* tf.Ye: every snake's head and nearby body, and the wall. */
static void gather(game_data* gdata) {
  B.se_n = 0;
  memset(B.ie_set, 0, sizeof(B.ie_set));
  int ns = tdarray_length(gdata->data.snakes);
  for (int i = 0; i < ns; i++) {
    snake* s = gdata->data.snakes + i;
    if (s->id == B.id || s->dead) continue;
    double er = ntl_width(s->sc) / 2.0;
    double g = fmin(1.0, s->sp / NTL_SPEED_BASE - 1.0);
    double hx = s->xx + cos(s->ehang) * er * g * B.de / 2.0;
    double hy = s->yy + sin(s->ehang) * er * g * B.de / 2.0;
    double hd2 = dist2(B.hx, B.hy, hx, hy);
    note_sector(hx, hy, hd2, B.ne.r, i);
    push_se((cpt){hx, hy, hd2, B.ne.r, i, true});
    int pn = tdarray_length(s->pts);
    for (int j = 0; j < pn; j++) {
      body_part* po = s->pts + j;
      if (po->dying || !in_box(po->xx, po->yy)) continue;
      double d2 = dist2(B.hx, B.hy, po->xx, po->yy);
      note_sector(po->xx, po->yy, d2, er, i);
      double reach = B.ne.r + er;
      if (d2 <= reach * reach) push_se((cpt){po->xx, po->yy, d2, er, i, false});
    }
  }
  /* The wall, as NTL draws it: a point every 8 units along 2000 of it.
     Tagged -1 (NTL tagged it snake 0, which counted the wall as that snake). */
  if (fabs(B.prox_r - B.gu) < NTL_WALL_NEAR) {
    for (int b = -1000; b <= 1000; b += 8) {
      double wx = B.centre + cos(B.iu + b / B.centre) * B.pts_r;
      double wy = B.centre + sin(B.iu + b / B.centre) * B.pts_r;
      double d2 = dist2(B.hx, B.hy, wx, wy);
      note_sector(wx, wy, d2, 8.0, -1);
      push_se((cpt){wx, wy, d2, 8.0, -1, false});
    }
  }
  qsort(B.se, B.se_n, sizeof(cpt), se_cmp);
}

/* tf.Ue: something touches the danger circle in front: steer away. A
   boosting snake's head makes it boost away too. */
static bool dodge(game_data* gdata) {
  gather(gdata);
  if (B.se_n == 0) return false;
  for (int i = 0; i < B.se_n; i++) {
    cpt* p = B.se + i;
    hit h;
    if (circles_touch(B.ne, rcirc(p->x, p->y, p->r), &h) && in_front(h)) {
      B.boost = p->si >= 0 && p->head && gdata->data.snakes[p->si].sp > 10.0f;
      avoid(h);
      return true;
    }
  }
  B.boost = false;
  return false;
}

/* tf.Xe: head for the middle of the widest open gap, else the farthest thing. */
static void widest_gap(void) {
  typedef struct {
    int s, e, sz;
  } gap;
  gap opens[NTL_ARCS];
  int no = 0, start = -1;
  int far_i = -1;
  double far_d = 0;
  for (int i = 0; i < NTL_ARCS; i++) {
    double d;
    if (!B.ie_set[i]) {
      d = 0;
      if (start < 0) start = i;
    } else {
      d = B.ie[i].d2;
      if (start >= 0) {
        opens[no++] = (gap){start, i - 1, i - 1 - start};
        start = -1;
      }
    }
    if (far_i < 0 || (far_d < d && far_d != 0)) {
      far_d = d;
      far_i = i;
    }
  }
  if (start >= 0) {
    if (no > 0) {
      opens[0].s = start;
      opens[0].sz = opens[0].e - start;
      if (opens[0].sz < 0) opens[0].sz += NTL_ARCS;
    } else {
      opens[no++] = (gap){start, start, 0};
    }
  }
  if (no > 0) {
    /* Stable, widest first (JavaScript's sort). */
    int best = 0;
    for (int i = 1; i < no; i++)
      if (opens[i].sz > opens[best].sz) best = i;
    head_for((opens[best].e - opens[best].sz / 2.0) * NTL_ARC);
  } else {
    head_for(far_i * NTL_ARC);
  }
}

/* tf.pe: surrounded — by one snake over half the sectors, or by anything
   close in over half of them. Wyrm: always flee with boost. */
static bool surrounded(game_data* gdata) {
  (void)gdata;
  int count[1024];
  memset(count, 0, sizeof(count));
  int most = 0, close = 0;
  for (int i = 0; i < NTL_ARCS; i++) {
    if (!B.ie_set[i]) continue;
    int si = B.ie[i].si;
    if (si >= 0 && si < 1024 && ++count[si] > most) most = count[si];
    double near = B.radius * NTL_ENCIRCLE_DIST;
    if (B.ie[i].d2 < near * near) close++;
  }
  if (most > NTL_ARCS * NTL_ENCIRCLE_ONE || close > NTL_ARCS * NTL_ENCIRCLE_ALL) {
    widest_gap();
    B.boost = true;
    return true;
  }
  B.boost = false;
  return false;
}

/* ------------------------------------------------------------ food: Vf, Zf */

static void note_food(double fx, double fy, double fsz) {
  double a = ntl_atan2(js_round(fy - B.hy), js_round(fx - B.hx));
  int s = sector_of(a);
  double d2 = dist2(B.hx, B.hy, fx, fy);
  if (B.ie_set[s] &&
      !(sqrt(B.ie[s].d2) > sqrt(d2) + B.radius * B.de * B.speed_mult / 2.0))
    return;
  double score = fsz * fsz / d2;
  if (!B.wf_set[s]) {
    B.wf[s] = (fsector){js_round(fx), js_round(fy), a, fabs(ang_between(a, B.aang)),
                        d2, fsz, score};
    B.wf_set[s] = true;
  } else {
    fsector* f = B.wf + s;
    f->sz += js_round(fsz);
    f->score += score;
    if (f->d2 > d2) {
      f->x = js_round(fx);
      f->y = js_round(fy);
      f->d2 = d2;
    }
  }
}

/* tf.Vf: the best food cluster, or the middle of the arena. */
static void pick_food(game_data* gdata) {
  memset(B.wf_set, 0, sizeof(B.wf_set));
  int fn = tdarray_length(gdata->data.foods);
  for (int i = fn - 1; i >= 0; i--) {
    food* fo = gdata->data.foods + i;
    if (fo->eaten) continue;
    circ fc = rcirc(fo->xx, fo->yy, 2.0);
    if (circles_touch(fc, B.side_l, NULL) || circles_touch(fc, B.side_r, NULL)) continue;
    note_food(fo->xx, fo->yy, fo->sz);
  }
  int best = -1;
  for (int i = 0; i < NTL_ARCS; i++)
    if (B.wf_set[i] && (best < 0 || B.wf[i].score > B.wf[best].score)) best = i;
  if (best >= 0 && B.wf[best].sz > 0)
    B.goal = (v2){B.wf[best].x, B.wf[best].y};
  else
    B.goal = (v2){B.centre, B.centre};
}

/* ------------------------------------------------------------ tocircle: fe */

static void to_circle(game_data* gdata) {
  snake* me = find_me(gdata);
  if (!me) return;
  int pn = tdarray_length(me->pts);
  int t = 0;
  while (t < pn && me->pts[t].dying) t++;
  B.boost = false;
  double k = fmin(100.0, B.width);
  k = (double)(int)(k / 100.0 * NTL_TOCIRCLE_TURN);
  if (k < 8) k = 8;
  turn_by(B.dir * M_PI / k);
  if (t >= pn) return;
  circ tail = rcirc(me->pts[t].xx, me->pts[t].yy, (double)(int)(B.ne.r / 2.0));
  if (circles_touch(B.ne, tail, NULL)) B.state = BOT_CIRCLE;
  circ head = rcirc(B.hx, B.hy, (double)(int)(B.width / 2.0));
  for (int i = 0; i < pn * NTL_NECK_SHARE; i++) {
    if (me->pts[i].dying) continue;
    if (circles_touch(head, rcirc(me->pts[i].xx, me->pts[i].yy, (double)(int)(B.width / 2.0)), NULL)) {
      B.state = BOT_CIRCLE;
      break;
    }
  }
}

/* ------------------------------------------------------------ circle: Re */

/* tf.Ee: our own body as a line from the head, with its length along it. */
static void own_body(game_data* gdata) {
  B.xn = 0;
  B.xlen = 0;
  snake* me = find_me(gdata);
  if (!me) return;
  double bx = B.hx + B.fx, by = B.hy + B.fy, l = 0;
  B.X[B.xn++] = (bpt){bx, by, 0};
  for (int p = tdarray_length(me->pts) - 1; p >= 0 && B.xn < MAX_BODY_PTS; p--) {
    body_part* po = me->pts + p;
    if (po->dying) continue;
    double gx = po->xx + po->fx, gy = po->yy + po->fy;
    l += sqrt(dist2(bx, by, gx, gy));
    B.X[B.xn++] = (bpt){gx, gy, l};
    bx = gx;
    by = gy;
  }
  B.xlen = l;
}

/* tf.Oe: the point [t] along our body. */
static v2 body_at(double t) {
  if (t >= B.xlen) return (v2){B.X[B.xn - 1].x, B.X[B.xn - 1].y};
  if (t <= 0) return (v2){B.X[0].x, B.X[0].y};
  int lo = 0, hi = B.xn - 1;
  while (1 < hi - lo) {
    int m = (int)js_round((lo + hi) / 2.0);
    if (t > B.X[m].len)
      lo = m;
    else
      hi = m;
  }
  double wp = B.X[hi].len - t, wq = t - B.X[lo].len, w = wp + wq;
  if (w == 0) return (v2){B.X[lo].x, B.X[lo].y};
  return (v2){(wp * B.X[lo].x + wq * B.X[hi].x) / w,
              (wp * B.X[lo].y + wq * B.X[hi].y) / w};
}

/* tf.Me: how far along our body its closest point to the head is. */
static double closest_along(void) {
  double bx = B.hx + B.fx, by = B.hy + B.fy;
  int n = B.xn, e = 0;
  double g = 0;
  if (n < 3) return B.xlen;
  for (;;) {
    double prev = g;
    e++;
    g = dist2(bx, by, B.X[e].x, B.X[e].y);
    if (g < prev || e == n - 1) break;
  }
  if (e >= n || e <= 1) return B.xlen;
  for (int i = e + 1; i < n; i++) {
    double d = dist2(bx, by, B.X[i].x, B.X[i].y);
    if (d < g) {
      e = i;
      g = d;
    }
  }
  int c;
  double bd;
  if (e == n - 1) {
    c = e - 1;
    bd = dist2(bx, by, B.X[c].x, B.X[c].y);
  } else {
    double dm = dist2(bx, by, B.X[e - 1].x, B.X[e - 1].y);
    double dp = dist2(bx, by, B.X[e + 1].x, B.X[e + 1].y);
    if (dm < dp) {
      c = e - 1;
      bd = dm;
    } else {
      c = e + 1;
      bd = dp;
    }
  }
  double a = B.X[e].len - B.X[c].len;
  a *= a;
  if (a == 0) return B.X[e].len;
  return (B.X[e].len * (a - (g - bd)) + B.X[c].len * (a + (g - bd))) / (2 * a);
}

/* tf.Je: which way to coil — away from the body's middle. */
static void coil_direction(void) {
  double cx = 0, cy = 0;
  for (int i = 0; i < B.xn; i++) {
    cx += B.X[i].x;
    cy += B.X[i].y;
  }
  cx = B.hx + B.fx - cx / B.xn;
  cy = B.hy + B.fy - cy / B.xn;
  B.dir = 0 < -cy * B.ca + cx * B.sa ? -1 : 1;
}

/* tf.Le: the zone our next turn sweeps, grown by [off]. */
static void danger_zone(double off, v2 target, v2 norm, double close_dist, v2 past,
                        v2 close_pt, poly* out) {
  double hx = B.hx + B.fx, hy = B.hy + B.fy, w = B.width, ca = B.ca, sa = B.sa;
  int o = B.dir;
  v2 raw[10] = {
      {hx - o * off * sa, hy + o * off * ca},
      {hx + w * ca + off * (ca - o * sa), hy + w * sa + off * (sa + o * ca)},
      {hx + 1.75 * w * ca + 0.3 * o * w * sa + off * (ca - o * sa),
       hy + 1.75 * w * sa - 0.3 * o * w * ca + off * (sa + o * ca)},
      {hx + 2.5 * w * ca + 0.7 * o * w * sa + off * (ca - o * sa),
       hy + 2.5 * w * sa - 0.7 * o * w * ca + off * (sa + o * ca)},
      {hx + 3 * w * ca + 1.2 * o * w * sa + off * ca,
       hy + 3 * w * sa - 1.2 * o * w * ca + off * sa},
      {target.x + norm.x * (off + 0.5 * fmax(close_dist, 0)),
       target.y + norm.y * (off + 0.5 * fmax(close_dist, 0))},
      {past.x + norm.x * off, past.y + norm.y * off},
      past,
      target,
      close_pt,
  };
  out->pts = hull_buf;
  out->n = convex_hull(raw, 10, hull_buf);
  poly_box(out);
}

/* Coiled, a snake wrapped round us (Wyrm, OM 2026-10-13): one snake's points
   outside our own coil fill more than half the sectors. Then break out of the
   coil to the widest gap, with boost. */
static bool wrapped_round(game_data* gdata, const poly* inside) {
  memset(B.ie_set, 0, sizeof(B.ie_set));
  int ns = tdarray_length(gdata->data.snakes);
  int most = 0;
  for (int i = 0; i < ns; i++) {
    snake* s = gdata->data.snakes + i;
    if (s->id == B.id || s->dead) continue;
    bool mine[NTL_ARCS] = {0};
    int count = 0;
    double er = ntl_width(s->sc) / 2.0;
    int pn = tdarray_length(s->pts);
    for (int j = -1; j < pn; j++) {
      double x, y, r;
      if (j < 0) {
        x = s->xx;
        y = s->yy;
        r = B.ne.r;
      } else {
        body_part* po = s->pts + j;
        if (po->dying) continue;
        x = po->xx;
        y = po->yy;
        r = er;
      }
      if (!in_box(x, y) || in_poly((v2){x, y}, inside)) continue;
      note_sector(x, y, dist2(B.hx, B.hy, x, y), r, i);
      int sec = sector_of(ntl_atan2(js_round(y - B.hy), js_round(x - B.hx)));
      if (!mine[sec]) {
        mine[sec] = true;
        count++;
      }
    }
    if (count > most) most = count;
  }
  if (most <= NTL_ARCS * NTL_ENCIRCLE_ONE) return false;
  widest_gap();
  B.boost = true;
  B.state = BOT_TOCIRCLE;
  return true;
}

/* tf.Re: follow our own body round, keeping the coil clear. */
static void coil(game_data* gdata) {
  own_body(gdata);
  if (B.xn < 2) return;
  coil_direction();
  int o = B.dir;
  double w = B.width;
  if (B.xlen < 9 * w) return;
  double ax = B.hx + B.fx, ay = B.hy + B.fy;
  double eb = closest_along();
  v2 close_pt = body_at(eb);
  v2 tang = body_at(eb - w);
  tang = unit_vec((v2){tang.x - close_pt.x, tang.y - close_pt.y});
  v2 norm = {-o * tang.y, o * tang.x};
  double course = asin(fmax(-1, fmin(1, B.ca * norm.x + B.sa * norm.y)));
  double close_dist = (ax - close_pt.x) * norm.x + (ay - close_pt.y) * norm.y;

  /* The inside of our coil. */
  poly inside = {inside_buf, 0, 0, 0, 0, 0};
  double from = 5 * w, to = eb + 5 * w;
  inside_buf[inside.n++] = body_at(to);
  inside_buf[inside.n++] = body_at(from);
  for (double t = from; t < to && inside.n < MAX_INSIDE; t += w) inside_buf[inside.n++] = body_at(t);
  poly_box(&inside);

  if (wrapped_round(gdata, &inside)) return;

  double target_t = eb, target_far = 0, step = w / 64;
  for (double h = close_dist, a = course; h >= 0.125 * w;) {
    target_t -= step;
    target_far += step * cos(a);
    h += step * sin(a);
    a = fmax(-M_PI / 4, a - step / w);
  }
  v2 target = body_at(target_t);
  v2 past = body_at(target_t - 3 * w);

  bool head_inside = false;
  double enemy_head = 4096 * w * w;
  double body_off = 0.15 * w;
  int ns = tdarray_length(gdata->data.snakes);
  for (int i = 0; i < ns; i++) {
    snake* s = gdata->data.snakes + i;
    if (s->id == B.id || s->dead) continue;
    v2 eh = {s->xx + s->fx, s->yy + s->fy};
    v2 ea = {eh.x + cos(s->ang) * w, eh.y + sin(s->ang) * w};
    if (in_poly(eh, &inside))
      head_inside = true;
    else
      enemy_head = fmin(enemy_head, fmin(dist2(eh.x, eh.y, target.x, target.y),
                                         dist2(ea.x, ea.y, target.x, target.y)));
    bool zone_set = false;
    poly zone = {hull_buf, 0, 0, 0, 0, 0};
    double ew = ntl_width(s->sc);
    int pn = tdarray_length(s->pts);
    for (int j = 0; j < pn; j++) {
      body_part* po = s->pts + j;
      if (po->dying) continue;
      v2 p = {po->xx + po->fx, po->yy + po->fy};
      /* Inside our coil it is our prey, not a wall. */
      if (in_poly(p, &inside)) continue;
      while (!zone_set || (body_off >= -w && in_poly(p, &zone))) {
        if (zone_set)
          body_off -= 0.0625 * w;
        else
          zone_set = true;
        danger_zone(NTL_GT * (w + ew) + body_off, target, norm, close_dist, past, close_pt, &zone);
      }
    }
  }
  enemy_head = sqrt(enemy_head);

  double wall_off = 0.25 * w;
  bool wall_near = fabs(B.prox_r - B.gu) < NTL_WALL_NEAR;
  if (wall_near) {
    bool zone_set = false;
    poly zone = {hull_buf, 0, 0, 0, 0, 0};
    for (int b = -1000; b <= 1000; b += 8) {
      v2 p = {B.centre + cos(B.iu + b / B.centre) * B.pts_r,
              B.centre + sin(B.iu + b / B.centre) * B.pts_r};
      while (!zone_set || (wall_off >= -w && in_poly(p, &zone))) {
        if (zone_set)
          wall_off -= 0.0625 * w;
        else
          zone_set = true;
        danger_zone(NTL_NT * (w + wall_off), target, norm, close_dist, past, close_pt, &zone);
      }
    }
  }

  double gb = course;
  if (fabs(B.centre - B.gu) < NTL_WALL_LEAN) gb += 0.25;
  double hp = -1 - (2 * target_far - enemy_head) / w;
  gb = fmin(gb, hp > 0 ? 0.125 * hp * hp : -0.5 * hp * hp);
  bool body_cut = false;
  double body_course = 0;
  if ((body_off - 0.0625 * w) / w < 0) {
    body_cut = true;
    body_course = gb += (body_off - 0.0625 * w) / w;
  }
  if (wall_near) gb = fmin(gb, gb + (wall_off - 0.0625 * w) / w);
  double tail = B.xlen - eb;
  v2 to_target = unit_vec((v2){B.follow.x - ax, B.follow.y - ay});
  gb = fmin(gb, (tail - w * (2 - 0.5 * (to_target.x * norm.x + to_target.y * norm.y)) + (w - close_dist)) / w);
  gb = fmin(gb, -0.5 * (close_dist - (head_inside ? 1 : 4) * w) / w);
  gb = fmax(gb, NTL_TT * close_dist / w);
  gb = fmin(gb, 1);
  if (body_cut && gb > body_course) gb -= NTL_ST;

  double gx = ax + 4 * (tang.x * cos(gb) - o * tang.y * sin(gb)) * w;
  double gy = ay + 4 * (tang.y * cos(gb) + o * tang.x * sin(gb)) * w;
  if (fabs(gx - B.goal.x) < 1000 && fabs(gy - B.goal.y) < 1000)
    B.goal = (v2){js_round(0.25 * gx + 0.75 * B.goal.x), js_round(0.25 * gy + 0.75 * B.goal.y)};
  else
    B.goal = (v2){js_round(gx), js_round(gy)};
}

/* ------------------------------------------------------------ the border (Wyrm) */

/* Border safety outranks every state (OM, 2026-10-12, from the reference
   client): a coiling snake could follow its own body into the wall. This
   predictive guard breaks the food or coil state early and turns towards a
   safe point inward. */
static bool avoid_border_emergency(game_data* gdata) {
  const double border_radius = safe_border_radius(gdata);
  const double center = gdata->data.grd;
  if (border_radius <= 0.0 || center <= 0.0) return false;

  double dx = B.hx - center;
  double dy = B.hy - center;
  double dist = sqrt(dx * dx + dy * dy);
  if (dist < 1.0) return false;

  double outward_x = dx / dist;
  double outward_y = dy / dist;
  double clearance = border_radius - dist - B.radius;
  double guard = fmax(700.0, B.ne.r + B.width * (4.0 + B.speed_mult));
  double lookahead = fmax(500.0, B.width * (5.0 + 2.0 * B.speed_mult));
  double predicted_x = B.hx + B.ca * lookahead;
  double predicted_y = B.hy + B.sa * lookahead;
  double predicted_dist = sqrt(dist2(predicted_x, predicted_y, center, center));
  double predicted_clearance = border_radius - predicted_dist - B.radius;
  double outward_heading = B.ca * outward_x + B.sa * outward_y;

  bool imminent = clearance <= guard * 0.45 || predicted_clearance <= guard * 0.70;
  bool unsafe_course = clearance <= guard &&
                       (outward_heading > -0.25 || B.state == BOT_CIRCLE);
  if (!imminent && !unsafe_course) return false;

  double retreat = fmax(1000.0, guard * 1.75);
  B.goal = (v2){js_round(B.hx - outward_x * retreat), js_round(B.hy - outward_y * retreat)};
  B.state = BOT_GROW;
  B.action_at = 0;
  B.boost = false;
  return true;
}

/* ------------------------------------------------------------ go */

/* tf.go, once a drawn frame; tf.Se (the timer) at its end. */
static void think(game_data* gdata, int follow_circle) {
  bool alive = every(gdata);
  if (!alive) return;
  uint64_t now = SDL_GetTicks();
  B.boost = false;

  if (avoid_border_emergency(gdata)) return;

  /* Smart bot, always on: grow below the length, then circle. */
  if (B.len_score < follow_circle)
    B.state = BOT_GROW;
  else if (B.state != BOT_CIRCLE)
    to_circle(gdata);

  if (B.state == BOT_CIRCLE) {
    B.boost = false;
    coil(gdata);
  } else if (dodge(gdata) || surrounded(gdata)) {
    if (B.action_at) B.action_at = now + NTL_DANGER_MS;
  } else {
    if (B.len_score > follow_circle) B.state = BOT_TOCIRCLE;
    if (!B.action_at) B.action_at = now + NTL_FOOD_MS;
  }

  if (B.action_at && now >= B.action_at) {
    B.action_at = 0;
    if (B.state == BOT_GROW)
      pick_food(gdata);
    else if (B.state == BOT_TOCIRCLE)
      to_circle(gdata);
  }
}

void sbot_init(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  memset(&B, 0, sizeof(B));
  B.id = -1;
  B.state = BOT_GROW;
  B.dir = 1;
  gdata->bot.output.accel = false;
  gdata->bot.output.xm = 0;
  gdata->bot.output.ym = 0;
}

void sbot_go(tenv* env) {
  tuser_data* usr = env->usr;
  user_settings* usrs = &usr->usrs;
  game_data* gdata = &usr->gdata;
  sbot* bot = &gdata->bot;
  if (tdarray_length(gdata->data.snakes) == 0) return;
  B.de = usrs->bot_radius_mult;
  think(gdata, usrs->bot_follow_circle_score);
  bot->output.accel = B.boost;
  /* dA.Y: the aim, from the head, in screen units. */
  bot->output.xm = (float)((B.goal.x - B.hx) * gdata->data.gsc);
  bot->output.ym = (float)((B.goal.y - B.hy) * gdata->data.gsc);
}

void sbot_destroy(tenv* env) { (void)env; }

void sbot_reset_ai_contexts(void) {
  memset(ai_contexts, 0, sizeof(ai_contexts));
}

void sbot_forget_ai_snake(int snake_id) {
  for (int i = 0; i < 15; ++i)
    if (ai_contexts[i].used && ai_contexts[i].id == snake_id) {
      memset(&ai_contexts[i], 0, sizeof(ai_contexts[i]));
      return;
    }
}

/* The AI arena's snakes: the same bot, each with its own state. */
bool sbot_decide_for_snake(tenv* env, int snake_id, sbot_decision* decision) {
  if (!decision) return false;
  game_data* gdata = &env->usr->gdata;
  snake* controlled = NULL;
  for (int i = 0; i < (int)tdarray_length(gdata->data.snakes); ++i)
    if (gdata->data.snakes[i].id == snake_id && !gdata->data.snakes[i].dead) {
      controlled = gdata->data.snakes + i;
      break;
    }
  if (!controlled) return false;

  ai_bot_context* context = NULL;
  for (int i = 0; i < 15; ++i) {
    if (ai_contexts[i].used && ai_contexts[i].id == snake_id) {
      context = ai_contexts + i;
      break;
    }
    if (!context && !ai_contexts[i].used) context = ai_contexts + i;
  }
  if (!context) return false;
  if (!context->used) {
    context->used = true;
    context->id = snake_id;
    context->mind = (bot_mind){snake_id, BOT_GROW, 1, 0,
                               {controlled->xx + cos(controlled->ang) * 500.0,
                                controlled->yy + sin(controlled->ang) * 500.0}};
  }

  /* Only the memory moves; the frame's working space is shared. */
  bot_mind own = mind_of();
  mind_to(context->mind);
  B.id = snake_id;
  B.de = env->usr->usrs.bot_radius_mult;
  think(gdata, env->usr->usrs.bot_follow_circle_score);
  decision->heading = (float)atan2(B.goal.y - controlled->yy, B.goal.x - controlled->xx);
  decision->accel = B.boost;
  context->mind = mind_of();
  mind_to(own);
  return isfinite(decision->heading);
}
'''

pairs("app/src/game/user_settings.c",
      ("  usr_settings->bot_radius_mult = 20;\n",
       "  usr_settings->bot_radius_mult = 12; /* NTL's de (OM, 2026-10-13) */\n"))

pairs("app/src/platform/android_settings.c",
      ("""    {"general.bot_circle", "general.bot", "Circle after score",
     "The score at which the bot starts circling instead of hunting.",
     SETTING_INT, 1000, 6000, NULL, OWNER_SETTINGS,
     SETTINGS_FIELD(bot_follow_circle_score)},
    {"general.bot_radius", "general.bot", "Bot radius",
     "How wide the bot keeps its distance.", SETTING_INT, 10, 40, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(bot_radius_mult)},""",
       """    {"general.bot_circle", "general.bot", "Circle after score",
     "Below this score the bot eats. Above it, it turns until its head meets "
     "its own body and coils round itself, keeping the coil clear and closing "
     "it on a snake caught inside. NTL's bot length; 2000 is NTL's.",
     SETTING_INT, 1000, 50000, NULL, OWNER_SETTINGS,
     SETTINGS_FIELD(bot_follow_circle_score)},
    {"general.bot_radius", "general.bot", "Bot radius",
     "How far ahead of its head the bot watches for snakes, in half snake "
     "widths. Smaller goes closer to snakes for food; bigger dodges sooner. "
     "12 is NTL's.", SETTING_INT, 10, 40, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(bot_radius_mult)},"""))


def apply(root, label="engine NTL bot 2026-10-13", skip_applied=False):
    root = Path(root)
    for relative, text in NEW_FILES.items():
        target = root / relative
        if not target.exists() or target.read_text(encoding="utf-8") != text:
            target.write_text(text, encoding="utf-8", newline="")
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        for old, new in items:
            if skip_applied and new in text and old not in text:
                continue
            count = text.count(old)
            if count != 1:
                raise SystemExit(f"{label}: anchor x{count} in {relative}: {old[:70]!r}")
            text = text.replace(old, new)
        if text != original:
            target.write_text(text, encoding="utf-8", newline="")
    return len(PAIRS) + len(NEW_FILES)


if __name__ == "__main__":
    print(apply(sys.argv[1], skip_applied=True), "files written")
