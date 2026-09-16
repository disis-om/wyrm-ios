#include "ai_mode.h"

#include <SDL3/SDL.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../mobile/mobile_controls.h"
#include "../mobile/mobile_hotkeys.h"
#include "../user.h"
#include "game_data.h"
#include "arena_theme.h"
#include "oef.h"
#include "redraw.h"
#include "ui_overlay.h"

enum {
  AI_BOTS = 14,
  AI_SNAKES = 15,
  AI_INITIAL_FOOD = 100,
  AI_FOOD_CAP = 1000
};
static const char* names[AI_BOTS] = {
    "Vector (bot)", "Mamba (bot)", "Orbit (bot)", "Razor (bot)", "Ghost (bot)",
    "Ember (bot)",  "Pixel (bot)", "Nova (bot)",  "Frost (bot)", "Bliss (bot)",
    "Zilla (bot)",  "Drum (bot)",  "Peace (bot)", "Kuavos (bot)"};
typedef struct {
  bool used;
  int id, avoid;
  float coward, accel;
  uint64_t last_avoid, retarget, stop_violence, last_drop;
  int64_t food_id;
  bool violent, accelerating;
  float tip_x, tip_y;
  bool has_tip;
} ai_state;
typedef struct {
  uint32_t rng;
  int64_t food_id;
  uint64_t spawn, violence, cull, death;
  ai_state state[AI_SNAKES];
} ai_session;
static ai_session ses;
static bool editor_session;
static bool notice_visible;
static bool notice_ok_down;
static uint64_t notice_finger;

static void notice_geometry(tenv* e, float* left, float* top, float* right,
                            float* bottom, float* ok_top) {
  float w = (float)e->wnd->size[0], h = (float)e->wnd->size[1];
  float card_w = fminf(650.0f, w - 36.0f);
  float card_h = fminf(330.0f, h - 42.0f);
  *left = (w - card_w) * .5f;
  *top = (h - card_h) * .5f;
  *right = *left + card_w;
  *bottom = *top + card_h;
  *ok_top = *bottom - 70.0f;
}

static bool notice_ok_hit(tenv* e, float x, float y) {
  float l, t, r, b, ot;
  notice_geometry(e, &l, &t, &r, &b, &ot);
  return x >= l + 24.0f && x <= r - 24.0f && y >= ot && y <= b - 20.0f;
}

bool ai_mode_notice_process_event(tenv* e, const void* raw_event) {
  if (!notice_visible || editor_session || !e->usr->gdata.ai_mode) return false;
  const SDL_Event* event = raw_event;
  if (event->type != SDL_EVENT_FINGER_DOWN &&
      event->type != SDL_EVENT_FINGER_MOTION &&
      event->type != SDL_EVENT_FINGER_UP &&
      event->type != SDL_EVENT_FINGER_CANCELED)
    return false;
  uint64_t finger = (uint64_t)event->tfinger.fingerID;
  float x = event->tfinger.x * e->wnd->size[0];
  float y = event->tfinger.y * e->wnd->size[1];
  if (event->type == SDL_EVENT_FINGER_DOWN) {
    notice_ok_down = notice_ok_hit(e, x, y);
    notice_finger = finger;
  } else if ((event->type == SDL_EVENT_FINGER_UP ||
              event->type == SDL_EVENT_FINGER_CANCELED) &&
             notice_finger == finger) {
    if (event->type == SDL_EVENT_FINGER_UP && notice_ok_down &&
        notice_ok_hit(e, x, y))
      notice_visible = false;
    notice_ok_down = false;
  }
  return true;
}

static void draw_notice(tenv* e) {
  if (!notice_visible || editor_session) return;
  float l, t, r, b, ot;
  notice_geometry(e, &l, &t, &r, &b, &ot);
  /* ai_mode_tick is rendered inside the fullscreen game window and runs after
     every arena/control layer, so its current draw list is the true top layer. */
  ImDrawList* dl = igGetWindowDrawList();
  ImDrawList_AddRectFilled(dl, (ImVec2){0, 0},
                           (ImVec2){e->wnd->size[0], e->wnd->size[1]},
                           arena_theme_colour(ARENA_THEME_INK, .54f), 0, 0);
  ImDrawList_AddRectFilled(dl, (ImVec2){l, t}, (ImVec2){r, b},
                           arena_theme_colour(ARENA_THEME_CARD, .98f), 18, 0);
  ImDrawList_AddRect(dl, (ImVec2){l, t}, (ImVec2){r, b},
                     arena_theme_colour(ARENA_THEME_RULE, 1), 18, 0, 1.5f);
  ImFont* label = e->usr->imgui_data.mono_font[FONT_SIZE_SMALL];
  ImFont* title = e->usr->imgui_data.regular_font_bold[FONT_SIZE_LARGE];
  ImFont* body = e->usr->imgui_data.body_font[FONT_SIZE_REGULAR];
  ImDrawList_AddText_FontPtr(dl, label, label->LegacySize,
                             (ImVec2){l + 28, t + 24},
                             arena_theme_colour(ARENA_THEME_LIVE, 1),
                             "AI ARENA / EARLY ACCESS", NULL, 0, NULL);
  ImDrawList_AddText_FontPtr(dl, title, title->LegacySize,
                             (ImVec2){l + 28, t + 55},
                             arena_theme_colour(ARENA_THEME_INK, 1),
                             "Train without limits.", NULL, 0, NULL);
  const char* copy =
      "This arena is still in development, so you may experience a few bugs.\n\n"
      "Practice fights, SQZ, escapes and much more while we finish the arena.";
  ImDrawList_AddText_FontPtr(dl, body, body->LegacySize,
                             (ImVec2){l + 28, t + 102},
                             arena_theme_colour(ARENA_THEME_QUIET, 1), copy,
                             NULL, r - l - 56, NULL);
  ImDrawList_AddRectFilled(dl, (ImVec2){l + 24, ot},
                           (ImVec2){r - 24, b - 20},
                           arena_theme_colour(ARENA_THEME_INK,
                                              notice_ok_down ? .78f : 1),
                           12, 0);
  const char* ok = "OK, LET ME PLAY";
  ImVec2 sz;
  igPushFont(label, label->LegacySize);
  igCalcTextSize(&sz, ok, NULL, false, -1);
  igPopFont();
  ImDrawList_AddText_FontPtr(dl, label, label->LegacySize,
                             (ImVec2){(l + r - sz.x) * .5f,
                                      ot + ((b - 20) - ot - sz.y) * .5f},
                             arena_theme_colour(ARENA_THEME_ON_INK, 1), ok,
                             NULL, 0, NULL);
}

