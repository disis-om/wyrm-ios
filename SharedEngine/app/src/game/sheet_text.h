#ifndef WYRM_SHEET_TEXT_H
#define WYRM_SHEET_TEXT_H
/* Baked glyph overlay: outline NORMAL, face ADDITIVE, after ImGui plates.
   ASCII strings only; whole Unicode strings keep the app font. */
#include "../user.h"
#include "original_art_data.h"

extern VkDescriptorSet wyrm_sheet_set;
extern bool wyrm_sheet_warned;
extern spr_renderer *wyrm_text_normal, *wyrm_text_add;

#define SHEET_THIN 285 /* Nunito Bold: leaderboard, names, keys */
#define SHEET_BLACK 0  /* Nunito Black: the stats */
#define SHEET_EM 0.7331f
#define SHEET_DROP 0.0277f

static inline bool sheet_ok(const char* text) {
  if (!text || !text[0]) return false;
  if (!wyrm_sheet_set || !wyrm_text_normal || !wyrm_text_add) {
    if (!wyrm_sheet_warned) {
      SDL_Log("Wyrm sheet unavailable: falling back to app font");
      wyrm_sheet_warned = true;
    }
    return false;
  }
  for (const unsigned char* p = (const unsigned char*)text; *p; ++p)
    if (*p < 32 || *p > 126) return false;
  return true;
}

/* Main.as drawText's width: the advances, the last letter to its ink. */
static inline float sheet_width(const char* text, float size, int font) {
  float w = 0, last = 0;
  for (const unsigned char* p = (const unsigned char*)text; *p; ++p) {
    if (*p < 32 || *p > 126) continue;
    const original_glyph* g = &ORIGINAL_GLYPHS[font + (*p - 32) * 3];
    w += g->advance;
    last = g->advance - g->rw;
  }
  return (w - last) * size * SHEET_EM / 52.0f;
}

/* Cull a whole glyph at clipping edges: sprite batches have no ImGui scissor.
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

/* The same signature as ImGui, for engine roster/chat call sites. Wrapping
   is done by the caller using sheet advances, never ImGui's ASCII widths. */
static inline void sheet_add_text(ImDrawList* draw, ImFont* font, float size,
    ImVec2 pos, ImU32 colour, const char* text, const char* end,
    float wrap, const ImVec4* clip) {
  if (!text) return;
  char run[2048];
  if (end) {
    size_t n = (size_t)(end-text);
    if (n >= sizeof(run)) { return; }
    memcpy(run, text, n); run[n] = 0; text = run;
  }
  if (sheet_ok(text)) sheet_layer(draw,text,size,pos,colour,SHEET_THIN,0);
  else ImDrawList_AddText_FontPtr(draw,font,size,pos,colour,text,NULL,wrap,clip);
}
#endif
