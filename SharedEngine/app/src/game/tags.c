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

/* Points in the rope, and the length of one segment in snake-widths. */
#define ROPE_POINTS 10
#define ROPE_SEGMENT 4.0f

/*
 * NTL 9.68 measures elapsed time in 16.667 ms quanta and runs no more than four
 * catch-up steps. Keeping this literal matters: it makes a Wyrm tag lag and
 * settle exactly like the same `tg` value rendered by another NTL client.
 */
#define ROPE_STEP (1.0f / 60.0f)
#define ROPE_MAX_STEPS 4

/* How far behind the head the rope is pinned, and the height a bobble is
   allowed to reach when small tags are on — both in snake-widths. */
#define ROPE_ANCHOR 8.0f
#define SMALL_TAG_HEIGHT 40.6f

/* Every tag's artwork is drawn at this fraction of its own size before the
   player's own size setting is applied. */
#define TAG_SCALE 0.285f

/*
 * How much of the way the bobble turns towards the rope's direction each
 * frame. This one line is the difference between a tag that hangs and a tag
 * that is welded on.
 *
 * The mod applies it once a frame at its own sixty, so it is a rate rather than
 * a fraction and has to be raised to the frames elapsed. `TAG_TURN_FRAME` is
 * the length of the frame it belongs to — and it is written out here rather
 * than borrowed from `ROPE_STEP`, which is what it used to do. When the rope's
 * step went to 240 the turn silently came with it and the bobble started
 * snapping round at twice the speed it should, which on a springy rope tip is
 * seen as the tag flicking back and forth.
 */
#define TAG_TURN 0.15f
#define TAG_TURN_FRAME (1.0f / 60.0f)

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
  float angle;
  float x[ROPE_POINTS];
  float y[ROPE_POINTS];
  float vx[ROPE_POINTS];
  float vy[ROPE_POINTS];
  float draw_x[ROPE_POINTS];
  float draw_y[ROPE_POINTS];
  bool draw_seeded;
  float debt; /* time owed to the simulation, in seconds */
} tag_slot;

static tag_slot slots[TAG_SLOTS];
static double last_frame_time = 0.0;
static float frame_delta = ROPE_STEP;
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

void tags_tick(tenv* env) {
  (void)env;
  /* The ropes are advanced when their snakes are drawn, which is the only
     moment a snake's head position is known. All that is needed here is how
     much time has passed since the last frame, measured once so that every
     rope in the frame is advanced by the same amount. */
  double now = igGetTime();
  float delta = (float)(now - last_frame_time);
  last_frame_time = now;
  if (delta < 0.0f || delta > 0.25f) delta = ROPE_STEP;
  frame_delta = delta;
  ++frame_number;
}

/**
 * The shortest way round from one angle to another.
 *
 * Without this a snake crossing the wrap point would send its tag the long way
 * round the circle — a full spin for one degree of turn.
 */