static uint32_t rnd(void) {
  ses.rng = ses.rng * 1664525u + 1013904223u;
  return ses.rng;
}
static float unit(void) { return (rnd() >> 8) / 16777215.f; }
static float wrap(float a) {
  a = fmodf(a, PI2);
  return a < 0 ? a + PI2 : a;
}
static float d2(float ax, float ay, float bx, float by) {
  float x = ax - bx, y = ay - by;
  return x * x + y * y;
}
static float cheb(float ax, float ay, float bx, float by) {
  return fmaxf(fabsf(ax - bx), fabsf(ay - by));
}
static body_part* points(game_data* g) {
  int n = tdarray_length(g->data.pts_dp);
  if (n) {
    body_part* p = g->data.pts_dp[n - 1];
    tdarray_pop(g->data.pts_dp);
    tdarray_clear(p);
    return p;
  }
  return tdarray_create(body_part);
}
static gpt* gpoints(game_data* g) {
  int n = tdarray_length(g->data.gptz_dp);
  if (n) {
    gpt* p = g->data.gptz_dp[n - 1];
    tdarray_pop(g->data.gptz_dp);
    tdarray_clear(p);
    return p;
  }
  return tdarray_create(gpt);
}
static ai_state* state(int id, bool make) {
  ai_state* e = NULL;
  for (int i = 0; i < AI_SNAKES; i++) {
    if (ses.state[i].used && ses.state[i].id == id) return ses.state + i;
    if (!ses.state[i].used && !e) e = ses.state + i;
  }
  if (!make || !e) return NULL;
  *e = (ai_state){.used = true, .id = id, .avoid = 1, .food_id = -1};
  return e;
}
static snake* snake_id(game_data* g, int id) {
  for (int i = 0; i < tdarray_length(g->data.snakes); i++)
    if (g->data.snakes[i].id == id) return g->data.snakes + i;
  return NULL;
}
static food* food_id(game_data* g, int64_t id) {
  for (int i = 0; i < tdarray_length(g->data.foods); i++)
    if (g->data.foods[i].id == id && !g->data.foods[i].eaten)
      return g->data.foods + i;
  return NULL;
}

static void scale(game_data* g, snake* s) {
  s->sc = fminf(6, 1 + (s->sct - 2) / 106.f);
  s->scang = .13f + .87f * powf((7 - s->sc) / 6.f, 2);
  s->ssp = g->data.nsp1 + g->data.nsp2 * s->sc;
  s->fsp = s->ssp + .1f;
  s->msp = g->data.nsp3;
  s->spang = fminf(s->sp / g->data.spangdv, 1);
  s->wsep = fmaxf(GD_NSEP, 6 * s->sc);
}

/* This is Slither.txt's snl(): score length and drawn body length are not the
   same quantity. Fractional mass contributes at most one visual segment and
   its change is eased through the existing length filter. */
