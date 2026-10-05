#include "tags.h"

#include <math.h>
#include <string.h>

#include "../user.h"
#include "tag_table.h"

/*
 * A tag is a bobble on the end of a rope, and the rope is a real one.
 *
 * This is the mod's own mechanism in the mod's own numbers, read off the draw
 * path in `main-mt.js` rather than off a summary of it — the last two attempts
 * at this were written from a summary and both were wrong. Ten points, each
 * pulled towards a spot a little past the point in front of it and then damped,
 * with a hard limit on how far two neighbours may drift apart. The bobble hangs
 * off the last point, not off the head, and turns to face the last segment.
 * Because the tip lags, the bobble lags; because the chain is springy, it
 * overshoots and settles.
 *
 * Two things here are easy to get subtly wrong and were:
 *
 *   The rope is anchored and seeded along `ang`, the direction the snake is
 *   actually travelling — not along the eased angle the head sprite is drawn
 *   at. The mod uses its heading for the tag and its eased angle for the eyes,
 *   and they are different fields for a reason.
 *
 *   The pull only ever maintains the direction the chain already points, so a
 *   rope laid down facing the wrong way stays facing the wrong way for as long
 *   as the snake lives. Everything that decides the initial direction therefore
 *   has to be right, and a rope that has gone bad has to be dropped rather than
 *   nursed. `rope_broken` is that drop.
 *
 * The numbers are written up in ntl-tags.md.
 */

#define TWO_PI 6.28318530718f

/* Points in the rope, and the length of one segment in snake-widths. Both are
   the mod's; ten points is enough to look like rope and few enough to run a
   hundred snakes' worth every frame. */
#define ROPE_POINTS 10
#define ROPE_SEGMENT 4.0f

/*
 * How the rope is stepped: NTL 9.68's own two integrators, as written in
 * `legacy/ntl 9.68/main-mt.js` (N5), picked by Swing the way NTL picks them
 * (OM, 2026-10-05: "same to same original NTL").
 *
 *   Swing 1, the default: one step per drawn frame with the constants NTL
 *   uses at its default "Browser default" FPS setting (ri = 1000, so
 *   mb = 6.94): push .2 mb, stiffness .005 mb, damping .05 mb, advance mb/17.
 *
 *   Swing above 1: 16.667 ms steps caught up to the clock, at most four a
 *   frame and at most 250 ms owed, with push 3.3332 + .6668 s, stiffness
 *   .08333 + .01667 s, damping .838 + .145 s (at most .985), advance 1; the
 *   drawn rope is then eased .248 a frame towards the simulated one.
 *
 * Wyrm used to run the second set 240 times a second on Android (a stiff rope
 * that stayed straight) and 60 times a second on iOS whatever the screen did
 * (a rope that moved in jumps on a 120 Hz phone).
 */
#define NTL_DEFAULT_MB 6.94
/* NTL's clock, in its own units: milliseconds, in doubles. */
#define ROPE_STEP_MS 16.667
#define ROPE_MAX_STEPS 4
#define ROPE_MAX_DEBT_MS 250.0

/* How far behind the head the rope is pinned, and the height a bobble is
   allowed to reach when small tags are on — both in snake-widths. */
#define ROPE_ANCHOR 8.0f
#define SMALL_TAG_HEIGHT 40.6f

/* Every tag's artwork is drawn at this fraction of its own size before the
   player's own size setting is applied. */
#define TAG_SCALE 0.285f

/* How much of the way the bobble turns towards the rope's last segment each
   drawn frame: NTL's `EA += .15 * delta`, once a frame, as NTL does it. */
#define TAG_TURN 0.15

/* The mod drops a rope whose anchor has left the world it can see, so that it
   is laid out cleanly again when it comes back rather than dragged across the
   map. This is the margin on that rectangle, in world units. */
#define ROPE_BOUNDS_MARGIN 210.0f

/* What the skin editor's preview rope hangs under, so that it dangles and
   sways instead of pointing stiffly at nothing. The mod applies these to its
   own skin chooser; they are in snake-widths per step, so they are scaled up
   with the preview the same way every other length here is. */
#define PREVIEW_GRAVITY 0.3f
#define PREVIEW_SWAY 0.14f