static float angle_delta(float from, float to) {
  float delta = fmodf(to - from, TWO_PI);
  if (delta > (float)M_PI) delta -= TWO_PI;
  if (delta < -(float)M_PI) delta += TWO_PI;
  return delta;
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
static void rope_step(tag_slot* slot, float scale, float push, float stiffness,
                      float advance, float damping, float segment,
                      float fallback) {
  for (int i = 1; i < ROPE_POINTS; ++i) {
    float px = slot->x[i - 1];
    float py = slot->y[i - 1];
    float dx = slot->x[i] - px;
    float dy = slot->y[i] - py;
    float angle = (dx == 0.0f && dy == 0.0f) ? fallback : atan2f(dy, dx);
    float tx = px + push * cosf(angle) * scale;
    float ty = py + push * sinf(angle) * scale;

    slot->vx[i] += stiffness * (tx - slot->x[i]);
    slot->vy[i] += stiffness * (ty - slot->y[i]);
    slot->x[i] += advance * slot->vx[i];
    slot->y[i] += advance * slot->vy[i];
    slot->vx[i] *= damping;
    slot->vy[i] *= damping;

    dx = slot->x[i] - px;
    dy = slot->y[i] - py;
    float distance = sqrtf(dx * dx + dy * dy);
    if (distance > segment) {
      float a = (dx == 0.0f && dy == 0.0f) ? fallback : atan2f(dy, dx);
      slot->x[i] = px + segment * cosf(a);
      slot->y[i] = py + segment * sinf(a);
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
  slot->draw_seeded = false;
  slot->debt = 0.0f;
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
  return dx * dx + dy * dy > span * span * 1.05f;
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

  /*
   * One integrator, stepped at a true sixty.
   *
   * The mod has two and picks between them on the swing setting, and the one it
   * uses by default works its constants out from the frame time. That was copied
   * faithfully and it was the wrong thing to copy: the mod derives them from its
   * *configured* frame rate, which is around sixteen milliseconds whatever the
   * screen is doing, and Wyrm was deriving them from the frame time it actually
   * measured. On a 110Hz phone that is nine milliseconds, which gives a
   * stiffness of 0.045 against 0.083 and a step of 0.53 against 0.98 — a rope
   * roughly half as willing to follow, per second, as the one the mod runs.
   *
   * What that looks like is a tag that cannot keep up under boost: it stretches
   * to the limit and hangs there, and the snake appears to be dragging
   * something that has caught on the floor.
   *
   * So the frame rate is caught up to rather than fed in, always, and the drawn
   * rope is eased towards the simulated one so that stepping at sixty does not
   * judder on a screen running faster.
   */
  {
    float push = (3.3332f + 0.6668f * loose) * chain;
    float stiffness = 0.08333f + 0.01667f * loose;
    float damping = 0.838f + 0.145f * loose;
    if (damping > 0.985f) damping = 0.985f;

    slot->debt += frame_delta;
    int steps = 0;
    while (slot->debt >= ROPE_STEP && steps < ROPE_MAX_STEPS) {
      rope_step(slot, scale, push, stiffness, 1.0f, damping, segment,
                head_angle);
      slot->debt -= ROPE_STEP;
      ++steps;
    }
    if (slot->debt > ROPE_STEP * ROPE_MAX_STEPS) slot->debt = 0.0f;
  }

  /* The preview hangs under its own weight and sways, because a rope that only
     ever pointed backwards would tell the player nothing about how it moves. */
  if (dangle) {
    float phase = frame_number / 23.0f;
    for (int i = 1; i < ROPE_POINTS; ++i) {
      slot->vx[i] -= PREVIEW_GRAVITY * scale;
      slot->vy[i] += PREVIEW_SWAY * scale *
                     cosf(phase - 7.0f * i / (float)(ROPE_POINTS - 1));
    }
  }

  /* NTL 9.68 eases the visible rope by .248 when Swing is above one. The
     physics arrays keep running at sixty; only the rendered path is softened. */
  const float* rx = slot->x;
  const float* ry = slot->y;
  if (swing > 1.0f) {
    if (!slot->draw_seeded) {
      memcpy(slot->draw_x, slot->x, sizeof(slot->draw_x));
      memcpy(slot->draw_y, slot->y, sizeof(slot->draw_y));
      slot->draw_seeded = true;
    }
    for (int i = 1; i < ROPE_POINTS; ++i) {
      slot->draw_x[i] += 0.248f * (slot->x[i] - slot->draw_x[i]);
      slot->draw_y[i] += 0.248f * (slot->y[i] - slot->draw_y[i]);
    }
    slot->draw_x[0] = slot->x[0];
    slot->draw_y[0] = slot->y[0];
    rx = slot->draw_x;
    ry = slot->draw_y;
  } else {
    slot->draw_seeded = false;
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

  /* The bobble turns towards the direction of the rope's last segment, a
     fraction of the way each frame — and "each frame" is the mod's sixty, not
     this screen's hundred and ten. Applied raw it chases nearly twice as hard
     on a fast phone, which lines the tag up with the rope sooner than it should
     and takes the lag out of the one part of this that is meant to lag. */
  float rope_angle = atan2f(sy[last] - sy[last - 1], sx[last] - sx[last - 1]);
  float frames = frame_delta / TAG_TURN_FRAME;
  if (frames < 0.1f) frames = 0.1f;
  if (frames > 4.0f) frames = 4.0f;
  float turn = 1.0f - powf(1.0f - TAG_TURN, frames);
  slot->angle += turn * angle_delta(slot->angle, rope_angle);
  slot->angle = fmodf(slot->angle, TWO_PI);

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

/* Tags are switched off until Wyrm's own backend serves them: announcing NTL
   tags got snakes dropped from the arena. Set to 0 to draw tags again. */
#define WYRM_TAGS_DISABLED 1

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