static void length_changed(game_data* g, snake* s) {
  float old = s->tl;
  s->tl = s->sct + fminf(1, s->fam);
  float delta = s->tl - old;
  int pos = s->flpos;
  for (int i = 0; i < GD_EEZ; ++i) {
    s->fls[pos] -= delta * g->data.xfas[i];
    if (++pos >= GD_EEZ) pos = 0;
  }
  s->fl = s->fls[s->flpos];
  s->fltg = GD_EEZ;
  s->cfl = s->tl + s->fl - .6f;
}
static snake make_snake(game_data* g, int id, const char* name, int cv, float x,
                        float y, float a, int count, bool curved, bool local) {
  snake s = {0};
  s.id = id;
  s.local_player = local;
  s.cv = cv % NUM_DEFAULT_SKINS;
  s.accessory = NO_ACCESSORY;
  s.xx = x;
  s.yy = y;
  s.ang = s.eang = s.wang = s.ehang = s.wehang = wrap(a);
  s.msl = g->data.default_msl;
  s.sct = count;
  s.sp = s.tsp = g->data.nsp1;
  s.alive_amt = 1;
  s.pts = points(g);
  s.gptz = gpoints(g);
  snprintf(s.nk, sizeof(s.nk), "%s", name && name[0] ? name : "Wyrm Player");
  snprintf(s.original_nickname, sizeof(s.original_nickname), "%s", s.nk);
  float px = x, py = y, h = curved ? a + unit() * .9f - .45f : a + PI;
  for (int i = 0; i < count; i++) {
    float ox = px, oy = py;
    px += cosf(h) * s.msl;
    py += sinf(h) * s.msl;
    if (curved) h += 3 * (unit() - .5f) / count;
    body_part p = {0};
    p.xx = px;
    p.yy = py;
    p.ebx = px - ox;
    p.eby = py - oy;
    p.smu = p.ltn = 1;
    p.ftg = -1;
    tdarray_insert(&s.pts, 0, &p);
  }
  if (curved && tdarray_length(s.pts)) {
    body_part* p = s.pts + tdarray_length(s.pts) - 1;
    s.xx = p->xx;
    s.yy = p->yy;
    s.ang = s.eang = s.wang = s.ehang = s.wehang = wrap(h + PI);
  }
  scale(g, &s);
  s.tl = s.sct + fminf(1, s.fam);
  s.cfl = s.tl - .6f;
  s.sep = s.wsep;
  return s;
}
static void food_add(game_data* g, float x, float y, float r, int cv) {
  food f = {0};
  f.id = ses.food_id++;
  f.cv = ((cv % NUM_COLOR_GROUPS) + NUM_COLOR_GROUPS) % NUM_COLOR_GROUPS;
  f.cv2 = (int)(NUM_FOOD_SIZES * r / 16.5f);
  if (f.cv2 < 0) f.cv2 = 0;
  if (f.cv2 >= NUM_FOOD_SIZES) f.cv2 = NUM_FOOD_SIZES - 1;
  f.xx = f.rx = x;
  f.yy = f.ry = y;
  f.sz = r;
  f.rad = f.lrrad = f.fr = f.rsp = 1;
  f.gr = .65f + .1f * r;
  f.wsp = (unit() * 2 - 1) * .0225f;
  f.sx = (int)(x / g->data.sector_size);
  f.sy = (int)(y / g->data.sector_size);
  tdarray_push(&g->data.foods, &f);
}
static void seed_food_count(game_data* g, snake* p, int count) {
  for (int i = 0; i < count; i++) {
    float x = p->xx + 1600 * (unit() - .5f), y = p->yy + 1600 * (unit() - .5f);
    if (d2(x, y, g->data.grd, g->data.grd) <
        g->data.flux_grd * g->data.flux_grd)
      food_add(g, x, y, 2 + powf(unit(), 2.5f) * 14.5f, (int)(unit() * 9));
  }
}
static void seed_food(game_data* g, snake* p) {
  seed_food_count(g, p, AI_INITIAL_FOOD);
}
static void maintain_food(game_data* g, snake* p, uint64_t now) {
  (void)p;
  (void)now;
  if (tdarray_length(g->data.foods) < AI_FOOD_CAP) {
    int count = tdarray_length(g->data.snakes),
        start = count ? (int)(rnd() % count) : 0;
    snake* centre = p;
    for (int offset = 0; offset < count; offset++) {
      snake* candidate = g->data.snakes + (start + offset) % count;
      if (!candidate->dead) {
        centre = candidate;
        break;
      }
    }
    float a = unit() * PI2, r = 300 + powf(unit(), .3f) * 950,
          x = centre->xx + cosf(a) * r, y = centre->yy + sinf(a) * r;
    if (d2(x, y, g->data.grd, g->data.grd) <
        g->data.flux_grd * g->data.flux_grd)
      food_add(g, x, y, 2 + powf(unit(), 2.5f) * 14.5f, (int)(unit() * 9));
  }
}
static void steer(snake* s, float target) {
  target = wrap(target);
  float d = target - wrap(s->ang);
  if (d > PI) d -= PI2;
  if (d < -PI) d += PI2;
  s->eang = s->wang = target;
  s->dir = fabsf(d) < .00001f ? 0 : (d < 0 ? 1 : 2);
}
static void accelerate(game_data* g, snake* s, ai_state* a, bool on) {
  a->accelerating = on;
  float div = 1 + .305f * (s->sc - 1);
  if (on && a->accel < .9999f) {
    a->accel += .015f * g->data.vfr / div;
    if (a->accel > 1) a->accel = 1;
  } else if (!on && a->accel > 0) {
    a->accel -= .02f * g->data.vfr / div;
    if (a->accel < 0) a->accel = 0;
  }
  s->sp = s->ssp + (g->data.nsp3 - s->ssp) * a->accel;
  s->spang = fminf(s->sp / g->data.spangdv, 1);
}
static void player_input(tenv* e) {
  game_data* g = &e->usr->gdata;
  int n = tdarray_length(g->data.snakes);
  if (!n) return;
  snake* p = g->data.snakes + n - 1;
  if (!p->local_player || p->dead) return;
  int x = 0, y = 0;
  if (mobile_controls_get_aim(e, &x, &y) && x * x + y * y > 16)
    steer(p, atan2f((float)y, (float)x));
  bool boost = mobile_controls_boost_down(e) ||
               mobile_hotkeys_down(e, MOBILE_HOTKEY_BOOST);
  accelerate(g, p, state(p->id, true), boost);
  g->data.md = g->data.wmd = boost;
}

