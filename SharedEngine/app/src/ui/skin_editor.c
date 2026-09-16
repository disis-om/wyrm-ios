#include "skin_editor.h"

#include "../game/backgrounds.h"

#include <string.h>

#include "../game/tags.h"
#include "../user.h"

/*
 * Compose-reported geometry, in framebuffer pixels.
 *
 * Defaults keep the preview roughly where it used to sit, so the screen is
 * still legible if a frame arrives before Compose has measured itself.
 */
static float layout_preview_cy = -1.0f;
static float layout_preview_scale = 48.0f;
static float layout_accessory_x = 0.0f;
static float layout_accessory_y = 0.0f;
static float layout_accessory_cell = 0.0f;
static float layout_accessory_gap = 0.0f;
static bool postcard_preview = false;

/* The body is drawn as two rows of this many segments, head at the right. */
#define SKIN_PREVIEW_SEGMENTS (MAX_SKIN_CODE_LEN / 2)

void ui_skin_editor_init(tenv* env) { (void)env; }

void ui_skin_editor_set_layout(float preview_cy, float preview_scale,
                               float accessory_x, float accessory_y,
                               float accessory_cell, float accessory_gap) {
  layout_preview_cy = preview_cy;
  layout_preview_scale = preview_scale > 1.0f ? preview_scale : 1.0f;
  layout_accessory_x = accessory_x;
  layout_accessory_y = accessory_y;
  layout_accessory_cell = accessory_cell;
  layout_accessory_gap = accessory_gap;
}

void ui_skin_editor_set_postcard(bool on) { postcard_preview = on; }

bool ui_skin_editor_postcard(void) { return postcard_preview; }

/** The colour group a given body segment should use, in either mode. */
static int segment_cg(game_data* gdata, user_settings* usrs, int segment) {
  if (usrs->custom_skin)
    return get_cg_id(gdata, usrs->skin_code[MAX_SKIN_CODE_LEN - 1 - segment]);

  int length = gdata->default_skins[usrs->default_skin][0];
  if (length <= 0) return -1;
  return gdata->default_skins[usrs->default_skin]
                             [1 + ((MAX_SKIN_CODE_LEN - 1 - segment) % length)];
}

/**
 * The exact colour a built segment carries, or 0 when it renders from the
 * palette. Positions line up with `skin_code`, which the preview reads from the
 * end of the buffer so that code position 0 sits nearest the head.
 */
static uint32_t segment_rgba(user_settings* usrs, int segment) {
  if (!usrs->custom_skin) return 0;
  int index = MAX_SKIN_CODE_LEN - 1 - segment;
  if (index < 0 || index >= MAX_SKIN_CODE_LEN) return 0;
  return usrs->skin_rgba[index];
}

/** One row of body segments. Returns where the last segment landed. */
static void draw_row(tenv* env, float x, float y, float scale, float step,
                     int first_segment, bool reversed, vec2 out_last) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  user_settings* usrs = &usr->usrs;

  /* Every shadow first, then every segment: the segments overlap heavily, and
   * interleaving would let each shadow fall across the segment before it. */
  for (int i = 0; i < SKIN_PREVIEW_SEGMENTS; i++) {
    int slot = reversed ? i : (SKIN_PREVIEW_SEGMENTS - 1 - i);
    float sx = x + slot * step;
    /* A segment you can see through casts proportionally less shadow, or a
     * faded body would sit on a hard black outline of itself. */
    uint32_t rgba = segment_rgba(usrs, first_segment + i);
    float opacity = rgba ? ((rgba >> 24) & 0xFF) / 255.0f : 1.0f;
    bp_renderer_push(usr->r->bpr,
                     &(bp_instance){{sx - 10 * (scale / 48),
                                     y - 10 * (scale / 48), 68 * (scale / 48)},
                                    gdata->SHADOW_UV,
                                    {0, 0, 0, 0.2f * opacity}});
  }

  for (int i = 0; i < SKIN_PREVIEW_SEGMENTS; i++) {
    int slot = reversed ? i : (SKIN_PREVIEW_SEGMENTS - 1 - i);
    float sx = x + slot * step;
    int segment = first_segment + i;
    int cg_id = segment_cg(gdata, usrs, segment);
    if (cg_id != -1) {
      uint32_t rgba = segment_rgba(usrs, segment);
      if (rgba) {
        /* A built segment's colour is not in the atlas, so it is drawn the way
         * the arena draws every body point: the blank bead, tinted exactly.
         * That also makes this preview honest about transparency, which only
         * the flat path can show. */
        bp_renderer_push(
            usr->r->bpr,
            &(bp_instance){{sx, y, scale, reversed ? PI : 0},
                           gdata->cg_uvs[BLANK_UV],
                           {((rgba >> 16) & 0xFF) / 255.0f,
                            ((rgba >> 8) & 0xFF) / 255.0f,
                            (rgba & 0xFF) / 255.0f,
                            ((rgba >> 24) & 0xFF) / 255.0f}});
      } else {
        /* Default skins carry the engine's shading ripple down the body; a
         * custom skin is flat, so its segments are pushed at full brightness. */
        float we = gdata->worm_effect[segment % WORM_EFFECT_LEN] *
                       (!usrs->custom_skin) +
                   usrs->custom_skin;
        bp_renderer_push(
            usr->r->bpr,
            &(bp_instance){{sx, y, scale, reversed ? PI : 0},
                           gdata->cg_uvs[cg_id],
                           {we, we, we, 1}});
      }
    }

    if (out_last) {
      out_last[0] = sx;
      out_last[1] = y;
    }
  }
}

