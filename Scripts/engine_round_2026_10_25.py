"""OM's round of 2026-10-25, engine side.

1. Assist mode shows no Wyrm skin (creature or strip look): every snake wears
   its ordinary beads there, the ones its skin block carries.
2. Food textures, normal and assist apart (ext.food_tex, settings
   normal/assist.food_texture): Wyrm, Slither app (the AIR client's
   bright-centred orb over a soft shadow), Crisp, Square (NTL's), Glossy,
   Small. Far away (a pellet under 6 px) or on a crowded screen (more than
   1800 pellets in view) every pellet becomes one cheap dot. Drawn by
   fd.slang's food_texture; the shadow goes on fd_renderer's new under layer
   (plain alpha blending, before the food).
3. Skin textures, NTL's five (ext.skin_tex, settings skin.texture and
   skin.texture_mine = mine only / everyone): Default, Rounded plain, Squared
   plain, NTL textured, Striped plain. The bead sprites a snake pushed are
   turned into plain beads in their own colour (bp.slang reads a uv of -1, -2
   or -3); far away (a head bead under 5 px) every other bead is dropped, as
   NTL widens its bead gap.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree. Each change is skipped when its marker is already present.
The shaders (fd.slang, bp.slang and their .spv) are files, not text patches:
Android's res/shaders and SharedEngine's carry the same bytes.
"""
import sys
from pathlib import Path

FOOD_HELPERS = r'''/* Food textures (OM, 2026-10-25; fd.slang food_texture). `shape` carries
   texture * 16 + shape. A pellet under WYRM_FOOD_LIGHT_PX across, or any
   pellet on a screen with more than WYRM_FOOD_CROWD in view, is one cheap
   dot whatever the texture: the far and the crowded cost least. */
#define WYRM_FOOD_LIGHT_PX 6.0f
#define WYRM_FOOD_CROWD 1800

static void wyrm_food_push(fd_renderer* fdr, float cx, float cy, float d, vec3s c,
                           float fade, float flicker, float shape, int tex,
                           bool crowded) {
  if (crowded || d * 0.9f < WYRM_FOOD_LIGHT_PX) {
    float z = d * 0.35f;
    fd_renderer_push(fdr, &(fd_instance){{cx - z * 0.5f, cy - z * 0.5f, z},
                                         (vec4s){c.r, c.g, c.b, fade}, 0.0f,
                                         5 * 16.0f});
    return;
  }
  switch (tex) {
    case 1: {
      /* The AIR client: a dark disc a little larger and lower, blurred,
         under an additive orb (Main.as foimg_t / per_color_imgs img_t). */
      float z = d * 0.58f;
      fd_renderer_push_u(fdr, &(fd_instance){{cx - z * 0.5f, cy + d * 0.08f - z * 0.5f, z},
                                             (vec4s){0, 0, 0, fade}, 0.0f, 6 * 16.0f});
      fd_renderer_push(fdr, &(fd_instance){{cx - d * 0.5f, cy - d * 0.5f, d},
                                           (vec4s){c.r, c.g, c.b, fade}, flicker,
                                           1 * 16.0f});
      return;
    }
    case 2:
      fd_renderer_push(fdr, &(fd_instance){{cx - d * 0.5f, cy - d * 0.5f, d},
                                           (vec4s){c.r, c.g, c.b, fade}, 0.0f,
                                           2 * 16.0f});
      return;
    case 3: {
      float z = d * 0.3f;
      fd_renderer_push(fdr, &(fd_instance){{cx - z * 0.5f, cy - z * 0.5f, z},
                                           (vec4s){c.r, c.g, c.b, fade}, 0.0f,
                                           3 * 16.0f});
      return;
    }
    case 4:
      fd_renderer_push(fdr, &(fd_instance){{cx - d * 0.5f, cy - d * 0.5f, d},
                                           (vec4s){c.r, c.g, c.b, fade}, 0.0f,
                                           4 * 16.0f});
      return;
    case 5: {
      float z = d * 0.6f;
      fd_renderer_push(fdr, &(fd_instance){{cx - z * 0.5f, cy - z * 0.5f, z},
                                           (vec4s){c.r, c.g, c.b, fade}, flicker,
                                           shape});
      return;
    }
    default:
      fd_renderer_push(fdr, &(fd_instance){{cx - d * 0.5f, cy - d * 0.5f, d},
                                           (vec4s){c.r, c.g, c.b, fade}, flicker,
                                           shape});
      return;
  }
}

/* Skin textures (OM, 2026-10-25), NTL 9.76's "Skin texture": 1 Rounded
   plain (a disc in the bead's colour), 2 Squared plain (upright squares, the
   head's first two round), 3 NTL textured (a soft shaded ball, keeping the
   body's light and dark rhythm), 4 Striped plain (squares turned with the
   body). Runs after a snake's beads are pushed and rewrites them; shadows
   (black) and Skin Studio beads (their own atlas) are left alone. */
static bool skin_uv_same(vec4s a, vec4s b) {
  return a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;
}

static bool skin_texture_bead(const bp_instance* in) {
  if (in->uv_rect.x >= 3.0f) return false;
  return !(in->color.r == 0 && in->color.g == 0 && in->color.b == 0);
}

static void skin_texture_apply(tenv* env, snake* o, int start) {
  user_settings* usrs = &env->usr->usrs;
  int tex = usrs->ext.skin_tex;
  if (tex < 1 || tex > 4) return;
  game_data* gdata = &env->usr->gdata;
  if (usrs->ext.skin_tex_mine && o->id != gdata->data.snake_id) return;
  bp_renderer* r = env->usr->r->bpr;
  int end = r->num_instances;
  if (start < 0 || start >= end) return;

  int beads = 0;
  float head_px = 0;
  for (int i = start; i < end; i++)
    if (skin_texture_bead(r->instances + i)) {
      beads++;
      head_px = r->instances[i].circle.z; /* the head is pushed last */
    }
  /* Far away every other bead is enough (NTL widens its bead gap). */
  bool thin = head_px > 0 && head_px < 5.0f;

  int seen = 0, kept = start;
  for (int i = start; i < end; i++) {
    bp_instance in = r->instances[i];
    if (!skin_texture_bead(&in)) {
      r->instances[kept++] = in;
      continue;
    }
    int from_head = beads - 1 - seen;
    seen++;
    if (thin && from_head > 2 && (from_head & 1)) continue;

    vec3s col = {{in.color.r, in.color.g, in.color.b}};
    float shade = 1.0f;
    for (int g = 0; g < NUM_COLOR_GROUPS; g++) {
      if (g == BLANK_UV) continue;
      if (skin_uv_same(gdata->cg_uvs[g], in.uv_rect)) {
        shade = in.color.r;
        col = gdata->cg_colors[g];
        break;
      }
    }
    int kind = 2;
    if (tex == 1) kind = 1;
    else if (tex == 2) {
      kind = from_head < 2 ? 1 : 2;
      in.circle.w = 0;
    } else if (tex == 3) {
      kind = 3;
      col.r *= shade;
      col.g *= shade;
      col.b *= shade;
    }
    in.uv_rect = (vec4s){{-(float)kind, 0, 0, 0}};
    in.color = (vec4s){{col.r, col.g, col.b, in.color.a}};
    r->instances[kept++] = in;
  }
  r->num_instances = kept;
}

'''

