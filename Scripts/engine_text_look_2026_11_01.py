"""The original's glyph sheet drawn the way the original draws it (OM, 2026-11-01).

Moto 8.5.4: every sheet text looked faded and its black outline too thick at
small sizes, and the PNG text stayed bright while the death fade darkened the
rest of the screen.

1. original_art.png is straight alpha with black under every clear pixel. Its
   GPU mip levels averaged the white faces with that black, so a shrunk glyph
   greyed and its outline grew. Stage3D (the original) keeps textures
   premultiplied: the atlas is premultiplied once when it loads (the PNG stays
   byte-identical) and every ospr pipeline blends premultiplied.
2. Wyrm-mode snake names follow Main.as: face in the snake's csw colour
   (0.5 + 0.64 c) at the name's alpha, outline at 0.75 of it, both NORMAL,
   every outline before every face. They no longer turn dark on light floors.
3. The overlay text is drawn after ImGui, so the death veil never covered it:
   it now takes the veil's darkening (wyrm_sheet_veil, set in main.c).
4. Stats ping value is the number alone: "PING(ms)  264".

The same text goes into Wyrm Android's tree (run once:
`python engine_text_look_2026_11_01.py "<Wyrm Android>"`) and into the
prepared Apple tree (prepare-original-engine.py). Every anchor must occur once.
"""
from pathlib import Path
import sys

PAIRS = {}


def add(path, old, new, optional=False, stage=1):
    PAIRS.setdefault('app/src/' + path, []).append((old, new, optional, stage))


# ---- 1. premultiplied atlas + blending ----
add('rendering/texture.c',
    '  /* The game atlas is mipmapped too since 2026-10-18 (renderer.c\n',
    '  /* The original\'s baked art (OM, 2026-11-01): Stage3D keeps textures\n'
    '     premultiplied, so its mip levels average colour by coverage. The PNG\n'
    '     is straight alpha with black under every clear pixel: mipped as it\n'
    '     is, a glyph\'s white face greys and its outline grows as it shrinks.\n'
    '     Premultiply once here; the ospr pipelines blend that way. */\n'
    '  const bool premultiply = strstr(filename, "original_art") != NULL;\n'
    '  if (premultiply && !using_fallback) {\n'
    '    const size_t count = (size_t)w * (size_t)h;\n'
    '    for (size_t i = 0; i < count; ++i) {\n'
    '      unsigned a = data[i * 4 + 3];\n'
    '      for (int k = 0; k < 3; ++k)\n'
    '        data[i * 4 + k] = (stbi_uc)((data[i * 4 + k] * a + 127) / 255);\n'
    '    }\n'
    '  }\n'
    '  /* The game atlas is mipmapped too since 2026-10-18 (renderer.c\n')
add('rendering/texture.c',
    '  if (wants_mips && mip_levels == 1 && !using_fallback && (cpu_floor || cpu_atlas)) {\n',
    '  /* Mali: the sheet gets its chain from the CPU as well (premultiplied). */\n'
    '  const bool cpu_art = premultiply &&\n'
    '                       (uint64_t)w * (uint64_t)h <= TEXTURE_CPU_MIP_MAX_PIXELS;\n'
    '  if (wants_mips && mip_levels == 1 && !using_fallback &&\n'
    '      (cpu_floor || cpu_atlas || cpu_art)) {\n',
    optional=True)  # Apple's tree has no CPU chain: its GPUs blit
add('rendering/spr_renderer.c',
    '                          .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,\n'
    '                          .dstColorBlendFactor =\n'
    '                              additive ? VK_BLEND_FACTOR_ONE : VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,\n'
    '                          .colorBlendOp = VK_BLEND_OP_ADD,\n'
    '                          .srcAlphaBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,\n',
    '                          /* The original\'s art is premultiplied (texture.c,\n'
    '                             OM 2026-11-01); its tints are pushed that way. */\n'
    '                          .srcColorBlendFactor = original ? VK_BLEND_FACTOR_ONE : VK_BLEND_FACTOR_SRC_ALPHA,\n'
    '                          .dstColorBlendFactor =\n'
    '                              additive ? VK_BLEND_FACTOR_ONE : VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,\n'
    '                          .colorBlendOp = VK_BLEND_OP_ADD,\n'
    '                          .srcAlphaBlendFactor = original ? VK_BLEND_FACTOR_ONE : VK_BLEND_FACTOR_SRC_ALPHA,\n')