/** The head: two eyes, two pupils, and whatever is worn on top. */
static void draw_head(tenv* env, vec2 at, float scale) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  user_settings* usrs = &usr->usrs;

  float ssc = scale / 29;
  float ed = 6 * ssc;
  float esp = 6 * ssc;
  default_skin_data* dfs =
      gdata->dfs + ((1 - usrs->custom_skin) * (1 + usrs->default_skin));
  float iris_r = 6 * ssc;
  float pupil_r = dfs->pr * ssc;

  float cx = at[0] + scale / 2;
  float cy = at[1] + scale / 2;

  for (int side = 0; side < 2; side++) {
    float ey = (side ? esp : -esp) - (side ? 0.0f : 0.5f);
    bp_renderer_push(usr->r->bpr,
                     &(bp_instance){{(cx + ed) - iris_r, (cy + ey) - iris_r,
                                     iris_r * 2},
                                    gdata->cg_uvs[BLANK_UV],
                                    {dfs->ec.r, dfs->ec.g, dfs->ec.b, 1}});
  }

  for (int side = 0; side < 2; side++) {
    float ex = ed + 0.5f + 2 * ssc;
    float ey = side ? esp : -esp;
    bp_renderer_push(usr->r->bpr,
                     &(bp_instance){{(cx + ex) - pupil_r, (cy + ey) - pupil_r,
                                     pupil_r * 2},
                                    gdata->cg_uvs[BLANK_UV],
                                    {dfs->ppc.r, dfs->ppc.g, dfs->ppc.b, 1}});
  }

  if (usrs->accessory < NUM_ACCESSORIES) {
    accessory_data* acc = gdata->accessories + usrs->accessory;
    float m = scale * 0.5f * acc->sc;
    bp_renderer_push(usr->r->bpr,
                     &(bp_instance){{(acc->of * ed + cx) - m, cy - m, m * 2, 0},
                                    acc->uv,
                                    {1, 1, 1, 1}});
  }
}

/** The 33 accessory sprites, laid into the grid Compose reserved for them. */
static void draw_accessory_grid(tenv* env) {
  if (layout_accessory_cell < 1.0f) return;

  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  float step = layout_accessory_cell + layout_accessory_gap;

  for (int id = 0; id < NUM_ACCESSORIES; id++) {
    int row = id / 7;
    int column = id % 7;
    bp_renderer_push(
        usr->r->bpr,
        &(bp_instance){{layout_accessory_x + column * step,
                        layout_accessory_y + row * step,
                        layout_accessory_cell},
                       gdata->accessories[id].uv,
                       {1, 1, 1, 0.92f}});
  }
}

void ui_skin_editor(tenv* env) {
  tuser_data* usr = env->usr;
  tcontext* ctx = env->ctx;
  user_settings* usrs = &usr->usrs;

  /* Postcard (paper Skin tab) sits in a hole over paper, so the arena floor
   * must not paint through. The full editor still shows a dimmed floor. */
  bool postcard =
      postcard_preview && usr->gdata.curr_screen != SKIN_EDITOR;
  usr->r->global.bg_opacity =
      postcard ? 0.0f
               : (background_clamp(usrs->arena_background) == BACKGROUND_NONE
                      ? 0.0f
                      : 0.55f);
  usr->r->global.bg_scale = 1.0f;
  usr->r->global.bd_opacity = 0;
  usr->r->global.minimap_opacity = 0;

  /* Anything past the terminator is stale from a longer code; the renderer
   * reads the whole buffer, so it has to be clean. */
  for (int i = strlen(usrs->skin_code); i < MAX_SKIN_CODE_LEN + 1; i++)
    usrs->skin_code[i] = 0;

  float scale = layout_preview_scale;
  float step = 8 * (scale / 48);
  float gap = scale * 0.16f;
  float width = scale + step * (SKIN_PREVIEW_SEGMENTS - 1);
  float x = ctx->size[0] * 0.5f - width * 0.5f;
  float cy = layout_preview_cy >= 0.0f ? layout_preview_cy
                                       : ctx->size[1] * 0.28f;

  float head_y = cy - scale - gap * 0.5f;
  float tail_y = cy + gap * 0.5f;

  vec2 head_at = {0, 0};
  /* Tail half below, head half above and running the other way, so the body
   * reads as one snake doubling back on itself. */
  draw_row(env, x, tail_y, scale, step, 0, false, NULL);
  draw_row(env, x, head_y, scale, step, SKIN_PREVIEW_SEGMENTS, true, head_at);
  draw_head(env, head_at, scale);

  /* The tag, on the same rope the arena hangs it from, so that changing the
     chain or the swing is answered here rather than three screens away in a
     live game. The preview head faces right, which is an angle of zero. */
  tags_tick(env);
  tags_draw_preview(env, head_at[0] + scale * 0.5f, head_at[1] + scale * 0.5f,
                    scale);

  if (!postcard) draw_accessory_grid(env);
}

void ui_skin_editor_destroy(tenv* env) { (void)env; }