/*
 * Where each snake's rope currently is.
 *
 * Kept beside the snakes rather than inside them: a snake is rebuilt from the
 * network constantly, and a rope that started again on every packet would not
 * be a rope. Indexed by snake id, which is what the arena gives us.
 */
#define TAG_SLOTS 512

/* How many frames a rope may go undrawn before the next snake to claim its id
   is treated as a new snake rather than the old one coming back. The arena
   reuses ids, and a recycled id inheriting a rope stretched across the map
   from a snake that is gone was one of the ways this looked broken. */
#define SLOT_STALE_FRAMES 30

/* The rope the skin editor's preview hangs from. Arena snakes are numbered
   from zero, so a negative id can never be one of theirs. */
#define PREVIEW_SNAKE_ID (-7)

typedef struct tag_slot {
  int id;
  int tag;
  bool used;
  bool seeded;
  unsigned frame;    /* the frame this rope was last drawn in */
  double angle; /* the bobble's turn, NTL's `EA` (a JS number) */
  float x[ROPE_POINTS];
  float y[ROPE_POINTS];
  float vx[ROPE_POINTS];
  float vy[ROPE_POINTS];
  double debt; /* ms owed to the simulation; below zero: one step owed */
  /* The rope as drawn when Swing is above one (NTL's eased copy, which NTL
     keeps in plain JS numbers, so doubles). */
  double draw_x[ROPE_POINTS];
  double draw_y[ROPE_POINTS];
  bool draw_seeded;
} tag_slot;

static tag_slot slots[TAG_SLOTS];
static double last_frame_time = 0.0;
static double frame_delta_ms = ROPE_STEP_MS;
static unsigned frame_number = 0;

int tags_count(void) { return TAG_COUNT; }

bool tags_valid(int index) { return index >= 0 && index < TAG_COUNT; }

int tags_ntl_id(int index) {
  return tags_valid(index) ? TAG_TABLE[index].ntl : -1;
}

int tags_from_ntl_id(int ntl) {
  for (int i = 0; i < TAG_COUNT; ++i)
    if (TAG_TABLE[i].ntl == ntl) return i;
  return -1;
}

/**
 * The rope belonging to a snake id, allocating one if it has none.
 *
 * The table is small and the arena is not, so a slot that has not been drawn
 * for a while is taken from whoever held it. Without that the table filled with
 * snakes that had died a match ago and every later snake — the player's own
 * included — silently got no tag at all.
 */
static tag_slot* slot_find(int id) {
  for (int i = 0; i < TAG_SLOTS; ++i) {
    tag_slot* slot = slots + i;
    if (slot->used && slot->id == id) {
      /* Gone long enough that this is far more likely to be a new snake handed
         a recycled id than the same one coming back. Start its rope again. */
      if (frame_number - slot->frame > SLOT_STALE_FRAMES) slot->seeded = false;
      return slot;
    }
  }
  return NULL;
}

static tag_slot* slot_for(int id) {
  tag_slot* slot = slot_find(id);
  if (slot) return slot;

  tag_slot* free_slot = NULL;
  tag_slot* oldest = NULL;
  for (int i = 0; i < TAG_SLOTS; ++i) {
    if (!slots[i].used) {
      free_slot = slots + i;
      break;
    }
    if (!oldest || slots[i].frame < oldest->frame) oldest = slots + i;
  }

  if (!free_slot) {
    /* Everything in the table was drawn this frame; there is genuinely no room
       and a tag has to go without. Otherwise take the least recently drawn. */
    if (!oldest || oldest->frame == frame_number) return NULL;
    free_slot = oldest;
  }

  memset(free_slot, 0, sizeof(*free_slot));
  free_slot->used = true;
  free_slot->id = id;
  free_slot->tag = -1;
  return free_slot;
}

void tags_set(int snake_id, int tag) {
  /* The whole table arrives from the NTL network each time, most of it saying
     that most snakes are wearing nothing. Claiming a rope for every one of
     those would fill the table with snakes that have no tag, which is how it
     used to starve the ones that do. */
  tag_slot* slot = tags_valid(tag) ? slot_for(snake_id) : slot_find(snake_id);
  if (slot) slot->tag = tag;
}

void tags_forget_all(void) { memset(slots, 0, sizeof(slots)); }

