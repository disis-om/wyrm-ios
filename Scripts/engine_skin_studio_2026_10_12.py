"""Skin Studio, engine side (OM, 2026-10-12).

One source for both apps, like engine_sync_2026_10_12.py: Wyrm Android's
engine tree gets these pairs once
(`python engine_skin_studio_2026_10_12.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree,
so the text is identical on Android, iOS and Wyrm Desktop. On iOS and the
desktop nothing calls it yet, so it stays inert there.

What it does:
  - A second texture for the sprite shader (binding 4): the player's own
    Studio atlas, 8 x 8 cells of 128 px (beads, eye whites, pupils), baked by
    the app. A sprite whose uv is shifted right by 4 samples it; every other
    sprite samples the game atlas as before. One draw call, the same order,
    the shadows and glows from the game atlas in between.
  - The atlas loads like the arena floor: PNG decoded on a worker thread, the
    GPU copy on its own fence, each frame in flight switched once its fence has
    signalled. The new skin (pattern, colours, eyes) takes effect only when
    every frame shows the new atlas.
  - The own snake only, only on this phone: its beads come from the Studio
    atlas in the texture render mode; its eyes are the Studio's eyes (any
    number, any place, any pupil); the flat/solid modes, the boost glow and
    the skinless strip take each bead's own colour. The arena gets what the
    app wears in the settings (one black bead): nothing on the wire changes.
"""

import sys
from pathlib import Path

PAIRS = {}
NEW_FILES = {}
# The app's call (JNI) exists only where the Android mailbox does; the iOS
# tree's android_skin.c is its own file and has no JNI.
ANDROID_ONLY = {"app/src/platform/android_skin.c"}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


# ------------------------------------------------------------ the module

NEW_FILES["app/src/game/studio.h"] = r'''#ifndef WYRM_STUDIO_H
#define WYRM_STUDIO_H

/*
 * Skin Studio (OM, 2026-10-12): the player's own snake drawn from an atlas the
 * app bakes. Only this phone sees it; the arena gets the settings' skin.
 *
 * The atlas is STUDIO_GRID x STUDIO_GRID cells. The app decides what each
 * cell holds; the engine only reads the indices it is given:
 *   P: the body, cell index per bead, repeated along the snake (head first)
 *   C: each cell's own colour (RRGGBB), for the flat modes and the glow
 *   E: the eyes, each "forward,side,white radius,pupil radius,look,white
 *      cell,pupil cell" in snake units (slither's eye: 6,+-6.5,6,3.5,1)
 * Sections are joined by '|', items by ',' and eyes by ';'. Numbers use '.'.
 */

#include <stdbool.h>
#include <stdint.h>

#define STUDIO_GRID 8
#define STUDIO_CELLS (STUDIO_GRID * STUDIO_GRID)
#define STUDIO_MAX_PATTERN 256
#define STUDIO_MAX_EYES 8
/* A sprite uv shifted this far right samples the Studio atlas (bp.slang). */
#define STUDIO_UV_SHIFT 4.0f

typedef struct studio_eye {
  float fwd, side;    /* centre, snake units from the head, +side = right */
  float white_r;      /* eye white radius, snake units */
  float pupil_r;      /* pupil radius, snake units */
  float look;         /* how far the pupil follows where the snake looks */
  int white_cell, pupil_cell;
} studio_eye;

typedef struct studio_skin {
  int pattern_len;
  uint8_t pattern[STUDIO_MAX_PATTERN];
  uint32_t cell_rgb[STUDIO_CELLS];
  int eye_count;
  studio_eye eyes[STUDIO_MAX_EYES];
} studio_skin;

/* Parses the app's text; false (and nothing usable) when it is not valid. */
bool studio_parse(const char* text, studio_skin* out);

/* The renderer calls this once every frame in flight shows the new atlas. */
void studio_commit(const studio_skin* skin);
/* Off at once (the atlas stays bound and unused). */
void studio_clear(void);

bool studio_on(void);
const studio_skin* studio_current(void);
/* The cell the [index]th bead from the head wears. */
int studio_cell_at(int index);
/* That bead's own colour, 0xRRGGBB. */
uint32_t studio_rgb_at(int index);

#endif
'''

