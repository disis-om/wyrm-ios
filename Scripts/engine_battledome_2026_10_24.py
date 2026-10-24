"""Battledome texts and dome (OM, 2026-10-24).

The Battledome network's servers spell their words in pellets (one per pixel of
a 5 x 7 font, `cell` apart, size byte = dot * 5) and publish the layout and the
dome in a public live.json. network/battledome.c (copied from SharedEngine)
fetches it only on that network's eight servers; redraw.c skips the letter
pellets in the food loops and draws them, joined by straight strokes, on a new
alpha-blended food layer (fd_renderer_push_t) after the food and before the
snakes, plus the green dome ring. Byte 7 of the operator's /live stream does not
exist in the /slither game stream, so the pellets are found by the text grid.

Same text as Wyrm Android's tree (applied there by hand first; this script
sees it applied and leaves it). Applied by prepare-original-engine.py to the
generated iOS tree.
"""
import sys
from pathlib import Path

HELPERS = "/* Battledome letters (OM, 2026-10-24; network/battledome.h). The server\n * spells its words with one pellet per pixel of a 5 x 7 font, `cell` apart.\n * Shown as pixels they read as loose dots, so each pixel is joined to its\n * neighbours by a straight stroke, like the font's own lines: across, down\n * and diagonally, but a diagonal only where no pixel already turns that\n * corner (else an L or a box would get a needless slash). The ring words are\n * turned, so neighbours are found by distance, never by a fixed grid. */\ntypedef struct bd_px {\n  float x, y, cell;\n  vec3s c;\n  float a;\n} bd_px;\n\n#define BD_MAX_PX 6144\nstatic bd_px bd_pxs[BD_MAX_PX];\n\nstatic int bd_px_cmp(const void* a, const void* b) {\n  float d = ((const bd_px*)a)->x - ((const bd_px*)b)->x;\n  return (d > 0) - (d < 0);\n}\n\n/* Whether a letter pixel of this cell size sits at world (x, y). The list is\n   sorted by x. */\nstatic bool bd_px_at(int n, float x, float y, float cell) {\n  float tol = cell * 0.3f;\n  int lo = 0, hi = n;\n  while (lo < hi) {\n    int mid = (lo + hi) / 2;\n    if (bd_pxs[mid].x < x - tol) lo = mid + 1;\n    else hi = mid;\n  }\n  for (int i = lo; i < n && bd_pxs[i].x <= x + tol; i++)\n    if (fabsf(bd_pxs[i].y - y) <= tol && fabsf(bd_pxs[i].cell - cell) < 0.5f)\n      return true;\n  return false;\n}\n\nstatic void bd_dot(fd_renderer* fdr, float sx, float sy, float w, vec3s c,\n                   float a) {\n  /* fd.slang fills 0.9 of the quad. */\n  float z = w / 0.9f;\n  fd_renderer_push_t(fdr, &(fd_instance){{sx - z * 0.5f, sy - z * 0.5f, z},\n                                         (vec4s){c.r, c.g, c.b, a / 0.7f},\n                                         0.0f, 0.0f});\n}\n\n/* A round-capped line as a row of dots close enough to read as one. */\nstatic void bd_line(fd_renderer* fdr, float ax, float ay, float bx, float by,\n                    float w, vec3s c, float a) {\n  float len = hypotf(bx - ax, by - ay);\n  int n = (int)ceilf(len / fmaxf(1.0f, w * 0.25f));\n  if (n > 256) n = 256;\n  for (int k = 1; k < n; k++) {\n    float f = (float)k / (float)n;\n    bd_dot(fdr, ax + (bx - ax) * f, ay + (by - ay) * f, w, c, a);\n  }\n}\n\nstatic void draw_battledome(tenv* env, float mww2, float mhh2) {\n  tuser_data* usr = env->usr;\n  game_data* gdata = &usr->gdata;\n  fd_renderer* fdr = usr->r->fdr;\n  float gsc = gdata->data.gsc;\n\n  int n = 0;\n  int foods_len = tdarray_length(gdata->data.foods);\n  for (int i = 0; i < foods_len && n < BD_MAX_PX; i++) {\n    food* fo = gdata->data.foods + i;\n    float cell;\n    bool square;\n    if (fo->eaten ||\n        !battledome_text_pixel(fo->xx, fo->yy, fo->sz, &cell, &square))\n      continue;\n    /* A cell beyond the food margin, so a stroke into the edge still draws. */\n    if (fo->xx < gdata->data.fpx1 - 2 * cell || fo->yy < gdata->data.fpy1 - 2 * cell ||\n        fo->xx > gdata->data.fpx2 + 2 * cell || fo->yy > gdata->data.fpy2 + 2 * cell)\n      continue;\n    bd_pxs[n++] = (bd_px){fo->xx, fo->yy, cell, gdata->cg_colors[fo->cv], fo->fr};\n  }\n  if (n > 1) qsort(bd_pxs, (size_t)n, sizeof(bd_px), bd_px_cmp);\n\n  for (int i = 0; i < n; i++) {\n    bd_px* p = bd_pxs + i;\n    float w = p->cell * 0.62f * gsc;\n    float sx = mww2 + gsc * (p->x - gdata->data.view_xx);\n    float sy = mhh2 + gsc * (p->y - gdata->data.view_yy);\n    bd_dot(fdr, sx, sy, w, p->c, p->a);\n\n    /* Each pair once: only neighbours further along x (or level, below). */\n    for (int j = i + 1; j < n && bd_pxs[j].x - p->x <= p->cell * 1.6f; j++) {\n      bd_px* q = bd_pxs + j;\n      if (fabsf(q->cell - p->cell) >= 0.5f) continue;\n      float dx = q->x - p->x, dy = q->y - p->y;\n      float d = sqrtf(dx * dx + dy * dy) / p->cell;\n      bool straight = fabsf(d - 1.0f) <= 0.2f;\n      bool diagonal = fabsf(d - 1.41421f) <= 0.2f;\n      if (!straight && !diagonal) continue;\n      if (diagonal) {\n        /* The two corner pixels between them, in the text's own (maybe\n           turned) grid: d = u + v with u, v one cell and at right angles. */\n        float ux = (dx + dy) * 0.5f, uy = (dy - dx) * 0.5f;\n        if (bd_px_at(n, p->x + ux, p->y + uy, p->cell) ||\n            bd_px_at(n, p->x + dx - ux, p->y + dy - uy, p->cell))\n          continue;\n      }\n      float qx = mww2 + gsc * (q->x - gdata->data.view_xx);\n      float qy = mhh2 + gsc * (q->y - gdata->data.view_yy);\n      bd_line(fdr, sx, sy, qx, qy, w, p->c, fminf(p->a, q->a));\n    }\n  }\n\n  /* The dome: a green ring of the server's radius round the middle, as the\n     server's own live view draws it, only where it is on screen. */\n  float dome_x, dome_y, dome_r;\n  if (battledome_dome(&dome_x, &dome_y, &dome_r)) {\n    float sx = mww2 + gsc * (dome_x - gdata->data.view_xx);\n    float sy = mhh2 + gsc * (dome_y - gdata->data.view_yy);\n    float rr = dome_r * gsc;\n    float half = sqrtf(mww2 * mww2 + mhh2 * mhh2);\n    float dist = hypotf(sx - mww2, sy - mhh2);\n    if (rr > 1 && dist + half > rr && dist - half < rr) {\n      float unit = fminf(mww2, mhh2) * 2.0f / 480.0f;\n      float w = fmaxf(3.0f, 2.5f * unit);\n      int steps = (int)fminf(20000.0f, 2 * PI * rr / (w * 0.4f));\n      vec3s green = {0.0f, 1.0f, 0.0f};\n      for (int k = 0; k < steps; k++) {\n        float a = 2 * PI * (float)k / (float)steps;\n        float px = sx + cosf(a) * rr, py = sy + sinf(a) * rr;\n        if (px < -w || py < -w || px > 2 * mww2 + w || py > 2 * mhh2 + w)\n          continue;\n        bd_dot(fdr, px, py, w, green, 1.0f);\n      }\n    }\n  }\n}\n\n"