/* The tag socket closed (OM, 2026-10-06: tags flickered once a second and
   went straight in turns). It retries every second, and each close used to
   wipe every rope, laying them out straight again each time. Only the tag
   numbers the socket sent go; the ropes keep swinging, and a snake falls
   back to its skin-block corner tag (yours to your own) meanwhile. */
void tags_clear_network(void) {
  for (int i = 0; i < TAG_SLOTS; ++i) slots[i].tag = -1;
}

void tags_tick(tenv* env) {
  (void)env;
  /* The ropes are advanced when their snakes are drawn, which is the only
     moment a snake's head position is known. All that is needed here is how
     much time has passed since the last frame, measured once so that every
     rope in the frame is advanced by the same amount. */
  double now = igGetTime();
  double delta_ms = (now - last_frame_time) * 1000.0;
  last_frame_time = now;
  if (delta_ms < 0.0 || delta_ms > ROPE_MAX_DEBT_MS) delta_ms = ROPE_STEP_MS;
  frame_delta_ms = delta_ms;
  ++frame_number;
}

/**
 * One step of the rope.
 *
 * Each point is pulled towards a spot a little way past the point in front of
 * it, along the line between them; the pull goes into a velocity rather than
 * straight into the position, which is what lets it overshoot. Then the
 * velocity is bled off, and finally the point is dragged back if it has
 * strayed further than a segment's length from its neighbour, so that the rope
 * can stretch a little under a hard turn but never come apart.
 *
 * `fallback` is the direction to use when two points have landed on top of one
 * another. It matters more than it looks: the angle between them is otherwise
 * atan2(0, 0), which is zero, which would push that part of the rope due east
 * whatever the snake was doing — and since the pull only maintains whatever
 * direction the chain already has, east is where it would then stay.
 */
/*
 * The angle of a link, the way NTL 9.68 takes it: from its 256 x 256 `Zu`
 * table (atan2 of whole steps around 128), with the link scaled by 32, 16, 8
 * or 1 by how short it is, and plain atan2 only for a link 127 or longer.
 * A short link's angle is therefore stepped, and on a rope that swings freely
 * those steps are part of how NTL's tag moves (OM, 2026-10-05: same as NTL).
 * The table holds floats, as NTL's Float32Array does.
 */
static float ntl_angle(double dx, double dy) {
  double s = (dx >= -4.0 && dy >= -4.0 && dx < 4.0 && dy < 4.0)       ? 32.0
             : (dx >= -8.0 && dy >= -8.0 && dx < 8.0 && dy < 8.0)     ? 16.0
             : (dx >= -16.0 && dy >= -16.0 && dx < 16.0 && dy < 16.0) ? 8.0
             : (dx >= -127.0 && dy >= -127.0 && dx < 127.0 && dy < 127.0)
                 ? 1.0
                 : 0.0;
  if (s == 0.0) return (float)atan2(dy, dx);
  int qx = (int)(s * dx + 128.0) - 128;
  int qy = (int)(s * dy + 128.0) - 128;
  return (float)atan2((double)qy, (double)qx);
}

/* NTL keeps the rope in Float32Arrays and does every sum in doubles; so does
   this, so the two land on the same floats (OM, 2026-10-05). */
static void rope_step(tag_slot* slot, double scale, double push,
                      double stiffness, double advance, double damping,
                      double segment, float fallback, bool exact_limit) {
  for (int i = 1; i < ROPE_POINTS; ++i) {
    double px = slot->x[i - 1];
    double py = slot->y[i - 1];
    double dx = slot->x[i] - px;
    double dy = slot->y[i] - py;
    double angle = (dx == 0.0 && dy == 0.0) ? fallback : ntl_angle(dx, dy);
    double tx = px + push * cos(angle) * scale;
    double ty = py + push * sin(angle) * scale;

    slot->vx[i] = (float)(slot->vx[i] + stiffness * (tx - slot->x[i]));
    slot->vy[i] = (float)(slot->vy[i] + stiffness * (ty - slot->y[i]));
    slot->x[i] = (float)(slot->x[i] + advance * slot->vx[i]);
    slot->y[i] = (float)(slot->y[i] + advance * slot->vy[i]);
    slot->vx[i] = (float)(slot->vx[i] * damping);
    slot->vy[i] = (float)(slot->vy[i] * damping);

    dx = (double)slot->x[i] - slot->x[i - 1];
    dy = (double)slot->y[i] - slot->y[i - 1];
    if (sqrt(dx * dx + dy * dy) > segment) {
      /* NTL's default path takes this one with plain atan2, its clocked path
         from the table. */
      double a = (dx == 0.0 && dy == 0.0) ? fallback
                 : exact_limit            ? atan2(dy, dx)
                                          : ntl_angle(dx, dy);
      slot->x[i] = (float)(slot->x[i - 1] + segment * cos(a));
      slot->y[i] = (float)(slot->y[i - 1] + segment * sin(a));
    }
  }
}