NEW_FILES["app/src/game/studio.c"] = r'''#include "studio.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

/* Skin Studio (OM, 2026-10-12): see studio.h. Engine thread only. */

static studio_skin current;
static bool on = false;

void studio_commit(const studio_skin* skin) {
  if (!skin || skin->pattern_len <= 0) {
    on = false;
    return;
  }
  current = *skin;
  on = true;
}

void studio_clear(void) { on = false; }

bool studio_on(void) { return on; }

const studio_skin* studio_current(void) { return &current; }

int studio_cell_at(int index) {
  if (current.pattern_len <= 0) return 0;
  int i = index % current.pattern_len;
  if (i < 0) i += current.pattern_len;
  return current.pattern[i];
}

uint32_t studio_rgb_at(int index) {
  return current.cell_rgb[studio_cell_at(index)] & 0xFFFFFFu;
}

static float clampf(float v, float lo, float hi) {
  if (!isfinite(v)) return lo;
  return v < lo ? lo : v > hi ? hi : v;
}

static const char* skip_comma(const char* p, const char* end, char mark) {
  if (p < end && *p == mark) ++p;
  return p;
}

bool studio_parse(const char* text, studio_skin* out) {
  if (!text || !out) return false;
  memset(out, 0, sizeof(*out));
  const char* p = text;
  while (*p) {
    char key = p[0];
    if (p[1] != ':') return false;
    p += 2;
    const char* end = strchr(p, '|');
    if (!end) end = p + strlen(p);
    if (key == 'P') {
      while (p < end && out->pattern_len < STUDIO_MAX_PATTERN) {
        char* next = NULL;
        long cell = strtol(p, &next, 10);
        if (next == p || next > end || cell < 0 || cell >= STUDIO_CELLS)
          return false;
        out->pattern[out->pattern_len++] = (uint8_t)cell;
        p = skip_comma(next, end, ',');
      }
    } else if (key == 'C') {
      int i = 0;
      while (p < end && i < STUDIO_CELLS) {
        char* next = NULL;
        unsigned long rgb = strtoul(p, &next, 16);
        if (next == p || next > end) return false;
        out->cell_rgb[i++] = (uint32_t)rgb & 0xFFFFFFu;
        p = skip_comma(next, end, ',');
      }
    } else if (key == 'E') {
      while (p < end && out->eye_count < STUDIO_MAX_EYES) {
        float f[5];
        char* next = NULL;
        for (int k = 0; k < 5; ++k) {
          f[k] = strtof(p, &next);
          if (next == p || next > end) return false;
          p = skip_comma(next, end, ',');
        }
        long white = strtol(p, &next, 10);
        if (next == p || next > end) return false;
        p = skip_comma(next, end, ',');
        long pupil = strtol(p, &next, 10);
        if (next == p || next > end) return false;
        p = skip_comma(next, end, ';');
        if (white < 0 || white >= STUDIO_CELLS || pupil < 0 ||
            pupil >= STUDIO_CELLS)
          return false;
        studio_eye* e = out->eyes + out->eye_count++;
        e->fwd = clampf(f[0], -40.0f, 40.0f);
        e->side = clampf(f[1], -40.0f, 40.0f);
        e->white_r = clampf(f[2], 0.0f, 30.0f);
        e->pupil_r = clampf(f[3], 0.0f, 30.0f);
        e->look = clampf(f[4], 0.0f, 3.0f);
        e->white_cell = (int)white;
        e->pupil_cell = (int)pupil;
      }
    }
    /* An unknown section is skipped: an older engine reads a newer app. */
    p = *end == '|' ? end + 1 : end;
  }
  return out->pattern_len > 0;
}
'''

# ------------------------------------------------------------ the shader