PIPE = '\n  /* The same food shaders with plain alpha blending, for the Battledome\n     letters (fd_renderer_push_t): food adds light, so two overlapping dots\n     of a stroke would show a brighter seam. */\n  vkCreateGraphicsPipelines(\n      ctx->device, NULL, 1,\n      &(VkGraphicsPipelineCreateInfo){\n          .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,\n          .pNext = NULL,\n          .flags = 0,\n          .stageCount = 2,\n          .pStages =\n              (VkPipelineShaderStageCreateInfo[]){\n                  {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,\n                   .pNext = NULL,\n                   .flags = 0,\n                   .stage = VK_SHADER_STAGE_VERTEX_BIT,\n                   .module = vertex_shader,\n                   .pName = "main",\n                   .pSpecializationInfo = NULL},\n                  {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,\n                   .pNext = NULL,\n                   .flags = 0,\n                   .stage = VK_SHADER_STAGE_FRAGMENT_BIT,\n                   .module = fragment_shader,\n                   .pName = "main",\n                   .pSpecializationInfo = NULL}},\n          .pVertexInputState =\n              &(VkPipelineVertexInputStateCreateInfo){\n                  .sType =\n                      VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,\n                  .pNext = NULL,\n                  .flags = 0,\n                  .vertexBindingDescriptionCount = 2,\n                  .pVertexBindingDescriptions =\n                      (VkVertexInputBindingDescription[]){\n                          {.binding = 0,\n                           .stride = 2 * sizeof(float),\n                           .inputRate = VK_VERTEX_INPUT_RATE_VERTEX},\n                          {.binding = 1,\n                           .stride = sizeof(fd_instance),\n                           .inputRate = VK_VERTEX_INPUT_RATE_INSTANCE},\n                      },\n                  .vertexAttributeDescriptionCount = 5,\n                  .pVertexAttributeDescriptions =\n                      (VkVertexInputAttributeDescription[]){\n                          {.location = 0,\n                           .binding = 0,\n                           .format = VK_FORMAT_R32G32_SFLOAT,\n                           .offset = 0},\n                          {.location = 1,\n                           .binding = 1,\n                           .format = VK_FORMAT_R32G32B32_SFLOAT,\n                           .offset = 0},\n                          {.location = 2,\n                           .binding = 1,\n                           .format = VK_FORMAT_R32G32B32A32_SFLOAT,\n                           .offset = offsetof(fd_instance, color)},\n                          {.location = 3,\n                           .binding = 1,\n                           .format = VK_FORMAT_R32_SFLOAT,\n                           .offset = offsetof(fd_instance, flicker)},\n                          {.location = 4,\n                           .binding = 1,\n                           .format = VK_FORMAT_R32_SFLOAT,\n                           .offset = offsetof(fd_instance, shape)}}},\n          .pInputAssemblyState =\n              &(VkPipelineInputAssemblyStateCreateInfo){\n                  .sType =\n                      VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,\n                  .pNext = NULL,\n                  .flags = 0,\n                  .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,\n                  .primitiveRestartEnable = VK_FALSE},\n          .pTessellationState = NULL,\n          .pViewportState =\n              &(VkPipelineViewportStateCreateInfo){\n                  .sType =\n                      VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,\n                  .pNext = NULL,\n                  .flags = 0,\n                  .viewportCount = 1,\n                  .scissorCount = 1},\n          .pRasterizationState =\n              &(VkPipelineRasterizationStateCreateInfo){\n                  .sType =\n                      VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,\n                  .pNext = NULL,\n                  .flags = 0,\n                  .depthClampEnable = VK_FALSE,\n                  .rasterizerDiscardEnable = VK_FALSE,\n                  .polygonMode = VK_POLYGON_MODE_FILL,\n                  .cullMode = VK_CULL_MODE_NONE,\n                  .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE,\n                  .depthBiasEnable = VK_FALSE,\n                  .depthBiasConstantFactor = 0.0f,\n                  .depthBiasClamp = 0.0f,\n                  .depthBiasSlopeFactor = 0.0f,\n                  .lineWidth = 1.0f},\n          .pMultisampleState =\n              &(VkPipelineMultisampleStateCreateInfo){\n                  .sType =\n                      VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,\n                  .pNext = NULL,\n                  .flags = 0,\n                  .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,\n                  .sampleShadingEnable = VK_FALSE,\n                  .minSampleShading = 0.0f,\n                  .pSampleMask = NULL,\n                  .alphaToCoverageEnable = VK_FALSE,\n                  .alphaToOneEnable = VK_FALSE},\n          .pDepthStencilState =\n              &(VkPipelineDepthStencilStateCreateInfo){\n                  .sType =\n                      VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,\n                  .pNext = NULL,\n                  .flags = 0,\n                  .depthTestEnable = VK_FALSE,\n              },\n          .pColorBlendState =\n              &(VkPipelineColorBlendStateCreateInfo){\n                  .sType =\n                      VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,\n                  .pNext = NULL,\n                  .flags = 0,\n                  .logicOpEnable = VK_FALSE,\n                  .logicOp = VK_LOGIC_OP_COPY,\n                  .attachmentCount = 1,\n                  .pAttachments =\n                      &(VkPipelineColorBlendAttachmentState){\n                          .blendEnable = VK_TRUE,\n                          .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,\n                          .dstColorBlendFactor =\n                              VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,\n                          .colorBlendOp = VK_BLEND_OP_ADD,\n                          .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,\n                          .dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO,\n                          .alphaBlendOp = VK_BLEND_OP_ADD,\n                          .colorWriteMask = VK_COLOR_COMPONENT_R_BIT |\n                                            VK_COLOR_COMPONENT_G_BIT |\n                                            VK_COLOR_COMPONENT_B_BIT |\n                                            VK_COLOR_COMPONENT_A_BIT},\n                  .blendConstants = {0.0f, 0.0f, 0.0f, 0.0f}},\n          .pDynamicState =\n              &(VkPipelineDynamicStateCreateInfo){\n                  .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,\n                  .pNext = NULL,\n                  .flags = 0,\n                  .dynamicStateCount = 2,\n                  .pDynamicStates =\n                      (VkDynamicState[]){VK_DYNAMIC_STATE_VIEWPORT,\n                                         VK_DYNAMIC_STATE_SCISSOR}},\n          .layout = layout,\n          .renderPass = pass,\n          .subpass = 0,\n          .basePipelineHandle = VK_NULL_HANDLE,\n          .basePipelineIndex = 0},\n      NULL, &r->pipelines[2]);\n'