static void playable_zoom(tenv* e) {
  game_data* g = &e->usr->gdata;
  if (mobile_hotkeys_pressed(e, MOBILE_HOTKEY_ZOOM_IN))
    g->data.ms_zoom *= expf(e->usr->usrs.zoom_step);
  if (mobile_hotkeys_pressed(e, MOBILE_HOTKEY_ZOOM_OUT))
    g->data.ms_zoom *= expf(-e->usr->usrs.zoom_step);
  g->data.ms_zoom = fmaxf(MAX_ZOOM_OUT, fminf(MAX_ZOOM_IN, g->data.ms_zoom));
}

/* The online loop normally translates touch-button edges into hotkey state.
   Playable AI deliberately bypasses that socket-owning loop, so mirror only
   its local toggle/hold semantics here. No packet path is involved. */
static void playable_hotkeys(tenv* e) {
  user_settings* settings = &e->usr->usrs;
  for (int i = 0; i < NUM_HOTKEYS; ++i) {
    hotkey* key = settings->hotkeys + i;
    bool pressed = mobile_hotkeys_pressed(e, i);
    if (i == HOTKEY_RESTART || i == HOTKEY_QUIT)
      key->active = pressed;
    else if (key->mode)
      key->active = mobile_hotkeys_down(e, i);
    else if (pressed)
      key->active = !key->active;
  }
}

static void playable_player(tenv* e) {
  game_data* g = &e->usr->gdata;
  int count = tdarray_length(g->data.snakes);
  snake* player = count ? g->data.snakes + count - 1 : NULL;
  if (e->usr->usrs.hotkeys[HOTKEY_BOT].active && player && !player->dead) {
    sbot_decision decision;
    if (sbot_decide_for_snake(e, player->id, &decision)) {
      ai_state* mind = state(player->id, true);
      steer(player, decision.heading);
      bool boost = decision.accel || mobile_controls_boost_down(e) ||
                   mobile_hotkeys_down(e, MOBILE_HOTKEY_BOOST);
      accelerate(g, player, mind, boost);
      g->data.md = g->data.wmd = boost;
    }
  } else {
    player_input(e);
  }
  playable_zoom(e);
}

static body_part* threat(game_data* g, snake* b, ai_state* a, uint64_t now) {
  body_part* bestp = NULL;
  float best = a->coward * (a->accelerating ? 2 : 1);
  for (int si = tdarray_length(g->data.snakes) - 1; si >= 0; si--) {
    snake* o = g->data.snakes + si;
    if (o == b || o->dead) continue;
    int m = 0;
    for (int i = tdarray_length(o->pts) - 1; i >= 0; i--) {
      body_part* p = o->pts + i;
      m++;
      if (p->dying) break;
      float d = cheb(b->xx, b->yy, p->xx, p->yy);
      if (d < best && (!o->local_player || m >= 3)) {
        if (!bestp) a->retarget = now + 1000 + (uint64_t)(unit() * 500);
        best = d;
        bestp = p;
      }
    }
  }
  return bestp;
}
static food* nearest_food(game_data* g, snake* s) {
  food* best = NULL;
  float bd = 999999;
  for (int i = tdarray_length(g->data.foods) - 1; i >= 0; i--) {
    food* f = g->data.foods + i;
    if (!f->eaten) {
      float d = cheb(s->xx, s->yy, f->xx, f->yy);
      if (d < bd) {
        bd = d;
        best = f;
      }
    }
  }
  return best;
}
static void slither_bot_mind(game_data* g, snake* b, ai_state* a,
                             uint64_t now) {
  int n = tdarray_length(g->data.snakes);
  snake* player = g->data.snakes + n - 1;
  body_part* t = threat(g, b, a, now);
  if (now - a->last_avoid > 2000 && !t) {
    a->last_avoid = now;
    a->avoid = a->avoid == 1 ? 2 : 1;
  }
  food* f = food_id(g, a->food_id);
  if (now > a->retarget || !f) {
    f = nearest_food(g, b);
    if (f) {
      a->food_id = f->id;
      a->retarget = now + 3000 + (uint64_t)(unit() * 500);
    }
  }
  if (a->violent) {
    if (now > a->stop_violence) a->violent = false;
  } else if (b->sct > 10 && player->sct > 7 && now > ses.violence &&
             unit() < .3f) {
    ses.violence = now + (uint64_t)fmaxf(1000, 16000 - (player->sct - 7) * 25);
    a->violent = true;
    a->stop_violence = now + 4000 + (uint64_t)(unit() * 7500);
  }
  float heading;
  if (t)
    heading =
        (a->avoid == 1 ? .26f : -.26f) + atan2f(b->yy - t->yy, b->xx - t->xx);
  else if (a->violent)
    heading = atan2f(player->yy + sinf(player->ang) * 95 - b->yy,
                     player->xx + cosf(player->ang) * 95 - b->xx);
  else if (f)
    heading = atan2f(f->yy - b->yy, f->xx - b->xx);
  else
    heading = atan2f(player->yy - b->yy, player->xx - b->xx);
  steer(b, heading);
  accelerate(g, b, a, a->violent);
}