/** Straightens the rope out behind the head, for a snake that has just arrived. */
static void rope_seed(tag_slot* slot, float ax, float ay, float angle,
                      float segment) {
  float cs = cosf(angle);
  float sn = sinf(angle);
  for (int i = 0; i < ROPE_POINTS; ++i) {
    slot->x[i] = ax - cs * i * segment;
    slot->y[i] = ay - sn * i * segment;
    slot->vx[i] = 0.0f;
    slot->vy[i] = 0.0f;
  }
  slot->seeded = true;
  /* Below zero: the next clocked frame owes one whole step, as NTL's clock
     starts 16.667 ms back on a fresh rope (`_tag_lt = now - 16.667`). */
  slot->debt = -1.0f;
  slot->draw_seeded = false;
}

/**
 * Whether this rope has stopped being a rope.
 *
 * Nine segments is the furthest the tip can legitimately be from the anchor,
 * so anything past that means the chain has been pulled apart by something the
 * simulation cannot undo — a teleport, a scale that jumped, a slot inherited
 * from a snake that is gone. The mod never has to ask, because it throws the
 * rope away whenever the anchor leaves the screen and lays a fresh one when it
 * returns. That covers every snake except the one in the middle of the screen,
 * which is the player's own, which is the one they are looking at.
 */
static bool rope_broken(const tag_slot* slot, float segment) {
  float dx = slot->x[ROPE_POINTS - 1] - slot->x[0];
  float dy = slot->y[ROPE_POINTS - 1] - slot->y[0];
  float span = (ROPE_POINTS - 1) * segment;
  /* NTL never re-lays a rope on screen, and a near miss here laid this one
     straight again mid-swing: only a broken number or a real jump counts
     (OM, 2026-10-05). The step's own limit keeps every link in reach. */
  if (!isfinite(dx) || !isfinite(dy)) return true;
  return dx * dx + dy * dy > span * span * 9.0f;
}

/**
 * Lays the rope's path into the draw list, from the far end back towards the
 * head, as a chain of curves through the midpoints between the points. Drawing
 * it straight through the points themselves would show every joint.
 */
static void rope_path(ImDrawList* draw, const float* sx, const float* sy,
                      int from, int to, bool close_to_anchor) {
  ImDrawList_PathLineTo(draw, (ImVec2){sx[from], sy[from]});
  for (int i = from - 1; i >= to; --i) {
    ImVec2 control = {sx[i], sy[i]};
    ImVec2 end = {(sx[i] + sx[i - 1]) * 0.5f, (sy[i] + sy[i - 1]) * 0.5f};
    ImDrawList_PathBezierQuadraticCurveTo(draw, control, end, 0);
  }
  if (close_to_anchor)
    ImDrawList_PathBezierQuadraticCurveTo(draw, (ImVec2){sx[1], sy[1]},
                                          (ImVec2){sx[0], sy[0]}, 0);
}

static ImU32 accent(unsigned int rgb, float alpha) {
  return igColorConvertFloat4ToU32((ImVec4){((rgb >> 16) & 0xFF) / 255.0f,
                                            ((rgb >> 8) & 0xFF) / 255.0f,
                                            (rgb & 0xFF) / 255.0f, alpha});
}

/**
 * Draws one tag, wherever it is.
 *
 * The rope lives in world coordinates and is turned into screen coordinates by
 * `zoom` and the two offsets, which is what keeps it still under a moving
 * camera. The skin editor's preview passes a zoom of one and no offset, so its
 * world and its screen are the same thing and the same code serves both — the
 * preview is the tag, not a drawing of one.
 */
