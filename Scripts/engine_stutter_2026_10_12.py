"""Stutter fixes of 2026-10-12 (OM: "same as the reference client").

One source for both apps, like engine_sync_2026_10_12.py: Wyrm Android's
engine tree gets these pairs once
(`python engine_stutter_2026_10_12.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree,
so the text is identical on Android, iOS and Wyrm Desktop (which compiles the
Android tree). Items in ANDROID_ONLY touch code the iOS tree does not have
(the Android/Desktop frame pacing in main.c); iOS skips them.

Analysis: Wyrm Android ARCHITECTURE §3 "Stutter with many snakes".

  1. Vsync always: FIFO only, never IMMEDIATE, on every platform and in every
     mode (the `general.vsync` field of user.dat is no longer read). The
     engine's software cap (`wyrm_pace`) runs only when the app asks for one;
     Android asks only while the display still runs faster than the
     player's limit (WyrmActivity), so FIFO alone paces the frame.
  2. Names (phones): the font atlas is bound once around the whole snake
     loop instead of a push/pop per name (each name was its own draw
     command). The Adreno black-strip fix stays: every ImGui draw in the loop
     samples the font atlas.
  3. Spine: thin = the reference client's centre line (one line per on-screen segment,
     one colour); wide = the skinless mesh, one layer (no dark under-layer).
     The ImGui eyes are drawn only where something ImGui covers the head
     (skinless, a wide spine), only when the head is on screen, and with
     ImGui's own segment count for their size.
  4. Per-snake extras only on screen and lighter: an AIR snake-shadow stamp
     is pushed only when it touches the screen and is visible (alpha >= 1/255);
     the skinless mesh is sampled every 3 px (was 1.5 px).
"""

import sys
from pathlib import Path

PAIRS = {}
ANDROID_ONLY = set()


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


# ------------------------------------------------------------- 1 vsync always

pairs("app/src/main.c",
      ("  env->config.vsync = usrs->vsync;\n",
       "  /* Vsync always (OM, 2026-10-12, \"same as the reference client\"): FIFO only.\n"
       "     The settings file's `vsync` is no longer read. */\n"
       "  env->config.vsync = true;\n"))

pairs("app/src/platform/android_settings.c",
      ("""  if (strcmp(id, "general.vsync") == 0) {
    env->config.vsync = settings->vsync;
    twindow_request_refresh(env->wnd);
  }
""",
       """  /* Vsync always (2026-10-12): the old switch no longer changes the
     present mode. */
  if (strcmp(id, "general.vsync") == 0) env->config.vsync = true;
"""),
      ("""    user_settings_default(&env->usr->usrs);
    env->config.vsync = env->usr->usrs.vsync;
    twindow_request_refresh(env->wnd);
""",
       """    user_settings_default(&env->usr->usrs);
    env->config.vsync = true; /* vsync always (2026-10-12) */
    twindow_request_refresh(env->wnd);
"""))

pairs("app/src/platform/android_update.c",
      ("  env->config.vsync = restored.vsync;\n",
       "  env->config.vsync = true; /* vsync always (2026-10-12) */\n"))

# Android / Wyrm Desktop pacing (main.c, not in the iOS tree).
_PACING = (
    """/*
 * Settings › Performance (OM, 2026-10-01), set by WyrmActivity: the present
 * mode (vsync on = FIFO, off = IMMEDIATE where the phone offers it) and a frame
 * cap (0 = none). Only how often a frame is drawn changes.
 */
static atomic_int wyrm_policy_vsync = -1;
static atomic_int wyrm_policy_cap = 0;

/* Any thread. */
void wyrm_set_frame_policy(int vsync, int cap) {
  atomic_store(&wyrm_policy_vsync, vsync ? 1 : 0);
  atomic_store(&wyrm_policy_cap, cap > 0 ? cap : 0);
}
""",
    """/*
 * Settings › Performance (OM, 2026-10-01), set by WyrmActivity / Wyrm
 * Desktop: a frame cap (0 = none). Vsync is on always (OM, 2026-10-12, "same
 * to same the reference client"): FIFO only, never IMMEDIATE, whatever `vsync` says. A cap
 * is a sleep on a second clock next to the display's, which made a heavy
 * frame miss its slot and show twice, so Android sends one only while the
 * display runs faster than the player's limit (the display is asked for the
 * limit first); Wyrm Desktop's hidden window does not wait for the monitor,
 * so there the cap is the only clock.
 */
static atomic_int wyrm_policy_vsync = 1;
static atomic_int wyrm_policy_cap = 0;

/* Any thread. */
void wyrm_set_frame_policy(int vsync, int cap) {
  (void)vsync;
  atomic_store(&wyrm_policy_vsync, 1);
  atomic_store(&wyrm_policy_cap, cap > 0 ? cap : 0);
}
""")
pairs("app/src/main.c", _PACING)
ANDROID_ONLY.add(("app/src/main.c", _PACING[0]))