add('game/original_art.h',
    '      {{rect[0]/2048, rect[1]/2048, rect[2]/2048, rect[3]/2048}}, colour});\n',
    '      {{rect[0]/2048, rect[1]/2048, rect[2]/2048, rect[3]/2048}},\n'
    '      /* Premultiplied (texture.c, OM 2026-11-01). */\n'
    '      (vec4s){{colour.r*colour.a, colour.g*colour.a, colour.b*colour.a, colour.a}}});\n')

# ---- 2 + 3. sheet text: premultiplied, the veil, names the original way ----
add('game/sheet_text.h',
    'extern spr_renderer *wyrm_text_normal, *wyrm_text_add;\n',
    'extern spr_renderer *wyrm_text_normal, *wyrm_text_add;\n'
    '/* The death fade\'s darkening (main.c): this text is drawn after ImGui,\n'
    '   so the veil never covers it. 1 = none. */\n'
    'extern float wyrm_sheet_veil;\n')
add('game/sheet_text.h',
    '''/* Cull a whole glyph at clipping edges: sprite batches have no ImGui scissor.
   Test the union of both layers so an edge never loses only its outline. */
static inline void sheet_layer(ImDrawList* draw, const char* text, float size,
                               ImVec2 pos, ImU32 colour, int font, int layer) {
  (void)layer; /* Kept for existing callers: every call is now the real pair. */
  if (!draw || !sheet_ok(text) || !(colour & 0xFF000000u)) return;
  ImVec2 lo, hi;
  ImDrawList_GetClipRectMin(&lo, draw);
  ImDrawList_GetClipRectMax(&hi, draw);
  float scale = size * SHEET_EM / 52.0f;
  float top = pos.y + size * SHEET_DROP, pen = 0;
  vec4s tint = {{(colour & 255)/255.0f, ((colour >> 8)&255)/255.0f,
                ((colour >> 16)&255)/255.0f, (colour >> 24)/255.0f}};
  for (const unsigned char* p = (const unsigned char*)text; *p; ++p) {
    const original_glyph* face = &ORIGINAL_GLYPHS[font + (*p - 32)*3];
    bool visible = true;
    for (int pass = 0; pass < 2; ++pass) {
      const original_glyph* g = face + (pass == 0 ? 1 : 0);
      float s = scale * g->scale;
      float x = pos.x + pen - g->px*s, y = top - g->py*s;
      if (g->w > 1 && (x < lo.x || y < lo.y || x+g->w*s > hi.x || y+g->h*s > hi.y))
        visible = false;
    }
    if (visible) for (int pass = 0; pass < 2; ++pass) {
      const original_glyph* g = face + (pass == 0 ? 1 : 0);
      float s = scale*g->scale;
      if (g->w <= 1) continue;
      float x = pos.x + pen - g->px*s, y = top - g->py*s;
      spr_renderer_push(pass == 0 ? wyrm_text_normal : wyrm_text_add,
          &(spr_instance){
          {{x+g->w*s*.5f, y+g->h*s*.5f, g->w*s, g->h*s}},
          {{g->x/2048.0f, g->y/2048.0f, g->w/2048.0f, g->h/2048.0f}}, tint});
    }
    pen += face->advance*scale;
  }
}
''',
    '''/* Cull a whole glyph at clipping edges: sprite batches have no ImGui scissor.
   Test the union of both layers so an edge never loses only its outline.
   Main.as drawText order: every outline (ochars) first, then every face, so
   a face is never covered by the next letter's outline. `outline` scales the
   outline's alpha; `face_add` puts the faces in the ADD batch (leaderboard,
   HUD) or the NORMAL one (names: face alpha, outline 0.75 of it). Tints are
   premultiplied, the atlas too (texture.c). */
static inline void sheet_draw(ImDrawList* draw, const char* text, float size,
                              ImVec2 pos, ImU32 colour, int font,
                              float outline, bool face_add) {
  if (!draw || !sheet_ok(text) || !(colour & 0xFF000000u)) return;
  ImVec2 lo, hi;
  ImDrawList_GetClipRectMin(&lo, draw);
  ImDrawList_GetClipRectMax(&hi, draw);
  float scale = size * SHEET_EM / 52.0f;
  float top = pos.y + size * SHEET_DROP;
  float alpha = (colour >> 24)/255.0f;
  float veil = wyrm_sheet_veil < 0 ? 0 : wyrm_sheet_veil > 1 ? 1 : wyrm_sheet_veil;
  vec3s rgb = {{(colour & 255)/255.0f, ((colour >> 8)&255)/255.0f,
               ((colour >> 16)&255)/255.0f}};
  for (int pass = 0; pass < 2; ++pass) {
    float a = pass == 0 ? alpha*outline : alpha;
    if (a <= 0.0f) continue;
    /* The veil darkens what is under it and keeps its coverage. */
    vec4s tint = {{rgb.r*a*veil, rgb.g*a*veil, rgb.b*a*veil, a}};
    spr_renderer* batch = pass == 0 || !face_add ? wyrm_text_normal : wyrm_text_add;
    float pen = 0;
    for (const unsigned char* p = (const unsigned char*)text; *p; ++p) {
      const original_glyph* face = &ORIGINAL_GLYPHS[font + (*p - 32)*3];
      bool visible = true;
      for (int layer = 0; layer < 2; ++layer) {
        const original_glyph* g = face + (layer == 0 ? 1 : 0);
        float s = scale * g->scale;
        float x = pos.x + pen - g->px*s, y = top - g->py*s;
        if (g->w > 1 && (x < lo.x || y < lo.y || x+g->w*s > hi.x || y+g->h*s > hi.y))
          visible = false;
      }
      const original_glyph* g = face + (pass == 0 ? 1 : 0);
      if (visible && g->w > 1) {
        float s = scale*g->scale;
        float x = pos.x + pen - g->px*s, y = top - g->py*s;
        spr_renderer_push(batch, &(spr_instance){
            {{x+g->w*s*.5f, y+g->h*s*.5f, g->w*s, g->h*s}},
            {{g->x/2048.0f, g->y/2048.0f, g->w/2048.0f, g->h/2048.0f}}, tint});
      }
      pen += face->advance*scale;
    }
  }
}

static inline void sheet_layer(ImDrawList* draw, const char* text, float size,
                               ImVec2 pos, ImU32 colour, int font, int layer) {
  (void)layer; /* Kept for existing callers: every call is now the real pair. */
  sheet_draw(draw, text, size, pos, colour, font, 1.0f, true);
}
''')