pairs("app/res/shaders/src/bp.slang",
      ("[[vk::binding(1, 0)]] Sampler2D tex_atlas;\n",
       "[[vk::binding(1, 0)]] Sampler2D tex_atlas;\n"
       "/* Skin Studio (OM, 2026-10-12): the player's own atlas. */\n"
       "[[vk::binding(4, 0)]] Sampler2D studio_tex;\n"),
      ("  float4 c = tex_atlas.Sample(input.uv2).rgba;\n",
       """  /* A uv shifted right by 4 samples the Studio atlas (game/studio.h).
     The gradients are taken before the branch, so the mip choice stays
     defined whichever texture a sprite reads. */
  float2 uv = input.uv2;
  float2 gx = ddx(uv);
  float2 gy = ddy(uv);
  float4 c;
  if (uv.x >= 3.0)
    c = studio_tex.SampleGrad(uv - float2(4.0, 0.0), gx, gy).rgba;
  else
    c = tex_atlas.SampleGrad(uv, gx, gy).rgba;
"""))

# ------------------------------------------------------------ the renderer

pairs("app/src/rendering/renderer.h",
      ("  struct bg_swap* bg_swap;\n",
       """  struct bg_swap* bg_swap;
  /* Skin Studio (OM, 2026-10-12): the player's own atlas on binding 4, and
     its change in progress. NULL until one is worn (binding 4 then points
     at the game atlas, never read). */
  texture* studio_tex;
  struct studio_swap* studio_swap;
"""),
      ("void renderer_set_background(renderer* r, tcontext* ctx, int index);\n",
       """void renderer_set_background(renderer* r, tcontext* ctx, int index);

/* Skin Studio (OM, 2026-10-12): load the atlas at [path] (an RGBA PNG) in
   the background and wear [skin] once every frame shows it. NULL path: off
   at once. Engine thread. */
struct studio_skin;
void renderer_set_studio(renderer* r, tcontext* ctx, const char* path,
                         const struct studio_skin* skin);
"""))