# ------------------------------------------------------------------ 2 names

pairs("app/src/game/redraw.c",
      ("""  for (int i = snakes_len - 1; i >= 0; i--) {
    snake* o = gdata->data.snakes + i;
    int sct = o->sct + o->rsc;
""",
       """#if defined(__ANDROID__) || defined(WYRM_MOBILE)
  /* Names (OM, 2026-10-12): the font atlas is bound once for the whole snake
     loop, so every name joins one draw command (the reference client draws them in one
     batch; a push/pop per name made each its own). Direct world-space text
     does not go through ImGui's widget path, and with the dynamic font atlas
     this list can otherwise have an unrelated texture bound: Adreno then
     samples the glyph UVs from it (opaque black strips behind remote snakes).
     The spine, skinless strip and ImGui eyes in this loop use the atlas's
     white pixel, so they want the atlas bound too. */
  ImDrawList* name_draw_list = igGetWindowDrawList();
  ImDrawList_PushTexture(name_draw_list,
                         snake_name_font->ContainerAtlas->TexRef);
#endif
  for (int i = snakes_len - 1; i >= 0; i--) {
    snake* o = gdata->data.snakes + i;
    int sct = o->sct + o->rsc;
"""),
      ("""          // Direct world-space text does not go through ImGui's normal widget
          // path. With the dynamic font atlas this draw list can therefore
          // still have a different texture descriptor active. Adreno then
          // samples the glyph UVs from that unrelated texture, producing the
          // opaque black strips seen behind every remote snake. Bind the font
          // atlas explicitly for this label and restore the previous texture
          // immediately afterwards.
          ImDrawList* name_draw_list = igGetWindowDrawList();
          ImDrawList_PushTexture(name_draw_list,
                                 snake_name_font->ContainerAtlas->TexRef);
          ImDrawList_AddText_FontPtr(""",
       """          // The font atlas is bound once around the snake loop (above).
          ImDrawList_AddText_FontPtr("""),
      ("""              usrs->snake_scores ? nk_label_buff : o->nk, NULL, 0, NULL);
          ImDrawList_PopTexture(name_draw_list);
""",
       """              usrs->snake_scores ? nk_label_buff : o->nk, NULL, 0, NULL);
"""),
      ("""  igPopFont();

  usr->r->global.view[0] = gdata->data.view_xx;
""",
       """#if defined(__ANDROID__) || defined(WYRM_MOBILE)
  ImDrawList_PopTexture(name_draw_list);
#endif
  igPopFont();

  usr->r->global.view[0] = gdata->data.view_xx;
"""))

# ------------------------------------------------------------------ 3 spine