FOOD_SETUP = '''  float bd_cell = 0;
  /* Food texture and the crowded screen (OM, 2026-10-25). */
  const int food_tex =
      usrs->ext.food_tex[usrs->hotkeys[HOTKEY_ASSIST].active ? 1 : 0];
  int food_in_view = 0;
  for (int i = 0; i < foods_len && food_in_view <= WYRM_FOOD_CROWD; i++) {
    food* fv = gdata->data.foods + i;
    if (fv->rx >= gdata->data.fpx1 && fv->ry >= gdata->data.fpy1 &&
        fv->rx <= gdata->data.fpx2 && fv->ry <= gdata->data.fpy2)
      food_in_view++;
  }
  const bool food_crowded = food_in_view > WYRM_FOOD_CROWD;
'''

OLD_PUSH = '''        fd_renderer_push(usr->r->fdr,
                         &(fd_instance){{fx, fy, d},
                                        (vec4s){c.r, c.g, c.b, fo->fr},
                                        mode->food_flicker *
                                            (.5 + .5 * cosf(fo->gfr / 13)),
                                        food_shape(fo, mode->food_type)});
'''
NEW_PUSH = '''        wyrm_food_push(usr->r->fdr, fx + d * 0.5f, fy + d * 0.5f, d, c, fo->fr,
                       mode->food_flicker * (.5 + .5 * cosf(fo->gfr / 13)),
                       food_shape(fo, mode->food_type), food_tex, food_crowded);
'''

EXT_OLD = "  float arrow_sens;\n} user_settings_ext;\n"
EXT_NEW = '''  float arrow_sens;
  /* Food texture (OM, 2026-10-25), normal and assist: 0 Wyrm, 1 Slither
     app, 2 Crisp, 3 Square, 4 Glossy, 5 Small. Append only. */
  int32_t food_tex[2];
  /* Skin texture (OM, 2026-10-25, NTL's five): 0 Default, 1 Rounded plain,
     2 Squared plain, 3 NTL textured, 4 Striped plain. */
  int32_t skin_tex;
  /* The skin texture on my snake only (true) or on every snake. */
  bool skin_tex_mine;
} user_settings_ext;
'''