SKIP_OLD = """      food* fo = gdata->data.foods + i;

      if (usrs->hotkeys[HOTKEY_BIG_FOOD].active && fo->sz < 10) continue;"""
SKIP_NEW = """      food* fo = gdata->data.foods + i;

      if (battledome_text_pixel(fo->xx, fo->yy, fo->sz, &bd_cell, &bd_square))
        continue;
      if (usrs->hotkeys[HOTKEY_BIG_FOOD].active && fo->sz < 10) continue;"""
SCALE = "  float food_scale = mode->const_food_scale ? 1.0f : gdata->data.gsc;\n"
PREY = "  for (int i = preys_len - 1; i >= 0; i--) {"
CALL = ("  /* Battledome letters and dome: their own layer, drawn after the food\n"
        "     (so above it) and before the snakes. */\n"
        "  draw_battledome(env, mww2, mhh2);\n\n")


def _edit(path, change, label):
    raw = path.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")
    new = change(text, f"{label} {path.name}")
    if new == text:
        return
    if crlf:
        new = new.replace("\n", "\r\n")
    path.write_bytes(new.encode("utf-8"))


def _once(text, old, new, label, count=1):
    if text.count(old) != count:
        raise SystemExit(f"{label}: anchor x{text.count(old)}: {old[:60]!r}")
    return text.replace(old, new)