static void draw_tag(tenv* env, tag_slot* slot, const tag_entry* tag,
                     float anchor_x, float anchor_y, float head_angle,
                     float scale, float zoom, float ox, float oy, float alpha,
                     bool dangle) {
  user_settings* usrs = &env->usr->usrs;
  float pixels = scale * zoom;

  /* The two sliders, exactly as the mod scales them: chain lengthens both the
     rope and the pull along it, and swing softens the damping so the bobble
     carries further past a turn before it settles. */
  float chain = usrs->tag_chain < 1.0f ? 1.0f : usrs->tag_chain;
  float swing = usrs->tag_swing;
  float loose = (swing - 1.0f) * 0.5f;
  if (loose < 0.0f) loose = 0.0f;
  if (loose > 1.0f) loose = 1.0f;
  float segment = ROPE_SEGMENT * chain * scale;

  if (!slot->seeded || rope_broken(slot, segment))
    rope_seed(slot, anchor_x, anchor_y, head_angle, segment);
  slot->x[0] = anchor_x;
  slot->y[0] = anchor_y;

  /* NTL's order (N5): the preview's weight first, then the step. The preview
     always takes the default path, as NTL's skin chooser does. */
  bool ntl_default = dangle || swing <= 1.0f;
  if (dangle) {
    float phase = frame_number / 23.0f;
    for (int i = 1; i < ROPE_POINTS; ++i) {
      slot->vx[i] -= PREVIEW_GRAVITY * scale;
      slot->vy[i] += PREVIEW_SWAY * scale *
                     cosf(phase - 7.0f * i / (float)(ROPE_POINTS - 1));
    }
  }

  if (ntl_default) {
    /* Swing 1: one step for this frame, NTL's default constants. */
    double mb = NTL_DEFAULT_MB;
    rope_step(slot, scale, 0.2 * mb * chain, 0.005 * mb, mb / 17.0,
              0.05 * mb, (double)ROPE_SEGMENT * chain * scale, head_angle,
              true);
    /* NTL forgets its clock on this path, so a later switch to Swing above 1
       starts with one step owed. */
    slot->debt = -1.0f;
  } else {
    /* Swing above 1: 16.667 ms steps caught up to the clock, as NTL does. */
    double push = (3.3332 + 0.6668 * loose) * chain;
    double stiffness = 0.08333 + 0.01667 * loose;
    double damping = 0.838 + 0.145 * loose;
    if (damping > 0.985) damping = 0.985;

    if (slot->debt < 0.0)
      slot->debt = ROPE_STEP_MS;
    else
      slot->debt += frame_delta_ms;
    if (slot->debt > ROPE_MAX_DEBT_MS) slot->debt = ROPE_MAX_DEBT_MS;
    int steps = (int)(slot->debt / ROPE_STEP_MS);
    if (steps > ROPE_MAX_STEPS) steps = ROPE_MAX_STEPS;
    for (int s = 0; s < steps; ++s)
      rope_step(slot, scale, push, stiffness, 1.0, damping,
                (double)ROPE_SEGMENT * chain * scale, head_angle, false);
    slot->debt -= steps * ROPE_STEP_MS;
  }

  /* With Swing above 1 NTL draws an eased copy of the rope (.248 a frame);
     the simulation itself is untouched by it. */
  double rx[ROPE_POINTS];
  double ry[ROPE_POINTS];
  if (!ntl_default) {
    if (!slot->draw_seeded) {
      for (int i = 0; i < ROPE_POINTS; ++i) {
        slot->draw_x[i] = slot->x[i];
        slot->draw_y[i] = slot->y[i];
      }
      slot->draw_seeded = true;
    }
    for (int i = 1; i < ROPE_POINTS; ++i) {
      slot->draw_x[i] += 0.248 * (slot->x[i] - slot->draw_x[i]);
      slot->draw_y[i] += 0.248 * (slot->y[i] - slot->draw_y[i]);
    }
    slot->draw_x[0] = slot->x[0];
    slot->draw_y[0] = slot->y[0];
    for (int i = 0; i < ROPE_POINTS; ++i) {
      rx[i] = slot->draw_x[i];
      ry[i] = slot->draw_y[i];
    }
  } else {
    slot->draw_seeded = false;
    for (int i = 0; i < ROPE_POINTS; ++i) {
      rx[i] = slot->x[i];
      ry[i] = slot->y[i];
    }
  }

  float sx[ROPE_POINTS];
  float sy[ROPE_POINTS];
  for (int i = 0; i < ROPE_POINTS; ++i) {
    sx[i] = ox + rx[i] * zoom;
    sy[i] = oy + ry[i] * zoom;
  }

  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(NULL);
  const int last = ROPE_POINTS - 1;

  /* The rope is two strokes: a thick one in the tag's first accent for the
     whole length, then a narrower one in the second, laid over it three times
     at falling widths so that it tapers into the head instead of stopping
     dead. */
  rope_path(draw, sx, sy, last, 1, false);
  ImDrawList_PathStroke(draw, accent(tag->c1, alpha), 0, 5.0f * pixels);

  ImU32 trim = accent(tag->c2, 0.5f * alpha);
  const float widths[3] = {4.0f, 3.0f, 2.0f};
  for (int pass = 0; pass < 3; ++pass) {
    rope_path(draw, sx, sy, last, 2, true);
    ImDrawList_PathStroke(draw, trim, 0, widths[pass] * pixels);
  }

  /* The bobble turns towards the rope's last segment, .15 of the way each
     drawn frame, exactly as NTL turns it (`EA = (EA + .15 * d) % 2pi`). */
  {
    /* In world units, as NTL measures it; the screen is the same line. */
    double d = atan2(ry[last] - ry[last - 1], rx[last] - rx[last - 1]) -
               slot->angle;
    const double he = 6.283185307179586;
    if (d < 0.0 || d >= he) d = fmod(d, he);
    if (d < -M_PI)
      d += he;
    else if (d > M_PI)
      d -= he;
    slot->angle = fmod(slot->angle + TAG_TURN * d, he);
  }

  float size = TAG_SCALE * usrs->tag_scale;
  float height = tag->h * size * pixels;

  /* Small tags: rather than clipping a big bobble, every term is multiplied
     down by one ratio, so the tag shrinks whole. */
  float shrink = 1.0f;
  if (usrs->tags_small && height > SMALL_TAG_HEIGHT * pixels)
    shrink = SMALL_TAG_HEIGHT * pixels / height;

  float bx = shrink * tag->bx * size * pixels;
  float by = shrink * tag->by * size * pixels;
  float w = shrink * tag->w * size * pixels;
  float h = shrink * height;

  /* The bobble's box, rotated about the end of the rope and hung off it. */
  float cs = cosf(slot->angle);
  float sn = sinf(slot->angle);
  const float cx[4] = {0.0f, 1.0f, 1.0f, 0.0f};
  const float cy[4] = {0.0f, 0.0f, 1.0f, 1.0f};
  ImVec2 corners[4];
  for (int i = 0; i < 4; ++i) {
    float px = bx + cx[i] * w;
    float py = by + cy[i] * h;
    corners[i] = (ImVec2){sx[last] + (cs * px - sn * py),
                          sy[last] + (sn * px + cs * py)};
  }

  ImTextureRef texture = {NULL,
                          (ImTextureID)(uintptr_t)env->usr->r->tags_descriptor};
  ImDrawList_AddImageQuad(
      draw, texture, corners[0], corners[1], corners[2], corners[3],
      (ImVec2){tag->uv[0], tag->uv[1]}, (ImVec2){tag->uv[2], tag->uv[1]},
      (ImVec2){tag->uv[2], tag->uv[3]}, (ImVec2){tag->uv[0], tag->uv[3]},
      igColorConvertFloat4ToU32((ImVec4){1, 1, 1, alpha}));
}

