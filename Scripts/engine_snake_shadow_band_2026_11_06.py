"""Snake shadow as one band round each snake (OM, 2026-11-06).

Modes > Snake shadow drew AIR's `ksmc_t` stamp (a black disc 1.15 bead radii
across with a soft rim to 1.6) once for every body point of every snake.
Body points sit about half a bead radius apart, so every shadow pixel was
blended by ten or more translucent stamps, on every snake: 130+ FPS with two
or three snakes on screen fell to 60 with eight or nine (Moto g85, OM).

Now the shadow is one mesh per snake that follows the body, with round ends,
in two layers measured from AIR's stamps composited at the real point
spacing (tex_atlas_8k.png cell 4/6, points 0.48 bead radii apart):
- a core centred on the body, solid to 1.12 bead radii;
- a soft halo whose centre line is 0.15 bead radii lower on the screen. The
  stamp is a drop shadow lit from above and is never turned, so AIR's shadow
  reaches 1.3 above a body, 1.45 at its sides and 1.6 below; one shifted
  halo matches all three within 0.03 alpha.
Checked by running this C (harness) and AIR's own stamps on the same coiled
snake in the same draw order: mean difference 0.13/255 a pixel, 99th
percentile 2/255. Each pixel is now shaded at most twice, not ten-plus times.

It stays in the air, as AIR's does (OM): each snake's band is drawn in the
middle of the bead stream, just before that snake's own beads, in pieces of
24 body points that go in at the same place AIR's stamps went (four points
behind the bead being drawn). So a snake's shadow falls on every snake drawn
before it and on its own coils, and never on its own beads above.

How a piece reaches the screen: a marker bp_instance (uv.x 2.5, black, alpha
0, circle.z -1) is pushed into the bead stream where the piece belongs;
bp_renderer_render draws the beads up to it, then the piece's triangles with
the new shadow pipeline (sh.slang: black, alpha per vertex), then the beads
after it. The marker looks like a black atlas sprite (a shadow) to the bead
passes, so it moves with them, is dropped where they drop shadows (far
snakes at frame-budget level 2+, plain and NTL skin textures) and is never
taken for a body bead.

New shader binaries shv.spv / shf.spv (slangc with build.py's flags);
Android packages them through tassets.c, iOS through SharedEngine's res.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

BAND_CODE = r'''/* Snake shadow band (OM, 2026-11-06;
   Wyrm iOS/Scripts/engine_snake_shadow_band_2026_11_06.py). AIR's ksmc_t
   stamps composited along the body at the real point spacing (0.48 bead
   radii), measured from tex_atlas_8k.png, in bead radii (lsz):
   - a core, centred on the body: solid to 1.12;
   - a soft halo whose centre line sits 0.15 lower on the screen (the stamp
     is a drop shadow lit from above, never turned), so it reaches 1.3 above
     the body, 1.45 at the sides and 1.6 below, as AIR's does. */
#define AIR_CORE_RINGS 3
static const float air_core_r[AIR_CORE_RINGS] = {0, 1.12f, 1.17f};
static const float air_core_a[AIR_CORE_RINGS] = {1, 1, 0};
#define AIR_HALO_RINGS 8
static const float air_halo_r[AIR_HALO_RINGS] = {0,     0.95f, 1.05f, 1.15f,
                                                 1.25f, 1.35f, 1.45f, 1.5f};
static const float air_halo_a[AIR_HALO_RINGS] = {1,     1,      0.65f, 0.41f,
                                                 0.27f, 0.125f, 0.02f, 0};
#define AIR_HALO_DROP 0.15f
#define AIR_BAND_INTERVALS ((AIR_CORE_RINGS - 1) + (AIR_HALO_RINGS - 1))
#define AIR_BAND_CAP_STEPS 8
/* Body points a piece holds: under the shortest coil a snake can make, so a
   piece never has to lie both under and over the same snake's beads. */
#define AIR_BAND_CHUNK 24

static struct {
  float unit;  /* one bead radius on screen */
  float alpha;
  int bp;      /* body points of the snake being drawn */
  int pending; /* segments in the open piece */
} air_band;

typedef struct air_band_layer {
  const float* r;
  const float* a;
  int rings;
  float dy; /* the layer's centre line, this far below the body (px) */
} air_band_layer;

static int air_band_layers(air_band_layer out[2]) {
  out[0] = (air_band_layer){air_core_r, air_core_a, AIR_CORE_RINGS, 0};
  out[1] = (air_band_layer){air_halo_r, air_halo_a, AIR_HALO_RINGS,
                            AIR_HALO_DROP * air_band.unit};
  return 2;
}

static void air_band_point(tenv* env, int p, float mww2, float mhh2,
                           float* x, float* y) {
  game_data* gdata = &env->usr->gdata;
  *x = (gdata->data.pbx[p] - gdata->data.view_xx) * gdata->data.gsc + mww2;
  *y = (gdata->data.pby[p] - gdata->data.view_yy) * gdata->data.gsc + mhh2;
}

/* At body point p: screen place, unit tangent (towards the tail), normal, and
   how far each side may reach. The inside of a bend never reaches past the
   bend's own centre, so the mesh does not fold over itself in a tight coil. */
typedef struct air_band_frame {
  float x, y, tx, ty, nx, ny, left, right;
} air_band_frame;

static air_band_frame air_band_frame_at(tenv* env, int bp, int p, float mww2,
                                        float mhh2) {
  air_band_frame f;
  float px, py, qx, qy;
  int prev = p > 0 ? p - 1 : p, next = p < bp - 1 ? p + 1 : p;
  air_band_point(env, p, mww2, mhh2, &f.x, &f.y);
  air_band_point(env, prev, mww2, mhh2, &px, &py);
  air_band_point(env, next, mww2, mhh2, &qx, &qy);
  float ax = f.x - px, ay = f.y - py, bx = qx - f.x, by = qy - f.y;
  float la = sqrtf(ax * ax + ay * ay), lb = sqrtf(bx * bx + by * by);
  float tx = (la > 1e-4f ? ax / la : 0) + (lb > 1e-4f ? bx / lb : 0);
  float ty = (la > 1e-4f ? ay / la : 0) + (lb > 1e-4f ? by / lb : 0);
  float tl = sqrtf(tx * tx + ty * ty);
  if (tl < 1e-4f) {
    tx = 1;
    ty = 0;
  } else {
    tx /= tl;
    ty /= tl;
  }
  f.tx = tx;
  f.ty = ty;
  f.nx = -ty;
  f.ny = tx;
  f.left = f.right = 1;
  if (la > 1e-4f && lb > 1e-4f) {
    float cross = (ax * by - ay * bx) / (la * lb);
    float dot = (ax * bx + ay * by) / (la * lb);
    float turn = fabsf(atan2f(cross, dot));
    float reach = air_halo_r[AIR_HALO_RINGS - 1] * air_band.unit;
    if (turn > 1e-4f && reach > 0) {
      float bend = 0.5f * (la + lb) / turn;
      if (bend < reach) {
        if (cross > 0)
          f.left = bend / reach;
        else
          f.right = bend / reach;
      }
    }
  }
  return f;
}

static void air_band_vertex(bp_shadow_vertex** v, float x, float y, float a) {
  **v = (bp_shadow_vertex){x, y, a};
  (*v)++;
}

/* Two triangles: a0-a1 on one rail, b0-b1 on the next. */
static void air_band_quad(bp_shadow_vertex** v, float a0x, float a0y,
                          float a1x, float a1y, float b0x, float b0y,
                          float b1x, float b1y, float ia, float oa) {
  air_band_vertex(v, a0x, a0y, ia);
  air_band_vertex(v, a1x, a1y, oa);
  air_band_vertex(v, b1x, b1y, oa);
  air_band_vertex(v, a0x, a0y, ia);
  air_band_vertex(v, b1x, b1y, oa);
  air_band_vertex(v, b0x, b0y, ia);
}

/* A new piece at this point of the bead stream. */
static void air_band_open(tenv* env) {
  if (bp_renderer_shadow_chunk(env->usr->r->bpr)) air_band.pending = 0;
}

/* The band between body points p and p + 1. */
static void air_band_segment(tenv* env, int bp, int p, float mww2, float mhh2) {
  game_data* gdata = &env->usr->gdata;
  if (p < 0 || p + 1 >= bp || gdata->data.pbu[p] != 2 ||
      gdata->data.pbu[p + 1] != 2)
    return;
  if (air_band.pending >= AIR_BAND_CHUNK) air_band_open(env);
  bp_shadow_vertex* v = bp_renderer_shadow_reserve(
      env->usr->r->bpr, 2 * AIR_BAND_INTERVALS * 6);
  if (!v) return;
  air_band_frame f0 = air_band_frame_at(env, bp, p, mww2, mhh2);
  air_band_frame f1 = air_band_frame_at(env, bp, p + 1, mww2, mhh2);
  /* One normal sense for both ends, so the rails never cross. */
  float s1 = f0.nx * f1.nx + f0.ny * f1.ny < 0 ? -1.0f : 1.0f;
  air_band_layer layers[2];
  int count = air_band_layers(layers);
  for (int l = 0; l < count; ++l) {
    const air_band_layer* L = layers + l;
    for (int side = 0; side < 2; ++side) {
      float sg = side ? -1.0f : 1.0f;
      float k0 = side ? f0.right : f0.left;
      float k1 = (side ^ (s1 < 0)) ? f1.right : f1.left;
      float n0x = sg * f0.nx, n0y = sg * f0.ny;
      float n1x = sg * s1 * f1.nx, n1y = sg * s1 * f1.ny;
      float c0x = f0.x, c0y = f0.y + L->dy, c1x = f1.x, c1y = f1.y + L->dy;
      for (int k = 0; k + 1 < L->rings; ++k) {
        float ri = L->r[k] * air_band.unit, ro = L->r[k + 1] * air_band.unit;
        float ia = L->a[k] * air_band.alpha, oa = L->a[k + 1] * air_band.alpha;
        air_band_quad(&v, c0x + n0x * ri * k0, c0y + n0y * ri * k0,
                      c0x + n0x * ro * k0, c0y + n0y * ro * k0,
                      c1x + n1x * ri * k1, c1y + n1y * ri * k1,
                      c1x + n1x * ro * k1, c1y + n1y * ro * k1, ia, oa);
      }
    }
  }
  air_band.pending++;
}

/* A round end at body point p, bulging along the tangent times `sign`. */
static void air_band_cap(tenv* env, int bp, int p, float sign, float mww2,
                         float mhh2) {
  game_data* gdata = &env->usr->gdata;
  if (p < 0 || p >= bp || gdata->data.pbu[p] != 2) return;
  bp_shadow_vertex* v = bp_renderer_shadow_reserve(
      env->usr->r->bpr, AIR_BAND_CAP_STEPS * AIR_BAND_INTERVALS * 6);
  if (!v) return;
  air_band_frame f = air_band_frame_at(env, bp, p, mww2, mhh2);
  float ox = sign * f.tx, oy = sign * f.ty;
  air_band_layer layers[2];
  int count = air_band_layers(layers);
  for (int l = 0; l < count; ++l) {
    const air_band_layer* L = layers + l;
    float cx = f.x, cy = f.y + L->dy;
    for (int i = 0; i < AIR_BAND_CAP_STEPS; ++i) {
      float t0 = (float)PI * i / AIR_BAND_CAP_STEPS;
      float t1 = (float)PI * (i + 1) / AIR_BAND_CAP_STEPS;
      float d0x = f.nx * cosf(t0) + ox * sinf(t0), d0y = f.ny * cosf(t0) + oy * sinf(t0);
      float d1x = f.nx * cosf(t1) + ox * sinf(t1), d1y = f.ny * cosf(t1) + oy * sinf(t1);
      for (int k = 0; k + 1 < L->rings; ++k) {
        float ri = L->r[k] * air_band.unit, ro = L->r[k + 1] * air_band.unit;
        float ia = L->a[k] * air_band.alpha, oa = L->a[k + 1] * air_band.alpha;
        air_band_quad(&v, cx + d0x * ri, cy + d0y * ri, cx + d0x * ro,
                      cy + d0y * ro, cx + d1x * ri, cy + d1y * ri,
                      cx + d1x * ro, cy + d1y * ro, ia, oa);
      }
    }
  }
}

'''

ENDS_OLD = r'''static void air_snake_shadow_ends(tenv* env, int bp, float half, float a,
                                  float mww2, float mhh2, float* sx,
                                  float* sy) {
  game_data* gdata = &env->usr->gdata;
  for (int p = bp - 1 < 8 ? bp - 1 : 8; p >= 0; p--)
    if (gdata->data.pbu[p] == 2)
      apple_air_shadow(env, p, half, a * (1 - p / 9.0f), mww2, mhh2);
  for (int n = 1; n <= 4; ++n) {
    int p = bp - n;
    if (p < 0 || gdata->data.pbu[p] != 2) continue;
    float spacing = apple_air_spacing(env, p, sx, sy);
    if (n == 1) spacing = 1;
    apple_air_shadow(env, p, half, spacing * a * (p < 9 ? p / 9.0f : 1), mww2,
                     mhh2);
  }
}

static void air_snake_shadow_behind(tenv* env, int j, float half, float a,
                                    float mww2, float mhh2, float* sx,
                                    float* sy) {
  game_data* gdata = &env->usr->gdata;
  int p = j - 4;
  if (p < 0 || gdata->data.pbu[p] != 2) return;
  float spacing = apple_air_spacing(env, p, sx, sy);
  apple_air_shadow(env, p, half, spacing * a * (p < 9 ? p / 9.0f : 1), mww2,
                   mhh2);
}'''

ENDS_NEW = BAND_CODE + r'''/* Before a snake's beads, where AIR drew its head and tail stamps: a new
   piece with both round ends and the tail's last four points. */
static void air_snake_shadow_ends(tenv* env, int bp, float half, float a,
                                  float mww2, float mhh2, float* sx,
                                  float* sy) {
  (void)sx;
  (void)sy;
  air_band.unit = half / APPLE_AIR_SHADOW_SCALE;
  air_band.alpha = a;
  air_band.bp = bp;
  air_band_open(env);
  air_band_cap(env, bp, 0, -1, mww2, mhh2);
  air_band_cap(env, bp, bp - 1, 1, mww2, mhh2);
  /* Segments bp-4 .. bp-1; the body beads bring the rest (bead j: j-4). */
  for (int p = bp - 2; p >= 0 && p >= bp - 4; p--)
    air_band_segment(env, bp, p, mww2, mhh2);
}

/* Before body bead j, as AIR drew the stamp four points behind it: the band
   from that point on towards the tail. */
static void air_snake_shadow_behind(tenv* env, int j, float half, float a,
                                    float mww2, float mhh2, float* sx,
                                    float* sy) {
  (void)half;
  (void)a;
  (void)sx;
  (void)sy;
  int p = j - 4;
  if (p < 0) return;
  air_band_segment(env, air_band.bp, p, mww2, mhh2);
}'''

RENDER_OLD = r'''void bp_renderer_render(bp_renderer* r, tcontext* ctx) {
  tcontext_frame* fr = ctx->frames + ctx->current_frame;
  if (r->num_instances <= 0 || !tdbuffer_upload(ctx, r->instance_buffer,
      ctx->current_frame, r->instances,
      (VkDeviceSize)r->num_instances * sizeof(bp_instance))) return;
  vkCmdBindPipeline(fr->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->pipeline);
  vkCmdBindVertexBuffers(fr->cmd, 1, 1, &r->instance_buffer[ctx->current_frame].handle, (VkDeviceSize[]){0});
  vkCmdDraw(fr->cmd, 4, r->num_instances, 0, 0);
}'''

RENDER_NEW = r'''/* Snake shadow band (OM, 2026-11-06; game/redraw.c air_band_*): a marker
   in the bead stream says "this piece of shadow goes here". */
static bool bp_shadow_marker(const bp_instance* in) {
  return in->circle.z == -1.0f && in->uv_rect.x == BP_SHADOW_MARK_U &&
         in->color.a == 0.0f;
}

void bp_renderer_render(bp_renderer* r, tcontext* ctx) {
  tcontext_frame* fr = ctx->frames + ctx->current_frame;
  if (r->num_instances <= 0 || !tdbuffer_upload(ctx, r->instance_buffer,
      ctx->current_frame, r->instances,
      (VkDeviceSize)r->num_instances * sizeof(bp_instance))) return;
  bool shadows = r->shadow_pipeline != VK_NULL_HANDLE &&
                 r->num_shadow_vertices > 0 && r->num_shadow_chunks > 0 &&
                 tdbuffer_upload(ctx, r->shadow_buffer, ctx->current_frame,
                     r->shadow_vertices,
                     (VkDeviceSize)r->num_shadow_vertices *
                         sizeof(bp_shadow_vertex));
  vkCmdBindPipeline(fr->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->pipeline);
  vkCmdBindVertexBuffers(fr->cmd, 1, 1, &r->instance_buffer[ctx->current_frame].handle, (VkDeviceSize[]){0});
  if (!shadows) {
    /* Markers are invisible (alpha 0); without shadows they are drawn as
       nothing along with the beads. */
    vkCmdDraw(fr->cmd, 4, r->num_instances, 0, 0);
    return;
  }
  vkCmdBindVertexBuffers(fr->cmd, 2, 1, &r->shadow_buffer[ctx->current_frame].handle, (VkDeviceSize[]){0});
  int from = 0;
  for (int i = 0; i < r->num_instances; i++) {
    const bp_instance* in = r->instances + i;
    if (!bp_shadow_marker(in)) continue;
    int chunk = (int)in->circle.x;
    if (chunk < 0 || chunk >= r->num_shadow_chunks) continue;
    int first = r->shadow_chunk_first[chunk];
    int last = chunk + 1 < r->num_shadow_chunks
                   ? r->shadow_chunk_first[chunk + 1]
                   : r->num_shadow_vertices;
    if (last <= first) continue;
    if (i > from) vkCmdDraw(fr->cmd, 4, (uint32_t)(i - from), 0, (uint32_t)from);
    vkCmdBindPipeline(fr->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->shadow_pipeline);
    vkCmdDraw(fr->cmd, (uint32_t)(last - first), 1, (uint32_t)first, 0);
    vkCmdBindPipeline(fr->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->pipeline);
    from = i + 1;
  }
  if (r->num_instances > from)
    vkCmdDraw(fr->cmd, 4, (uint32_t)(r->num_instances - from), 0, (uint32_t)from);
}

void bp_renderer_enable_shadows(bp_renderer* r, tcontext* ctx,
                                VkPipelineLayout layout, VkRenderPass pass,
                                int max_vertices, int max_chunks) {
  VkShaderModule vs = tcontext_create_shader(ctx, "app/res/shaders/bin/shv.spv");
  VkShaderModule fs = tcontext_create_shader(ctx, "app/res/shaders/bin/shf.spv");
  VkResult made = vkCreateGraphicsPipelines(
      ctx->device, VK_NULL_HANDLE, 1,
      &(VkGraphicsPipelineCreateInfo){
          .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
          .stageCount = 2,
          .pStages =
              (VkPipelineShaderStageCreateInfo[]){
                  {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                   .stage = VK_SHADER_STAGE_VERTEX_BIT,
                   .module = vs,
                   .pName = "main"},
                  {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                   .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
                   .module = fs,
                   .pName = "main"}},
          .pVertexInputState =
              &(VkPipelineVertexInputStateCreateInfo){
                  .sType =
                      VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                  .vertexBindingDescriptionCount = 1,
                  .pVertexBindingDescriptions =
                      &(VkVertexInputBindingDescription){
                          .binding = 2,
                          .stride = sizeof(bp_shadow_vertex),
                          .inputRate = VK_VERTEX_INPUT_RATE_VERTEX},
                  .vertexAttributeDescriptionCount = 1,
                  .pVertexAttributeDescriptions =
                      &(VkVertexInputAttributeDescription){
                          .location = 0,
                          .binding = 2,
                          .format = VK_FORMAT_R32G32B32_SFLOAT,
                          .offset = 0}},
          .pInputAssemblyState =
              &(VkPipelineInputAssemblyStateCreateInfo){
                  .sType =
                      VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                  .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST},
          .pViewportState =
              &(VkPipelineViewportStateCreateInfo){
                  .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                  .viewportCount = 1,
                  .scissorCount = 1},
          .pRasterizationState =
              &(VkPipelineRasterizationStateCreateInfo){
                  .sType =
                      VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                  .polygonMode = VK_POLYGON_MODE_FILL,
                  .cullMode = VK_CULL_MODE_NONE,
                  .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE,
                  .lineWidth = 1.0f},
          .pMultisampleState =
              &(VkPipelineMultisampleStateCreateInfo){
                  .sType =
                      VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                  .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT},
          .pDepthStencilState =
              &(VkPipelineDepthStencilStateCreateInfo){
                  .sType =
                      VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
                  .depthTestEnable = VK_FALSE},
          .pColorBlendState =
              &(VkPipelineColorBlendStateCreateInfo){
                  .sType =
                      VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                  .logicOp = VK_LOGIC_OP_COPY,
                  .attachmentCount = 1,
                  .pAttachments =
                      &(VkPipelineColorBlendAttachmentState){
                          .blendEnable = VK_TRUE,
                          .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
                          .dstColorBlendFactor =
                              VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
                          .colorBlendOp = VK_BLEND_OP_ADD,
                          .srcAlphaBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
                          .dstAlphaBlendFactor =
                              VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
                          .alphaBlendOp = VK_BLEND_OP_ADD,
                          .colorWriteMask = VK_COLOR_COMPONENT_R_BIT |
                                            VK_COLOR_COMPONENT_G_BIT |
                                            VK_COLOR_COMPONENT_B_BIT |
                                            VK_COLOR_COMPONENT_A_BIT}},
          .pDynamicState =
              &(VkPipelineDynamicStateCreateInfo){
                  .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                  .dynamicStateCount = 2,
                  .pDynamicStates =
                      (VkDynamicState[]){VK_DYNAMIC_STATE_VIEWPORT,
                                         VK_DYNAMIC_STATE_SCISSOR}},
          .layout = layout,
          .renderPass = pass,
          .subpass = 0},
      NULL, &r->shadow_pipeline);
  vkDestroyShaderModule(ctx->device, fs, NULL);
  vkDestroyShaderModule(ctx->device, vs, NULL);
  if (made != VK_SUCCESS) {
    r->shadow_pipeline = VK_NULL_HANDLE;
    SDL_Log("Wyrm shadow band: pipeline refused (%d); snakes draw no shadow", made);
    return;
  }
  r->shadow_buffer = tdbuffer_create_stream(ctx,
      (VkDeviceSize)max_vertices * sizeof(bp_shadow_vertex),
      VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
  r->shadow_vertices = malloc((size_t)max_vertices * sizeof(bp_shadow_vertex));
  r->shadow_chunk_first = malloc((size_t)max_chunks * sizeof(int));
  if (!r->shadow_buffer || !r->shadow_vertices || !r->shadow_chunk_first) {
    SDL_Log("Wyrm shadow band: no memory; snakes draw no shadow");
    if (r->shadow_buffer) tdbuffer_destroy(ctx, r->shadow_buffer);
    free(r->shadow_vertices);
    free(r->shadow_chunk_first);
    vkDestroyPipeline(ctx->device, r->shadow_pipeline, NULL);
    r->shadow_pipeline = VK_NULL_HANDLE;
    r->shadow_buffer = NULL;
    r->shadow_vertices = NULL;
    r->shadow_chunk_first = NULL;
    return;
  }
  r->max_shadow_vertices = max_vertices;
  r->max_shadow_chunks = max_chunks;
}

int bp_renderer_shadow_chunk(bp_renderer* r) {
  if (r->shadow_pipeline == VK_NULL_HANDLE ||
      r->num_shadow_chunks >= r->max_shadow_chunks ||
      r->num_instances >= r->max_instances)
    return 0;
  int chunk = r->num_shadow_chunks++;
  r->shadow_chunk_first[chunk] = r->num_shadow_vertices;
  bp_renderer_push(r, &(bp_instance){{(float)chunk, 0, -1.0f, 0},
                                     {BP_SHADOW_MARK_U, 0, 0, 0},
                                     {0, 0, 0, 0}});
  return 1;
}

bp_shadow_vertex* bp_renderer_shadow_reserve(bp_renderer* r, int count) {
  if (r->shadow_pipeline == VK_NULL_HANDLE || r->num_shadow_chunks <= 0 ||
      r->num_shadow_vertices + count > r->max_shadow_vertices)
    return NULL;
  bp_shadow_vertex* v = r->shadow_vertices + r->num_shadow_vertices;
  r->num_shadow_vertices += count;
  return v;
}

void bp_renderer_clear_shadows(bp_renderer* r) {
  r->num_shadow_vertices = 0;
  r->num_shadow_chunks = 0;
}'''

DESTROY_OLD = r'''void bp_renderer_destroy(bp_renderer* r, tcontext* ctx) {
  free(r->instances);'''

DESTROY_NEW = r'''void bp_renderer_destroy(bp_renderer* r, tcontext* ctx) {
  if (r->shadow_pipeline != VK_NULL_HANDLE) {
    tdbuffer_destroy(ctx, r->shadow_buffer);
    vkDestroyPipeline(ctx->device, r->shadow_pipeline, NULL);
  }
  free(r->shadow_vertices);
  free(r->shadow_chunk_first);
  free(r->instances);'''

PAIRS = {
    "app/src/rendering/bp_renderer.h": [
        ("""  vec4s clip;
} bp_instance;""", """  vec4s clip;
} bp_instance;

