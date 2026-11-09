"""Hidden bead parts, far snakes and a frame budget (OM, 2026-10-30).

1. Hidden parts are not drawn. A snake's beads are drawn tail first, so each
   bead lies under the next one. Where the next bead is solid (alpha 1, a
   colour-group cell or a plain kind; every group cell is opaque to 0.99 of
   its radius, measured from tex_atlas_8k.png), the part of the bead it covers
   is never shaded: the bead's sprite is shortened, in the shader, to the
   half-plane t <= d along the line to the next bead, with
       d = (s^2 + R^2 - ro^2) / (2 s)
   (s the centre distance, R the sprite's outer radius, ro the next bead's
   solid radius, R - EDGE - 0.5 and at most 0.95 R). Every point of the bead
   beyond d lies inside the next bead's solid disc, so the picture is the same
   pixel for pixel. It is worked out again every frame from the real centres,
   so a turn that uncovers a bead's edge draws that edge: nothing covered by
   nothing is ever left out. A fading snake (alpha < 1), a Studio bead, a
   Wyrm or AIR textured bead as the cover, and the square plain bead are left
   whole.

2. Far snakes: where the beads crowd under a pixel apart, every other bead is
   left out, but only where the two kept neighbours still overlap by at least
   half a bead, so the body stays one solid line.

3. The frame budget: the engine measures its own frame time against the
   display's top refresh rate (120 Hz on the Moto) and, only for other players'
   snakes, steps the far-snake rule up (level 0..3) and at level 2 leaves out
   their shadows while it cannot keep up, and steps back down once it can.
   Your own snake always keeps full detail.

The shader change is the vertex stage only (bpv.spv, rebuilt with slangc;
SharedEngine's copy and hash refreshed). bp_instance gains `clip` at its end,
so every existing compound literal leaves it zero (whole bead).

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

CULL_CODE = r'''/* Hidden bead parts, far snakes and the frame budget (OM, 2026-10-30;
   Wyrm iOS/Scripts/engine_bead_cull_2026_10_30.py). */
static int wyrm_budget_level;
static float wyrm_budget_avg_ms, wyrm_budget_target_ms = 1000.0f / 60.0f;
static Uint64 wyrm_budget_last_ns, wyrm_budget_changed_ns, wyrm_budget_rate_ns;

/* Once a frame: how far this frame came after the last, against the display. */
static void wyrm_budget_tick(tenv* env) {
  Uint64 now = SDL_GetTicksNS();
  if (wyrm_budget_rate_ns == 0 || now - wyrm_budget_rate_ns > SDL_NS_PER_SECOND) {
    wyrm_budget_rate_ns = now;
    SDL_DisplayID display =
        env->wnd && env->wnd->handle ? SDL_GetDisplayForWindow(env->wnd->handle) : 0;
    const SDL_DisplayMode* dm = display ? SDL_GetCurrentDisplayMode(display) : NULL;
    if (dm && dm->refresh_rate >= 30.0f && dm->refresh_rate <= 360.0f)
      wyrm_budget_target_ms = 1000.0f / dm->refresh_rate;
  }
  float dt = wyrm_budget_last_ns ? (float)(now - wyrm_budget_last_ns) / 1e6f : -1;
  wyrm_budget_last_ns = now;
  /* A pause (menu, background) starts the average afresh. */
  if (dt <= 0 || dt > 250) {
    wyrm_budget_avg_ms = wyrm_budget_target_ms;
    return;
  }
  wyrm_budget_avg_ms += (dt - wyrm_budget_avg_ms) * 0.05f;
  float since = (float)(now - wyrm_budget_changed_ns) / 1e9f;
  int before = wyrm_budget_level;
  if (wyrm_budget_avg_ms > wyrm_budget_target_ms * 1.2f && since > 1.0f &&
      wyrm_budget_level < 3)
    wyrm_budget_level++;
  else if (wyrm_budget_avg_ms < wyrm_budget_target_ms * 1.05f && since > 4.0f &&
           wyrm_budget_level > 0)
    wyrm_budget_level--;
  if (wyrm_budget_level != before) {
    wyrm_budget_changed_ns = now;
    SDL_Log("Wyrm frame budget: level %d (%.1f ms a frame, display %.1f ms)",
            wyrm_budget_level, wyrm_budget_avg_ms, wyrm_budget_target_ms);
  }
}

/* A round body bead of this snake (not a shadow, not the square plain bead). */
static bool bead_round_body(const bp_instance* in, float size) {
  if (fabsf(in->circle.z - size) > 0.01f) return false;
  if (in->color.r == 0 && in->color.g == 0 && in->color.b == 0) return false;
  float u = in->uv_rect.x;
  return !(u < -1.5f && u > -2.5f);
}

/* Solid to its rim: alpha 1 and a colour-group cell (rows 0..5) or a plain kind. */
static bool bead_solid_cover(const bp_instance* in) {
  if (in->color.a < 0.999f) return false;
  float u = in->uv_rect.x;
  if (u < -0.5f) return true;
  if (u >= 3.0f) return false;
  return fabsf(in->uv_rect.z - 1.0f / 7.0f) < 1e-5f &&
         fabsf(in->uv_rect.w - 1.0f / 9.0f) < 1e-5f &&
         in->uv_rect.y < 6.0f / 9.0f - 1e-4f;
}

static bool bead_shadow(const bp_instance* in) {
  return in->uv_rect.x < 3.0f && in->uv_rect.x > -0.5f && in->color.r == 0 &&
         in->color.g == 0 && in->color.b == 0;
}

#define WYRM_CULL_MAX 8192
static void bead_cull_apply(tenv* env, snake* o, int start, float size) {
  static int idx[WYRM_CULL_MAX];
  static unsigned char drop[WYRM_CULL_MAX];
  bp_renderer* r = env->usr->r->bpr;
  int end = r->num_instances;
  if (start < 0 || end - start < 2 || size < 1.0f) return;
  const bool mine = o->id == env->usr->gdata.data.snake_id;
  static const float thin_px[4] = {0.75f, 1.5f, 2.5f, 4.0f};
  const int level = mine ? 0 : wyrm_budget_level;
  const float thin = fminf(thin_px[level], 0.25f * size);
  const bool drop_shadows = !mine && level >= 2;

  int n = 0;
  for (int i = start; i < end && n < WYRM_CULL_MAX; i++)
    if (bead_round_body(r->instances + i, size)) {
      idx[n] = i;
      drop[n] = 0;
      n++;
    }

  /* Far beads: every other one, where its kept neighbours still overlap by
     half a bead or more. The tail tip and the last four (the head) stay. */
  for (int k = 1; k < n - 4; k += 2) {
    const bp_instance* a = r->instances + idx[k - 1];
    const bp_instance* b = r->instances + idx[k + 1];
    float dx = b->circle.x - a->circle.x, dy = b->circle.y - a->circle.y;
    if (dx * dx + dy * dy < 4.0f * thin * thin) drop[k] = 1;
  }

  /* Hidden parts: each kept bead against the next kept one. */
  const float edge = 2.0f; /* EDGE_SOFTNESS in modules/common.slang */
  const float half = 0.5f * (size + edge);
  const float solid = fminf(half - edge - 0.5f, 0.95f * half);
  for (int k = 0; k < n; k++) {
    if (drop[k]) continue;
    bp_instance* in = r->instances + idx[k];
    in->clip = (vec4s){{0, 0, 0, 0}};
    int next = k + 1;
    while (next < n && drop[next]) next++;
    if (next >= n || solid <= 0) continue;
    const bp_instance* cover = r->instances + idx[next];
    if (!bead_solid_cover(cover)) continue;
    float dx = cover->circle.x - in->circle.x, dy = cover->circle.y - in->circle.y;
    float s = sqrtf(dx * dx + dy * dy);
    if (s < 0.5f) continue;
    float d = (s * s + half * half - solid * solid) / (2.0f * s);
    if (d >= half - 0.5f) continue;
    in->clip = (vec4s){{dx / s, dy / s, d, 1}};
  }

  bool any = drop_shadows;
  for (int k = 0; k < n && !any; k++) any = drop[k];
  if (!any) return;
  int kept = start, k = 0;
  for (int i = start; i < end; i++) {
    if (k < n && idx[k] == i) {
      if (drop[k++]) continue;
    } else if (drop_shadows && bead_shadow(r->instances + i)) {
      continue;
    }
    r->instances[kept++] = r->instances[i];
  }
  r->num_instances = kept;
}

static bool skin_uv_same(vec4s a, vec4s b) {'''

PAIRS = {
    "app/src/rendering/bp_renderer.h": [
        ("""  vec4s color;
} bp_instance;""", """  vec4s color;
  /* Hidden part (OM, 2026-10-30, game/redraw.c bead_cull_apply): x, y the
     unit line to the bead above, z where that bead's solid disc begins, w 1
     when set. Zero (every compound literal) draws the whole bead. */
  vec4s clip;
} bp_instance;"""),
    ],
    "app/src/rendering/bp_renderer.c": [
        (""".vertexAttributeDescriptionCount = 4,""", """.vertexAttributeDescriptionCount = 5,"""),
        ("""                          {.location = 3,
                           .binding = 1,
                           .format = VK_FORMAT_R32G32B32A32_SFLOAT,
                           .offset = offsetof(bp_instance, color)}}},""", """                          {.location = 3,
                           .binding = 1,
                           .format = VK_FORMAT_R32G32B32A32_SFLOAT,
                           .offset = offsetof(bp_instance, color)},
                          {.location = 4,
                           .binding = 1,
                           .format = VK_FORMAT_R32G32B32A32_SFLOAT,
                           .offset = offsetof(bp_instance, clip)}}},"""),
    ],
    "app/src/game/redraw.c": [
        ("""static bool skin_uv_same(vec4s a, vec4s b) {""", CULL_CODE),
        ("""  tags_draw_flying(env);
""", """  tags_draw_flying(env);
  /* The frame budget (OM, 2026-10-30): measured once a frame. */
  wyrm_budget_tick(env);
"""),
        ("""            draw_skinless_strip(env, o, bp, mww2, mhh2, lsz, a);
          }
""", """            draw_skinless_strip(env, o, bp, mww2, mhh2, lsz, a);
          }
          /* Hidden bead parts and far beads (OM, 2026-10-30). */
          if (mode->render_mode != 3)
            bead_cull_apply(env, o, skin_tex_start, gdata->data.gsc * 2 * lsz);
"""),
    ],
}


def apply(root, label="bead cull 2026-10-30", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        text = path.read_text(encoding="utf-8")
        for old, new in pairs:
            if skip_applied and new in text:
                continue
            if text.count(old) != 1:
                raise SystemExit(f"{label}: anchor x{text.count(old)} in {relative}: {old[:80]!r}")
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8", newline="\n" if "build-original-source" in str(root) else "")


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