add('rendering/renderer.c', 'spr_renderer *wyrm_text_normal = NULL, *wyrm_text_add = NULL;\n',
    'spr_renderer *wyrm_text_normal = NULL, *wyrm_text_add = NULL;\n'
    'float wyrm_sheet_veil = 1.0f;\n')
add('main.c',
    '  ui_theme_transition_begin(env);\n  switch (usr->gdata.curr_screen) {\n',
    '  ui_theme_transition_begin(env);\n'
    '  /* The death fade (below) also darkens the sheet text, drawn after\n'
    '     ImGui (OM, 2026-11-01). */\n'
    '  wyrm_sheet_veil = usr->gdata.curr_screen == PLAYING && android_home_death_pending()\n'
    '                        ? android_home_death_opacity() : 1.0f;\n'
    '  switch (usr->gdata.curr_screen) {\n')
add('main.c', '#include "user.h"\n',
    '#include "user.h"\n'
    'extern float wyrm_sheet_veil; /* rendering/renderer.c */\n')

add('game/redraw.c',
    '''              float shown = usrs->snake_scores ? tsize.x : nsize.x;
              float sx = ntx + (shown - sheet_width(label, size, SHEET_THIN)) * 0.5f;
              sheet_layer(name_draw_list, label, size, (ImVec2){sx, nty}, name_ink,
                          SHEET_THIN, 0);
''',
    '''              float shown = usrs->snake_scores ? tsize.x : nsize.x;
              float sx = ntx + (shown - sheet_width(label, size, SHEET_THIN)) * 0.5f;
              /* Main.as names (OM, 2026-11-01): csw = 0.5 + 0.64 c, face at
                 the name's alpha, outline 0.75 of it, both NORMAL. Not the
                 floor's dark ink: that read dark and muddy on light floors. */
              ImU32 sheet_ink = name_ink;
              if (o->id == gdata->data.snake_id ||
                  !android_team_is_teammate(env, o->ntl_id, o->nk)) {
                ImVec4 csw = {fminf(1, fmaxf(0, roundf(127.5f + scolor->r*255*.64f)/255)),
                              fminf(1, fmaxf(0, roundf(127.5f + scolor->g*255*.64f)/255)),
                              fminf(1, fmaxf(0, roundf(127.5f + scolor->b*255*.64f)/255)), a};
                sheet_ink = igColorConvertFloat4ToU32(csw);
              }
              sheet_draw(name_draw_list, label, size, (ImVec2){sx, nty}, sheet_ink,
                         SHEET_THIN, 0.75f, false);
''')

