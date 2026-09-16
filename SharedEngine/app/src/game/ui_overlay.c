#include "ui_overlay.h"

#include "arena_theme.h"
#include "../mobile/mobile_controls.h"
#include "../platform/android_team.h"
#include "../platform/android_voice.h"
#include "../user.h"

/*
 * The arena's overlay, in Wyrm's language.
 *
 * Same palette and the same two typefaces as every paper screen in the app:
 * the display serif for numbers, the body face for words, warm paper and ink.
 * This remains native ImGui paint on the engine thread. No Compose surface,
 * bridge or second state model is involved, so the arena remains the sole
 * owner of both the values and the frame in which they appear.
 *
 * One exception survives: each snake keeps its own colour, as a dot beside its
 * name rather than as the name. That is the one piece of information here that
 * colour carries better than words.
 */

#define HUD_PANEL_ROUNDING 14.0f

static float leaderboard_hit[4] = {0, 0, 0, 0};
static bool leaderboard_expanded;
static float leaderboard_expand;

/** Places a measured HUD item by its normalized centre and keeps it visible. */
static ImVec2 hud_top_left(tenv* env, float nx, float ny, float width,
                           float height, float edge) {
  return (ImVec2){glm_clamp(nx, 0.0f, 1.0f) * env->ctx->size[0] - width * 0.5f,
                  glm_clamp(ny, 0.0f, 1.0f) * env->ctx->size[1] - height * 0.5f};
}

static ImVec2 hud_clamp_top_left(tenv* env, ImVec2 value, float width,
                                  float height, float edge) {
  value.x = GLM_MAX(edge, GLM_MIN(value.x, env->ctx->size[0] - edge - width));
  value.y = GLM_MAX(edge, GLM_MIN(value.y, env->ctx->size[1] - edge - height));
  return value;
}

typedef struct hud_rgb {
  float r;
  float g;
  float b;
} hud_rgb;

static ImU32 hud_colour(float r, float g, float b, float a) {
  return igColorConvertFloat4ToU32((ImVec4){r, g, b, a});
}

/** A vertical spectrum: every snake name gets a distinct point on one flow. */
static ImU32 leaderboard_name_colour(int row, float alpha) {
  static const hud_rgb stops[] = {
      {0.96f, 0.38f, 0.55f}, {0.98f, 0.64f, 0.28f},
      {0.48f, 0.82f, 0.52f}, {0.26f, 0.72f, 0.92f},
      {0.68f, 0.46f, 0.96f}, {0.94f, 0.36f, 0.82f},
  };
  float position = (float)row / (NUM_LEADERBOARD_ENTRIES - 1) * 5.0f;
  int left = (int)floorf(position);
  if (left > 4) left = 4;
  float t = position - left;
  hud_rgb a = stops[left];
  hud_rgb b = stops[left + 1];
  return hud_colour(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                    a.b + (b.b - a.b) * t, alpha);
}

bool ui_overlay_leaderboard_hit(tenv* env, float x, float y) {
  if (!env || env->usr->gdata.curr_screen != PLAYING ||
      (env->usr->gdata.conn != CONNECTED &&
       env->usr->gdata.conn != AI_CONNECTED) ||
      !env->usr->gdata.data.gotlb)
    return false;
  if (x < leaderboard_hit[0] || y < leaderboard_hit[1] ||
      x > leaderboard_hit[0] + leaderboard_hit[2] ||
      y > leaderboard_hit[1] + leaderboard_hit[3])
    return false;
  leaderboard_expanded = !leaderboard_expanded;
  return true;
}

void ui_overlay_toggle_leaderboard(tenv* env) {
  if (!env || env->usr->gdata.curr_screen != PLAYING ||
      !env->usr->gdata.data.gotlb)
    return;
  leaderboard_expanded = !leaderboard_expanded;
}

/**
 * A paper card behind a block of the overlay.
 *
 * One shadow, one fill and one hairline are deliberately cheaper than the old
 * layered glass recipe. The panel is nearly opaque because this information
 * must stay readable over pale food, but it occupies exactly the same measured
 * rectangle and does not change any arena or input geometry.
 */
