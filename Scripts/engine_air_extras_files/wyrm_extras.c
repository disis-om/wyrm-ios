#include "wyrm_extras.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <SDL3/SDL.h>

#include "wyrm_extras_data.h"
#include "backgrounds.h"

#ifndef PI
#define PI 3.14159265358979f
#endif

static texture* extras_texture;
static VkDescriptorSet extras_descriptor;
/* The bead atlas for ImGui: a special skin's accessory is drawn after its
   AIR art, as Main.as does (2026-11-08). */
static VkDescriptorSet atlas_descriptor;

void wyrm_extras_create(renderer* r, tcontext* ctx) {
  if (!r || !ctx || extras_texture) return;
  extras_texture = create_mipmap_texture(ctx, "app/res/textures/wyrm_extras.png");
  if (!extras_texture || extras_texture->size[0] < 1024) {
    SDL_Log("Wyrm extras: atlas unreadable; AIR skin art and minimap icons off");
    if (extras_texture) destroy_texture(ctx, extras_texture);
    extras_texture = NULL;
    return;
  }
  extras_descriptor = igImplVulkan_AddTexture(
      r->linear_sampler, extras_texture->view,
      VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
  if (r->tex_atlas)
    atlas_descriptor = igImplVulkan_AddTexture(r->linear_sampler, r->tex_atlas->view,
                                               VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
  SDL_Log("Wyrm extras: atlas ready (%d AIR, %d Wyrm, %d NTL icons)",
          WYRM_ART_COUNT, WYRM_ICON_COUNT, NTL_ICON_COUNT);
}

void wyrm_extras_destroy(tcontext* ctx) {
  if (extras_descriptor) igImplVulkan_RemoveTexture(extras_descriptor);
  if (atlas_descriptor) igImplVulkan_RemoveTexture(atlas_descriptor);
  atlas_descriptor = VK_NULL_HANDLE;
  extras_descriptor = VK_NULL_HANDLE;
  if (extras_texture && ctx) destroy_texture(ctx, extras_texture);
  extras_texture = NULL;
}

static VkDescriptorSet quad_set;
static bool art_covered(game_data* g, float x, float y, float r);
static void draw_art(ImDrawList* draw, tenv* env, int art, float wx, float wy,
                     float world_w, float world_h, float rot, float alpha,
                     float mww2, float mhh2);
static ImTextureRef extras_ref(void) {
  return (ImTextureRef){NULL, (ImTextureID)(uintptr_t)(quad_set ? quad_set : extras_descriptor)};
}

/* One atlas image, w x h screen pixels, turned `rot` about its pivot, which
   sits at (x, y). Starling's Image with pivotX/Y and rotation. */
static void extras_quad(ImDrawList* draw, const wyrm_extra_rect* r, float px,
                        float py, float x, float y, float w, float h,
                        float rot, ImU32 colour) {
  if (!draw || !extras_descriptor) return;
  float cs = cosf(rot), sn = sinf(rot);
  const float lx[4] = {-px * w, (1 - px) * w, (1 - px) * w, -px * w};
  const float ly[4] = {-py * h, -py * h, (1 - py) * h, (1 - py) * h};
  ImVec2 c[4];
  for (int i = 0; i < 4; i++)
    c[i] = (ImVec2){x + cs * lx[i] - sn * ly[i], y + sn * lx[i] + cs * ly[i]};
  ImDrawList_AddImageQuad(draw, extras_ref(), c[0], c[1], c[2], c[3],
                          (ImVec2){r->u0, r->v0}, (ImVec2){r->u1, r->v0},
                          (ImVec2){r->u1, r->v1}, (ImVec2){r->u0, r->v1},
                          colour);
}

static ImU32 rgb_alpha(int rgb, float a) {
  if (a < 0) a = 0;
  if (a > 1) a = 1;
  return igColorConvertFloat4ToU32((ImVec4){((rgb >> 16) & 255) / 255.0f,
                                            ((rgb >> 8) & 255) / 255.0f,
                                            (rgb & 255) / 255.0f, a});
}

/* ------------------------------------------------------------ AIR skins */

/* Main.as setSkin, `if(!param1.cusk)` branch, value for value. */
typedef struct {
  int cv;
  int bulb;   /* WYRM_ART_*, -1 none */
  int atpc;   /* antenna points */
  int atc2;   /* segment tint */
  bool abrot; /* the bulb turns with the antenna's tip */
  float bsc;  /* bulb scale */
  float blba; /* antenna alpha */
} air_antenna;

static const air_antenna ANTENNAS[] = {
    {24, WYRM_ART_ACBULB, 9, 6605031, false, 0.25f, 0.75f},
    {25, WYRM_ART_CDBULB, 9, 5648599, true, 0.34f, 1.0f},
    {37, WYRM_ART_KWKBULB, 9, 16738323, true, 0.45f, 1.0f},
    {39, WYRM_ART_PWDBULB, 9, 4510975, true, 0.25f, 1.0f},
    {42, WYRM_ART_PLAYBULB, 9, 8442064, true, 0.36f, 1.0f},
    {45, WYRM_ART_LEAFBULB, 9, 16728128, true, 0.33f, 1.0f},
    {46, WYRM_ART_SWISSBULB, 9, 16728128, true, 0.285f, 1.0f},
    {47, WYRM_ART_MOLDOVABULB, 9, 6316287, true, 0.33f, 1.0f},
    {48, WYRM_ART_VIETBULB, 9, 16728128, true, 0.3f, 1.0f},
    {49, WYRM_ART_ARGENTINABULB, 11, 8707327, true, 0.33f, 1.0f},
    {59, WYRM_ART_MOVBULB, 11, 16769088, true, 0.33f, 1.0f},
    {62, WYRM_ART_BONKBULB, 9, 16761359, true, 0.25f, 1.0f},
    {65, WYRM_ART_FGTEEVBULB, 11, 16777215, true, 0.33f, 1.0f},
};
#define ANTENNA_COUNT (int)(sizeof(ANTENNAS) / sizeof(ANTENNAS[0]))
#define ANTENNA_MAX 11

bool air_looks_on(const snake* o) {
  return o && !o->cusk && !o->wyrm_skin && o->cv >= 0 && o->cv < 66;
}

static const air_antenna* antenna_of(const snake* o) {
  if (!air_looks_on(o)) return NULL;
  for (int i = 0; i < ANTENNA_COUNT; i++)
    if (ANTENNAS[i].cv == o->cv) return ANTENNAS + i;
  return NULL;
}

float air_looks_pma(const snake* o) {
  if (!air_looks_on(o)) return 2.3f;
  if (o->cv == 27) return 4.0f;
  if (o->cv == 41) return 3.0f;
  return 2.3f;
}

float air_looks_swell(const snake* o, int bead_from_head) {
  if (!air_looks_on(o) || o->cv != 27 || bead_from_head >= 4 || bead_from_head < 0)
    return 1.0f;
  return 1.0f + (4 - bead_from_head) * 0.06f;
}

float air_looks_density(const snake* o) {
  return air_looks_on(o) && o->cv == 60 ? 2.0f : 1.0f;
}

void air_looks_eye_params(const snake* o, float* ed, float* esp, float* er) {
  if (!air_looks_on(o) || o->cv != 41) return;
  /* ed/esp arrive already times ssc; keep that scale. */
  float scale = *ed / 6.0f;
  *ed = 34.0f * scale;
  *esp = 14.0f * scale;
  *er = 8.0f;
}

float air_looks_eye_rim(const snake* o) {
  return air_looks_on(o) && o->cv == 41 ? 3.0f : 0.0f;
}

bool air_looks_hide_eyes(const snake* o) {
  return air_looks_on(o) && (o->cv == 27 || o->cv == 40);
}

typedef struct {
  int id;
  bool used, shown;
  uint64_t last_ns, owed_ns;
  float x[ANTENNA_MAX], y[ANTENNA_MAX], vx[ANTENNA_MAX], vy[ANTENNA_MAX];
  float atba;
} antenna_slot;

#define ANTENNA_SLOTS 64
static antenna_slot slots[ANTENNA_SLOTS];

void air_looks_forget(int snake_id) {
  for (int i = 0; i < ANTENNA_SLOTS; i++)
    if (slots[i].used && slots[i].id == snake_id) slots[i].used = false;
}

static antenna_slot* slot_for(int id, uint64_t now) {
  antenna_slot* free_slot = NULL;
  antenna_slot* oldest = slots;
  for (int i = 0; i < ANTENNA_SLOTS; i++) {
    antenna_slot* s = slots + i;
    if (s->used && s->id == id) return s;
    if (!s->used && !free_slot) free_slot = s;
    if (s->last_ns < oldest->last_ns) oldest = s;
  }
  antenna_slot* s = free_slot ? free_slot : oldest;
  memset(s, 0, sizeof(*s));
  s->used = true;
  s->id = id;
  s->last_ns = now;
  return s;
}

static float rnd1(void) { return (float)rand() / (float)RAND_MAX * 2.0f - 1.0f; }

/* One Main.as frame of the antenna (its 60 Hz frame), in world units. */
static void antenna_step(antenna_slot* s, const air_antenna* a, float ax,
                         float ay, float ang, float ssc) {
  int last = a->atpc - 1;
  s->x[0] = ax;
  s->y[0] = ay;
  if (!s->shown) {
    s->shown = true;
    for (int i = 1; i <= last; i++) {
      s->x[i] = ax - cosf(ang) * i * 4 * ssc;
      s->y[i] = ay - sinf(ang) * i * 4 * ssc;
      s->vx[i] = s->vy[i] = 0;
    }
  }
  for (int i = 1; i <= last; i++) {
    float tx = s->x[i - 1] + rnd1();
    float ty = s->y[i - 1] + rnd1();
    float t = atan2f(s->y[i] - ty, s->x[i] - tx);
    tx += cosf(t) * 4 * ssc;
    ty += sinf(t) * 4 * ssc;
    s->vx[i] += (tx - s->x[i]) * 0.1f;
    s->vy[i] += (ty - s->y[i]) * 0.1f;
    s->x[i] += s->vx[i];
    s->y[i] += s->vy[i];
    s->vx[i] *= 0.88f;
    s->vy[i] *= 0.88f;
    float dx = s->x[i] - s->x[i - 1], dy = s->y[i] - s->y[i - 1];
    if (sqrtf(dx * dx + dy * dy) > 4 * ssc) {
      t = atan2f(dy, dx);
      s->x[i] = s->x[i - 1] + cosf(t) * 4 * ssc;
      s->y[i] = s->y[i - 1] + sinf(t) * 4 * ssc;
    }
  }
  if (a->abrot) {
    float t = atan2f(s->y[last] - s->y[last - 1], s->x[last] - s->x[last - 1]);
    float v = fmodf(t - s->atba, 2 * PI);
    if (v < -PI) v += 2 * PI;
    else if (v > PI) v -= 2 * PI;
    s->atba = fmodf(s->atba + v * 0.15f, 2 * PI);
  }
}

static void draw_antenna(tenv* env, snake* o, const air_antenna* a, float hx,
                         float hy, float ssc, float alpha, float mww2,
                         float mhh2, ImDrawList* draw) {
  game_data* g = &env->usr->gdata;
  float gsc = g->data.gsc;
  float ang = o->ang;
  float ax = hx - cosf(ang) * 8 * ssc;
  float ay = hy - sinf(ang) * 8 * ssc;
  uint64_t now = SDL_GetTicksNS();
  antenna_slot* s = slot_for(o->id, now);
  uint64_t step = 16666667ull;
  uint64_t dt = now - s->last_ns;
  /* Off screen a while (AIR: antenna_shown = false): lay it out again. */
  if (dt > 250000000ull) s->shown = false;
  if (!s->shown) dt = step;
  s->owed_ns += dt;
  s->last_ns = now;
  int steps = 0;
  while (s->owed_ns >= step && steps < 4) {
    antenna_step(s, a, ax, ay, ang, ssc);
    s->owed_ns -= step;
    steps++;
  }
  if (s->owed_ns > step) s->owed_ns = 0;
  if (!s->shown) antenna_step(s, a, ax, ay, ang, ssc);

  (void)draw;
  int last = a->atpc - 1;
  /* The rope in the snake's own sprite order (2026-11-08): round beads of
     Main.as's segment thickness (20 px x 0.3 ssc) on each link and between
     them, in atc2, so other snakes cover it as they cover the body. */
  float rr = (float)((a->atc2 >> 16) & 255) / 255.0f, rg = (float)((a->atc2 >> 8) & 255) / 255.0f,
        rb = (float)(a->atc2 & 255) / 255.0f, ra = alpha * a->blba;
  float d = 6.0f * ssc * gsc;
  for (int i = last; i >= 0; i--) {
    for (int half = 0; half < (i > 0 ? 2 : 1); half++) {
      float wx = half ? (s->x[i] + s->x[i - 1]) * 0.5f : s->x[i];
      float wy = half ? (s->y[i] + s->y[i - 1]) * 0.5f : s->y[i];
      float sx = mww2 + (wx - g->data.view_xx) * gsc, sy = mhh2 + (wy - g->data.view_yy) * gsc;
      bp_renderer_push(env->usr->r->bpr,
                       &(bp_instance){{sx - d * 0.5f, sy - d * 0.5f, d, 0},
                                      {-1.0f, 0, 0, 0}, {rr, rg, rb, ra}});
    }
  }
  const wyrm_extra_art* bulb = WYRM_ART + a->bulb;
  float k = a->bsc * ssc;
  draw_art(NULL, env, a->bulb, s->x[last], s->y[last], bulb->ow * k, bulb->oh * k,
           a->abrot ? s->atba : 0.0f, alpha * a->blba, mww2, mhh2);
}

/* Main.as draws a snake's art in that snake's own batch, so a snake drawn
   later (lower index here, redraw.c draws from the last) covers it. The art
   is drawn after every snake (ImGui), so a piece that sits under a later
   snake's body is left out instead (OM, 2026-11-08). */
static int art_index = -1;

/* Only a piece whose centre is under another snake's body hides (2026-11-08:
   with the piece's own size added, eyes vanished whenever a snake came near).
   A snake whose head is farther than its whole body could reach is skipped
   without walking its points, and the walk takes every other point. */
static bool art_covered(game_data* g, float x, float y, float r) {
  (void)r;
  if (art_index <= 0) return false;
  int n = (int)tdarray_length(g->data.snakes);
  for (int i = 0; i < art_index && i < n; i++) {
    snake* k = g->data.snakes + i;
    if (k->dead) continue;
    float br = 14.5f * k->sc;
    float br2 = br * br;
    float dx = k->xx - x, dy = k->yy - y;
    int pn = (int)tdarray_length(k->pts);
    float reach = (float)pn * 44.0f * (k->sc > 1.0f ? k->sc : 1.0f) + br;
    if (dx * dx + dy * dy > reach * reach) continue;
    if (dx * dx + dy * dy < br2) return true;
    for (int p = pn - 1; p >= 0; p -= 2) {
      float px = k->pts[p].xx + k->pts[p].fx - x, py = k->pts[p].yy + k->pts[p].fy - y;
      if (px * px + py * py < br2) return true;
    }
  }
  return false;
}

static void draw_art(ImDrawList* draw, tenv* env, int art, float wx, float wy,
                     float world_w, float world_h, float rot, float alpha,
                     float mww2, float mhh2) {
  /* In the snake's own sprite order (bead pass, binding 6; 2026-11-08), so a
     snake drawn later covers it, as in Main.as's snake_batch. The cell is
     square with the piece in its middle (tools/wyrm-extras/make.py). */
  (void)draw;
  (void)world_h;
  game_data* g = &env->usr->gdata;
  const wyrm_extra_art* a = WYRM_ART + art;
  if (a->ow <= 0) return;
  float k = world_w / a->ow;                  /* world units per texel */
  float side = (float)a->r.w * k;             /* the square cell, world */
  float ox = (0.5f - a->px) * side, oy = (0.5f - a->py) * side;
  float cs = cosf(rot), sn = sinf(rot);
  float cx = wx + cs * ox - sn * oy, cy = wy + sn * ox + cs * oy;
  float gsc = g->data.gsc;
  float sx = mww2 + (cx - g->data.view_xx) * gsc, sy = mhh2 + (cy - g->data.view_yy) * gsc;
  float sd = side * gsc;
  if (alpha <= 0 || !env->usr->r) return;
  bp_renderer_push(env->usr->r->bpr,
                   &(bp_instance){{sx - sd * 0.5f, sy - sd * 0.5f, sd, rot},
                                  {a->r.u0 + 8.0f, a->r.v0, a->r.u1 - a->r.u0, a->r.v1 - a->r.v0},
                                  {1, 1, 1, alpha}});
}

bool air_looks_owns_accessory(const snake* o) {
  /* The art is in the bead pass now, before the sprite accessory (2026-11-08). */
  (void)o;
  return false;
}

/* The accessory after the art, as Main.as draws it (atlas uv from game_data.c,
   the same rotation the sprite pass gives it). */
static void draw_accessory(ImDrawList* draw, tenv* env, snake* o, float hx, float hy,
                           float fang, float lsz, float ed, float alpha, float mww2,
                           float mhh2) {
  game_data* g = &env->usr->gdata;
  if (o->accessory >= NUM_ACCESSORIES) return;
  accessory_data* acc = g->accessories + o->accessory;
  float wx = hx + acc->of * cosf(fang) * ed, wy = hy + acc->of * sinf(fang) * ed;
  if (art_covered(g, wx, wy, lsz * acc->sc * 0.3f)) return;
  float m = lsz * g->data.gsc * acc->sc;
  wyrm_extra_rect r = {acc->uv.x, acc->uv.y, acc->uv.x + acc->uv.z, acc->uv.y + acc->uv.w, 0, 0};
  quad_set = atlas_descriptor;
  extras_quad(draw, &r, 0.5f, 0.5f, mww2 + (wx - g->data.view_xx) * g->data.gsc,
              mhh2 + (wy - g->data.view_yy) * g->data.gsc, 2 * m, 2 * m, fang,
              rgb_alpha(0xFFFFFF, alpha));
  quad_set = VK_NULL_HANDLE;
}

void air_looks_draw(tenv* env, snake* o, float hx, float hy, float fang,
                    float ssc, float alpha, float mww2, float mhh2, float lsz,
                    float ed, bool accessory) {
  if (!env || !extras_texture || !air_looks_on(o)) return;
  game_data* g = &env->usr->gdata;
  float sx = mww2 + (hx - g->data.view_xx) * g->data.gsc;
  float sy = mhh2 + (hy - g->data.view_yy) * g->data.gsc;
  float margin = 400.0f * ssc * g->data.gsc + 64.0f;
  if (sx < -margin || sy < -margin || sx > 2 * mww2 + margin || sy > 2 * mhh2 + margin)
    return;
  ImDrawList* draw = igGetWindowDrawList();
  float c = cosf(fang), s = sinf(fang);
  float cl = cosf(fang - PI / 2), sl = sinf(fang - PI / 2);
  float cr = cosf(fang + PI / 2), sr = sinf(fang + PI / 2);

  if (o->cv == 27) {
    /* One eye: the ball 3 ssc ahead, 29 ssc wide; the pupil 14 ssc. */
    float ed = 3 * ssc;
    draw_art(draw, env, WYRM_ART_JSEBI, hx + c * ed, hy + s * ed, 29 * ssc,
             29 * ssc, 0, alpha, mww2, mhh2);
    draw_art(draw, env, WYRM_ART_JSEPI, hx + c * (ed + 0.15f) + o->rex * ssc,
             hy + s * (ed + 0.15f) + o->rey * ssc, 14 * ssc, 14 * ssc, 0, alpha,
             mww2, mhh2);
  } else if (o->cv == 40) {
    /* Closed eyes (jyt) and the mouth. */
    float ed = -3 * ssc, esp = 7 * ssc, k = 0.25f * ssc;
    const wyrm_extra_art* ce = WYRM_ART + WYRM_ART_CLOSED_EYE;
    draw_art(draw, env, WYRM_ART_CLOSED_EYE,
             hx + c * (ed + 0.5f) + o->rex * ssc + cl * esp,
             hy + s * (ed + 0.5f) + o->rey * ssc + sl * esp, ce->ow * k,
             ce->oh * k, fang, alpha, mww2, mhh2);
    draw_art(draw, env, WYRM_ART_CLOSED_EYE,
             hx + c * (ed + 0.5f) + o->rex * ssc + cr * esp,
             hy + s * (ed + 0.5f) + o->rey * ssc + sr * esp, ce->ow * k,
             ce->oh * k, fang, alpha, mww2, mhh2);
    const wyrm_extra_art* jm = WYRM_ART + WYRM_ART_JMOUTH;
    float mk = 0.16f * ssc;
    ed = 5 * ssc;
    draw_art(draw, env, WYRM_ART_JMOUTH, hx + c * (ed + 0.5f) + o->rex * ssc,
             hy + s * (ed + 0.5f) + o->rey * ssc, jm->ow * mk, jm->oh * mk,
             fang, alpha, mww2, mhh2);
  } else if (o->cv == 41) {
    /* Slug stalks over the eyes, 0.4 rad out to each side. */
    const wyrm_extra_art* st = WYRM_ART + WYRM_ART_SEST;
    float k = 0.25f * ssc;
    draw_art(draw, env, WYRM_ART_SEST, hx + c * 13 * ssc + cl * (6 * ssc + 0.5f),
             hy + s * 13 * ssc + sl * (6 * ssc + 0.5f), st->ow * k, st->oh * k,
             fang - 0.4f, alpha, mww2, mhh2);
    draw_art(draw, env, WYRM_ART_SEST, hx + c * 13 * ssc + cr * (6 * ssc + 0.5f),
             hy + s * 13 * ssc + sr * (6 * ssc + 0.5f), st->ow * k, st->oh * k,
             fang + 0.4f, alpha, mww2, mhh2);
  }

  if (accessory && air_looks_owns_accessory(o))
    draw_accessory(draw, env, o, hx, hy, fang, lsz, ed, alpha, mww2, mhh2);
  const air_antenna* a = antenna_of(o);
  if (a) draw_antenna(env, o, a, hx, hy, ssc, alpha, mww2, mhh2, draw);
}

/* ------------------------------------------------------------ minimap */

bool wyrm_extras_ntl_mark(ImDrawList* draw, ImVec2 at, float radius, int di) {
  if (!draw || !extras_descriptor) return false;
  const wyrm_extra_rect* r = NULL;
  if (di >= 0 && di < NTL_ICON_COUNT) r = NTL_ICONS + di;
  else if (di >= 996 && di <= 1000) r = NTL_ICON_SPECIAL + (di - 996);
  if (!r || r->w <= 0) return false;
  /* NTL draws them 14 px over an 80 px map; here they follow the dot. */
  float size = radius * 3.0f;
  if (size < 13.0f) size = 13.0f;
  if (size > 22.0f) size = 22.0f;
  extras_quad(draw, r, 0.5f, 0.5f, at.x, at.y, size, size, 0,
              rgb_alpha(0xFFFFFF, 1));
  return true;
}

typedef struct {
  float x, y;
  int icon;
} friend_mark;

#define FRIEND_MAX 64
static friend_mark friends[FRIEND_MAX];
static int friend_count;
static SDL_Mutex* friend_mutex;

void wyrm_extras_set_friends(const char* packed) {
  friend_mark parsed[FRIEND_MAX];
  int count = 0;
  const char* line = packed ? packed : "";
  while (*line && count < FRIEND_MAX) {
    float x = 0, y = 0;
    int icon = 0;
    if (sscanf(line, "%f\t%f\t%d", &x, &y, &icon) == 3 && isfinite(x) &&
        isfinite(y)) {
      parsed[count].x = x;
      parsed[count].y = y;
      parsed[count].icon = icon >= 0 && icon < WYRM_ICON_COUNT ? icon : 0;
      count++;
    }
    const char* end = strchr(line, '\n');
    if (!end) break;
    line = end + 1;
  }
  if (!friend_mutex) friend_mutex = SDL_CreateMutex();
  if (friend_mutex) SDL_LockMutex(friend_mutex);
  memcpy(friends, parsed, sizeof(friend_mark) * (size_t)count);
  friend_count = count;
  if (friend_mutex) SDL_UnlockMutex(friend_mutex);
}

#ifdef WYRM_IOS
void WyrmIOSSetFriendMarks(const char* packed) { wyrm_extras_set_friends(packed); }
#endif
#ifdef WYRM_SDL_JNI
#include <jni.h>
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetFriendMarks(JNIEnv* env, jclass clazz,
                                                         jstring packed) {
  (void)clazz;
  const char* text = packed ? (*env)->GetStringUTFChars(env, packed, NULL) : "";
  wyrm_extras_set_friends(text);
  if (packed) (*env)->ReleaseStringUTFChars(env, packed, text);
}
#endif

void wyrm_extras_draw_friends(tenv* env, float left, float top, float diameter) {
  if (!env || !extras_descriptor || diameter <= 0 || !friend_mutex) return;
  friend_mark local[FRIEND_MAX];
  SDL_LockMutex(friend_mutex);
  int count = friend_count;
  memcpy(local, friends, sizeof(friend_mark) * (size_t)count);
  SDL_UnlockMutex(friend_mutex);
  if (count <= 0) return;
  game_data* g = &env->usr->gdata;
  float world_radius = g->data.flux_grd;
  if (world_radius <= 1.0f) return;
  float cx = left + diameter * 0.5f, cy = top + diameter * 0.5f;
  float reach = diameter * 0.5f * 0.9f;
  float size = diameter * 0.075f;
  if (size < 14.0f) size = 14.0f;
  if (size > 24.0f) size = 24.0f;
  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(NULL);
  for (int i = 0; i < count; i++) {
    float nx = (local[i].x - g->data.grd) / world_radius;
    float ny = (local[i].y - g->data.grd) / world_radius;
    float out = sqrtf(nx * nx + ny * ny);
    if (out > 1.0f) {
      nx /= out;
      ny /= out;
    }
    extras_quad(draw, WYRM_ICONS + local[i].icon, 0.5f, 0.5f, cx + nx * reach,
                cy + ny * reach, size, size, 0, rgb_alpha(0xFFFFFF, 1));
  }
}

/* ------------------------------------------------------------ gallery floors */

/* A floor from the player's own photo (OM, 2026-11-08): the app shrinks it
   (long side 2048 px), saves it in its own files and hands the path here; the
   stored background index is BACKGROUND_CUSTOM. One pixel is two world units,
   so a 2048 px photo tiles every 4096 units. Never sent anywhere. */
static char custom_floor_path[1024];
background_def wyrm_custom_floor = {"custom", "Your photo", NULL, 4096.0f, 4096.0f};
int wyrm_custom_floor_generation;

void wyrm_custom_floor_set(const char* path, int width, int height) {
  if (!path || !path[0] || width <= 0 || height <= 0) {
    custom_floor_path[0] = '\0';
    wyrm_custom_floor.path = NULL;
  } else {
    snprintf(custom_floor_path, sizeof(custom_floor_path), "%s", path);
    wyrm_custom_floor.path = custom_floor_path;
    wyrm_custom_floor.tile_w = 2.0f * (float)width;
    wyrm_custom_floor.tile_h = 2.0f * (float)height;
  }
  wyrm_custom_floor_generation++;
  SDL_Log("Wyrm floor: your photo %s (%dx%d)", wyrm_custom_floor.path ? "set" : "cleared",
          width, height);
}

#ifdef WYRM_IOS
void WyrmIOSSetCustomFloor(const char* path, int width, int height) {
  wyrm_custom_floor_set(path, width, height);
}
#endif
#ifdef WYRM_SDL_JNI
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetCustomFloor(JNIEnv* env, jclass clazz,
                                                         jstring path, jint width,
                                                         jint height) {
  (void)clazz;
  const char* text = path ? (*env)->GetStringUTFChars(env, path, NULL) : "";
  wyrm_custom_floor_set(text, (int)width, (int)height);
  if (path) (*env)->ReleaseStringUTFChars(env, path, text);
}
#endif

VkImageView wyrm_extras_view(renderer* r) {
  if (extras_texture) return extras_texture->view;
  return r && r->tex_atlas ? r->tex_atlas->view : VK_NULL_HANDLE;
}

/* Main.as auto zoom, see game/oef.c (OM, 2026-11-08). */
float wyrm_air_zoom = 1.0f;

/* Settings > Display > Auto zoom (OM, 2026-11-09): off keeps the player's
   own zoom (game/oef.c). On by default. Any thread; read each frame. */
static volatile int auto_zoom_on = 1;
void wyrm_extras_set_auto_zoom(bool on) { auto_zoom_on = on ? 1 : 0; }
bool wyrm_extras_auto_zoom(void) { return auto_zoom_on != 0; }

#ifdef WYRM_SDL_JNI
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetAutoZoom(JNIEnv* jenv,
                                                      jclass clazz,
                                                      jboolean on) {
  (void)jenv;
  (void)clazz;
  wyrm_extras_set_auto_zoom(on == JNI_TRUE);
}
#endif