# ---- 4. ping value without the unit (OM: the label carries it) ----
add('game/ui_overlay.c',
    '    snprintf(ping_text, sizeof(ping_text), "%d(ms)", gdata->data.ping);\n',
    '    snprintf(ping_text, sizeof(ping_text), "%d", gdata->data.ping);\n')
add('game/ui_overlay.c',
    '      /* Ping in brackets (OM, 2026-11-01): "PING(ms)  64(ms)". */\n',
    '      /* The unit on the label only (OM, 2026-11-01): "PING(ms)  64". */\n')


# ---- 5. Classic steering: the assist laser turns with the finger ----
add('mobile/mobile_controls.h',
    'int mobile_controls_steering_mode(tenv* env);\n',
    'int mobile_controls_steering_mode(tenv* env);\n'
    '/* Classic steering (OM, 2026-11-01): while a steering finger is down, the\n'
    '   unit direction from the screen\'s centre to it. False otherwise. */\n'
    'bool mobile_controls_classic_aim(tenv* env, float* dx, float* dy);\n')
add('mobile/mobile_controls.c',
    'bool mobile_controls_get_arrow_position(tenv* env, float* x, float* y) {\n',
    '/* The assist laser follows the finger in Classic, as it follows the arrow\n'
    '   in Arrow (OM, 2026-11-01). Draw-only: classic_touch already steers by\n'
    '   this same axis. */\n'
    'bool mobile_controls_classic_aim(tenv* env, float* dx, float* dy) {\n'
    '  if (!dx || !dy || mobile_controls_steering_mode(env) != MOBILE_STEERING_CLASSIC)\n'
    '    return false;\n'
    '  mobile_controls_state* state = &env->usr->mobile_controls;\n'
    '  for (int i = 0; i < 16; ++i)\n'
    '    if (classic_fingers[i].down && !classic_fingers[i].ignored) {\n'
    '      if (!state->aim_valid) return false;\n'
    '      *dx = state->joystick_axis[0];\n'
    '      *dy = state->joystick_axis[1];\n'
    '      return true;\n'
    '    }\n'
    '  return false;\n'
    '}\n'
    '\n'
    'bool mobile_controls_get_arrow_position(tenv* env, float* x, float* y) {\n')
add('game/ui_overlay.c',
    '        float lx = cosf(me->ehang);\n'
    '        float ly = sinf(me->ehang);\n',
    '        float lx = cosf(me->ehang);\n'
    '        float ly = sinf(me->ehang);\n'
    '        /* Classic: the finger\'s way, as the arrow\'s laser (OM, 2026-11-01). */\n'
    '        float aim_x, aim_y;\n'
    '        if (mobile_controls_classic_aim(env, &aim_x, &aim_y)) {\n'
    '          lx = aim_x;\n'
    '          ly = aim_y;\n'
    '        }\n')

# ---- 6. The zoom bar above the on-screen buttons and the boost button ----
add('mobile/mobile_controls.c',
    '  // Visible on-screen buttons own their finger before joystick, boost or zoom.\n'
    '  // This preserves the direct-touch isolation contract for every button.\n'
    '  if (mobile_hotkeys_process_event(env, raw_event)) return true;\n',
    '  /* The zoom bar is on top (OM, 2026-11-01): a finger that lands on it\n'
    '     zooms, even where an on-screen button or the boost button lies under\n'
    '     it (Classic\'s zoom did nothing beside a big boost button). */\n'
    '  if (event->type == SDL_EVENT_FINGER_DOWN && !state->zoom_down &&\n'
    '      inside_zoom(env, x, y)) {\n'
    '    state->zoom_down = true;\n'
    '    state->zoom_finger = finger;\n'
    '    set_zoom_from_touch(env, x, y);\n'
    '    return true;\n'
    '  }\n'
    '  if (event->type == SDL_EVENT_FINGER_MOTION && state->zoom_down &&\n'
    '      state->zoom_finger == finger) {\n'
    '    set_zoom_from_touch(env, x, y);\n'
    '    return true;\n'
    '  }\n'
    '\n'
    '  // Visible on-screen buttons own their finger before joystick, boost or zoom.\n'
    '  // This preserves the direct-touch isolation contract for every button.\n'
    '  if (mobile_hotkeys_process_event(env, raw_event)) return true;\n')