static void draw_hud_paper(ImDrawList* draw, ImVec2 min, ImVec2 max,
                           float alpha) {
  ImDrawList_AddRectFilled(draw, (ImVec2){min.x, min.y + 3.0f},
                           (ImVec2){max.x, max.y + 3.0f},
                           hud_colour(0, 0, 0, 0.16f * alpha),
                           HUD_PANEL_ROUNDING, 0);
  ImDrawList_AddRectFilled(draw, min, max,
                           arena_theme_colour(ARENA_THEME_CARD, 0.96f * alpha),
                           HUD_PANEL_ROUNDING, 0);
  ImDrawList_AddRect(draw, min, max,
                     arena_theme_colour(ARENA_THEME_RULE, alpha),
                     HUD_PANEL_ROUNDING, 0, 1.0f);
}

/** How wide a string is in a given font, without disturbing the cursor. */
static float measure(ImFont* font, const char* text) {
  ImVec2 size;
  igPushFont(font, font->LegacySize);
  igCalcTextSize(&size, text, NULL, false, -1);
  igPopFont();
  return size.x;
}

static ImVec2 measure_scaled(ImFont* font, const char* text, float scale) {
  ImVec2 size;
  igPushFont(font, font->LegacySize * scale);
  igCalcTextSize(&size, text, NULL, false, -1);
  igPopFont();
  return size;
}

/**
 * Draws a name, shortened until it fits.
 *
 * Arena nicknames run past twenty characters and the column is as wide as it
 * is; without this the long ones carried straight on over the scores beside
 * them. Cut with a trailing ellipsis rather than clipped mid-letter, so a
 * shortened name still reads as a name.
 */
static void draw_fitted_text(ImDrawList* draw, ImFont* font, ImVec2 pos,
                             ImU32 colour, const char* text, float max_width) {
  if (measure(font, text) <= max_width) {
    ImDrawList_AddText_FontPtr(draw, font, font->LegacySize, pos, colour, text,
                               NULL, 0, NULL);
    return;
  }
  char shortened[MAX_NICKNAME_LEN + 8];
  int length = (int)strlen(text);
  if (length > (int)sizeof(shortened) - 5) length = (int)sizeof(shortened) - 5;
  while (length > 1) {
    snprintf(shortened, sizeof(shortened), "%.*s...", --length, text);
    if (measure(font, shortened) <= max_width) break;
  }
  ImDrawList_AddText_FontPtr(draw, font, font->LegacySize, pos, colour,
                             shortened, NULL, 0, NULL);
}

/** A label and value in the user's chosen stats size. */
static void draw_stat_row(tenv* env, ImDrawList* draw, float right, float y,
                          const char* label, const char* value, float alpha) {
  tuser_data* usr = env->usr;
  ImFont* body = usr->imgui_data.regular_font[usr->usrs.stats_font_size];
  ImFont* display =
      usr->imgui_data.regular_font_bold[usr->usrs.stats_font_size];

  float scale = usr->usrs.hud_stats_scale;
  alpha *= usr->usrs.hud_stats_opacity;
  ImVec2 value_size = measure_scaled(display, value, scale);

  ImDrawList_AddText_FontPtr(draw, display, display->LegacySize * scale,
                             (ImVec2){right - value_size.x, y},
                             arena_theme_colour(ARENA_THEME_INK, alpha), value,
                             NULL, 0, NULL);

  ImVec2 label_size = measure_scaled(body, label, scale);
  ImDrawList_AddText_FontPtr(
      draw, body, body->LegacySize * scale,
      (ImVec2){right - value_size.x - 10.0f * scale - label_size.x,
               y + (value_size.y - label_size.y) * 0.72f},
      arena_theme_colour(ARENA_THEME_QUIET, 0.92f * alpha), label, NULL, 0,
      NULL);
}