TAKE_OLD = "/* A bool is one byte. A value other than 0 or 1 is not a bool this build wrote. */\n"
TAKE_NEW = '''/* An int field this build knows the range of; missing or outside = fallback. */
static bool ext_take_int(int32_t* field, int present, int32_t lo, int32_t hi,
                         int32_t fallback) {
  if (present && *field >= lo && *field <= hi) return false;
  *field = fallback;
  return true;
}

''' + TAKE_OLD

LOAD_OLD = '''    fixed |= ext_take_float(&ext->arrow_sens, written >= sens_at + 4, 0.0f,
                            1.0f, 0.0f);
  }
'''
LOAD_NEW = LOAD_OLD + '''  {
    /* Food and skin textures (OM, 2026-10-25): missing or unknown = 0. */
    size_t food_at = offsetof(user_settings_ext, food_tex);
    fixed |= ext_take_int(&ext->food_tex[0], written >= food_at + 4, 0, 5, 0);
    fixed |= ext_take_int(&ext->food_tex[1], written >= food_at + 8, 0, 5, 0);
    size_t tex_at = offsetof(user_settings_ext, skin_tex);
    fixed |= ext_take_int(&ext->skin_tex, written >= tex_at + 4, 0, 4, 0);
    size_t mine_at = offsetof(user_settings_ext, skin_tex_mine);
    fixed |= ext_take_bool(&ext->skin_tex_mine, written >= mine_at + 1);
  }
'''

TABLE_OLD = '''    {"assist.boost_own", "assist", "", "", SETTING_BOOL, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(ext.boost_own[1])},
'''
TABLE_NEW = TABLE_OLD + '''    /* Food texture (OM, 2026-10-25), normal and assist; Food page. */
    {"normal.food_texture", "normal", "", "", SETTING_INT, 0, 5, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(ext.food_tex[0])},
    {"assist.food_texture", "assist", "", "", SETTING_INT, 0, 5, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(ext.food_tex[1])},
    /* Skin texture (OM, 2026-10-25), Skin tab › Select texture. */
    {"skin.texture", "skin", "", "", SETTING_INT, 0, 4, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(ext.skin_tex)},
    {"skin.texture_mine", "skin", "", "", SETTING_BOOL, 0, 1, NULL,
     OWNER_SETTINGS, SETTINGS_FIELD(ext.skin_tex_mine)},
'''

FDH_OLD = "  tdbuffer* t_instance_buffer;\n"
FDH_NEW = '''  /* Drawn first, with the same plain alpha blending: shadows under food
     (the Slither app food texture, OM 2026-10-25). */
  tdbuffer* u_instance_buffer;
  fd_instance* u_instances;
  int max_u_instances;
  int num_u_instances;
''' + FDH_OLD
FDH2_OLD = "void fd_renderer_push_t(fd_renderer* r, const fd_instance* instance);\n"
FDH2_NEW = FDH2_OLD + "void fd_renderer_push_u(fd_renderer* r, const fd_instance* instance);\n"

FDC_ALLOC_OLD = "  r->num_t_instances = 0;\n\n  return r;\n"
FDC_ALLOC_NEW = '''  r->num_t_instances = 0;

  r->max_u_instances = FD_MAX_T_INSTANCES;
  r->u_instance_buffer =
      tdbuffer_create(ctx, NULL, r->max_u_instances * sizeof(fd_instance),
                      VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
  r->u_instances = malloc(r->max_u_instances * sizeof(fd_instance));
  r->num_u_instances = 0;

  return r;
'''
FDC_PUSH_OLD = "void fd_renderer_render(fd_renderer* r, tcontext* ctx) {\n"
FDC_PUSH_NEW = '''void fd_renderer_push_u(fd_renderer* r, const fd_instance* instance) {
  if (r->num_u_instances >= r->max_u_instances) {
    return;
  }
  r->u_instances[r->num_u_instances++] = *instance;
}

''' + FDC_PUSH_OLD
FDC_RENDER_OLD = '''  memcpy(r->instance_buffer[ctx->current_frame].data, r->instances,
         r->num_instances * sizeof(fd_instance));
'''
FDC_RENDER_NEW = '''  if (r->num_u_instances > 0) {
    memcpy(r->u_instance_buffer[ctx->current_frame].data, r->u_instances,
           r->num_u_instances * sizeof(fd_instance));
    vkCmdBindPipeline(fr->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
                      r->pipelines[2]);
    vkCmdBindVertexBuffers(fr->cmd, 1, 1,
                           &r->u_instance_buffer[ctx->current_frame].handle,
                           (VkDeviceSize[]){0});
    vkCmdDraw(fr->cmd, 4, r->num_u_instances, 0, 0);
  }
''' + FDC_RENDER_OLD
FDC_FREE_OLD = "  free(r->t_instances);\n"
FDC_FREE_NEW = "  free(r->u_instances);\n  tdbuffer_destroy(ctx, r->u_instance_buffer);\n" + FDC_FREE_OLD
REN_OLD = "  r->fdr->num_t_instances = 0;\n"
REN_NEW = REN_OLD + "  r->fdr->num_u_instances = 0;\n"