add('mobile/mobile_controls.c',
    '    draw_original_controls(env, dl);\n'
    '    draw_zoom(env, dl, false);\n'
    '    mobile_hotkeys_draw_gameplay(env);\n'
    '    return;\n',
    '    draw_original_controls(env, dl);\n'
    '    mobile_hotkeys_draw_gameplay(env);\n'
    '    draw_zoom(env, dl, false); /* on top (OM, 2026-11-01) */\n'
    '    return;\n')
add('mobile/mobile_controls.c',
    '    draw_boost(env, dl, bx, by, boosting, false);\n'
    '  draw_zoom(env, dl, false);\n'
    '  mobile_hotkeys_draw_gameplay(env);\n',
    '    draw_boost(env, dl, bx, by, boosting, false);\n'
    '  mobile_hotkeys_draw_gameplay(env);\n'
    '  /* The zoom bar over the buttons and boost, as it takes their touches\n'
    '     (OM, 2026-11-01). */\n'
    '  draw_zoom(env, dl, false);\n')


# ---- 7. Starling's sampler for the sheet: BILINEAR = linear + MIPNEAREST,
#      CLAMP (starling/utils/RenderUtil.setSamplerStateAt; MeshStyle's
#      default smoothing). Wyrm sampled it trilinear with REPEAT. ----
add('rendering/renderer.h', '  VkSampler atlas_sampler;\n',
    '  VkSampler atlas_sampler;\n'
    '  /* The original\'s art as Starling samples it (OM, 2026-11-01). */\n'
    '  VkSampler sheet_sampler;\n', stage=2)
add('rendering/renderer.c', '      NULL, &r->atlas_sampler);\n',
    '      NULL, &r->atlas_sampler);\n'
    '\n'
    '  /* The original\'s glyphs and food as Starling samples them (OM,\n'
    '     2026-11-01): TextureSmoothing.BILINEAR on a mipmapped texture is\n'
    '     linear filtering with the nearest mip level, clamped at the edges\n'
    '     (RenderUtil.setSamplerStateAt). */\n'
    '  vkCreateSampler(\n'
    '      ctx->device,\n'
    '      &(VkSamplerCreateInfo){.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,\n'
    '                             .pNext = NULL,\n'
    '                             .flags = 0,\n'
    '                             .magFilter = VK_FILTER_LINEAR,\n'
    '                             .minFilter = VK_FILTER_LINEAR,\n'
    '                             .mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST,\n'
    '                             .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,\n'
    '                             .addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,\n'
    '                             .addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,\n'
    '                             .minLod = 0.0f,\n'
    '                             .maxLod = VK_LOD_CLAMP_NONE},\n'
    '      NULL, &r->sheet_sampler);\n', stage=2)
add('rendering/renderer.c',
    '             .pImageInfo = &(VkDescriptorImageInfo){r->linear_sampler,r->original_art_tex->view,\n',
    '             .pImageInfo = &(VkDescriptorImageInfo){r->sheet_sampler,r->original_art_tex->view,\n', stage=2)

add('rendering/renderer.c', '  vkDestroySampler(ctx->device, r->atlas_sampler, NULL);\n',
    '  vkDestroySampler(ctx->device, r->atlas_sampler, NULL);\n'
    '  vkDestroySampler(ctx->device, r->sheet_sampler, NULL);\n', stage=2)


def apply(root, label='engine text look 2026-11-01', dry=False, stages=(1, 2)):
    root = Path(root)
    report = []
    for file, pairs in PAIRS.items():
        path = root / file
        raw = path.read_bytes().decode('utf-8')
        crlf = '\r\n' in raw
        text = raw.replace('\r\n', '\n')
        for old, new, optional, stage in pairs:
            if stage not in stages:
                continue
            count = text.count(old)
            if optional and count == 0:
                continue
            if count != 1:
                raise SystemExit(f'{label}: {file}: {count} anchors: {old[:80]!r}')
            if new in text:
                raise SystemExit(f'{label}: {file}: already applied: {old[:60]!r}')
            text = text.replace(old, new, 1)
            report.append(file)
        if not dry:
            path.write_bytes((text.replace('\n', '\r\n') if crlf else text).encode('utf-8'))
    print(f'{label}: {len(report)} edits in {len(PAIRS)} files{" (dry run)" if dry else ""}')


if __name__ == '__main__':
    # --stage2: only the pairs added after the first Android run.
    apply(sys.argv[1], dry='--dry' in sys.argv,
          stages=(2,) if '--stage2' in sys.argv else (1, 2))