/* Snake shadow band (OM, 2026-11-06; game/redraw.c air_band_*): screen
   position and the shadow's alpha there. */
typedef struct bp_shadow_vertex {
  float x, y, alpha;
} bp_shadow_vertex;

/* uv.x of the marker instance that places a piece of shadow in the bead
   stream (a black atlas sprite to every bead pass, alpha 0). */
#define BP_SHADOW_MARK_U 2.5f"""),
        ("""  int num_instances;
} bp_renderer;""", """  int num_instances;
  /* Snake shadow band (OM, 2026-11-06). */
  VkPipeline shadow_pipeline;
  tdbuffer* shadow_buffer;
  bp_shadow_vertex* shadow_vertices;
  int max_shadow_vertices;
  int num_shadow_vertices;
  int* shadow_chunk_first;
  int max_shadow_chunks;
  int num_shadow_chunks;
} bp_renderer;"""),
        ("""void bp_renderer_destroy(bp_renderer* r, tcontext* ctx);""",
         """void bp_renderer_destroy(bp_renderer* r, tcontext* ctx);
void bp_renderer_enable_shadows(bp_renderer* r, tcontext* ctx,
                                VkPipelineLayout layout, VkRenderPass pass,
                                int max_vertices, int max_chunks);
/* Opens a piece of shadow at this point of the bead stream; 0 when full. */
int bp_renderer_shadow_chunk(bp_renderer* r);
/* Room for `count` vertices in the open piece, or NULL. */
bp_shadow_vertex* bp_renderer_shadow_reserve(bp_renderer* r, int count);
void bp_renderer_clear_shadows(bp_renderer* r);"""),
    ],
    "app/src/rendering/bp_renderer.c": [
        ("""  r->num_instances = 0;

  return r;
}""", """  r->num_instances = 0;
  r->shadow_pipeline = VK_NULL_HANDLE;
  r->shadow_buffer = NULL;
  r->shadow_vertices = NULL;
  r->max_shadow_vertices = 0;
  r->num_shadow_vertices = 0;
  r->shadow_chunk_first = NULL;
  r->max_shadow_chunks = 0;
  r->num_shadow_chunks = 0;

  return r;
}"""),
        (RENDER_OLD, RENDER_NEW),
        (DESTROY_OLD, DESTROY_NEW),
    ],
    "app/src/rendering/renderer.c": [
        ("""  r->bpr = bp_renderer_create(ctx, MAX_SPRITE_INSTANCES, r->pipeline_layout, r->render_pass);""",
         """  r->bpr = bp_renderer_create(ctx, MAX_SPRITE_INSTANCES, r->pipeline_layout, r->render_pass);
  /* Snake shadow band (OM, 2026-11-06): 108 vertices a body segment, 432 a
     round end; room for about 4,800 segments on screen. */
  bp_renderer_enable_shadows(r->bpr, ctx, r->pipeline_layout, r->render_pass,
                             1 << 19, 4096);"""),
        ("""  r->bpr->num_instances = 0;""", """  r->bpr->num_instances = 0;
  bp_renderer_clear_shadows(r->bpr);"""),
    ],
    "thermite/src/platform/tassets.c": [
        ("""    "shaders/bin/sprv.spv",""", """    "shaders/bin/sprv.spv",
    "shaders/bin/shf.spv",
    "shaders/bin/shv.spv","""),
    ],
    "app/src/game/redraw.c": [
        (ENDS_OLD, ENDS_NEW),
    ],
}


def apply(root, label="snake shadow band 2026-11-06", skip_applied=False):
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


def revert(root, label="snake shadow band 2026-11-06"):
    """Takes this pass back out of a tree (for checks of earlier passes)."""
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for old, new in reversed(pairs):
            if text.count(new) != 1:
                raise SystemExit(f"{label}: revert x{text.count(new)} in {relative}: {new[:80]!r}")
            text = text.replace(new, old)
        path.write_text(text, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