static void bot_minds(tenv* env, uint64_t now) {
  game_data* g = &env->usr->gdata;
  int n = tdarray_length(g->data.snakes);
  if (!n) return;
  for (int i = 0; i < n - 1; i++) {
    snake* b = g->data.snakes + i;
    if (b->dead) continue;
    ai_state* a = state(b->id, false);
    if (!a) continue;
    if ((b->id % 10) < 3) {
      slither_bot_mind(g, b, a, now);
      continue;
    }
    sbot_decision decision;
    if (sbot_decide_for_snake(env, b->id, &decision)) {
      steer(b, decision.heading);
      accelerate(g, b, a, decision.accel);
    }
  }
}
static void tail_die(snake* s) {
  for (int i = 0; i < tdarray_length(s->pts); i++)
    if (!s->pts[i].dying) {
      s->pts[i].dying = true;
      return;
    }
}
static void body_update(game_data* g) {
  for (int si = 0; si < tdarray_length(g->data.snakes); si++) {
    snake* s = g->data.snakes + si;
    if (s->dead || s->chl < 1 || !tdarray_length(s->pts)) continue;
    bool changed_length = false;
    if (s->fam >= 1) {
      s->fam -= 1;
      s->sct++;
      changed_length = true;
    } else
      tail_die(s);
    body_part* old = s->pts + tdarray_length(s->pts) - 1;
    body_part p = {0};
    p.xx = s->xx;
    p.yy = s->yy;
    p.ebx = p.xx - old->xx;
    p.eby = p.yy - old->yy;
    p.ltn = sqrtf(p.ebx * p.ebx + p.eby * p.eby) / s->msl;
    p.smu = 1;
    p.ftg = -1;
    tdarray_push(&s->pts, &p);
    int li = tdarray_length(s->pts) - 3;
    if (li >= 1) {
      body_part* lead = s->pts + li;
      float mv = 0;
      int n = 0, sm = 3;
      for (int i = li - 1; i >= 0; i--) {
        body_part* c = s->pts + i;
        n++;
        if (n <= 4) mv = g->data.cst * n / 4.f;
        c->xx += (lead->xx - c->xx) * mv;
        c->yy += (lead->yy - c->yy) * mv;
        if (sm < GD_SMUC) c->smu = g->data.smus[sm++];
        lead = c;
      }
    }
    scale(g, s);
    if (changed_length) length_changed(g, s);
    float old_chl = s->chl - 1;
    s->chl = 0;
    float delta_chl = s->chl - old_chl;
    int filter_pos = s->fpos;
    for (int frame = 0; frame < GD_EEZ; ++frame) {
      s->fchls[filter_pos] -= delta_chl * g->data.xfas[frame];
      if (++filter_pos >= GD_EEZ) filter_pos = 0;
    }
    s->fchl = s->fchls[s->fpos];
    s->ftg = GD_EEZ;
    int len = tdarray_length(s->pts);
    if (len >= 2) {
      body_part *a = s->pts + len - 1, *b = s->pts + len - 2;
      s->wehang = atan2f(a->yy - b->yy, a->xx - b->xx);
    }
  }
}
static void boost_mass(game_data* g, uint64_t now) {
  for (int i = 0; i < tdarray_length(g->data.snakes); i++) {
    snake* s = g->data.snakes + i;
    ai_state* a = state(s->id, false);
    if (!a || s->dead || !a->accelerating || now - a->last_drop < 150) continue;
    a->last_drop = now;
    if (s->sct > 2 || s->fam >= .14f)
      for (int p = 0; p < tdarray_length(s->pts); p++)
        if (!s->pts[p].dying) {
          food_add(g, s->pts[p].xx, s->pts[p].yy, 3 + powf(unit(), 2.5f),
                   s->cv);
          break;
        }
    int k = (int)(s->sct + s->fam);
    int max = g->data.mscps - 1;
    if (k > max) k = max;
    if (k >= 0 && k < tdarray_length(g->data.fmlts))
      s->fam -= .16f * g->data.fmlts[k];
    if (s->fam <= 0) {
      if (s->sct == 2) {
        s->fam = 0;
        accelerate(g, s, a, false);
      } else {
        s->fam += .999999999f;
        tail_die(s);
        s->sct--;
        scale(g, s);
      }
    }
    length_changed(g, s);
  }
}
static void eat(game_data* g) {
  for (int si = 0; si < tdarray_length(g->data.snakes); si++) {
    snake* s = g->data.snakes + si;
    if (s->dead) continue;
    float sc13 = powf(s->sc, 1.3f),
          mouth = (.36f * (29 * s->sc) + 31) * s->sp / 4.8f,
          x = s->xx + cosf(s->ang) * mouth, y = s->yy + sinf(s->ang) * mouth;
    for (int i = 0; i < tdarray_length(g->data.foods); i++) {
      food* f = g->data.foods + i;
      if (f->eaten || fabsf(f->xx - x) > 70 * sc13 ||
          fabsf(f->yy - y) > 70 * sc13 || d2(f->xx, f->yy, x, y) > 1600 * sc13)
        continue;
      f->eaten = true;
      f->ebid = s->id;
      int k = (int)(s->sct + s->fam);
      int max = g->data.mscps - 1;
      if (k > max) k = max;
      if (k >= 0 && k < tdarray_length(g->data.fmlts))
        s->fam += g->data.fmlts[k] * f->sz * f->sz * 25 / 7845.f;
      length_changed(g, s);
    }
  }
}
static void drop_snake(game_data* g, snake* s) {
  for (int i = 0; i < tdarray_length(s->pts); i++)
    if (!s->pts[i].dying)
      for (int n = 0; n < 2; n++)
        food_add(g, s->pts[i].xx + (unit() - .5f) * 18,
                 s->pts[i].yy + (unit() - .5f) * 18, 16, s->cv);
}
static void kill_ai_snake(game_data* g, snake* s) {
  if (s->dead) return;
  drop_snake(g, s);
  s->dead = true;
  s->dead_amt = 0;
  s->sp = s->tsp = 0;
  ai_state* a = state(s->id, false);
  if (a) a->used = false;
  sbot_forget_ai_snake(s->id);
  if (s->local_player) {
    g->data.dead = true;
    ses.death = SDL_GetTicks();
  }
}
static float point_seg(float px, float py, float ax, float ay, float bx,
                       float by) {
  float vx = bx - ax, vy = by - ay, l = vx * vx + vy * vy,
        t = l ? ((px - ax) * vx + (py - ay) * vy) / l : 0;
  t = fmaxf(0, fminf(1, t));
  return d2(px, py, ax + vx * t, ay + vy * t);
}
static void collide(game_data* g) {
  for (int i = 0; i < tdarray_length(g->data.snakes); i++) {
    snake* s = g->data.snakes + i;
    if (s->dead) continue;
    float r = s->sc * 29 / 2, tx = s->xx + s->fx + cosf(s->ehang) * r,
          ty = s->yy + s->fy + sinf(s->ehang) * r;
    ai_state* a = state(s->id, false);
    float ox = a && a->has_tip ? a->tip_x : tx + .01f,
          oy = a && a->has_tip ? a->tip_y : ty + .01f;
    if (d2(tx, ty, g->data.grd, g->data.grd) >
        g->data.flux_grd * g->data.flux_grd) {
      kill_ai_snake(g, s);
      continue;
    }
    for (int j = 0; j < tdarray_length(g->data.snakes) && !s->dead; j++) {
      snake* o = g->data.snakes + j;
      if (i == j || o->dead) continue;
      /* Main.as uses 3.666x only to reject distant segments before an exact
         swept intersection. The prior port accidentally used it as the hit
         radius, so snakes died visibly before their head reached a body. */
      float hit = 14.5f * (s->sc + o->sc), bx = o->xx, by = o->yy;
      for (int p = tdarray_length(o->pts) - 1; p >= 0; p--) {
        body_part* q = o->pts + p;
        if (q->dying) break;
        if (fminf(point_seg(tx, ty, q->xx, q->yy, bx, by),
                  point_seg(q->xx, q->yy, ox, oy, tx, ty)) < hit * hit) {
          kill_ai_snake(g, s);
          break;
        }
        bx = q->xx;
        by = q->yy;
      }
    }
    if (a) {
      a->tip_x = tx;
      a->tip_y = ty;
      a->has_tip = true;
    }
  }
}
static int next_id(game_data* g) {
  for (int i = 0; i < 20; i++) {
    int id = 10 + (int)(unit() * 1024);
    if (!snake_id(g, id)) return id;
  }
  return -1;
}
static bool spawn(game_data* g) {
  int n = tdarray_length(g->data.snakes);
  if (!n) return false;
  snake* p = g->data.snakes + n - 1;
  int id = next_id(g);
  if (id < 0) return false;
  (void)p;
  float a = unit() * PI2;
  float radius = sqrtf(unit()) * (g->data.flux_grd - 2000);
  float x = g->data.grd + cosf(a) * radius;
  float y = g->data.grd + sinf(a) * radius;
  int len = 2 + (int)(70 * powf(unit(), 2));
  snake b =
      make_snake(g, id, names[(id - 10) % AI_BOTS],
                 (int)(unit() * NUM_DEFAULT_SKINS), x, y, a, len, true, false);
  bool clear = true;
  for (int q = 0; q < tdarray_length(b.pts) && clear; q++) {
    body_part* c = b.pts + q;
    if (d2(c->xx, c->yy, g->data.grd, g->data.grd) >
        g->data.flux_grd * g->data.flux_grd) {
      clear = false;
      break;
    }
    for (int si = 0; si < n && clear; si++)
      for (int k = tdarray_length(g->data.snakes[si].pts) - 1; k >= 0; k--) {
        body_part* o = g->data.snakes[si].pts + k;
        if (o->dying) break;
        if (fabsf(c->xx - o->xx) < 160 && fabsf(c->yy - o->yy) < 160) {
          clear = false;
          break;
        }
      }
  }
  if (!clear) {
    tdarray_push(&g->data.pts_dp, &b.pts);
    tdarray_push(&g->data.gptz_dp, &b.gptz);
    return false;
  }
  ai_state* s = state(id, true);
  s->coward = 84 * (1.5f + unit() * 4);
  s->avoid = unit() < .5f ? 1 : 2;
  s->last_avoid = SDL_GetTicks();
  tdarray_insert(&g->data.snakes, n - 1, &b);
  seed_food_count(g, g->data.snakes + n - 1, 60);
  return true;
}
typedef struct {
  snake* s;
  int score;
} rank_item;
static int score(game_data* g, snake* s) {
  int i = s->sct + s->rsc, m = tdarray_length(g->data.fmlts) - 1;
  if (i < 0 || i > m || g->data.fmlts[i] <= 0) return 0;
  return (int)floorf((g->data.fpsls[i] + s->fam / g->data.fmlts[i] - 1) * 15 -
                     5);
}
static int rank_cmp(const void* a, const void* b) {
  return ((rank_item*)b)->score - ((rank_item*)a)->score;
}
static void hud(game_data* g) {
  int n = tdarray_length(g->data.snakes);
  g->data.slither_count = n;
  g->data.rank = n;
  g->data.gotlb = true;
  memset(g->data.lb.entries, 0, sizeof(g->data.lb.entries));
  rank_item* r = n ? malloc(sizeof(*r) * n) : NULL;
  for (int i = 0; r && i < n; i++) {
    r[i] = (rank_item){g->data.snakes + i, score(g, g->data.snakes + i)};
  }
  if (r) qsort(r, n, sizeof(*r), rank_cmp);
  for (int i = 0; r && i < n && i < NUM_LEADERBOARD_ENTRIES; i++) {
    snprintf(g->data.lb.entries[i].nickname,
             sizeof(g->data.lb.entries[i].nickname), "%s", r[i].s->nk);
    g->data.lb.entries[i].score = r[i].score;
    g->data.lb.entries[i].cv = r[i].s->cv;
  }
  for (int i = 0; r && i < n; i++)
    if (r[i].s->local_player) {
      g->data.rank = i + 1;
      g->data.score = r[i].score;
      break;
    }
  free(r);
  int z = g->data.mmsz;
  memset(g->data.mm_data, 0, (size_t)z * z);
  for (int i = 0; i < n; i++) {
    snake* s = g->data.snakes + i;
    if (!s->dead) {
      int x = (int)(s->xx / (g->data.grd * 2) * z),
          y = (int)(s->yy / (g->data.grd * 2) * z);
      if (x >= 0 && y >= 0 && x < z && y < z)
        g->data.mm_data[y * z + x] = s->local_player ? 255 : 170;
    }
  }
}