void ui_overlay(tenv* env) {
  tuser_data* usr = env->usr;
  tcontext* ctx = env->ctx;
  game_data* gdata = &usr->gdata;
  user_settings* usrs = &usr->usrs;

  float mww2 = ctx->size[0] / 2.0f;
  float mhh2 = ctx->size[1] / 2.0f;

  int snakes_len = tdarray_length(gdata->data.snakes);
  if (snakes_len) {
    snake* me = gdata->data.snakes + (snakes_len - 1);

    if (me->local_player && gdata->data.snake_id == me->id) {
      float a = me->alive_amt * (1 - me->dead_amt);
      int sct = me->sct + me->rsc;
      sct = GLM_MAX(0, GLM_MIN(sct, (int)tdarray_length(gdata->data.fpsls) - 1));
      float hx = me->xx + me->fx;
      float hy = me->yy + me->fy;
      gdata->data.score = (int)floorf((gdata->data.fpsls[sct] +
                                       me->fam / gdata->data.fmlts[sct] - 1) *
                                          15 -
                                      5) /
                          1;

      float arrow_x = 0.0f;
      float arrow_y = 0.0f;
      if (usrs->hotkeys[HOTKEY_ASSIST].active &&
          mobile_controls_get_arrow_position(env, &arrow_x, &arrow_y)) {
        ImDrawList_AddLine(
            igGetWindowDrawList(),
            (ImVec2){mww2 + (hx - gdata->data.view_xx) * gdata->data.gsc,
                     mhh2 + (hy - gdata->data.view_yy) * gdata->data.gsc},
            (ImVec2){arrow_x, arrow_y},
            igColorConvertFloat4ToU32(
                (ImVec4){usrs->laser_color[0], usrs->laser_color[1],
                         usrs->laser_color[2], usrs->laser_color[3] * a}),
            usrs->laser_thickness);
      }
    }
  }

  android_team_tick(env);

  usr->r->global.minimap_opacity = 0;
  if (usrs->hotkeys[HOTKEY_HUD].active) {
    android_team_begin_frame();
    igPushFont(usr->imgui_data.mono_font[usrs->stats_font_size],
               usr->imgui_data.mono_font[usrs->stats_font_size]->LegacySize);

    float ping_norm =
        (gdata->data.ping_follow - GOOD_PING) / (BAD_PING - GOOD_PING);
    float lag_norm = (gdata->data.lag_mult - 0.2f) / (1 - 0.2f);
    vec3 ping_col;
    glm_vec3_lerp((vec3){0.5f, 1, 0.5f}, (vec3){1, 0.5f, 0.5f}, ping_norm,
                  ping_col);
    vec3 ic_col;
    glm_vec3_lerp((vec3){1, 0.5f, 0.5f}, (vec3){1, 1, 1}, lag_norm, ic_col);

    int tot_sec = (int)gdata->data.play_etm;
    int hours = tot_sec / 3600;
    int minutes = (tot_sec % 3600) / 60;
    int seconds = tot_sec % 60;
    char kills_text[32];
    char rank_text[48];
    char score_text[32];
    char ping_text[32];
    char fps_text[32];
    char time_text[32];
    snprintf(kills_text, sizeof(kills_text), "%d", gdata->data.kills);
    snprintf(rank_text, sizeof(rank_text), "%d / %d", gdata->data.rank,
             gdata->data.slither_count);
    snprintf(score_text, sizeof(score_text), "%d", gdata->data.score);
    snprintf(ping_text, sizeof(ping_text), "%d ms", gdata->data.ping);
    snprintf(fps_text, sizeof(fps_text), "%d FPS", gdata->data.fps);
    snprintf(time_text, sizeof(time_text), "%02d:%02d:%02d", hours, minutes,
             seconds);

    float px = (((gdata->data.view_xx - gdata->data.grd) * 2) /
                ((gdata->data.flux_grd) * 2));
    float py = (((gdata->data.view_yy - gdata->data.grd) * 2) /
                ((gdata->data.flux_grd) * 2));
    int pang = (int)roundf(glm_deg(atan2f(-py, px)));
    if (pang < 0) pang += 360;
    int dst = (int)roundf(sqrtf(px * px + py * py) * 100.0f);

    igPopFont();

    ImDrawList* draw = igGetWindowDrawList();
    const float edge = 16.0f;
    const float pad = 14.0f;

    /* The leaderboard setting now scales every piece of leaderboard type,
       including its title, ranks and hint — not only the names. */
    ImFont* label_font = usr->imgui_data.regular_font[usrs->lb_font_size];
    ImFont* name_font = usr->imgui_data.regular_font_bold[usrs->lb_font_size];
    ImFont* rank_font = usr->imgui_data.regular_font[usrs->lb_font_size];
    ImFont* score_font = usr->imgui_data.regular_font_bold[usrs->lb_font_size];

    leaderboard_hit[2] = leaderboard_hit[3] = 0.0f;
    if (gdata->data.gotlb) {
      /* Five rows are the quiet default. The remaining five live behind a
         clipped, eased reveal; protocol storage remains the same ten rows. */
      float target = leaderboard_expanded ? 1.0f : 0.0f;
      float step = 0.12f * GLM_MAX(gdata->data.vfr, 0.25f);
      if (leaderboard_expand < target)
        leaderboard_expand = GLM_MIN(target, leaderboard_expand + step);
      else if (leaderboard_expand > target)
        leaderboard_expand = GLM_MAX(target, leaderboard_expand - step);
      float reveal = leaderboard_expand * leaderboard_expand *
                     (3.0f - 2.0f * leaderboard_expand);

      ImVec2 rank_size, score_size, name_size, title_size, position_size,
          hint_size;
      igPushFont(rank_font, rank_font->LegacySize);
      igCalcTextSize(&rank_size, "10", NULL, false, -1);
      igPopFont();
      igPushFont(score_font, score_font->LegacySize);
      igCalcTextSize(&score_size, "999999", NULL, false, -1);
      igPopFont();
      igPushFont(name_font, name_font->LegacySize);
      char widest[MAX_NICKNAME_LEN + 1] = {0};
      memset(widest, (int)'n', 14);
      igCalcTextSize(&name_size, widest, NULL, false, -1);
      igPopFont();
      igPushFont(label_font, label_font->LegacySize);
      igCalcTextSize(&title_size, "Wyrm Leaderboard", NULL, false, -1);
      igCalcTextSize(&position_size, "Your position  999 / 999", NULL, false,
                     -1);
      igCalcTextSize(&hint_size, "Tap on leaderboard to expand", NULL, false,
                     -1);
      igPopFont();

      float row_height = score_size.y + 7.0f;
      float dot = 5.0f;
      float board_width = GLM_MAX(
          position_size.x, GLM_MAX(hint_size.x,
                                   rank_size.x + 10.0f + dot * 2 + 8.0f +
                                       name_size.x + 12.0f + score_size.x));
      float board_height = title_size.y + 8.0f +
                           row_height * (5.0f + 5.0f * reveal) + 8.0f +
                           GLM_MAX(position_size.y, score_size.y) + 4.0f +
                           hint_size.y;
      ImVec2 board_min = hud_top_left(env, usrs->hud_leaderboard_x,
                                      usrs->hud_leaderboard_y, board_width,
                                      board_height, edge);
      board_min = hud_clamp_top_left(env, board_min, board_width, board_height,
                                     edge);
      ImVec2 board_max = {board_min.x + board_width, board_min.y};

      ImDrawList_AddText_FontPtr(draw, label_font, label_font->LegacySize,
                                 board_min,
                                 arena_theme_overlay_text(0.92f), "Leaderboard",
                                 NULL, 0, NULL);
      float row_y = board_min.y + title_size.y + 8.0f;
      float rows_bottom = row_y + row_height * (5.0f + 5.0f * reveal);
      ImDrawList_PushClipRect(draw, (ImVec2){0, row_y},
                                  (ImVec2){ctx->size[0], rows_bottom}, true);
      for (int row = 0; row < NUM_LEADERBOARD_ENTRIES; row++) {
        bool mine = gdata->data.lb_pos == (row + 1);
        float alpha = mine ? 1.0f : 0.86f;

        char rank_text[8];
        snprintf(rank_text, sizeof(rank_text), "%d", row + 1);
        ImVec2 measured;
        igPushFont(rank_font, rank_font->LegacySize);
        igCalcTextSize(&measured, rank_text, NULL, false, -1);
        igPopFont();
        ImDrawList_AddText_FontPtr(
            draw, rank_font, rank_font->LegacySize,
            (ImVec2){board_min.x + rank_size.x - measured.x, row_y + 2.0f},
            arena_theme_overlay_text(mine ? 1.0f : 0.78f), rank_text, NULL, 0,
            NULL);

        /* The one place colour is still worth spending: whose snake this is. */
        vec3s* snake_colour = gdata->cg_colors + gdata->data.lb.entries[row].cv;
        ImDrawList_AddCircleFilled(
            draw,
            (ImVec2){board_min.x + rank_size.x + 10.0f + dot,
                     row_y + row_height * 0.42f},
            dot,
            igColorConvertFloat4ToU32((ImVec4){snake_colour->x, snake_colour->y,
                                               snake_colour->z, alpha}),
            16);

        char score_text_row[16];
        snprintf(score_text_row, sizeof(score_text_row), "%d",
                 gdata->data.lb.entries[row].score);
        float score_width = measure(score_font, score_text_row);

        /* The name gets whatever is left after the score has taken its width,
           and is shortened to fit rather than allowed to run over it. */
        float name_x = board_min.x + rank_size.x + 10.0f + dot * 2 + 8.0f;
        draw_fitted_text(draw, name_font, (ImVec2){name_x, row_y + 3.0f},
                         leaderboard_name_colour(row, alpha),
                         gdata->data.lb.entries[row].nickname,
                         board_max.x - score_width - 10.0f - name_x);

        measured.x = score_width;
        ImDrawList_AddText_FontPtr(draw, score_font, score_font->LegacySize,
                                   (ImVec2){board_max.x - measured.x, row_y},
                                   arena_theme_overlay_text(alpha), score_text_row,
                                   NULL, 0, NULL);
        row_y += row_height;
      }
      ImDrawList_PopClipRect(draw);

      float footer_y = rows_bottom + 8.0f;
      ImDrawList_AddText_FontPtr(draw, label_font, label_font->LegacySize,
                                 (ImVec2){board_min.x, footer_y},
                                 arena_theme_overlay_text(0.92f), "Your position",
                                 NULL, 0, NULL);
      float rank_width = measure(score_font, rank_text);
      ImDrawList_AddText_FontPtr(draw, score_font, score_font->LegacySize,
                                 (ImVec2){board_max.x - rank_width, footer_y},
                                 arena_theme_overlay_text(1.0f), rank_text, NULL, 0,
                                 NULL);
      footer_y += GLM_MAX(position_size.y, score_size.y) + 4.0f;
      const char* hint = leaderboard_expanded
                             ? "Tap on leaderboard to show 5"
                             : "Tap on leaderboard to expand";
      ImDrawList_AddText_FontPtr(draw, label_font, label_font->LegacySize,
                                 (ImVec2){board_min.x, footer_y},
                                 arena_theme_overlay_text(0.66f), hint, NULL, 0,
                                 NULL);
      board_max.y = footer_y + hint_size.y;
      leaderboard_hit[0] = board_min.x - 10.0f;
      leaderboard_hit[1] = board_min.y - 8.0f;
      leaderboard_hit[2] = board_width + 20.0f;
      leaderboard_hit[3] = board_max.y - board_min.y + 16.0f;
    }

    /* ---- what you are doing, directly under the leaderboard ---- */
    {
      const char* labels[] = {"SCORE", "KILLS", "RANK", "TIME", "PING", "FPS"};
      const char* values[] = {score_text, kills_text, rank_text,
                              time_text,  ping_text,  fps_text};
      ImFont* stats_label_font =
          usr->imgui_data.regular_font[usrs->stats_font_size];
      ImFont* value_font =
          usr->imgui_data.regular_font_bold[usrs->stats_font_size];
      float stats_scale = usrs->hud_stats_scale;
      float stats_alpha = usrs->hud_stats_opacity;
      ImVec2 sample = measure_scaled(value_font, "000000", stats_scale);
      ImVec2 caption_size = measure_scaled(stats_label_font, usrs->ipv4,
                                           stats_scale);

      /* Measured from the widest row that is actually there rather than from a
         guessed sample: "245 / 378" and "60 FPS" are both wider than the six
         digits this used to reserve, and overflowed the panel they sit in. */
      float widest = caption_size.x;
      for (int i = 0; i < 6; ++i) {
        float row = measure_scaled(stats_label_font, labels[i], stats_scale).x +
                    12.0f * stats_scale +
                    measure_scaled(value_font, values[i], stats_scale).x;
        if (row > widest) widest = row;
      }

      float row_height = sample.y + 5.0f * stats_scale;
      float panel_width = pad * 2 + widest;
      float panel_height = pad + caption_size.y + 9.0f + row_height * 6 + pad * 0.6f;
      ImVec2 min = hud_top_left(env, usrs->hud_stats_x, usrs->hud_stats_y,
                                panel_width, panel_height, edge);
      min = hud_clamp_top_left(env, min, panel_width, panel_height, edge);
      ImVec2 max = {min.x + panel_width, min.y + panel_height};
      draw_hud_paper(draw, min, max, stats_alpha);

      ImDrawList_AddText_FontPtr(draw, stats_label_font,
                                 stats_label_font->LegacySize * stats_scale,
                                 (ImVec2){min.x + pad, min.y + pad * 0.7f},
                                 arena_theme_colour(ARENA_THEME_QUIET,
                                                    0.78f * stats_alpha),
                                 usrs->ipv4, NULL, 0,
                                 NULL);
      float rule_y = min.y + pad * 0.7f + caption_size.y + 5.0f;
      ImDrawList_AddLine(draw, (ImVec2){min.x + pad, rule_y},
                         (ImVec2){max.x - pad, rule_y},
                         arena_theme_colour(ARENA_THEME_RULE,
                                            0.72f * stats_alpha), 1.0f);

      float y = rule_y + 6.0f;
      for (int i = 0; i < 6; ++i) {
        draw_stat_row(env, draw, max.x - pad, y, labels[i], values[i], 0.88f);
        y += row_height;
      }
    }

    // The fullscreen gameplay window can inherit a large layout padding from
    // the menu theme. Use an explicit arena edge inset so the minimap is
    // anchored to the real top-left corner instead of drifting inward.
    const float minimap_edge_padding = 16.0f;
    usr->r->global.minimap_circ[2] = usrs->minimap_size;
    // The minimap shader treats x/y as the quad's top-left origin; z is its
    // rendered diameter. Do not add half or all of z to the origin.
    float minimap_diameter = usr->r->global.minimap_circ[2];
    ImVec2 minimap_min = hud_top_left(
        env, usrs->hud_minimap_x, usrs->hud_minimap_y, minimap_diameter,
        minimap_diameter, minimap_edge_padding);
    minimap_min = hud_clamp_top_left(env, minimap_min, minimap_diameter,
                                     minimap_diameter, minimap_edge_padding);
    float minimap_left = minimap_min.x;
    float minimap_top = minimap_min.y;
    usr->r->global.minimap_circ[0] = minimap_left;
    usr->r->global.minimap_circ[1] = minimap_top;
    usr->r->global.minimap_opacity = 1;

    // minimap_circ.z is already the rendered quad width/diameter.
    android_voice_publish_hud(minimap_left, minimap_top, minimap_diameter);
    android_team_draw_minimap(env, minimap_left, minimap_top, minimap_diameter);
    android_team_set_chat_centre(usrs->hud_chat_x * ctx->size[0],
                                 usrs->hud_chat_y * ctx->size[1]);
    /* The map itself is drawn by a shader underneath; this is the paper frame
       it sits in. Only the rim and the shadow are drawn here — a filled disc
       would be painted straight over the map, since the interface layer is
       composited last. */
    ImVec2 map_centre = {minimap_left + minimap_diameter * 0.5f,
                         minimap_top + minimap_diameter * 0.5f};
    float map_radius = minimap_diameter * 0.5f;
    ImDrawList_AddCircle(draw, (ImVec2){map_centre.x, map_centre.y + 2.0f},
                         map_radius + 3.0f, hud_colour(0, 0, 0, 0.16f), 64,
                         6.0f);
    ImDrawList_AddCircle(draw, map_centre, map_radius + 1.5f,
                         arena_theme_overlay_text(0.96f), 64, 5.0f);
    ImDrawList_AddCircle(draw, map_centre, map_radius - 1.0f,
                         arena_theme_colour(ARENA_THEME_INK, 0.28f), 64, 1.0f);

    /* Which way the middle of the arena lies, and how far out you have drifted. */
    char bearing_text[32];
    snprintf(bearing_text, sizeof(bearing_text), "%d°  %d%%", pang, dst);
    ImFont* bearing_font =
        usr->imgui_data.regular_font[usrs->stats_font_size];
    ImVec2 bearing_size;
    igPushFont(bearing_font, bearing_font->LegacySize);
    igCalcTextSize(&bearing_size, bearing_text, NULL, false, -1);
    igPopFont();
    ImVec2 bearing_min = {map_centre.x - bearing_size.x * 0.5f - 12.0f,
                          minimap_top + minimap_diameter + 6.0f};
    if (bearing_min.y + bearing_size.y + 10.0f > ctx->size[1] - edge)
      bearing_min.y = minimap_top - bearing_size.y - 16.0f;
    ImVec2 bearing_max = {map_centre.x + bearing_size.x * 0.5f + 12.0f,
                          bearing_min.y + bearing_size.y + 10.0f};
    draw_hud_paper(draw, bearing_min, bearing_max, 0.94f);
    ImDrawList_AddText_FontPtr(draw, bearing_font, bearing_font->LegacySize,
                               (ImVec2){map_centre.x - bearing_size.x * 0.5f,
                                        bearing_min.y + 5.0f},
                               arena_theme_colour(ARENA_THEME_INK, 0.86f),
                               bearing_text, NULL,
                               0, NULL);

    /* The team, under the map it is drawn on. Nothing at all when there is no
       team, which is the common case. */
    android_team_draw_roster_centered(env, usrs->hud_team_x * ctx->size[0],
                                      usrs->hud_team_y * ctx->size[1]);
  }

  /* Last, so it can be placed against a leaderboard that has already been
     measured — and so it is drawn over everything it sits beside. */
  android_team_draw_chat_button(env);
  android_team_draw_respawn_toggle(env);
  android_team_draw_chat_help(env);
}