def _redraw(text, label):
    if "draw_battledome(env, mww2, mhh2);" in text:
        return text
    text = _once(text, '#include "tags.h"\n',
                 '#include "tags.h"\n#include "../network/battledome.h"\n', label)
    text = _once(text, SCALE, SCALE + "  float bd_cell = 0;\n  bool bd_square = false;\n", label)
    text = _once(text, SKIP_OLD, SKIP_NEW, label, 2)
    text = _once(text, PREY, CALL + PREY, label)
    text = _once(text, "void redraw(tenv* env) {", HELPERS + "void redraw(tenv* env) {", label)
    return text


def _loop(text, label):
    if "battledome_tick(env);" in text:
        return text
    text = _once(text, '#include "../network/ntl_net.h"\n',
                 '#include "../network/ntl_net.h"\n#include "../network/battledome.h"\n', label)
    text = _once(text, "      ntl_net_tick(env);\n      server_poll(env);\n",
                 "      ntl_net_tick(env);\n      battledome_tick(env);\n      server_poll(env);\n", label)
    text = _once(text, "      ntl_net_close(env);\n      usr->r->global.bg_opacity = 0;\n",
                 "      ntl_net_close(env);\n      battledome_close(env);\n"
                 "      usr->r->global.bg_opacity = 0;\n", label)
    return text