PAIRS = [
    # (file, marker, old, new, count)
    ("game/redraw.c", "Assist mode shows no Wyrm skin (OM, 2026-10-25)",
     "        const int wyrm_skin =\n"
     "            rope_mode ? 0\n",
     "        /* Assist mode shows no Wyrm skin (OM, 2026-10-25): the snake wears\n"
     "           its ordinary beads there, as its skin block carries them. */\n"
     "        const int wyrm_skin =\n"
     "            rope_mode || usrs->hotkeys[HOTKEY_ASSIST].active ? 0\n", 1),
    ("game/user_settings.h", "int32_t food_tex[2];", EXT_OLD, EXT_NEW, 1),
    ("game/user_settings.c", "static bool ext_take_int(", TAKE_OLD, TAKE_NEW, 1),
    ("game/user_settings.c", "Food and skin textures (OM, 2026-10-25)", LOAD_OLD, LOAD_NEW, 1),
    ("platform/android_settings.c", "\"normal.food_texture\"", TABLE_OLD, TABLE_NEW, 1),
    ("rendering/fd_renderer.h", "u_instance_buffer", FDH_OLD, FDH_NEW, 1),
    ("rendering/fd_renderer.h", "fd_renderer_push_u", FDH2_OLD, FDH2_NEW, 1),
    ("rendering/fd_renderer.c", "r->max_u_instances = ", FDC_ALLOC_OLD, FDC_ALLOC_NEW, 1),
    ("rendering/fd_renderer.c", "void fd_renderer_push_u(", FDC_PUSH_OLD, FDC_PUSH_NEW, 1),
    ("rendering/fd_renderer.c", "r->u_instance_buffer[ctx->current_frame]", FDC_RENDER_OLD, FDC_RENDER_NEW, 1),
    ("rendering/fd_renderer.c", "free(r->u_instances);", FDC_FREE_OLD, FDC_FREE_NEW, 1),
    ("rendering/renderer.c", "num_u_instances = 0;", REN_OLD, REN_NEW, 1),
    ("game/redraw.c", "static void wyrm_food_push(", "void redraw(tenv* env) {",
     FOOD_HELPERS + "void redraw(tenv* env) {", 1),
    ("game/redraw.c", "const bool food_crowded", "  float bd_cell = 0;\n", FOOD_SETUP, 1),
    ("game/redraw.c", "food_tex, food_crowded);", OLD_PUSH, NEW_PUSH, 2),
    ("game/redraw.c", "int skin_tex_start =",
     "          if (mode->render_mode == 0) {\n            float shadow_strength = 0.25f;\n",
     "          /* Skin texture (OM, 2026-10-25): this snake's beads start here. */\n"
     "          int skin_tex_start = usr->r->bpr->num_instances;\n"
     "          if (mode->render_mode == 0) {\n            float shadow_strength = 0.25f;\n", 1),
    ("game/redraw.c", "skin_texture_apply(env, o, skin_tex_start);",
     "          } else if (mode->render_mode == 1) {\n",
     "            skin_texture_apply(env, o, skin_tex_start);\n"
     "          } else if (mode->render_mode == 1) {\n", 1),
]


def apply(root, label="engine round 2026-10-25"):
    src = Path(root) / "app" / "src"
    for name, marker, old, new, count in PAIRS:
        path = src / name
        raw = path.read_bytes().decode("utf-8")
        crlf = "\r\n" in raw
        text = raw.replace("\r\n", "\n")
        if marker in text:
            continue
        if text.count(old) != count:
            raise SystemExit(f"{label}: {name}: anchor x{text.count(old)}: {old[:60]!r}")
        text = text.replace(old, new)
        if crlf:
            text = text.replace("\n", "\r\n")
        path.write_bytes(text.encode("utf-8"))


if __name__ == "__main__":
    apply(Path(sys.argv[1]) if len(sys.argv) > 1 else Path("."))