pairs("app/src/rendering/renderer.c",
      ("#include \"../game/backgrounds.h\"\n",
       "#include \"../game/backgrounds.h\"\n#include \"../game/studio.h\"\n"),
      ("static void renderer_bg_swap_destroy(renderer* r, tcontext* ctx);\n",
       """static void renderer_bg_swap_destroy(renderer* r, tcontext* ctx);
/* Skin Studio's atlas swap (below renderer_set_studio). */
static void renderer_studio_swap_step(renderer* r, tcontext* ctx);
static void renderer_studio_swap_destroy(renderer* r, tcontext* ctx);
"""),
      ("""          .bindingCount = 4,
          .pBindings =""",
       """          .bindingCount = 5,
          .pBindings ="""),
      ("""                  {.binding = 3,
                   .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                   .descriptorCount = 1,
                   .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT}}},
      NULL, &r->global_set_layout);""",
       """                  {.binding = 3,
                   .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                   .descriptorCount = 1,
                   .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT},
                  /* Skin Studio's atlas (OM, 2026-10-12). */
                  {.binding = 4,
                   .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                   .descriptorCount = 1,
                   .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT}}},
      NULL, &r->global_set_layout);"""),
      ("""        ctx->device, 4,
        (VkWriteDescriptorSet[]){""",
       """        ctx->device, 5,
        (VkWriteDescriptorSet[]){"""),
      ("""                        r->nearest_sampler, r->mmr->minimap_tex[i]->view,
                        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
            }},
        0, NULL);""",
       """                        r->nearest_sampler, r->mmr->minimap_tex[i]->view,
                        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
            },
            {
                /* Skin Studio: the game atlas until one is worn (never
                   sampled then; a descriptor must point at something). */
                .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .pNext = NULL,
                .dstSet = r->global_set[i],
                .dstBinding = 4,
                .dstArrayElement = 0,
                .descriptorCount = 1,
                .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo =
                    &(VkDescriptorImageInfo){
                        r->atlas_sampler, r->tex_atlas->view,
                        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
            }},
        0, NULL);"""),
      ("  if (r->bg_swap) renderer_bg_swap_step(r, ctx);\n",
       "  if (r->bg_swap) renderer_bg_swap_step(r, ctx);\n"
       "  if (r->studio_swap) renderer_studio_swap_step(r, ctx);\n"),
      ("  renderer_bg_swap_destroy(r, ctx);\n  destroy_texture(ctx, r->tex_atlas);\n",
       "  renderer_bg_swap_destroy(r, ctx);\n"
       "  renderer_studio_swap_destroy(r, ctx);\n"
       "  if (r->studio_tex) destroy_texture(ctx, r->studio_tex);\n"
       "  destroy_texture(ctx, r->tex_atlas);\n"),
      ("void renderer_destroy(renderer* r, tcontext* ctx) {\n",
       r'''/* Skin Studio (OM, 2026-10-12): the player's own atlas, swapped the way the
   arena floor is (renderer_bg_swap_step): the PNG decodes on a worker
   thread, the GPU copy runs on its own fence, and each frame in flight takes
   the new atlas on binding 4 once its last use of the old one has finished.
   The skin that goes with it is worn (studio_commit) only when every frame
   shows the new atlas, so a pattern never points into an old one. A newer
   request supersedes an older one at every step. */
typedef struct studio_swap {
  int want;                 /* the newest request, by revision */
  char want_path[512];      /* "" = off */
  studio_skin want_skin;
  int job;                  /* the revision decoding or uploading, -1 none */
  studio_skin job_skin;
  char path[512];
  SDL_Thread* thread;
  SDL_AtomicInt decoded;
  unsigned char* pixels;
  int w, h;
  texture_upload* upload;
  texture* ready;           /* uploaded, being bound frame by frame */
  int ready_rev;
  studio_skin ready_skin;
  uint32_t bound;
  texture* retired;         /* the old atlas, until no frame can read it */
  int retire_after;
  int shown;                /* the revision worn now, 0 none */
} studio_swap;

static int studio_swap_decode(void* data) {
  studio_swap* s = data;
  int channels = 0;
  s->pixels = stbi_load(s->path, &s->w, &s->h, &channels, 4);
  SDL_SetAtomicInt(&s->decoded, 1);
  return 0;
}

static void renderer_bind_studio(renderer* r, tcontext* ctx, int frame,
                                 texture* tex) {
  vkUpdateDescriptorSets(
      ctx->device, 1,
      (VkWriteDescriptorSet[]){
          {
              .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
              .dstSet = r->global_set[frame],
              .dstBinding = 4,
              .dstArrayElement = 0,
              .descriptorCount = 1,
              .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
              .pImageInfo =
                  &(VkDescriptorImageInfo){r->atlas_sampler, tex->view,
                                           VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL},
          },
      },
      0, NULL);
}

static void renderer_studio_swap_step(renderer* r, tcontext* ctx) {
  studio_swap* s = r->studio_swap;
  int cur = ctx->current_frame;
  int fif = ctx->fif < 32 ? ctx->fif : 32;
  uint32_t all = fif >= 32 ? 0xFFFFFFFFu : ((1u << fif) - 1u);

  if (s->retired && --s->retire_after <= 0) {
    destroy_texture(ctx, s->retired);
    s->retired = NULL;
  }

  if (s->ready) {
    for (int i = 0; i < fif; ++i) {
      if (s->bound & (1u << i)) continue;
      if (i != cur &&
          vkGetFenceStatus(ctx->device, ctx->frames[i].wait_fence) != VK_SUCCESS)
        continue;
      renderer_bind_studio(r, ctx, i, s->ready);
      s->bound |= 1u << i;
    }
    if ((s->bound & all) == all) {
      if (r->studio_tex) {
        s->retired = r->studio_tex;
        s->retire_after = fif + 1;
      }
      r->studio_tex = s->ready;
      if (s->ready_rev == s->want && s->want_path[0]) {
        studio_commit(&s->ready_skin);
        s->shown = s->ready_rev;
      }
      s->ready = NULL;
      s->bound = 0;
    }
  } else if (s->upload) {
    texture* done = NULL;
    if (texture_upload_poll(ctx, s->upload, &done)) {
      s->upload = NULL;
      if (done && s->job == s->want && s->want_path[0]) {
        s->ready = done;
        s->ready_rev = s->job;
        s->ready_skin = s->job_skin;
        s->bound = 0;
      } else if (done) {
        destroy_texture(ctx, done); /* asked again meanwhile, or turned off */
      }
      s->job = -1;
    }
  } else if (s->thread) {
    if (SDL_GetAtomicInt(&s->decoded)) {
      SDL_WaitThread(s->thread, NULL);
      s->thread = NULL;
      if (s->pixels) {
        if (s->job == s->want && s->want_path[0])
          s->upload = texture_upload_begin(ctx, s->pixels, s->w, s->h);
        stbi_image_free(s->pixels);
        s->pixels = NULL;
      } else {
        SDL_Log("Wyrm studio: could not decode %s", s->path);
      }
      if (!s->upload) s->job = -1;
    }
  } else if (!s->retired && s->want_path[0] && s->want != s->shown) {
    snprintf(s->path, sizeof(s->path), "%s", s->want_path);
    s->job = s->want;
    s->job_skin = s->want_skin;
    SDL_SetAtomicInt(&s->decoded, 0);
    s->thread = SDL_CreateThread(studio_swap_decode, "wyrm-studio", s);
    if (!s->thread) {
      SDL_Log("Wyrm studio: no worker thread");
      s->job = -1;
      s->shown = s->want; /* do not retry every frame */
    }
  }
}

static void renderer_studio_swap_destroy(renderer* r, tcontext* ctx) {
  studio_swap* s = r->studio_swap;
  if (!s) return;
  if (s->thread) SDL_WaitThread(s->thread, NULL);
  if (s->pixels) stbi_image_free(s->pixels);
  if (s->upload) texture_upload_cancel(ctx, s->upload);
  if (s->ready) destroy_texture(ctx, s->ready);
  if (s->retired) destroy_texture(ctx, s->retired);
  free(s);
  r->studio_swap = NULL;
}

void renderer_set_studio(renderer* r, tcontext* ctx, const char* path,
                         const studio_skin* skin) {
  (void)ctx;
  if (!r) return;
  if (!r->studio_swap) {
    r->studio_swap = calloc(1, sizeof(studio_swap));
    if (!r->studio_swap) return;
    r->studio_swap->job = -1;
    r->studio_swap->ready_rev = -1;
  }
  studio_swap* s = r->studio_swap;
  s->want += 1;
  if (!path || !path[0] || !skin) {
    s->want_path[0] = 0;
    s->shown = 0;
    studio_clear();
    return;
  }
  snprintf(s->want_path, sizeof(s->want_path), "%s", path);
  s->want_skin = *skin;
}

void renderer_destroy(renderer* r, tcontext* ctx) {
'''))