void ai_mode_start(tenv* e, const char* nick) {
  game_data* g = &e->usr->gdata;
  if (g->connection) {
    SDL_Log("Wyrm AI: refused while arena socket exists");
    return;
  }
  game_data_reset(e);
  g->ai_mode = true;
  g->conn = AI_CONNECTED;
  g->curr_screen = PLAYING;
  g->stay_in_lobby = true;
  g->arena_ready = false;
  g->data.protocol_version = PROTOCOL_VERSION;
  g->data.grd = 21600;
  g->data.flux_grd = g->data.real_flux_grd = g->data.grd * .98f;
  g->data.sector_size = 450;
  g->data.ssd256 = 450 / 256.f;
  g->data.spangdv = 4.8f;
  g->data.nsp1 = 4.25f;
  g->data.nsp2 = .5f;
  g->data.nsp3 = 12;
  g->data.mamu = .033f;
  g->data.mamu2 = .028f;
  g->data.cst = .43f;
  g->data.default_msl = 42;
  g->data.mmsz = 80;
  notice_visible = !editor_session;
  notice_ok_down = false;
  /* game_data_reset deliberately leaves the online world dead and its camera
     at zero until a server spawn arrives. AI mode is its own spawn authority,
     so make the local life visible and centre the camera before frame one. */
  g->data.dead = false;
  g->data.follow_view = true;
  g->data.snake_id = 1;
  g->data.lag_mult = 1;
  g->data.view_xx = g->data.ovxx = g->data.grd;
  g->data.view_yy = g->data.ovyy = g->data.grd;
  e->usr->r->global.grd = g->data.grd;
  e->usr->r->global.bd_radius = g->data.flux_grd;
  g->life_started_sec = glfwGetTime();
  set_mscps(g, 411);
  recalc_sep_mults(g);
  for (int i = 0; i < GD_FLXC; i++) g->data.flux_grds[i] = g->data.flux_grd;
  uint64_t now = SDL_GetTicks();
  ses = (ai_session){.rng = 0x5759524d,
                     .food_id = 10000,
                     .spawn = now + 700,
                     .cull = now + 25};
  snake p = make_snake(g, 1, nick, e->usr->usrs.default_skin, g->data.grd,
                       g->data.grd, 0, 2, false, true);
  p.accessory = e->usr->usrs.accessory;
  if (e->usr->usrs.custom_skin) {
    p.cusk = true;
    for (int i = 0; i < MAX_SKIN_CODE_LEN && e->usr->usrs.skin_code[i]; i++) {
      int c = get_cg_id(g, e->usr->usrs.skin_code[i]);
      if (c >= 0) p.cusk_data[p.cusk_len++] = (uint8_t)c;
    }
    if (!p.cusk_len) p.cusk = false;
  }
  tdarray_push(&g->data.snakes, &p);
  state(1, true);
  sbot_reset_ai_contexts();
  seed_food(g, g->data.snakes);
  hud(g);
  SDL_Log("Wyrm AI: reference movement and bot mind active; socket=none");
}
void ai_mode_start_editor(tenv* e, const char* nick) {
  editor_session = true;
  ai_mode_start(e, nick);
}
bool ai_mode_is_editor(void) { return editor_session; }
void ai_mode_stop(tenv* e) {
  game_data* g = &e->usr->gdata;
  g->ai_mode = false;
  notice_visible = false;
  notice_ok_down = false;
  ses = (ai_session){0};
  sbot_reset_ai_contexts();
  game_clear_world(g);
  g->conn = DISCONNECTED;
  g->curr_screen = LOBBY;
  SDL_Log("Wyrm AI: local session cleared");
}
void ai_mode_finish_editor(tenv* e) {
  editor_session = false;
  ai_mode_stop(e);
  e->usr->gdata.curr_screen = TITLE_SCREEN;
}
void ai_mode_tick(tenv* e) {
  game_data* g = &e->usr->gdata;
  if (!g->ai_mode) return;
  time_step(e);
  uint64_t now = SDL_GetTicks();
  if (editor_session) {
    int count = tdarray_length(g->data.snakes);
    snake* player = count ? g->data.snakes + count - 1 : NULL;
    sbot_decision decision;
    if (player && !player->dead &&
        sbot_decide_for_snake(e, player->id, &decision)) {
      ai_state* mind = state(player->id, true);
      steer(player, decision.heading);
      accelerate(g, player, mind, decision.accel);
    }
    e->usr->mobile_controls.exit_requested = false;
    e->usr->mobile_controls.joystick_down = false;
    e->usr->mobile_controls.boost_down = false;
    e->usr->mobile_controls.zoom_down = false;
    e->usr->mobile_controls.aim_valid = false;
    mobile_hotkeys_reset_runtime(e);
    e->usr->usrs.hotkeys[HOTKEY_QUIT].active = false;
    e->usr->usrs.hotkeys[HOTKEY_RESTART].active = false;
  } else {
    if (notice_visible) {
      int count = tdarray_length(g->data.snakes);
      snake* player = count ? g->data.snakes + count - 1 : NULL;
      if (player && !player->dead)
        accelerate(g, player, state(player->id, true), false);
      g->data.md = g->data.wmd = false;
      mobile_hotkeys_reset_runtime(e);
    } else {
      playable_hotkeys(e);
      playable_player(e);
    }
  }
  bot_minds(e, now);
  boost_mass(g, now);
  oef(e);
  body_update(g);
  eat(g);
  collide(g);
  if (editor_session && ses.death) {
    char nick[MAX_NICKNAME_LEN + 1];
    snprintf(nick, sizeof(nick), "%s", e->usr->usrs.nickname);
    ai_mode_stop(e);
    ai_mode_start_editor(e, nick);
    return;
  }
  int n = tdarray_length(g->data.snakes);
  if (n && g->data.snakes[n - 1].local_player && !g->data.snakes[n - 1].dead) {
    snake* p = g->data.snakes + n - 1;
    maintain_food(g, p, now);
    if (now >= ses.spawn && n < AI_SNAKES) {
      spawn(g);
      ses.spawn = now + 700;
    }
  }
  hud(g);
  redraw(e);
  ui_overlay(e);
  mobile_controls_draw_gameplay(e);
  draw_notice(e);
  if (!editor_session && ses.death && now - ses.death >= 4000) {
    ai_mode_stop(e);
    return;
  }
  if (e->usr->mobile_controls.exit_requested ||
      e->usr->usrs.hotkeys[HOTKEY_QUIT].active) {
    e->usr->mobile_controls.exit_requested = false;
    e->usr->usrs.hotkeys[HOTKEY_QUIT].active = false;
    ai_mode_stop(e);
  } else if (e->usr->usrs.hotkeys[HOTKEY_RESTART].active) {
    e->usr->usrs.hotkeys[HOTKEY_RESTART].active = false;
    char nick[MAX_NICKNAME_LEN + 1];
    snprintf(nick, sizeof(nick), "%s", e->usr->usrs.nickname);
    ai_mode_stop(e);
    ai_mode_start(e, nick);
    notice_visible = false;
  }
}