pairs("app/src/game/redraw.c",
      ("""/* A spine wider than the thread is drawn on the skinless mesh, so it does
   not fold where the body coils tight (a thick ImGui polyline mitres). */
static void draw_spine_mesh(tenv* env, int bp, float cx, float cy, ImU32 under,
                            float under_w, ImU32 over, float over_w) {
  game_data* gdata = &env->usr->gdata;
  ImDrawList* draw = igGetWindowDrawList();
  ImVec2 buf[SKINLESS_RUN];
  int n = 0;
  int i;
  int continued = 0;
  for (i = 1; i <= bp; ++i) {
    int live = i < bp && gdata->data.pbu[i] >= 1;
    if (live && n < SKINLESS_RUN) {
      snake_screen_point(gdata, i, cx, cy, &buf[n]);
      n += 1;
      if (n < SKINLESS_RUN) continue;
    }
    if (n >= 1) {
      draw_skinless_run(draw, buf, n, under, under_w, !continued, !live);
      draw_skinless_run(draw, buf, n, over, over_w, !continued, !live);
    }
""",
       """/* A spine wider than the thread is drawn on the skinless mesh, so it does
   not fold where the body coils tight (a thick ImGui polyline mitres). One
   layer (OM, 2026-10-12). */
static void draw_spine_mesh(tenv* env, int bp, float cx, float cy, ImU32 over,
                            float over_w) {
  game_data* gdata = &env->usr->gdata;
  ImDrawList* draw = igGetWindowDrawList();
  ImVec2 buf[SKINLESS_RUN];
  int n = 0;
  int i;
  int continued = 0;
  for (i = 1; i <= bp; ++i) {
    int live = i < bp && gdata->data.pbu[i] >= 1;
    if (live && n < SKINLESS_RUN) {
      snake_screen_point(gdata, i, cx, cy, &buf[n]);
      n += 1;
      if (n < SKINLESS_RUN) continue;
    }
    if (n >= 1)
      draw_skinless_run(draw, buf, n, over, over_w, !continued, !live);
"""),
      ("""/* Spine width (OM, 2026-10-09): the slider is a share of the body's width
   (`body_w`, the bead's diameter on screen): 0 draws nothing, 1 is as wide as
   the snake, smooth in between. The dark edge is 2 dpi, or as wide as the
   white line when that is thinner, so a hairline stays a hairline. Up to
   2 dpi the anti-aliased ImGui line draws it; wider, the skinless mesh. */
static void draw_snake_spine(tenv* env, int bp, float cx, float cy, float alpha,
                             float body_w, float width) {
  float dpi = snake_line_dpi(env);
  float over_w;
  float edge;
  ImU32 dark = igColorConvertFloat4ToU32((ImVec4){0.0f, 0.0f, 0.0f, 0.35f * alpha});
  ImU32 white = igColorConvertFloat4ToU32((ImVec4){1.0f, 1.0f, 1.0f, 0.8f * alpha});
  if (!(width > 0.0f) || !(body_w > 0.0f)) return;
  if (width > 1.0f) width = 1.0f;
  over_w = body_w * width;
  edge = over_w < 2.0f * dpi ? over_w : 2.0f * dpi;
  if (over_w <= 2.0f * dpi)
    draw_body_line(env, bp, 1, cx, cy, dark, over_w + edge, white, over_w);
  else
    draw_spine_mesh(env, bp, cx, cy, dark, over_w + edge, white, over_w);
}
""",
       """/* The reference client's centre line (OM, 2026-10-12): one straight line per segment,
   skipped when neither end is within 8 px of the screen. */
static void draw_spine_lines(tenv* env, int bp, float cx, float cy, ImU32 col,
                             float width) {
  game_data* gdata = &env->usr->gdata;
  ImDrawList* draw = igGetWindowDrawList();
  const float margin = 8.0f;
  const float right = 2.0f * cx + margin;
  const float bottom = 2.0f * cy + margin;
  ImVec2 last = {0.0f, 0.0f};
  int have = 0;
  int i;
  for (i = 1; i < bp; ++i) {
    ImVec2 at;
    int seen;
    if (gdata->data.pbu[i] < 1) {
      have = 0;
      continue;
    }
    snake_screen_point(gdata, i, cx, cy, &at);
    seen = (at.x >= -margin && at.y >= -margin && at.x <= right && at.y <= bottom) ||
           (last.x >= -margin && last.y >= -margin && last.x <= right &&
            last.y <= bottom);
    if (have && seen) ImDrawList_AddLine(draw, last, at, col, width);
    last = at;
    have = 1;
  }
}

/* Spine width (OM, 2026-10-09): the slider is a share of the body's width
   (`body_w`, the bead's diameter on screen): 0 draws nothing, 1 is as wide as
   the snake, smooth in between. Light like the reference client's centre line (OM,
   2026-10-12): one colour, white, or black on a very light snake (the reference client's
   luminance rule); up to 2 dpi one line per segment, wider the skinless mesh
   in one layer. Returns 1 when the mesh was drawn (it can cover the head, so
   the eyes go on top). */
static int draw_snake_spine(tenv* env, snake* o, int bp, float cx, float cy,
                            float alpha, float body_w, float width) {
  float dpi = snake_line_dpi(env);
  float over_w;
  float red, green, blue;
  float ink;
  ImU32 col;
  if (!(width > 0.0f) || !(body_w > 0.0f)) return 0;
  if (width > 1.0f) width = 1.0f;
  over_w = body_w * width;
  snake_strip_colour(env, o, &red, &green, &blue);
  ink = red * 0.2126f + green * 0.7152f + blue * 0.0722f > 0.82f ? 0.0f : 1.0f;
  col = igColorConvertFloat4ToU32((ImVec4){ink, ink, ink, 0.8f * alpha});
  if (over_w <= 2.0f * dpi) {
    draw_spine_lines(env, bp, cx, cy, col, over_w);
    return 0;
  }
  draw_spine_mesh(env, bp, cx, cy, col, over_w);
  return 1;
}
"""),
      ("""  float side;
  float ex;
  float ey;
  ImVec2 at;
  for (side = -1.0f; side <= 1.0f; side += 2.0f) {""",
       """  float side;
  float ex;
  float ey;
  ImVec2 at;
  /* Only for a head on screen (OM, 2026-10-12). */
  if (!point_in_snake_view(gdata, hx, hy)) return;
  for (side = -1.0f; side <= 1.0f; side += 2.0f) {"""),
      ("    ImDrawList_AddCircleFilled(draw, at, iris_r, iris, 16);\n",
       "    ImDrawList_AddCircleFilled(draw, at, iris_r, iris, 0);\n"),
      ("    ImDrawList_AddCircleFilled(draw, at, pupil_r, pupil, 12);\n",
       "    ImDrawList_AddCircleFilled(draw, at, pupil_r, pupil, 0);\n"),
      ("""            if (spine_on)
              draw_snake_spine(env, bp, mww2, mhh2, a,
                               2.0f * lsz * gdata->data.gsc,
                               usrs->ext.spine_width[assist_on]);
            if (mode->render_mode == 3 || spine_on)
              draw_snake_imgui_eyes(env, o, fang, hx, hy, ssc, ea, mww2, mhh2);""",
       """            int spine_mesh = 0;
            if (spine_on)
              spine_mesh = draw_snake_spine(env, o, bp, mww2, mhh2, a,
                                            2.0f * lsz * gdata->data.gsc,
                                            usrs->ext.spine_width[assist_on]);
            /* A thin spine starts a point behind the head and leaves the
               sprite eyes uncovered (OM, 2026-10-12). */
            if (mode->render_mode == 3 || spine_mesh)
              draw_snake_imgui_eyes(env, o, fang, hx, hy, ssc, ea, mww2, mhh2);"""))