/* Tags are on (OM, 2026-10-04): the arena drops were not NTL's. 1 hides every
   tag again. */
#define WYRM_TAGS_DISABLED 0

void tags_draw(tenv* env, snake* o, bool mine, bool teammate) {
  tuser_data* usr = env->usr;
  user_settings* usrs = &usr->usrs;
  game_data* gdata = &usr->gdata;

  if (WYRM_TAGS_DISABLED) return;
  if (usrs->tags_hidden) return;
  if (usrs->tags_team_only && !mine && !teammate) return;
  if (!usr->r || !usr->r->tags_descriptor) return;

  /* Which tag, before any rope is claimed for it. Nothing is allocated for a
     snake that is not going to be drawn wearing anything: the table is five
     hundred slots and an arena is not, and filling it with tagless snakes used
     to starve the ones that had a tag — the player's own included. */
  tag_slot* slot = slot_find(o->id);
  int index = (mine && tags_valid(usrs->tag_index)) ? usrs->tag_index
              : slot                               ? slot->tag
                                                   : -1;
  if (!tags_valid(index)) return;
  if (!slot) {
    slot = slot_for(o->id);
    if (!slot) return;
  }

  /* Squared, because the snake's own fade is squared: a tag that faded
     linearly would still be visible over a snake that had all but gone. */
  float alpha = o->alive_amt * (1.0f - o->dead_amt);
  alpha *= alpha;
  if (alpha <= 0.01f) return;

  /* A tag is measured in snake-widths and drawn at the world's zoom, so it
     keeps its size relative to the snake wearing it however far out the camera
     has pulled. The rope is pinned a little way back from the nose, so that it
     comes out of the top of the head rather than off the end of it.

     The angle is `ang` and not `ehang`: `ang` is the direction the snake is
     actually moving, which is what the mod hangs the tag off. `ehang` is the
     eased angle the head sprite is drawn at, which the mod uses for the eyes
     and not for this — and stepping backwards along it puts the anchor on the
     wrong side of the head through a turn, which is a rope laid out forwards. */
  float scale = o->sc;
  float zoom = gdata->data.gsc;
  float angle = o->ang;
  float head_x = o->xx + o->fx;
  float head_y = o->yy + o->fy;
  float anchor_x = head_x - ROPE_ANCHOR * cosf(angle) * scale;
  float anchor_y = head_y - ROPE_ANCHOR * sinf(angle) * scale;

  /* Off the edge of the world the camera can see, the rope is dropped rather
     than simulated, and laid out fresh when the snake comes back. Dragging one
     home across half the map is how a tag ends up permanently pointing the
     wrong way — the pull maintains the chain's direction, it never fixes it. */
  float half_w = env->ctx->size[0] * 0.5f / zoom + ROPE_BOUNDS_MARGIN;
  float half_h = env->ctx->size[1] * 0.5f / zoom + ROPE_BOUNDS_MARGIN;
  if (anchor_x < gdata->data.view_xx - half_w ||
      anchor_y < gdata->data.view_yy - half_h ||
      anchor_x > gdata->data.view_xx + half_w ||
      anchor_y > gdata->data.view_yy + half_h) {
    slot->seeded = false;
    slot->frame = frame_number;
    return;
  }

  slot->frame = frame_number;
  draw_tag(env, slot, TAG_TABLE + index, anchor_x, anchor_y, angle, scale, zoom,
           env->ctx->size[0] * 0.5f - gdata->data.view_xx * zoom,
           env->ctx->size[1] * 0.5f - gdata->data.view_yy * zoom, alpha, false);
}

void tags_draw_preview(tenv* env, float head_x, float head_y, float head_size) {
  tuser_data* usr = env->usr;
  user_settings* usrs = &usr->usrs;

  if (!usr->r || !usr->r->tags_descriptor) return;
  if (!tags_valid(usrs->tag_index)) return;

  /* The preview snake is not a snake, so it has no id to key a rope to. It
     gets one of its own that no arena snake can collide with, and keeps it
     between visits — walking back into the editor should not snap the rope
     straight. */
  tag_slot* slot = slot_for(PREVIEW_SNAKE_ID);
  if (!slot) return;
  slot->frame = frame_number;

  /* The head sprite is one segment across, and a segment is twenty-nine
     snake-widths — the same ratio the arena's own head is drawn at. Feeding
     that in as the scale with a zoom of one puts the preview's tag at exactly
     the proportions it will have in the arena. */
  float scale = head_size / 29.0f;
  draw_tag(env, slot, TAG_TABLE + usrs->tag_index,
           head_x - ROPE_ANCHOR * scale, head_y, 0.0f, scale, 1.0f, 0.0f, 0.0f,
           1.0f, true);
}