# ------------------------------------------------------------ drawing

pairs("app/src/game/redraw.c",
      ("#include \"tags.h\"\n",
       "#include \"tags.h\"\n#include \"studio.h\"\n"),
      # The player's own colours: each Studio bead's own colour.
      ("""static uint32_t built_skin_rgba(tenv* env, snake* o, int index) {
  tuser_data* usr = env->usr;
  if (!o->cusk || index < 0 || index >= MAX_SKIN_CODE_LEN) return 0;
  if (o->id == usr->gdata.data.snake_id)
    return WYRM_BUILT_BEADS_IN_ARENA ? usr->usrs.skin_rgba[index] : 0;
""",
       """static uint32_t built_skin_rgba(tenv* env, snake* o, int index) {
  tuser_data* usr = env->usr;
  if (!o->cusk || index < 0 || index >= MAX_SKIN_CODE_LEN) return 0;
  /* Skin Studio (OM, 2026-10-12): the bead's own colour, opaque. */
  if (o->id == usr->gdata.data.snake_id && studio_on())
    return 0xFF000000u | studio_rgb_at(index);
  if (o->id == usr->gdata.data.snake_id)
    return WYRM_BUILT_BEADS_IN_ARENA ? usr->usrs.skin_rgba[index] : 0;
"""),
      ("int arp(snake* o, int q, float xx, float yy) {\n",
       r'''/* Skin Studio (OM, 2026-10-12): the player's own snake, on this phone. */
static bool studio_own(tenv* env, snake* o) {
  return studio_on() && o->id == env->usr->gdata.data.snake_id;
}

/* Which bead a body point wears: the Studio's pattern for the player's own
   snake, else the arena's skin. */
static int studio_slot(tenv* env, snake* o, int point, int cusk_len) {
  if (studio_own(env, o)) {
    int len = studio_current()->pattern_len;
    return len > 0 ? point % len : 0;
  }
  return cusk_len > 0 ? point % cusk_len : 0;
}

/* A Studio cell as a sprite uv: shifted right, so bp.slang samples the
   Studio atlas. */
static vec4s studio_cell_uv(int cell) {
  float g = 1.0f / STUDIO_GRID;
  return (vec4s){{STUDIO_UV_SHIFT + (cell % STUDIO_GRID) * g,
                  (cell / STUDIO_GRID) * g, g, g}};
}

/* The boost glow of a Studio bead: its own colour. */
static vec3s* studio_glow_for(tenv* env, snake* o, int point, vec3s* scratch,
                              vec3s* fallback) {
  if (!studio_own(env, o)) return fallback;
  uint32_t rgb = studio_rgb_at(studio_slot(env, o, point, 1));
  scratch->r = ((rgb >> 16) & 0xFF) / 255.0f;
  scratch->g = ((rgb >> 8) & 0xFF) / 255.0f;
  scratch->b = (rgb & 0xFF) / 255.0f;
  return scratch;
}

/* The Studio's eyes: any number, anywhere on the head, each a white and a
   pupil from the atlas, turned with the head. The pupil sits half a unit
   forward and follows where the snake looks (rex/rey) as slither's does. */
static void studio_draw_eyes(tenv* env, snake* o, float fang, float hx,
                             float hy, float ssc, float ea, float mww2,
                             float mhh2) {
  game_data* gdata = &env->usr->gdata;
  const studio_skin* s = studio_current();
  float c = cosf(fang), sn = sinf(fang);
  for (int i = 0; i < s->eye_count; ++i) {
    const studio_eye* e = s->eyes + i;
    float ex = (c * e->fwd - sn * e->side) * ssc;
    float ey = (sn * e->fwd + c * e->side) * ssc;
    float wr = e->white_r * ssc * gdata->data.gsc;
    if (wr > 0.0f) {
      float cx = mww2 + (ex + hx - gdata->data.view_xx) * gdata->data.gsc;
      float cy = mhh2 + (ey + hy - gdata->data.view_yy) * gdata->data.gsc;
      bp_renderer_push(env->usr->r->bpr,
                       &(bp_instance){{cx - wr, cy - wr, wr * 2, fang},
                                      studio_cell_uv(e->white_cell),
                                      {1, 1, 1, ea}});
    }
    float pr = e->pupil_r * ssc * gdata->data.gsc;
    if (pr > 0.0f) {
      float px = ex + c * 0.5f + o->rex * ssc * e->look;
      float py = ey + sn * 0.5f + o->rey * ssc * e->look;
      float cx = mww2 + (px + hx - gdata->data.view_xx) * gdata->data.gsc;
      float cy = mhh2 + (py + hy - gdata->data.view_yy) * gdata->data.gsc;
      bp_renderer_push(env->usr->r->bpr,
                       &(bp_instance){{cx - pr, cy - pr, pr * 2, fang},
                                      studio_cell_uv(e->pupil_cell),
                                      {1, 1, 1, ea}});
    }
  }
}

int arp(snake* o, int q, float xx, float yy) {
'''),
      # Texture mode: the Studio's own beads.
      ("""                  int slot = (int)j % o->cusk_len;
                  int cg_id = o->cusk_data[slot];
                  uint32_t built = built_skin_rgba(env, o, slot);

                  bp_renderer_push(
                      usr->r->bpr,
                      &(bp_instance){
                          {fix - (gdata->data.gsc * lsz),
                           fiy - (gdata->data.gsc * lsz),
                           gdata->data.gsc * 2 * lsz, gdata->data.pba[(int)j]},
                          /* A mixed colour is not in the atlas, so a built""",
       """                  int slot = studio_slot(env, o, (int)j, o->cusk_len);
                  int cg_id = o->cusk_data[(int)j % o->cusk_len];
                  uint32_t built = built_skin_rgba(env, o, slot);

                  if (studio_own(env, o))
                    bp_renderer_push(
                        usr->r->bpr,
                        &(bp_instance){
                            {fix - (gdata->data.gsc * lsz),
                             fiy - (gdata->data.gsc * lsz),
                             gdata->data.gsc * 2 * lsz, gdata->data.pba[(int)j]},
                            studio_cell_uv(studio_cell_at(slot)),
                            {1, 1, 1, a}});
                  else
                  bp_renderer_push(
                      usr->r->bpr,
                      &(bp_instance){
                          {fix - (gdata->data.gsc * lsz),
                           fiy - (gdata->data.gsc * lsz),
                           gdata->data.gsc * 2 * lsz, gdata->data.pba[(int)j]},
                          /* A mixed colour is not in the atlas, so a built"""),
      # Solid mode: each bead's own colour.
      ("""                  int slot = (int)j % o->cusk_len;
                  int cg_id = o->cusk_data[slot];
                  vec3s* cg_col = gdata->cg_colors + cg_id;""",
       """                  int slot = studio_slot(env, o, (int)j, o->cusk_len);
                  int cg_id = o->cusk_data[(int)j % o->cusk_len];
                  vec3s* cg_col = gdata->cg_colors + cg_id;"""),
      # Boost glow.
      ("ALL",
       """                      int cg_id = o->cusk_data[0];
                      vec3s* shc = gdata->cg_glow_colors + cg_id;""",
       """                      int cg_id = o->cusk_data[0];
                      vec3s studio_glow;
                      vec3s* shc = studio_glow_for(env, o, 0, &studio_glow,
                                                   gdata->cg_glow_colors + cg_id);"""),
      ("ALL",
       """                      int cg_id = o->cusk_data[(int)j % o->cusk_len];
                      vec3s* shc = gdata->cg_glow_colors + cg_id;""",
       """                      int cg_id = o->cusk_data[(int)j % o->cusk_len];
                      vec3s studio_glow;
                      vec3s* shc = studio_glow_for(env, o, (int)j, &studio_glow,
                                                   gdata->cg_glow_colors + cg_id);"""),
      # Eyes.
      ("""            if (mode->render_mode == 3 || spine_mesh)
              draw_snake_imgui_eyes(env, o, fang, hx, hy, ssc, ea, mww2, mhh2);
            else {""",
       """            if (mode->render_mode == 3 || spine_mesh)
              draw_snake_imgui_eyes(env, o, fang, hx, hy, ssc, ea, mww2, mhh2);
            else if (studio_own(env, o))
              studio_draw_eyes(env, o, fang, hx, hy, ssc, ea, mww2, mhh2);
            else {"""))