# --------------------------------------------------------- 4 lighter extras

pairs("app/src/game/redraw.c",
      ("""  float fix = (gdata->data.pbx[point] - gdata->data.view_xx) * gdata->data.gsc + mww2;
  float fiy = (gdata->data.pby[point] - gdata->data.view_yy) * gdata->data.gsc + mhh2;
  bp_renderer_push(env->usr->r->bpr,""",
       """  float fix = (gdata->data.pbx[point] - gdata->data.view_xx) * gdata->data.gsc + mww2;
  float fiy = (gdata->data.pby[point] - gdata->data.view_yy) * gdata->data.gsc + mhh2;
  /* Only a stamp that shows (OM, 2026-10-12): on screen, and not faded to
     nothing where the points bunch up. */
  if (alpha < 1.0f / 255.0f) return;
  if (fix + half < 0 || fiy + half < 0 || fix - half > 2 * mww2 ||
      fiy - half > 2 * mhh2)
    return;
  bp_renderer_push(env->usr->r->bpr,"""),
      ("    step = fmaxf(1.5f, r * 0.35f);\n",
       "    step = fmaxf(3.0f, r * 0.35f); /* 3 px (was 1.5): lighter (2026-10-12) */\n"))


def apply(root, label="engine stutter 2026-10-12", only=None, skip_applied=False,
          ios=False):
    root = Path(root)
    for relative, items in PAIRS.items():
        if only is not None and relative not in only:
            continue
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        for item in items:
            old, new = item
            if ios and (relative, old) in ANDROID_ONLY:
                continue
            if skip_applied and new in text and (old not in text or old in new):
                continue
            count = text.count(old)
            if count != 1:
                raise SystemExit(f"{label}: anchor x{count} in {relative}: {old[:70]!r}")
            text = text.replace(old, new)
        if text != original:
            target.write_text(text, encoding="utf-8", newline="")
    return len(PAIRS)


if __name__ == "__main__":
    # Wyrm Android's tree: python engine_stutter_2026_10_12.py "<Wyrm Android>"
    print(apply(sys.argv[1], skip_applied=True), "files patched")
