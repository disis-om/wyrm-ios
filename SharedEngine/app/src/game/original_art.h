#ifndef WYRM_ORIGINAL_ART_H
#define WYRM_ORIGINAL_ART_H
#include "../user.h"
#include "original_art_data.h"

static inline void original_quad(spr_renderer* batch, const float* rect,
                                 float left, float top, float scale, vec4s colour) {
  if (colour.a <= 0 || scale <= 0) return;
  spr_renderer_push(batch, &(spr_instance){
      {{left + rect[2]*scale*.5f, top + rect[3]*scale*.5f, rect[2]*scale, rect[3]*scale}},
      {{rect[0]/2048, rect[1]/2048, rect[2]/2048, rect[3]/2048}}, colour});
}

/* Main.as drawText: advance is not bitmap width; digits have 2x bitmaps.
   ASCII only, just as the source; preserve colour-control bytes and alignment. */
static inline float original_width(const char* text, float size) {
  float w = 0, last = 0;
  for (const unsigned char* p=(const unsigned char*)text; *p; ++p) {
    if (*p == 2) { for(int i=0;i<3 && p[1];++i) ++p; continue; }
    if (*p < 32 || *p > 126) continue;
    const original_glyph* g = &ORIGINAL_GLYPHS[285 + (*p-32)*3];
    w += g->advance; last = g->advance - g->rw;
  }
  return (w-last)*size/52;
}

static inline void original_glyph_run(spr_renderer* batch, const char* text,
    float size, float x, float y, vec3s colour, float alpha, int layer, float max_width) {
  float pen = 0, scale = size/52;
  vec3s initial = colour;
  for (const unsigned char* p=(const unsigned char*)text; *p; ++p) {
    if (*p == 1) { colour = initial; continue; }
    if (*p == 2 && p[1] && p[2] && p[3]) {
      colour = (vec3s){{p[1]*2/255.0f,p[2]*2/255.0f,p[3]*2/255.0f}}; p+=3; continue;
    }
    if (*p < 32 || *p > 126) continue;
    const original_glyph* g = &ORIGINAL_GLYPHS[285 + (*p-32)*3 + layer];
    if (pen + g->advance*scale >= max_width) break;
    const float rect[4]={g->x,g->y,g->w,g->h};
    original_quad(batch, rect, x+pen-g->px*scale*g->scale,
                  y-g->py*scale*g->scale, scale*g->scale,
                  (vec4s){{colour.r,colour.g,colour.b,alpha}});
    pen += g->advance*scale;
  }
}

static inline void original_board_text(renderer* r, const char* text, float size,
    float x, float y, vec3s colour, float alpha) {
  original_glyph_run(r->original_hud, text,size,x,y,colour,alpha,1,1e9f);
  original_glyph_run(r->original_hud_add, text,size,x,y,colour,alpha,0,1e9f);
}

static inline void original_name(renderer* r, const char* text, float size,
    float x, float y, vec3s colour, float alpha) {
  x -= original_width(text,size)*.5f;
  original_glyph_run(r->original_names,text,size,x,y,colour,alpha*.75f,1,1e9f);
  original_glyph_run(r->original_names,text,size,x,y,colour,alpha,0,1e9f);
}

static inline void original_food(renderer* r, float x, float y, float diameter,
    vec3s colour, float alpha, int original_colour) {
  /* Match the other textures' diameter at the orb's 52px half-light disc.
     The radial fringe and shadow retain their baked proportions. */
  float scale = diameter/52.0f;
  const float* shadow = ORIGINAL_FOOD_RECTS[10];
  original_quad(r->original_food_shadow,shadow,x-shadow[2]*scale*.5f,
      y-shadow[3]*scale*.5f,scale,(vec4s){{1,1,1,alpha}});
  /* Gray original has base 160, centre 240: tint reproduces 1.5x highlight. */
  int index=original_colour >= 0 ? original_colour % 10 : 9;
  vec4s tint=original_colour >= 0 ? (vec4s){{1,1,1,alpha}} :
      (vec4s){{colour.r*255/160,colour.g*255/160,colour.b*255/160,alpha}};
  const float* orb = ORIGINAL_FOOD_RECTS[index];
  original_quad(r->original_food_add,orb,x-orb[2]*scale*.5f,
      y-orb[3]*scale*.5f,scale,tint);
}
#endif