# ------------------------------------------------------------ the app's call

pairs("app/src/platform/android_skin.c",
      ("#include \"../rendering/renderer.h\"\n",
       "#include \"../rendering/renderer.h\"\n#include \"../game/studio.h\"\n"),
      ("static bool pending_sync_save = false;\n",
       """static bool pending_sync_save = false;
/* Skin Studio (OM, 2026-10-12): 1 wear (path + text), 2 off. */
static int pending_studio = 0;
static char pending_studio_path[512] = {0};
static char pending_studio_text[8192] = {0};
"""),
      ("""  if (skin_sync_save) save_user_settings(settings);
  if (skin_sync) android_skin_publish_state(env);
}
""",
       """  if (skin_sync_save) save_user_settings(settings);
  if (skin_sync) android_skin_publish_state(env);

  /* Skin Studio: parsed here, worn once the atlas is on screen. */
  int studio = 0;
  static char studio_path[512];
  static char studio_text[8192];
  SDL_LockMutex(skin_mutex);
  studio = pending_studio;
  if (studio == 1) {
    memcpy(studio_path, pending_studio_path, sizeof(studio_path));
    memcpy(studio_text, pending_studio_text, sizeof(studio_text));
  }
  pending_studio = 0;
  SDL_UnlockMutex(skin_mutex);
  if (studio == 1) {
    static studio_skin parsed;
    if (studio_parse(studio_text, &parsed))
      renderer_set_studio(env->usr->r, env->ctx, studio_path, &parsed);
    else {
      SDL_Log("Wyrm studio: the skin text was not valid");
      renderer_set_studio(env->usr->r, env->ctx, NULL, NULL);
    }
  } else if (studio == 2) {
    renderer_set_studio(env->usr->r, env->ctx, NULL, NULL);
  }
}
"""),
      ("""JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSkinSync(JNIEnv* env, jclass clazz,
""",
       """/* Skin Studio (OM, 2026-10-12): wear the atlas at [path] with [text]
   (game/studio.h); an empty path takes it off. */
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeStudioSet(JNIEnv* env, jclass clazz,
                                                    jstring path,
                                                    jstring text) {
  (void)clazz;
  if (!skin_mutex) return;
  const char* p = path ? (*env)->GetStringUTFChars(env, path, NULL) : NULL;
  const char* t = text ? (*env)->GetStringUTFChars(env, text, NULL) : NULL;
  SDL_LockMutex(skin_mutex);
  if (p && p[0] && t && t[0] && strlen(t) < sizeof(pending_studio_text) &&
      strlen(p) < sizeof(pending_studio_path)) {
    snprintf(pending_studio_path, sizeof(pending_studio_path), "%s", p);
    snprintf(pending_studio_text, sizeof(pending_studio_text), "%s", t);
    pending_studio = 1;
  } else {
    pending_studio = 2;
  }
  SDL_UnlockMutex(skin_mutex);
  if (p) (*env)->ReleaseStringUTFChars(env, path, p);
  if (t) (*env)->ReleaseStringUTFChars(env, text, t);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSkinSync(JNIEnv* env, jclass clazz,
"""))