def _fd_h(text, label):
    if "fd_renderer_push_t" in text:
        return text
    text = _once(text, "  VkPipeline pipelines[2];\n", "  VkPipeline pipelines[3];\n", label)
    text = _once(text, "  fd_instance* p_instances;\n",
                 "  fd_instance* p_instances;\n"
                 "  /* Battledome letters and dome (OM, 2026-10-24): drawn last, with plain\n"
                 "     alpha blending, so overlapping stroke dots stay one even colour. */\n"
                 "  tdbuffer* t_instance_buffer;\n  fd_instance* t_instances;\n"
                 "  int max_t_instances;\n  int num_t_instances;\n", label)
    text = _once(text, "void fd_renderer_push_p(fd_renderer* r, const fd_instance* instance);\n",
                 "void fd_renderer_push_p(fd_renderer* r, const fd_instance* instance);\n"
                 "void fd_renderer_push_t(fd_renderer* r, const fd_instance* instance);\n", label)
    return text


def _fd_c(text, label):
    if "fd_renderer_push_t" in text:
        return text
    end = "      NULL, &r->pipelines[0]);\n"
    text = _once(text, end, end + PIPE, label)
    text = _once(text, "#include <string.h>\n",
                 "#include <string.h>\n\n/* Battledome letter strokes and dome dots, per frame. */\n"
                 "#define FD_MAX_T_INSTANCES 65536\n", label)
    text = _once(text, "  r->num_p_instances = 0;\n\n  return r;\n",
                 "  r->num_p_instances = 0;\n\n"
                 "  r->max_t_instances = FD_MAX_T_INSTANCES;\n"
                 "  r->t_instance_buffer =\n"
                 "      tdbuffer_create(ctx, NULL, r->max_t_instances * sizeof(fd_instance),\n"
                 "                      VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);\n"
                 "  r->t_instances = malloc(r->max_t_instances * sizeof(fd_instance));\n"
                 "  r->num_t_instances = 0;\n\n  return r;\n", label)
    text = _once(text, "void fd_renderer_render(fd_renderer* r, tcontext* ctx) {\n",
                 "void fd_renderer_push_t(fd_renderer* r, const fd_instance* instance) {\n"
                 "  if (r->num_t_instances >= r->max_t_instances) {\n    return;\n  }\n"
                 "  r->t_instances[r->num_t_instances++] = *instance;\n}\n\n"
                 "void fd_renderer_render(fd_renderer* r, tcontext* ctx) {\n", label)
    text = _once(text, "  vkCmdDraw(fr->cmd, 4, r->num_p_instances, 0, 0);\n}\n",
                 "  vkCmdDraw(fr->cmd, 4, r->num_p_instances, 0, 0);\n\n"
                 "  if (r->num_t_instances > 0) {\n"
                 "    memcpy(r->t_instance_buffer[ctx->current_frame].data, r->t_instances,\n"
                 "           r->num_t_instances * sizeof(fd_instance));\n"
                 "    vkCmdBindPipeline(fr->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,\n"
                 "                      r->pipelines[2]);\n"
                 "    vkCmdBindVertexBuffers(fr->cmd, 1, 1,\n"
                 "                           &r->t_instance_buffer[ctx->current_frame].handle,\n"
                 "                           (VkDeviceSize[]){0});\n"
                 "    vkCmdDraw(fr->cmd, 4, r->num_t_instances, 0, 0);\n  }\n}\n", label)
    text = _once(text, "void fd_renderer_destroy(fd_renderer* r, tcontext* ctx) {\n",
                 "void fd_renderer_destroy(fd_renderer* r, tcontext* ctx) {\n"
                 "  free(r->t_instances);\n  tdbuffer_destroy(ctx, r->t_instance_buffer);\n"
                 "  vkDestroyPipeline(ctx->device, r->pipelines[2], NULL);\n\n", label)
    return text


def _renderer(text, label):
    if "num_t_instances = 0;" in text:
        return text
    return _once(text, "  r->fdr->num_p_instances = 0;\n",
                 "  r->fdr->num_p_instances = 0;\n  r->fdr->num_t_instances = 0;\n", label)


def apply(root, label="engine battledome 2026-10-24"):
    src = Path(root) / "app" / "src"
    for name in ("network/battledome.c", "network/battledome.h"):
        if not (src / name).exists():
            raise SystemExit(f"{label}: missing {name}")
    _edit(src / "game" / "redraw.c", _redraw, label)
    _edit(src / "game" / "loop.c", _loop, label)
    _edit(src / "rendering" / "fd_renderer.h", _fd_h, label)
    _edit(src / "rendering" / "fd_renderer.c", _fd_c, label)
    _edit(src / "rendering" / "renderer.c", _renderer, label)


if __name__ == "__main__":
    apply(Path(sys.argv[1]) if len(sys.argv) > 1 else Path("."))