def apply(root, label="engine skin studio 2026-10-12", only=None,
          skip_applied=False, ios=False):
    root = Path(root)
    for relative, text in NEW_FILES.items():
        target = root / relative
        if only is not None and relative not in only:
            continue
        if not target.exists() or target.read_text(encoding="utf-8") != text:
            target.write_text(text, encoding="utf-8", newline="")
    for relative, items in PAIRS.items():
        if only is not None and relative not in only:
            continue
        if ios and relative in ANDROID_ONLY:
            continue
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        for item in items:
            if len(item) == 3:
                _, old, new = item
                if skip_applied and old not in text:
                    continue
                if text.count(old) < 1:
                    raise SystemExit(f"{label}: anchor x0 in {relative}: {old[:70]!r}")
                text = text.replace(old, new)
                continue
            old, new = item
            if skip_applied and new in text and (old not in text or old in new):
                continue
            count = text.count(old)
            if count != 1:
                raise SystemExit(f"{label}: anchor x{count} in {relative}: {old[:70]!r}")
            text = text.replace(old, new)
        if text != original:
            target.write_text(text, encoding="utf-8", newline="")
    return len(PAIRS) + len(NEW_FILES)


if __name__ == "__main__":
    # Wyrm Android's tree: python engine_skin_studio_2026_10_12.py "<Wyrm Android>"
    print(apply(sys.argv[1], skip_applied=True), "files written")
