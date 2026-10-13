#include "wyrm_skins.h"

#include <math.h>
#include <string.h>

#include "../user.h"

/*
 * Wyrm skins (OM, 2026-10-13). Each skin is drawn the way a 2D canvas would
 * draw it: paths in screen pixels, a transform stack, solid and gradient
 * paint, stroke widths and round caps. The small canvas below turns that into
 * ImGui triangles on the window's draw list, so every skin keeps its own
 * shapes, colours and motion exactly as designed.
 *
 * Differences from a browser canvas, all small: "lighter" (additive) glows
 * blend normally, a stroke's corners are mitred (round only at its ends), and
 * a body outline is filled as a strip along the body.
 */

#define PI_F 3.14159265358979f
#define TAU_F 6.28318530717959f

typedef struct wcol {
  float r, g, b, a;
} wcol;

typedef struct v2 {
  float x, y;
} v2;

/* One body sample in screen pixels: a = the direction towards the head. */
typedef struct wsk_pt {
  float x, y, a;
} wsk_pt;

static wcol H(uint32_t rgb) {
  wcol c = {(float)((rgb >> 16) & 255) / 255.0f, (float)((rgb >> 8) & 255) / 255.0f,
            (float)(rgb & 255) / 255.0f, 1.0f};
  return c;
}
static wcol HA(uint32_t rgb, float a) {
  wcol c = H(rgb);
  c.a = a;
  return c;
}
static wcol RGBA(float r, float g, float b, float a) {
  wcol c = {r / 255.0f, g / 255.0f, b / 255.0f, a};
  return c;
}
/* CSS hsl(): hue in degrees (rounded, wraps), saturation and lightness in %. */
static wcol HSL(float h, float s, float l, float a) {
  h = fmodf(roundf(h), 360.0f);
  if (h < 0) h += 360.0f;
  s /= 100.0f;
  l /= 100.0f;
  float c = (1.0f - fabsf(2.0f * l - 1.0f)) * s;
  float x = c * (1.0f - fabsf(fmodf(h / 60.0f, 2.0f) - 1.0f));
  float m = l - c / 2.0f, r = 0, g = 0, b = 0;
  if (h < 60) r = c, g = x;
  else if (h < 120) r = x, g = c;
  else if (h < 180) g = c, b = x;
  else if (h < 240) g = x, b = c;
  else if (h < 300) r = x, b = c;
  else r = c, b = x;
  wcol out = {r + m, g + m, b + m, a};
  return out;
}

/* ------------------------------------------------------------------------ */
/* The canvas                                                               */
/* ------------------------------------------------------------------------ */

enum { P_SOLID, P_LINEAR, P_RADIAL };
typedef struct wpaint {
  int kind;
  wcol solid;
  float x0, y0, r0, x1, y1, r1; /* screen pixels */
  int n;
  float at[4];
  wcol c[4];
} wpaint;

typedef struct wstate {
  float m[6]; /* x' = m0 x + m2 y + m4, y' = m1 x + m3 y + m5 */
  float alpha;
  float width;
  bool round;
  wpaint fill, stroke;
} wstate;

#define MAXP 8192
#define MAXSUB 1024
#define MAXRIB 640
#define MAXS 640

static ImDrawList* g_dl;
static ImVec2 g_uv;
static wstate g_st;
static wstate g_stack[32];
static int g_depth;

static ImVec2 g_p[MAXP];
static ImVec2 g_tmp[MAXP];
static int g_pn;
static int g_sa[MAXSUB];  /* first point of each subpath */
static bool g_sc[MAXSUB]; /* closed */
static bool g_sd[MAXSUB]; /* had a drawing op (a lone moveTo draws nothing) */
static int g_sn;
/* The path is exactly one full ellipse (for a radial fill). */
static bool g_ell;
static ImVec2 g_ec;
static float g_erx, g_ery, g_erot;
/* The path is a body outline (filled as a strip). */
static bool g_rib;
static int g_rn;
static ImVec2 g_rl[MAXRIB], g_rr[MAXRIB];

static void tf(float x, float y, ImVec2* o) {
  const float* m = g_st.m;
  o->x = m[0] * x + m[2] * y + m[4];
  o->y = m[1] * x + m[3] * y + m[5];
}
static void sv(void) {
  if (g_depth < 32) g_stack[g_depth++] = g_st;
}
static void rs(void) {
  if (g_depth > 0) g_st = g_stack[--g_depth];
}
static void tr(float x, float y) {
  float* m = g_st.m;
  m[4] += m[0] * x + m[2] * y;
  m[5] += m[1] * x + m[3] * y;
}
static void ro(float a) {
  float c = cosf(a), s = sinf(a);
  float* m = g_st.m;
  float a0 = m[0], a1 = m[1], a2 = m[2], a3 = m[3];
  m[0] = a0 * c + a2 * s;
  m[1] = a1 * c + a3 * s;
  m[2] = -a0 * s + a2 * c;
  m[3] = -a1 * s + a3 * c;
}
static void identity(void) {
  g_st.m[0] = 1, g_st.m[1] = 0, g_st.m[2] = 0, g_st.m[3] = 1, g_st.m[4] = 0, g_st.m[5] = 0;
}

static wpaint solid(wcol c) {
  wpaint p;
  memset(&p, 0, sizeof(p));
  p.kind = P_SOLID;
  p.solid = c;
  return p;
}
static wpaint lin(float x0, float y0, float x1, float y1) {
  wpaint p;
  ImVec2 a, b;
  memset(&p, 0, sizeof(p));
  p.kind = P_LINEAR;
  tf(x0, y0, &a);
  tf(x1, y1, &b);
  p.x0 = a.x, p.y0 = a.y, p.x1 = b.x, p.y1 = b.y;
  return p;
}
static wpaint rad(float x0, float y0, float r0, float x1, float y1, float r1) {
  wpaint p;
  ImVec2 a, b;
  memset(&p, 0, sizeof(p));
  p.kind = P_RADIAL;
  tf(x0, y0, &a);
  tf(x1, y1, &b);
  p.x0 = a.x, p.y0 = a.y, p.r0 = r0, p.x1 = b.x, p.y1 = b.y, p.r1 = r1;
  return p;
}
static void stop(wpaint* p, float at, wcol c) {
  if (p->n < 4) {
    p->at[p->n] = at;
    p->c[p->n] = c;
    p->n++;
  }
}
static void fs(wcol c) { g_st.fill = solid(c); }
static void ss(wcol c) { g_st.stroke = solid(c); }
static void fp(wpaint p) { g_st.fill = p; }
static void sp(wpaint p) { g_st.stroke = p; }
static void lw(float w) { g_st.width = w; }
static void ga(float a) { g_st.alpha = a; }
static void cap(bool round) { g_st.round = round; }

static wcol stops_at(const wpaint* p, float t) {
  wcol none = {0, 0, 0, 0};
  int k;
  if (p->n == 0) return none;
  if (t <= p->at[0]) return p->c[0];
  if (t >= p->at[p->n - 1]) return p->c[p->n - 1];
  for (k = 0; k + 1 < p->n; ++k)
    if (t <= p->at[k + 1]) {
      float span = p->at[k + 1] - p->at[k];
      float f = span > 0 ? (t - p->at[k]) / span : 1.0f;
      wcol a = p->c[k], b = p->c[k + 1], o;
      o.r = a.r + (b.r - a.r) * f;
      o.g = a.g + (b.g - a.g) * f;
      o.b = a.b + (b.b - a.b) * f;
      o.a = a.a + (b.a - a.a) * f;
      return o;
    }
  return p->c[p->n - 1];
}

static wcol paint_at(const wpaint* p, ImVec2 q) {
  float t;
  if (p->kind == P_SOLID) return p->solid;
  if (p->kind == P_LINEAR) {
    float dx = p->x1 - p->x0, dy = p->y1 - p->y0, l = dx * dx + dy * dy;
    t = l > 0 ? ((q.x - p->x0) * dx + (q.y - p->y0) * dy) / l : 0;
  } else {
    /* The canvas's two-circle gradient: the largest t whose circle passes
       through q. */
    float cdx = p->x1 - p->x0, cdy = p->y1 - p->y0, dr = p->r1 - p->r0;
    float qx = q.x - p->x0, qy = q.y - p->y0;
    float a = cdx * cdx + cdy * cdy - dr * dr;
    float b = qx * cdx + qy * cdy + p->r0 * dr;
    float c = qx * qx + qy * qy - p->r0 * p->r0;
    if (fabsf(a) < 1e-6f) {
      t = fabsf(b) > 1e-6f ? c / (2.0f * b) : 0;
    } else {
      float d = b * b - a * c, s, t1, t2;
      if (d < 0) d = 0;
      s = sqrtf(d);
      t1 = (b + s) / a;
      t2 = (b - s) / a;
      t = fmaxf(t1, t2);
      if (p->r0 + t * dr < 0) t = fminf(t1, t2);
    }
  }
  return stops_at(p, t);
}

static ImU32 pack(wcol c, float alpha) {
  ImVec4 v = {fminf(fmaxf(c.r, 0), 1), fminf(fmaxf(c.g, 0), 1),
              fminf(fmaxf(c.b, 0), 1), fminf(fmaxf(c.a * alpha, 0), 1)};
  return igColorConvertFloat4ToU32(v);
}

/* Vertices written since v0 take the gradient's colour where they sit; their
   own alpha (ImGui's anti-aliased fringe is 0) is kept as a factor. */
static void recolor(int v0, const wpaint* p, float alpha) {
  ImDrawVert* v = g_dl->VtxBuffer.Data;
  int n = g_dl->VtxBuffer.Size, i;
  for (i = v0; i < n; ++i) {
    float f = (float)((v[i].col >> 24) & 0xFF) / 255.0f;
    v[i].col = pack(paint_at(p, v[i].pos), alpha * f);
  }
}

static void bp(void) {
  g_pn = 0;
  g_sn = 0;
  g_ell = false;
  g_rib = false;
}
static void push_pt(ImVec2 q) {
  if (g_pn >= MAXP || g_sn == 0) return;
  if (g_pn > g_sa[g_sn - 1]) {
    ImVec2 l = g_p[g_pn - 1];
    if (fabsf(l.x - q.x) < 0.01f && fabsf(l.y - q.y) < 0.01f) return;
  }
  g_p[g_pn++] = q;
}
static void mt(float x, float y) {
  ImVec2 q;
  if (g_sn >= MAXSUB || g_pn >= MAXP) return;
  g_sa[g_sn] = g_pn;
  g_sc[g_sn] = false;
  g_sd[g_sn] = false;
  g_sn++;
  tf(x, y, &q);
  g_p[g_pn++] = q;
  g_ell = false;
  g_rib = false;
}
static void lt(float x, float y) {
  ImVec2 q;
  if (!g_sn) {
    mt(x, y);
    return;
  }
  tf(x, y, &q);
  g_sd[g_sn - 1] = true;
  push_pt(q);
  g_ell = false;
  g_rib = false;
}
static int curve_steps(float len) {
  int k = (int)ceilf(len / 5.0f);
  return k < 2 ? 2 : k > 24 ? 24 : k;
}
static void qt(float cx, float cy, float x, float y) {
  ImVec2 a, c, b;
  int k, s;
  if (!g_sn) mt(cx, cy);
  a = g_p[g_pn - 1];
  tf(cx, cy, &c);
  tf(x, y, &b);
  k = curve_steps(hypotf(c.x - a.x, c.y - a.y) + hypotf(b.x - c.x, b.y - c.y));
  for (s = 1; s <= k; ++s) {
    float t = (float)s / (float)k, u = 1.0f - t;
    ImVec2 q = {u * u * a.x + 2 * u * t * c.x + t * t * b.x,
                u * u * a.y + 2 * u * t * c.y + t * t * b.y};
    push_pt(q);
  }
  g_sd[g_sn - 1] = true;
  g_ell = false;
  g_rib = false;
}
static void bz(float c1x, float c1y, float c2x, float c2y, float x, float y) {
  ImVec2 a, c1, c2, b;
  int k, s;
  if (!g_sn) mt(c1x, c1y);
  a = g_p[g_pn - 1];
  tf(c1x, c1y, &c1);
  tf(c2x, c2y, &c2);
  tf(x, y, &b);
  k = curve_steps(hypotf(c1.x - a.x, c1.y - a.y) + hypotf(c2.x - c1.x, c2.y - c1.y) +
                  hypotf(b.x - c2.x, b.y - c2.y));
  for (s = 1; s <= k; ++s) {
    float t = (float)s / (float)k, u = 1.0f - t;
    ImVec2 q = {u * u * u * a.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * b.x,
                u * u * u * a.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * b.y};
    push_pt(q);
  }
  g_sd[g_sn - 1] = true;
  g_ell = false;
  g_rib = false;
}
static float sweep_of(float a0, float a1, bool ccw) {
  float d;
  if (!ccw) {
    d = a1 - a0;
    if (d >= TAU_F) return TAU_F;
    d = fmodf(d, TAU_F);
    if (d < 0) d += TAU_F;
    return d;
  }
  d = a0 - a1;
  if (d >= TAU_F) return -TAU_F;
  d = fmodf(d, TAU_F);
  if (d < 0) d += TAU_F;
  return -d;
}
/* canvas ellipse() / arc(): a line from the current point to the start. */
static void el(float x, float y, float rx, float ry, float rot, float a0, float a1,
               bool ccw) {
  bool fresh = g_pn == 0;
  bool starts = !g_sn;
  float sweep = sweep_of(a0, a1, ccw);
  float big = fmaxf(fabsf(rx), fabsf(ry));
  int k = (int)ceilf(fabsf(sweep) / TAU_F * (8.0f + big * 1.2f)), s;
  float cr = cosf(rot), sr = sinf(rot);
  if (k < 4) k = 4;
  if (k > 56) k = 56;
  for (s = 0; s <= k; ++s) {
    float th = a0 + sweep * (float)s / (float)k;
    float ux = rx * cosf(th), uy = ry * sinf(th);
    float px = x + ux * cr - uy * sr, py = y + ux * sr + uy * cr;
    if (s == 0 && !g_sn) mt(px, py);
    else lt(px, py);
  }
  if (starts && fabsf(sweep) >= TAU_F - 0.001f && g_sn) {
    /* A whole ellipse is a closed ring, not a line that meets itself. */
    int first = g_sa[g_sn - 1];
    if (g_pn - first > 3 && fabsf(g_p[g_pn - 1].x - g_p[first].x) < 0.05f &&
        fabsf(g_p[g_pn - 1].y - g_p[first].y) < 0.05f)
      g_pn--;
    g_sc[g_sn - 1] = true;
  }
  if (fresh && fabsf(sweep) >= TAU_F - 0.001f) {
    g_ell = true;
    tf(x, y, &g_ec);
    g_erx = fabsf(rx);
    g_ery = fabsf(ry);
    g_erot = rot + atan2f(g_st.m[1], g_st.m[0]);
  }
}
static void ar(float x, float y, float r, float a0, float a1, bool ccw) {
  el(x, y, r, r, 0, a0, a1, ccw);
}
static void circ(float x, float y, float r) { ar(x, y, r, 0, TAU_F, false); }
static void cp(void) {
  if (g_sn) g_sc[g_sn - 1] = true;
}
static void rect(float x, float y, float w, float h) {
  mt(x, y);
  lt(x + w, y);
  lt(x + w, y + h);
  lt(x, y + h);
  cp();
}

static float shoelace(const ImVec2* p, int n) {
  float s = 0;
  int i;
  for (i = 0; i < n; ++i) {
    const ImVec2 a = p[i], b = p[(i + 1) % n];
    s += a.x * b.y - b.x * a.y;
  }
  return s * 0.5f;
}
static bool convex(const ImVec2* p, int n) {
  int sign = 0, i;
  for (i = 0; i < n; ++i) {
    ImVec2 a = p[i], b = p[(i + 1) % n], c = p[(i + 2) % n];
    float cr = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    int s;
    if (fabsf(cr) < 1e-4f) continue;
    s = cr > 0 ? 1 : -1;
    if (!sign) sign = s;
    else if (s != sign) return false;
  }
  return true;
}
static void fill_poly(const ImVec2* p, int n, ImU32 col) {
  float area;
  const ImVec2* q = p;
  int i;
  if (n < 3) return;
  area = shoelace(p, n);
  if (fabsf(area) < 0.01f) return;
  if (area < 0) {
    for (i = 0; i < n; ++i) g_tmp[i] = p[n - 1 - i];
    q = g_tmp;
  }
  if (convex(q, n)) ImDrawList_AddConvexPolyFilled(g_dl, q, n, col);
  else ImDrawList_AddConcavePolyFilled(g_dl, q, n, col);
}

/* A radial gradient over one ellipse: rings, so the colour really changes
   from the middle out. */
static void ring_fill(const wpaint* p, float alpha) {
  const int rings = 8;
  int seg = (int)fminf(fmaxf(fmaxf(g_erx, g_ery) * 0.8f, 12.0f), 40.0f);
  int k, s;
  float cr = cosf(g_erot), sr = sinf(g_erot);
  ImDrawIdx base;
  ImDrawList_PrimReserve(g_dl, seg * 3 + (rings - 1) * seg * 6, 1 + rings * seg);
  base = (ImDrawIdx)g_dl->_VtxCurrentIdx;
  ImDrawList_PrimWriteVtx(g_dl, g_ec, g_uv, pack(paint_at(p, g_ec), alpha));
  for (k = 1; k <= rings; ++k) {
    float f = (float)k / (float)rings;
    for (s = 0; s < seg; ++s) {
      float th = TAU_F * (float)s / (float)seg;
      float ux = g_erx * f * cosf(th), uy = g_ery * f * sinf(th);
      ImVec2 q = {g_ec.x + ux * cr - uy * sr, g_ec.y + ux * sr + uy * cr};
      ImDrawList_PrimWriteVtx(g_dl, q, g_uv, pack(paint_at(p, q), alpha));
    }
  }
  for (s = 0; s < seg; ++s) {
    ImDrawList_PrimWriteIdx(g_dl, base);
    ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)(base + 1 + s));
    ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)(base + 1 + (s + 1) % seg));
  }
  for (k = 1; k < rings; ++k) {
    int r0 = base + 1 + (k - 1) * seg, r1 = base + 1 + k * seg;
    for (s = 0; s < seg; ++s) {
      int s2 = (s + 1) % seg;
      ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)(r0 + s));
      ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)(r0 + s2));
      ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)(r1 + s2));
      ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)(r0 + s));
      ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)(r1 + s2));
      ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)(r1 + s));
    }
  }
}

/* A body outline: one quad per sample along the body. */
static void ribbon_fill(const wpaint* p, float alpha) {
  int n = g_rn, i;
  ImDrawIdx base;
  if (n < 2) return;
  ImDrawList_PrimReserve(g_dl, (n - 1) * 6, n * 2);
  base = (ImDrawIdx)g_dl->_VtxCurrentIdx;
  for (i = 0; i < n; ++i) {
    ImDrawList_PrimWriteVtx(g_dl, g_rl[i], g_uv, pack(paint_at(p, g_rl[i]), alpha));
    ImDrawList_PrimWriteVtx(g_dl, g_rr[i], g_uv, pack(paint_at(p, g_rr[i]), alpha));
  }
  for (i = 0; i + 1 < n; ++i) {
    int a = base + 2 * i, b = a + 1, c = a + 2, d = a + 3;
    ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)a);
    ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)c);
    ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)d);
    ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)a);
    ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)d);
    ImDrawList_PrimWriteIdx(g_dl, (ImDrawIdx)b);
  }
}

static void fl(void) {
  const wpaint* f = &g_st.fill;
  float alpha = g_st.alpha;
  bool grad = f->kind != P_SOLID;
  int v0, s;
  ImU32 col;
  if (g_pn == 0) return;
  if (!grad && f->solid.a * alpha <= 0.002f) return;
  if (grad && f->kind == P_RADIAL && g_ell && g_sn == 1) {
    ring_fill(f, alpha);
    return;
  }
  if (g_rib) {
    ribbon_fill(f, alpha);
    return;
  }
  v0 = g_dl->VtxBuffer.Size;
  col = grad ? pack(H(0xffffff), 1.0f) : pack(f->solid, alpha);
  for (s = 0; s < g_sn; ++s) {
    int start = g_sa[s], end = s + 1 < g_sn ? g_sa[s + 1] : g_pn;
    /* A path that comes back to its start: the repeated point goes. */
    while (end - start > 3 && fabsf(g_p[end - 1].x - g_p[start].x) < 0.05f &&
           fabsf(g_p[end - 1].y - g_p[start].y) < 0.05f)
      end--;
    fill_poly(g_p + start, end - start, col);
  }
  if (grad) recolor(v0, f, alpha);
}

static void sk(void) {
  const wpaint* p = &g_st.stroke;
  float alpha = g_st.alpha, w = g_st.width;
  bool grad = p->kind != P_SOLID;
  int v0, s;
  ImU32 col;
  bool caps;
  if (g_pn == 0) return;
  if (!grad && p->solid.a * alpha <= 0.002f) return;
  v0 = g_dl->VtxBuffer.Size;
  col = grad ? pack(H(0xffffff), 1.0f) : pack(p->solid, alpha);
  /* A see-through stroke gets no round ends: the end disc would show
     through twice. */
  caps = g_st.round && w >= 2.0f && (grad || p->solid.a * alpha >= 0.85f);
  for (s = 0; s < g_sn; ++s) {
    int start = g_sa[s], end = s + 1 < g_sn ? g_sa[s + 1] : g_pn, cnt = end - start;
    if (cnt <= 0) continue;
    if (cnt == 1) {
      if (g_sd[s] && g_st.round)
        ImDrawList_AddCircleFilled(g_dl, g_p[start], w * 0.5f, col, 0);
      continue;
    }
    ImDrawList_AddPolyline(g_dl, g_p + start, cnt, col, g_sc[s] ? ImDrawFlags_Closed : 0, w);
    if (caps && !g_sc[s]) {
      ImDrawList_AddCircleFilled(g_dl, g_p[start], w * 0.5f, col, 0);
      ImDrawList_AddCircleFilled(g_dl, g_p[end - 1], w * 0.5f, col, 0);
    }
  }
  if (grad) recolor(v0, p, alpha);
}

static void fill_rect(float x, float y, float w, float h) {
  bp();
  rect(x, y, w, h);
  fl();
}
static void stroke_rect(float x, float y, float w, float h) {
  bp();
  rect(x, y, w, h);
  sk();
}

/* ------------------------------------------------------------------------ */
/* Shared helpers                                                           */
/* ------------------------------------------------------------------------ */

static float W[MAXS];
static float OFF[MAXS];

static float hash(double i) {
  double x = sin(i * 12.9898 + 78.233) * 43758.5453;
  return (float)(x - floor(x));
}
static v2 side2(wsk_pt s, float sd, float d) {
  float a = s.a + sd * PI_F / 2;
  v2 p = {s.x + cosf(a) * d, s.y + sinf(a) * d};
  return p;
}
/* The closed body outline, width W[i] either side; filled as a strip. */
static void outline(const wsk_pt* S, int n) {
  int i;
  v2 p;
  bp();
  for (i = 0; i < n; ++i) {
    p = side2(S[i], -1, W[i]);
    if (i) lt(p.x, p.y);
    else mt(p.x, p.y);
  }
  for (i = n - 1; i >= 0; --i) {
    p = side2(S[i], 1, W[i]);
    lt(p.x, p.y);
  }
  cp();
  g_rn = n < MAXRIB ? n : MAXRIB;
  for (i = 0; i < g_rn; ++i) {
    v2 l = side2(S[i], -1, W[i]), r = side2(S[i], 1, W[i]);
    tf(l.x, l.y, &g_rl[i]);
    tf(r.x, r.y, &g_rr[i]);
  }
  g_rib = true;
}
/* A polyline along the body, from..to-1; off = OFF[i] sideways or none. */
static void line(const wsk_pt* S, int from, int to, bool off) {
  int i;
  bp();
  for (i = from; i < to; ++i) {
    v2 p = off ? side2(S[i], 1, OFF[i]) : (v2){S[i].x, S[i].y};
    if (i > from) lt(p.x, p.y);
    else mt(p.x, p.y);
  }
}
static void taper(int n, float a, float b) {
  int i;
  for (i = 0; i < n; ++i) W[i] = a + (b - a) * ((float)i / (float)(n - 1 > 1 ? n - 1 : 1));
}
static void glow_dot(float x, float y, float r, float cr, float cg, float cb, float a) {
  wpaint g = rad(x, y, 0, x, y, r);
  stop(&g, 0, RGBA(cr, cg, cb, a));
  stop(&g, 1, RGBA(cr, cg, cb, 0));
  fp(g);
  bp();
  circ(x, y, r);
  fl();
}
/* Drifting particles: smoke, fire, frost, gas. */
static void puff(float x0, float y0, float ang, float rr, float t, int n, float spread,
                 float cr, float cg, float cb, float rate, float dist) {
  int k;
  for (k = 0; k < n; ++k) {
    float f = fmodf(t * rate + (float)k / n, 1.0f);
    float d = rr * (0.5f + f * dist);
    float sw = (hash(k + floorf(t * rate + (float)k / n) * 7) - 0.5f) * spread;
    glow_dot(x0 + cosf(ang + sw) * d, y0 + sinf(ang + sw) * d, rr * (0.35f + f * 0.9f), cr,
             cg, cb, 0.75f * (1 - f));
  }
}
/* Small walking legs at the given sample indexes. */
static void limbs(const wsk_pt* S, int n, float rr, float t, int boost, const int* at,
                  int count, wcol col, const wcol* claw, float len) {
  int k, sd, q;
  for (k = 0; k < count; ++k) {
    int idx = at[k] < n - 1 ? at[k] : n - 1;
    wsk_pt s;
    if (idx < 0) continue;
    s = S[idx];
    for (sd = -1; sd <= 1; sd += 2) {
      float st = sinf(t * (boost ? 12 : 6) + k * PI_F + (sd > 0 ? PI_F : 0)) * 0.45f;
      v2 b = side2(s, sd, rr * 0.6f);
      float a1 = s.a + sd * PI_F / 2 - sd * st;
      float kx = b.x + cosf(a1) * rr * len, ky = b.y + sinf(a1) * rr * len;
      float a2 = s.a + sd * 0.5f;
      float fx = kx + cosf(a2) * rr * len * 0.6f, fy = ky + sinf(a2) * rr * len * 0.6f;
      ss(col);
      lw(fmaxf(1.2f, rr * 0.26f));
      bp();
      mt(b.x, b.y);
      lt(kx, ky);
      lt(fx, fy);
      sk();
      if (claw) {
        ss(*claw);
        lw(fmaxf(1, rr * 0.08f));
        for (q = -1; q <= 1; ++q) {
          float qa = a2 + q * 0.45f;
          bp();
          mt(fx, fy);
          lt(fx + cosf(qa) * rr * 0.25f, fy + sinf(qa) * rr * 0.25f);
          sk();
        }
      }
    }
  }
}

/* ------------------------------------------------------------------------ */
/* Creatures. S: samples head to tail; rr: body radius in px.               */
/* ------------------------------------------------------------------------ */

static void centipede(const wsk_pt* S, int n, float rr, float t, int boost, float alpha,
                      float look) {
  float legW = fmaxf(1, rr * 0.13f), ph = t * (boost ? 15 : 8);
  int i, side, bq;
  if (n < 2) return;
  cap(true);
  {
    wsk_pt L = S[n - 1];
    float ta = L.a + PI_F;
    ss(H(0xb83a1c));
    lw(fmaxf(1, rr * 0.1f));
    ga(alpha);
    for (side = -1; side <= 1; side += 2) {
      float ca = ta + side * 0.32f, len = rr * 3.6f, w = sinf(ph * 0.3f + side) * 0.12f;
      bp();
      mt(L.x, L.y);
      qt(L.x + cosf(ca) * len * 0.5f, L.y + sinf(ca) * len * 0.5f,
         L.x + cosf(ca + w + side * 0.15f) * len, L.y + sinf(ca + w + side * 0.15f) * len);
      sk();
    }
  }
  for (i = 1; i < n; ++i) {
    wsk_pt s = S[i];
    for (side = -1; side <= 1; side += 2) {
      float sw = sinf(ph - i * 0.9f + (side > 0 ? PI_F : 0)) * 0.32f;
      float nx = cosf(s.a + side * PI_F / 2), ny = sinf(s.a + side * PI_F / 2);
      float bx = s.x + nx * rr * 0.75f, by = s.y + ny * rr * 0.75f;
      float a1 = s.a + side * (PI_F / 2 + 0.35f) + side * sw, a2 = a1 + side * 0.55f;
      float kx = bx + cosf(a1) * rr * 0.7f, ky = by + sinf(a1) * rr * 0.7f;
      float fx = kx + cosf(a2) * rr * 0.75f, fy = ky + sinf(a2) * rr * 0.75f;
      ss(H(0xd9822b));
      lw(legW * 1.25f);
      bp();
      mt(bx, by);
      lt(kx, ky);
      sk();
      ss(H(0xffc15c));
      lw(legW);
      bp();
      mt(kx, ky);
      lt(fx, fy);
      sk();
    }
  }
  for (i = n - 1; i >= 1; --i) {
    wsk_pt s = S[i];
    float k2 = 1 - ((float)i / n) * 0.35f;
    sv();
    tr(s.x, s.y);
    ro(s.a);
    bp();
    el(0, 0, rr * 0.78f, rr * 0.92f * k2, 0, 0, TAU_F, false);
    fs(H(0x26262b));
    fl();
    lw(fmaxf(1, rr * 0.08f));
    ss(HA(0x000000, .55f));
    sk();
    bp();
    el(-rr * 0.05f, -rr * 0.18f * k2, rr * 0.55f, rr * 0.45f * k2, 0, 0, TAU_F, false);
    fs(RGBA(90, 90, 100, .35f));
    fl();
    bp();
    ar(-rr * 0.12f, 0, rr * 0.34f * k2, -0.9f, 0.9f, false);
    ss(RGBA(235, 235, 235, .8f));
    lw(fmaxf(1, rr * 0.12f));
    sk();
    rs();
  }
  {
    wsk_pt Hd = S[0];
    float lk = fmaxf(-1.1f, fminf(1.1f, look));
    float snap;
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    for (side = -1; side <= 1; side += 2) {
      float wig = sinf(t * 3.1f + side * 1.7f) * 0.2f + sinf(t * 7.3f + side) * 0.05f;
      int beads = 16;
      for (bq = 0; bq <= beads; ++bq) {
        float u = (float)bq / beads, iu = 1 - u;
        float ax = iu * iu * iu * rr * 0.75f + 3 * iu * iu * u * rr * 2.3f +
                   3 * iu * u * u * rr * 3.6f + u * u * u * rr * 5;
        float ay = side * (iu * iu * iu * rr * 0.32f + 3 * iu * iu * u * rr * (0.95f + wig) +
                           3 * iu * u * u * rr * (1.8f + wig * 2) +
                           u * u * u * rr * (2.7f + wig * 3.2f));
        bp();
        circ(ax, ay, fmaxf(0.6f, rr * (0.13f - u * 0.08f)));
        fs(bq % 2 ? H(0xe0935c) : H(0xa8391a));
        fl();
      }
    }
    snap = boost ? fabsf(sinf(t * 9)) : 0.25f + sinf(t * 1.6f) * 0.08f;
    for (side = -1; side <= 1; side += 2) {
      float open = side * (0.25f + snap * 0.45f);
      wpaint fg;
      sv();
      tr(rr * 0.55f, side * rr * 0.55f);
      ro(-open * 0.6f);
      bp();
      mt(0, -side * rr * 0.18f);
      qt(rr * 1.05f, side * rr * 0.1f, rr * 0.95f, -side * rr * 0.5f);
      qt(rr * 0.75f, side * rr * 0.05f, 0, side * rr * 0.18f);
      cp();
      fg = lin(0, 0, rr, 0);
      stop(&fg, 0, H(0x6b1407));
      stop(&fg, 0.7f, H(0x2a0603));
      stop(&fg, 1, H(0x050101));
      fp(fg);
      fl();
      lw(fmaxf(0.8f, rr * 0.05f));
      ss(HA(0x000000, .6f));
      sk();
      bp();
      circ(rr * 0.78f, -side * rr * 0.28f, fmaxf(0.6f, rr * 0.05f));
      fs(RGBA(255, 220, 200, .55f));
      fl();
      rs();
    }
    bp();
    mt(-rr * 0.75f, -rr * 0.98f);
    qt(rr * 0.35f, -rr * 1.12f, rr * 1.05f, -rr * 0.55f);
    qt(rr * 1.35f, 0, rr * 1.05f, rr * 0.55f);
    qt(rr * 0.35f, rr * 1.12f, -rr * 0.75f, rr * 0.98f);
    qt(-rr * 1.02f, 0, -rr * 0.75f, -rr * 0.98f);
    cp();
    {
      wpaint gr = lin(-rr, -rr, rr, rr);
      stop(&gr, 0, H(0x7a1d0c));
      stop(&gr, 0.45f, H(0xc2381a));
      stop(&gr, 1, H(0x5a1206));
      fp(gr);
    }
    fl();
    lw(fmaxf(1, rr * 0.08f));
    ss(RGBA(20, 0, 0, .7f));
    sk();
    bp();
    mt(-rr * 0.7f, 0);
    lt(rr * 0.95f, 0);
    ss(RGBA(40, 5, 0, .55f));
    lw(fmaxf(0.8f, rr * 0.06f));
    sk();
    bp();
    el(rr * 0.1f, -rr * 0.42f, rr * 0.55f, rr * 0.16f, -0.12f, 0, TAU_F, false);
    fs(RGBA(255, 200, 170, .28f));
    fl();
    for (side = -1; side <= 1; side += 2) {
      float ex = rr * 0.45f, ey = side * rr * 0.5f, er = rr * 0.3f;
      float pr = er * 0.55f, pd = er - pr - fmaxf(0.3f, rr * 0.02f);
      float px = ex + cosf(lk) * pd, py = ey + sinf(lk) * pd;
      bp();
      circ(ex, ey, er);
      fs(H(0xffffff));
      fl();
      lw(fmaxf(0.8f, rr * 0.06f));
      ss(H(0x1a0503));
      sk();
      bp();
      circ(px, py, pr);
      fs(H(0x0b0b0e));
      fl();
      bp();
      circ(px - pr * 0.35f, py - pr * 0.35f, pr * 0.3f);
      fs(RGBA(255, 255, 255, .85f));
      fl();
    }
    rs();
  }
}

static void dragon(const wsk_pt* S, int n, float rr, float t, int boost, float alpha) {
  int i, side, k, f;
  int legAt[2];
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.12f ? 0.8f + u * 1.6f : 1 - (u - 0.12f) * 0.72f);
  }
  cap(true);
  legAt[0] = (int)fmaxf(2, roundf(n * 0.14f));
  legAt[1] = (int)fmaxf(3, roundf(n * 0.42f));
  for (k = 0; k < 2; ++k) {
    int li = legAt[k] < n - 1 ? legAt[k] : n - 1;
    wsk_pt s = S[li];
    for (side = -1; side <= 1; side += 2) {
      float st = sinf(t * (boost ? 12 : 6) + k * PI_F + (side > 0 ? PI_F : 0)) * 0.45f;
      float Nx = cosf(s.a + side * PI_F / 2), Ny = sinf(s.a + side * PI_F / 2);
      float w = W[li];
      float bx = s.x + Nx * w * 0.7f, by = s.y + Ny * w * 0.7f;
      float a1 = s.a + side * (PI_F / 2) + st * side * -1;
      float kx = bx + cosf(a1) * rr * 0.9f, ky = by + sinf(a1) * rr * 0.9f;
      float a2 = s.a + side * 0.5f;
      float fx = kx + cosf(a2) * rr * 0.55f, fy = ky + sinf(a2) * rr * 0.55f;
      int cl;
      ss(H(0x5e1010));
      lw(fmaxf(1.5f, rr * 0.34f));
      bp();
      mt(bx, by);
      lt(kx, ky);
      lt(fx, fy);
      sk();
      ss(H(0xf3d27a));
      lw(fmaxf(1, rr * 0.09f));
      for (cl = -1; cl <= 1; ++cl) {
        float ca = a2 + cl * 0.45f;
        bp();
        mt(fx, fy);
        lt(fx + cosf(ca) * rr * 0.3f, fy + sinf(ca) * rr * 0.3f);
        sk();
      }
    }
  }
  outline(S, n);
  fs(H(0x8f1d17));
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(RGBA(20, 0, 0, .7f));
  sk();
  ss(RGBA(40, 0, 0, .45f));
  lw(fmaxf(1, rr * 0.08f));
  for (i = 2; i < n - 1; ++i) {
    wsk_pt s = S[i];
    float ww = W[i];
    int r2;
    for (r2 = -1; r2 <= 1; r2 += 2) {
      sv();
      tr(s.x + cosf(s.a + PI_F / 2) * r2 * ww * 0.45f, s.y + sinf(s.a + PI_F / 2) * r2 * ww * 0.45f);
      ro(s.a);
      bp();
      ar(-ww * 0.1f, 0, ww * 0.32f, -1.1f, 1.1f, false);
      sk();
      rs();
    }
  }
  bp();
  for (i = 1; i < n; ++i) {
    if (i > 1) lt(S[i].x, S[i].y);
    else mt(S[i].x, S[i].y);
  }
  ss(RGBA(242, 193, 78, .55f));
  lw(fmaxf(1, rr * 0.12f));
  sk();
  fs(H(0xf2c14e));
  for (i = 2; i < n - 1; i += 2) {
    wsk_pt s = S[i];
    float sz = W[i] * 0.75f, ba = s.a + PI_F;
    bp();
    mt(s.x + cosf(s.a + PI_F / 2) * sz * 0.35f, s.y + sinf(s.a + PI_F / 2) * sz * 0.35f);
    lt(s.x + cosf(ba) * sz, s.y + sinf(ba) * sz);
    lt(s.x - cosf(s.a + PI_F / 2) * sz * 0.35f, s.y - sinf(s.a + PI_F / 2) * sz * 0.35f);
    cp();
    fl();
  }
  {
    wsk_pt L = S[n - 1];
    float ta = L.a + PI_F, spd = rr * 0.9f;
    bp();
    mt(L.x, L.y);
    lt(L.x + cosf(ta + 0.9f) * spd * 0.6f, L.y + sinf(ta + 0.9f) * spd * 0.6f);
    lt(L.x + cosf(ta) * spd * 1.4f, L.y + sinf(ta) * spd * 1.4f);
    lt(L.x + cosf(ta - 0.9f) * spd * 0.6f, L.y + sinf(ta - 0.9f) * spd * 0.6f);
    cp();
    fs(H(0xb8321f));
    fl();
    ss(RGBA(20, 0, 0, .7f));
    sk();
  }
  {
    int wi = (int)fmaxf(1, roundf(n * 0.1f));
    wsk_pt W0 = S[wi < n - 1 ? wi : n - 1];
    float flap = 0.72f + 0.28f * sinf(t * (boost ? 9 : 4));
    for (side = -1; side <= 1; side += 2) {
      float Nx = cosf(W0.a + side * PI_F / 2), Ny = sinf(W0.a + side * PI_F / 2);
      float sx = W0.x + Nx * rr * 0.6f, sy = W0.y + Ny * rr * 0.6f, span = rr * 5.2f * flap;
      float arm = W0.a + side * (PI_F / 2 + 0.25f);
      float ex = sx + cosf(arm) * span, ey = sy + sinf(arm) * span;
      float tips[3][2], back = W0.a + PI_F;
      float rootx, rooty;
      for (f = 0; f < 3; ++f) {
        float fa = arm + side * (0.5f + f * 0.5f), fl2 = span * (1.05f - f * 0.12f);
        tips[f][0] = ex + cosf(fa) * fl2 * 0.55f;
        tips[f][1] = ey + sinf(fa) * fl2 * 0.55f;
      }
      rootx = W0.x + cosf(back) * rr * 2.6f + Nx * rr * 0.4f;
      rooty = W0.y + sinf(back) * rr * 2.6f + Ny * rr * 0.4f;
      bp();
      mt(sx, sy);
      lt(ex, ey);
      for (f = 0; f < 3; ++f) {
        float mx = f ? tips[f - 1][0] : ex, my = f ? tips[f - 1][1] : ey;
        qt((mx + tips[f][0]) / 2 + cosf(back) * rr * 0.4f, (my + tips[f][1]) / 2 + sinf(back) * rr * 0.4f,
           tips[f][0], tips[f][1]);
      }
      qt((tips[2][0] + rootx) / 2 + cosf(back) * rr * 0.3f, (tips[2][1] + rooty) / 2 + sinf(back) * rr * 0.3f,
         rootx, rooty);
      cp();
      ga(alpha * 0.9f);
      fs(H(0x5c1212));
      fl();
      ga(alpha);
      ss(H(0x2a0505));
      lw(fmaxf(1, rr * 0.14f));
      bp();
      mt(sx, sy);
      lt(ex, ey);
      sk();
      lw(fmaxf(1, rr * 0.08f));
      for (f = 0; f < 3; ++f) {
        bp();
        mt(ex, ey);
        lt(tips[f][0], tips[f][1]);
        sk();
      }
    }
  }
  {
    wsk_pt Hd = S[0];
    wpaint hg2;
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    if (boost) {
      for (k = 0; k < 7; ++k) {
        float fl2 = fmodf(t * 9 + k * 0.37f, 1.0f), fx2 = rr * (1.6f + fl2 * 5);
        float fy2 = sinf(t * 23 + k * 2.1f) * rr * fl2 * 0.9f, fr = rr * (0.35f + fl2 * 1.1f);
        wpaint fg = rad(fx2, fy2, 0, fx2, fy2, fr);
        stop(&fg, 0, RGBA(255, 240, 170, 0.9f - fl2 * 0.6f));
        stop(&fg, 0.5f, RGBA(255, 120, 30, 0.7f - fl2 * 0.5f));
        stop(&fg, 1, RGBA(200, 30, 0, 0));
        fp(fg);
        bp();
        circ(fx2, fy2, fr);
        fl();
      }
    }
    for (side = -1; side <= 1; side += 2) {
      bp();
      mt(-rr * 0.2f, side * rr * 0.45f);
      qt(-rr * 0.9f, side * rr * 1.0f, -rr * 1.55f, side * rr * 0.75f);
      ss(H(0xe9d8a6));
      lw(fmaxf(1.2f, rr * 0.2f));
      sk();
    }
    hg2 = lin(-rr, 0, rr * 1.4f, 0);
    stop(&hg2, 0, H(0x7d1812));
    stop(&hg2, 1, H(0xb52a1d));
    bp();
    el(0, 0, rr * 0.95f, rr * 0.8f, 0, 0, TAU_F, false);
    fp(hg2);
    fl();
    bp();
    el(rr * 0.85f, 0, rr * 0.7f, rr * 0.45f, 0, 0, TAU_F, false);
    fl();
    lw(fmaxf(1, rr * 0.09f));
    ss(RGBA(20, 0, 0, .7f));
    sk();
    fs(H(0x2a0505));
    for (side = -1; side <= 1; side += 2) {
      bp();
      circ(rr * 1.35f, side * rr * 0.18f, fmaxf(0.8f, rr * 0.07f));
      fl();
    }
    for (side = -1; side <= 1; side += 2) {
      bp();
      el(rr * 0.2f, side * rr * 0.42f, rr * 0.22f, rr * 0.13f, side * 0.3f, 0, TAU_F, false);
      fs(H(0xffd23f));
      fl();
      bp();
      el(rr * 0.22f, side * rr * 0.42f, rr * 0.05f, rr * 0.11f, 0, 0, TAU_F, false);
      fs(H(0x1a0000));
      fl();
    }
    rs();
  }
}

static void skeleton(const wsk_pt* S, int n, float rr, float t, int boost, float alpha) {
  const wcol BONE = H(0xece6d6), SHADE = H(0xb9b09a), DARK = HA(0x000000, .55f);
  int i, side, cage, hip, tq;
  wsk_pt s;
  (void)alpha;
  if (n < 3) return;
  cage = (int)fmaxf(3, roundf(n * 0.38f));
  hip = cage + 2 < n - 2 ? cage + 2 : n - 2;
  cap(true);
#define BONE_SEG(x1, y1, x2, y2, w)                                  \
  do {                                                               \
    float bw_ = (w);                                                 \
    ss(DARK);                                                        \
    lw(bw_ + fmaxf(1, bw_ * 0.35f));                                 \
    bp();                                                            \
    mt(x1, y1);                                                      \
    lt(x2, y2);                                                      \
    sk();                                                            \
    ss(BONE);                                                        \
    lw(bw_);                                                         \
    bp();                                                            \
    mt(x1, y1);                                                      \
    lt(x2, y2);                                                      \
    sk();                                                            \
    fs(BONE);                                                        \
    bp();                                                            \
    circ(x2, y2, bw_ * 0.62f);                                       \
    fl();                                                            \
  } while (0)
  for (i = 2; i < cage; ++i) {
    float u = (float)(i - 1) / (cage - 1), len = rr * (1.0f + sinf(u * PI_F) * 0.75f);
    float rw = fmaxf(1, rr * 0.2f), rattle = boost ? sinf(t * 40 + i) * 0.06f : 0;
    s = S[i];
    for (side = -1; side <= 1; side += 2) {
      float a0 = s.a + side * (PI_F / 2 - 0.15f + rattle), a1 = s.a + side * (PI_F / 2 + 0.75f);
      float mx = s.x + cosf(a0) * len * 0.6f, my = s.y + sinf(a0) * len * 0.6f;
      float ex = mx + cosf(a1) * len * 0.55f, ey = my + sinf(a1) * len * 0.55f;
      ss(DARK);
      lw(rw + fmaxf(1, rw * 0.4f));
      bp();
      mt(s.x, s.y);
      qt(mx, my, ex, ey);
      sk();
      ss(BONE);
      lw(rw);
      bp();
      mt(s.x, s.y);
      qt(mx, my, ex, ey);
      sk();
    }
  }
  s = S[hip];
  for (side = -1; side <= 1; side += 2) {
    float st = sinf(t * (boost ? 12 : 6) + (side > 0 ? PI_F : 0)) * 0.5f;
    float ha = s.a + side * (PI_F / 2 + 0.2f) - side * st;
    float kx = s.x + cosf(ha) * rr * 1.1f, ky = s.y + sinf(ha) * rr * 1.1f;
    float sa = s.a + PI_F + side * 0.3f + st * 0.3f;
    float fx = kx + cosf(sa) * rr * 0.95f, fy = ky + sinf(sa) * rr * 0.95f;
    BONE_SEG(s.x, s.y, kx, ky, fmaxf(1.2f, rr * 0.24f));
    BONE_SEG(kx, ky, fx, fy, fmaxf(1, rr * 0.2f));
    for (tq = -1; tq <= 1; ++tq) {
      float ta = sa + tq * 0.4f;
      BONE_SEG(fx, fy, fx + cosf(ta) * rr * 0.3f, fy + sinf(ta) * rr * 0.3f, fmaxf(1, rr * 0.09f));
    }
  }
  s = S[2 < n - 1 ? 2 : n - 1];
  for (side = -1; side <= 1; side += 2) {
    float st2 = sinf(t * (boost ? 12 : 6) + (side > 0 ? 0 : PI_F)) * 0.5f;
    float aa = s.a + side * (PI_F / 2 - 0.1f) - side * st2;
    float ax = s.x + cosf(aa) * rr * 0.95f, ay = s.y + sinf(aa) * rr * 0.95f;
    float fa2 = s.a + side * 0.35f;
    float hx2 = ax + cosf(fa2) * rr * 0.75f, hy2 = ay + sinf(fa2) * rr * 0.75f;
    BONE_SEG(s.x, s.y, ax, ay, fmaxf(1, rr * 0.2f));
    BONE_SEG(ax, ay, hx2, hy2, fmaxf(1, rr * 0.16f));
    for (tq = -1; tq <= 1; ++tq) {
      float fa3 = fa2 + tq * 0.45f;
      BONE_SEG(hx2, hy2, hx2 + cosf(fa3) * rr * 0.25f, hy2 + sinf(fa3) * rr * 0.25f,
               fmaxf(1, rr * 0.08f));
    }
  }
#undef BONE_SEG
  sv();
  tr(S[hip].x, S[hip].y);
  ro(S[hip].a);
  bp();
  el(0, 0, rr * 0.55f, rr * 0.9f, 0, 0, TAU_F, false);
  fs(BONE);
  fl();
  lw(fmaxf(1, rr * 0.08f));
  ss(DARK);
  sk();
  fs(RGBA(40, 30, 20, .65f));
  for (side = -1; side <= 1; side += 2) {
    bp();
    el(-rr * 0.05f, side * rr * 0.42f, rr * 0.2f, rr * 0.25f, 0, 0, TAU_F, false);
    fl();
  }
  rs();
  bp();
  for (i = 0; i < n; ++i) {
    if (i) lt(S[i].x, S[i].y);
    else mt(S[i].x, S[i].y);
  }
  ss(DARK);
  lw(fmaxf(1.5f, rr * 0.2f));
  sk();
  ss(SHADE);
  lw(fmaxf(1, rr * 0.12f));
  sk();
  for (i = n - 1; i >= 1; --i) {
    float k = i < cage ? 1 : fmaxf(0.3f, 1 - (float)(i - cage) / (n - cage) * 0.7f);
    s = S[i];
    sv();
    tr(s.x, s.y);
    ro(s.a);
    bp();
    el(0, 0, rr * 0.42f * k, rr * 0.3f * k, 0, 0, TAU_F, false);
    fs(BONE);
    fl();
    lw(fmaxf(1, rr * 0.07f));
    ss(DARK);
    sk();
    bp();
    mt(-rr * 0.1f * k, -rr * 0.5f * k);
    lt(-rr * 0.1f * k, rr * 0.5f * k);
    ss(SHADE);
    lw(fmaxf(1, rr * 0.12f * k));
    sk();
    rs();
  }
  {
    wsk_pt Hd = S[0];
    wpaint sg;
    float glow;
    int tt;
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    bp();
    mt(rr * 0.55f, -rr * 0.42f);
    lt(rr * 1.25f, -rr * 0.22f);
    lt(rr * 1.25f, rr * 0.22f);
    lt(rr * 0.55f, rr * 0.42f);
    cp();
    fs(SHADE);
    fl();
    lw(fmaxf(1, rr * 0.07f));
    ss(DARK);
    sk();
    ss(RGBA(40, 30, 20, .7f));
    lw(fmaxf(1, rr * 0.06f));
    for (tt = 0; tt < 4; ++tt) {
      float tx = rr * (0.7f + tt * 0.15f);
      bp();
      mt(tx, -rr * 0.3f);
      lt(tx, rr * 0.3f);
      sk();
    }
    bp();
    el(0, 0, rr * 0.9f, rr * 0.82f, 0, 0, TAU_F, false);
    sg = rad(-rr * 0.2f, -rr * 0.2f, rr * 0.1f, 0, 0, rr * 0.9f);
    stop(&sg, 0, H(0xfffaf0));
    stop(&sg, 1, H(0xcfc6ae));
    fp(sg);
    fl();
    lw(fmaxf(1, rr * 0.08f));
    ss(DARK);
    sk();
    glow = boost ? 0.75f + 0.25f * sinf(t * 20) : 0;
    for (side = -1; side <= 1; side += 2) {
      bp();
      el(rr * 0.25f, side * rr * 0.36f, rr * 0.26f, rr * 0.22f, 0, 0, TAU_F, false);
      fs(H(0x1a1510));
      fl();
      if (glow > 0) {
        wpaint eg = rad(rr * 0.25f, side * rr * 0.36f, 0, rr * 0.25f, side * rr * 0.36f, rr * 0.45f);
        stop(&eg, 0, RGBA(160, 255, 120, glow));
        stop(&eg, 1, RGBA(60, 255, 60, 0));
        fp(eg);
        bp();
        circ(rr * 0.25f, side * rr * 0.36f, rr * 0.45f);
        fl();
      }
    }
    bp();
    mt(rr * 0.62f, -rr * 0.08f);
    lt(rr * 0.78f, 0);
    lt(rr * 0.62f, rr * 0.08f);
    cp();
    fs(H(0x1a1510));
    fl();
    ss(RGBA(60, 50, 40, .45f));
    lw(fmaxf(1, rr * 0.05f));
    bp();
    mt(-rr * 0.55f, -rr * 0.1f);
    lt(-rr * 0.3f, -rr * 0.02f);
    lt(-rr * 0.2f, -rr * 0.18f);
    sk();
    rs();
  }
}

static void chinese(const wsk_pt* S, int n, float rr, float t, int boost, float alpha) {
  int i, sd, r2;
  int legs[2];
  const wcol claw = H(0xfff3c4);
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.1f ? 0.8f + u * 2 : 1 - (u - 0.1f) * 0.7f);
  }
  cap(true);
  legs[0] = (int)roundf(n * 0.12f);
  legs[1] = (int)roundf(n * 0.45f);
  limbs(S, n, rr, t, boost, legs, 2, H(0xb8860b), &claw, 0.85f);
  outline(S, n);
  fs(H(0xe0ad2a));
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(H(0x6b4400));
  sk();
  ss(RGBA(120, 70, 0, .55f));
  lw(fmaxf(1, rr * 0.08f));
  for (i = 2; i < n - 1; ++i) {
    wsk_pt s = S[i];
    float w = W[i];
    for (r2 = -1; r2 <= 1; r2 += 2) {
      v2 p = side2(s, r2, w * 0.45f);
      sv();
      tr(p.x, p.y);
      ro(s.a);
      bp();
      ar(-w * 0.1f, 0, w * 0.33f, -1.1f, 1.1f, false);
      sk();
      rs();
    }
  }
  line(S, 1, n, false);
  ss(RGBA(255, 245, 190, .7f));
  lw(fmaxf(1, rr * 0.16f));
  sk();
  if (boost) {
    for (i = 1; i < n; ++i) {
      float sh = sinf(i * 0.45f - t * 12);
      if (sh > 0.7f) glow_dot(S[i].x, S[i].y, W[i] * 1.3f, 255, 240, 160, (sh - 0.7f) * 2);
    }
  }
  ss(H(0xd8262a));
  lw(fmaxf(1, rr * 0.14f));
  for (i = 2; i < n - 2; i += 2) {
    wsk_pt s = S[i];
    float wv = sinf(t * 6 - i * 0.6f) * 0.35f, ml = W[i] * 1.1f;
    for (sd = -1; sd <= 1; sd += 2) {
      float a = s.a + PI_F + sd * (0.5f + wv * sd);
      bp();
      mt(s.x, s.y);
      qt(s.x + cosf(a + sd * 0.4f) * ml * 0.6f, s.y + sinf(a + sd * 0.4f) * ml * 0.6f,
         s.x + cosf(a) * ml, s.y + sinf(a) * ml);
      sk();
    }
  }
  {
    wsk_pt L = S[n - 1];
    float ta = L.a + PI_F;
    for (i = 0; i < 5; ++i) {
      float fa = ta + (i - 2) * 0.3f + sinf(t * 7 + i) * 0.1f, fl2 = rr * (1.4f + (i % 2) * 0.5f);
      bp();
      mt(L.x, L.y);
      qt(L.x + cosf(fa + 0.3f) * fl2 * 0.6f, L.y + sinf(fa + 0.3f) * fl2 * 0.6f,
         L.x + cosf(fa) * fl2, L.y + sinf(fa) * fl2);
      ss(i % 2 ? H(0xff8a1f) : H(0xd8262a));
      lw(fmaxf(1, rr * 0.2f));
      sk();
    }
  }
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    for (sd = -1; sd <= 1; sd += 2) {
      float ww;
      for (i = 0; i < 4; ++i) {
        float ma = PI_F + sd * (0.6f + i * 0.35f) + sinf(t * 5 + i) * 0.1f;
        bp();
        mt(-rr * 0.2f, sd * rr * 0.4f);
        lt(cosf(ma) * rr * 1.5f, sinf(ma) * rr * 1.5f);
        ss(H(0xd8262a));
        lw(fmaxf(1, rr * 0.22f));
        sk();
      }
      bp();
      mt(-rr * 0.1f, sd * rr * 0.35f);
      lt(-rr * 1.1f, sd * rr * 0.9f);
      mt(-rr * 0.6f, sd * rr * 0.62f);
      lt(-rr * 0.8f, sd * rr * 1.05f);
      ss(H(0xfff3c4));
      lw(fmaxf(1, rr * 0.13f));
      sk();
      ww = sinf(t * 4 + sd) * 0.4f;
      bp();
      mt(rr * 1.2f, sd * rr * 0.25f);
      bz(rr * 1.6f, sd * rr * (1 + ww), rr * 0.4f, sd * rr * (1.8f - ww), -rr * 0.6f, sd * rr * (2.4f + ww));
      ss(H(0x8a1010));
      lw(fmaxf(1, rr * 0.07f));
      sk();
    }
    bp();
    el(0, 0, rr * 0.95f, rr * 0.8f, 0, 0, TAU_F, false);
    fs(H(0xe8b832));
    fl();
    bp();
    el(rr * 0.85f, 0, rr * 0.6f, rr * 0.5f, 0, 0, TAU_F, false);
    fl();
    lw(fmaxf(1, rr * 0.08f));
    ss(H(0x6b4400));
    sk();
    for (sd = -1; sd <= 1; sd += 2) {
      bp();
      el(rr * 0.25f, sd * rr * 0.38f, rr * 0.2f, rr * 0.15f, 0, 0, TAU_F, false);
      fs(H(0xffffff));
      fl();
      bp();
      circ(rr * 0.3f, sd * rr * 0.38f, rr * 0.09f);
      fs(H(0xc21010));
      fl();
    }
    rs();
  }
}

static void eel(const wsk_pt* S, int n, float rr, float t, int boost, float alpha) {
  int i, sd;
  float pulse;
  (void)alpha;
  if (n < 3) return;
  taper(n, rr * 0.9f, rr * 0.25f);
  cap(true);
  for (sd = -1; sd <= 1; sd += 2) {
    for (i = 0; i < n; ++i) OFF[i] = sd * (W[i] + rr * (0.25f + 0.2f * sinf(i * 0.8f - t * 9)));
    line(S, 1, n, true);
    ss(RGBA(60, 140, 255, .45f));
    lw(fmaxf(1.5f, rr * 0.45f));
    sk();
  }
  outline(S, n);
  fs(H(0x16233f));
  fl();
  lw(fmaxf(1, rr * 0.08f));
  ss(H(0x050a14));
  sk();
  pulse = boost ? 1 : 0.55f + 0.25f * sinf(t * 3);
  for (sd = -1; sd <= 1; sd += 2) {
    for (i = 0; i < n; ++i) OFF[i] = sd * W[i] * 0.45f;
    line(S, 1, n, true);
    ss(RGBA(57, 225, 255, 0.25f * pulse));
    lw(fmaxf(2, rr * 0.35f));
    sk();
    ss(RGBA(160, 245, 255, 0.9f * pulse));
    lw(fmaxf(1, rr * 0.1f));
    sk();
  }
  for (i = 3; i < n - 1; i += 3) {
    fs(H(0xffd23f));
    bp();
    circ(S[i].x, S[i].y, fmaxf(1, W[i] * 0.18f));
    fl();
  }
  if (boost) {
    int fr = (int)floorf(t * 18), b, z;
    for (b = 0; b < 5; ++b) {
      int bi = 1 + (int)floorf(hash(fr * 5 + b) * (n - 2));
      wsk_pt s;
      v2 p;
      float ang, x, y;
      if (bi < 0 || bi >= n) continue;
      s = S[bi];
      sd = hash(fr + b * 3) > 0.5f ? 1 : -1;
      p = side2(s, sd, W[bi]);
      bp();
      mt(p.x, p.y);
      ang = s.a + sd * PI_F / 2;
      x = p.x;
      y = p.y;
      for (z = 1; z <= 4; ++z) {
        ang += (hash(fr * 13 + b * 7 + z) - 0.5f) * 1.2f;
        x += cosf(ang) * rr * 0.55f;
        y += sinf(ang) * rr * 0.55f;
        lt(x, y);
      }
      ss(RGBA(120, 220, 255, .4f));
      lw(fmaxf(2, rr * 0.3f));
      sk();
      ss(H(0xeaffff));
      lw(fmaxf(1, rr * 0.08f));
      sk();
    }
  }
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    bp();
    el(rr * 0.2f, 0, rr * 1.05f, rr * 0.8f, 0, 0, TAU_F, false);
    fs(H(0x1c2c50));
    fl();
    lw(fmaxf(1, rr * 0.08f));
    ss(H(0x050a14));
    sk();
    for (sd = -1; sd <= 1; sd += 2) {
      bp();
      circ(rr * 0.55f, sd * rr * 0.4f, rr * 0.16f);
      fs(H(0xffd23f));
      fl();
      bp();
      circ(rr * 0.6f, sd * rr * 0.4f, rr * 0.07f);
      fs(H(0x000000));
      fl();
    }
    rs();
  }
}

/* A train car spanning samples i0 (front) .. i1 (back): saves and turns the
   canvas onto it; the caller restores. */
static void car_box(const wsk_pt* S, int n, float rr, int i0, int i1, float* len) {
  wsk_pt A = S[i0], B = S[i1 < n - 1 ? i1 : n - 1];
  float cx = (A.x + B.x) / 2, cy = (A.y + B.y) / 2;
  float ang = atan2f(A.y - B.y, A.x - B.x);
  *len = hypotf(A.x - B.x, A.y - B.y) + rr * 0.9f;
  sv();
  tr(cx, cy);
  ro(ang);
}

static void train(const wsk_pt* S, int n, float rr, float t, int boost, float alpha) {
  const int CAR = 3;
  static const uint32_t colors[4] = {0xb3261e, 0x1f4f8f, 0x2e7d32, 0xc07a12};
  int i, sd, k, wq, wn, sp2i, bd;
  (void)alpha;
  if (n < 3) return;
  cap(false);
  ss(H(0x5a3b1e));
  lw(fmaxf(1, rr * 0.25f));
  for (i = 0; i < n; ++i) {
    v2 a = side2(S[i], -1, rr * 1.15f), b = side2(S[i], 1, rr * 1.15f);
    bp();
    mt(a.x, a.y);
    lt(b.x, b.y);
    sk();
  }
  for (sd = -1; sd <= 1; sd += 2) {
    for (i = 0; i < n; ++i) OFF[i] = sd * rr * 0.85f;
    line(S, 0, n, true);
    ss(H(0x8f959c));
    lw(fmaxf(1, rr * 0.12f));
    sk();
  }
  for (k = CAR * ((n - 1) / CAR); k >= CAR; k -= CAR) {
    float L, Wd = rr * 1.5f;
    wcol col = H(colors[(k / CAR) % 4]);
    car_box(S, n, rr, k, k + CAR - 1, &L);
    fs(H(0x111111));
    for (sd = -1; sd <= 1; sd += 2)
      for (wq = -1; wq <= 1; wq += 2) {
        bp();
        circ(wq * L * 0.32f, sd * Wd * 0.55f, rr * 0.28f);
        fl();
      }
    fs(col);
    fill_rect(-L / 2, -Wd / 2, L, Wd);
    lw(fmaxf(1, rr * 0.1f));
    ss(H(0x1a1a1a));
    stroke_rect(-L / 2, -Wd / 2, L, Wd);
    fs(H(0x3a3a3a));
    fill_rect(-L / 2 + rr * 0.15f, -Wd * 0.22f, L - rr * 0.3f, Wd * 0.44f);
    fs(H(0xffe08a));
    for (wn = 0; wn < 3; ++wn) {
      float wx = -L / 2 + L * (0.2f + wn * 0.3f);
      fill_rect(wx - rr * 0.18f, -Wd / 2 + rr * 0.05f, rr * 0.36f, rr * 0.16f);
      fill_rect(wx - rr * 0.18f, Wd / 2 - rr * 0.21f, rr * 0.36f, rr * 0.16f);
    }
    fs(H(0x222222));
    fill_rect(L / 2, -rr * 0.08f, rr * 0.45f, rr * 0.16f);
    rs();
    if (boost) {
      for (sp2i = 0; sp2i < 2; ++sp2i) {
        int si = k + (sp2i ? 2 : 0);
        wsk_pt s2 = S[si < n - 1 ? si : n - 1];
        v2 p = side2(s2, hash(k + sp2i + floorf(t * 20)) > 0.5f ? 1 : -1, rr * 0.9f);
        glow_dot(p.x, p.y, rr * 0.35f, 255, 170, 60, 0.9f);
      }
    }
  }
  {
    float EL, EW = rr * 1.6f, smokeX;
    car_box(S, n, rr, 0, CAR - 1 < n - 1 ? CAR - 1 : n - 1, &EL);
    fs(H(0x111111));
    for (sd = -1; sd <= 1; sd += 2)
      for (wq = -1; wq <= 1; wq += 2) {
        bp();
        circ(wq * EL * 0.3f, sd * EW * 0.55f, rr * 0.32f);
        fl();
      }
    fs(H(0xa3201a));
    fill_rect(-EL / 2, -EW / 2, EL * 0.38f, EW);
    fs(H(0x1d1d1f));
    bp();
    mt(-EL / 2 + EL * 0.36f, -EW * 0.42f);
    lt(EL / 2 - rr * 0.3f, -EW * 0.42f);
    qt(EL / 2 + rr * 0.3f, 0, EL / 2 - rr * 0.3f, EW * 0.42f);
    lt(-EL / 2 + EL * 0.36f, EW * 0.42f);
    cp();
    fl();
    ss(H(0xd4af37));
    lw(fmaxf(1, rr * 0.1f));
    for (bd = 0; bd < 3; ++bd) {
      float bxx = -EL / 2 + EL * (0.45f + bd * 0.14f);
      bp();
      mt(bxx, -EW * 0.42f);
      lt(bxx, EW * 0.42f);
      sk();
    }
    fs(H(0x444444));
    bp();
    circ(EL * 0.3f, 0, rr * 0.32f);
    fl();
    fs(H(0x000000));
    bp();
    circ(EL * 0.3f, 0, rr * 0.18f);
    fl();
    glow_dot(EL / 2 + rr * 0.5f, 0, rr * 1.4f, 255, 230, 140, 0.55f);
    smokeX = EL * 0.3f;
    rs();
    {
      wsk_pt Hd = S[0];
      float hx = Hd.x + cosf(Hd.a) * smokeX * 0.9f, hy = Hd.y + sinf(Hd.a) * smokeX * 0.9f;
      puff(hx, hy, Hd.a + PI_F, rr, t, boost ? 10 : 6, 0.6f, 200, 200, 205, boost ? 1.6f : 0.9f, 6);
    }
  }
}

static void robot(const wsk_pt* S, int n, float rr, float t, int boost, float alpha) {
  int i, sd;
  float pu;
  wsk_pt L;
  (void)alpha;
  if (n < 3) return;
  cap(true);
  line(S, 0, n, false);
  ss(H(0x20262e));
  lw(rr * 1.5f);
  sk();
  L = S[n - 1];
  if (boost) puff(L.x, L.y, L.a + PI_F, rr, t, 9, 0.35f, 90, 200, 255, 3, 4);
  for (i = n - 1; i >= 1; --i) {
    wsk_pt s = S[i];
    float k = 1 - ((float)i / n) * 0.35f, w = rr * 0.92f * k;
    wpaint g;
    sv();
    tr(s.x, s.y);
    ro(s.a);
    g = lin(0, -w, 0, w);
    stop(&g, 0, H(0xc9d2dc));
    stop(&g, 0.5f, H(0x8c97a4));
    stop(&g, 1, H(0x5d6772));
    fp(g);
    bp();
    mt(-rr * 0.45f, -w);
    lt(rr * 0.35f, -w);
    lt(rr * 0.5f, -w * 0.6f);
    lt(rr * 0.5f, w * 0.6f);
    lt(rr * 0.35f, w);
    lt(-rr * 0.45f, w);
    cp();
    fl();
    lw(fmaxf(1, rr * 0.07f));
    ss(H(0x2c333b));
    sk();
    fs(H(0xe6ebf0));
    for (sd = -1; sd <= 1; sd += 2) {
      bp();
      circ(-rr * 0.2f, sd * w * 0.7f, fmaxf(0.8f, rr * 0.07f));
      fl();
    }
    rs();
  }
  pu = boost ? 1 : 0.6f + 0.2f * sinf(t * 4);
  line(S, 1, n, false);
  ss(RGBA(41, 224, 255, 0.3f * pu));
  lw(fmaxf(2, rr * 0.5f));
  sk();
  ss(RGBA(200, 250, 255, pu));
  lw(fmaxf(1, rr * 0.12f));
  sk();
  if (boost)
    for (i = 1; i < n; ++i) {
      float sh = sinf(i * 0.7f - t * 16);
      if (sh > 0.85f) glow_dot(S[i].x, S[i].y, rr * 0.9f, 41, 224, 255, 0.8f);
    }
  sv();
  tr(L.x, L.y);
  ro(L.a);
  fs(H(0x3b434d));
  bp();
  mt(-rr * 0.2f, -rr * 0.45f);
  lt(-rr * 0.9f, -rr * 0.6f);
  lt(-rr * 0.9f, rr * 0.6f);
  lt(-rr * 0.2f, rr * 0.45f);
  cp();
  fl();
  rs();
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    fs(H(0x9aa6b3));
    bp();
    mt(-rr * 0.6f, -rr * 0.9f);
    lt(rr * 0.6f, -rr * 0.9f);
    lt(rr * 1.2f, -rr * 0.3f);
    lt(rr * 1.2f, rr * 0.3f);
    lt(rr * 0.6f, rr * 0.9f);
    lt(-rr * 0.6f, rr * 0.9f);
    cp();
    fl();
    lw(fmaxf(1, rr * 0.09f));
    ss(H(0x2c333b));
    sk();
    fs(H(0x1b1f24));
    fill_rect(rr * 0.35f, -rr * 0.6f, rr * 0.3f, rr * 1.2f);
    glow_dot(rr * 0.5f, 0, rr * 0.9f, 255, 45, 45, 0.8f);
    fs(H(0xff3b3b));
    fill_rect(rr * 0.42f, -rr * 0.5f, rr * 0.16f, rr * 1.0f);
    ss(H(0xcfd6de));
    lw(fmaxf(1, rr * 0.07f));
    bp();
    mt(-rr * 0.3f, 0);
    lt(-rr * 1.1f, -rr * 0.5f);
    sk();
    if ((int)floorf(t * 2) % 2 == 0) glow_dot(-rr * 1.1f, -rr * 0.5f, rr * 0.35f, 120, 255, 120, 0.9f);
    rs();
  }
}

static void phoenix(const wsk_pt* S, int n, float rr, float t, int boost, float alpha) {
  int i, sd, f, e;
  wsk_pt L;
  if (n < 3) return;
  taper(n, rr * 0.85f, rr * 0.3f);
  cap(true);
  L = S[n - 1];
  {
    float ta = L.a + PI_F;
    for (i = 0; i < 5; ++i) {
      float fa = ta + (i - 2) * 0.22f + sinf(t * 3 + i) * 0.12f, fl2 = rr * (4 + (i % 2) * 1.5f);
      float ex = L.x + cosf(fa) * fl2, ey = L.y + sinf(fa) * fl2;
      wpaint g = lin(L.x, L.y, ex, ey);
      stop(&g, 0, H(0xffd24a));
      stop(&g, 0.6f, H(0xff6a00));
      stop(&g, 1, RGBA(200, 20, 0, 0));
      sp(g);
      lw(fmaxf(1.5f, rr * 0.35f));
      bp();
      mt(L.x, L.y);
      qt(L.x + cosf(fa + 0.4f) * fl2 * 0.5f, L.y + sinf(fa + 0.4f) * fl2 * 0.5f, ex, ey);
      sk();
    }
  }
  {
    int wi = (int)fmaxf(1, roundf(n * 0.12f));
    wsk_pt W0 = S[wi < n - 1 ? wi : n - 1];
    float flap = 0.7f + 0.3f * sinf(t * (boost ? 10 : 4));
    for (sd = -1; sd <= 1; sd += 2)
      for (f = 0; f < 6; ++f) {
        float wa = W0.a + sd * (PI_F / 2 + 0.1f + f * 0.17f), wl = rr * (4.4f - f * 0.35f) * flap;
        float wx = W0.x + cosf(wa) * wl, wy = W0.y + sinf(wa) * wl;
        wpaint wg = lin(W0.x, W0.y, wx, wy);
        stop(&wg, 0, H(0xffe27a));
        stop(&wg, 0.5f, H(0xff7a1a));
        stop(&wg, 1, RGBA(220, 30, 0, .2f));
        sp(wg);
        lw(fmaxf(1.5f, rr * 0.5f));
        bp();
        mt(W0.x, W0.y);
        qt(W0.x + cosf(wa - sd * 0.25f) * wl * 0.6f, W0.y + sinf(wa - sd * 0.25f) * wl * 0.6f, wx, wy);
        sk();
      }
  }
  outline(S, n);
  {
    wpaint bg = lin(S[0].x, S[0].y, L.x, L.y);
    stop(&bg, 0, H(0xff8c1a));
    stop(&bg, 1, H(0xd93a00));
    fp(bg);
    fl();
  }
  for (i = 1; i < n - 1; ++i) {
    wsk_pt s = S[i];
    float fw = W[i];
    for (sd = -1; sd <= 1; sd += 2) {
      float sw = sinf(t * 7 - i * 0.7f) * 0.25f, a = s.a + PI_F + sd * (1.05f + sw);
      v2 b = side2(s, sd, fw * 0.85f);
      float len = fw * 2.3f;
      fs(i % 2 ? H(0xff5a00) : H(0xffb020));
      bp();
      mt(b.x, b.y);
      qt(b.x + cosf(a + sd * 0.5f) * len * 0.7f, b.y + sinf(a + sd * 0.5f) * len * 0.7f,
         b.x + cosf(a) * len, b.y + sinf(a) * len);
      qt(b.x + cosf(a - sd * 0.3f) * len * 0.4f, b.y + sinf(a - sd * 0.3f) * len * 0.4f, b.x, b.y);
      fl();
      ss(RGBA(120, 20, 0, .75f));
      lw(fmaxf(1, rr * 0.06f));
      sk();
    }
  }
  line(S, 1, n, false);
  ss(H(0xffd24a));
  lw(fmaxf(1, rr * 0.3f));
  sk();
  line(S, 0, n, false);
  ss(RGBA(255, 120, 20, boost ? 0.35f : 0.18f));
  lw(rr * (boost ? 3 : 2.2f));
  sk();
  for (e = 0; e < (boost ? 14 : 7); ++e) {
    float ef2 = fmodf(t * 0.8f + e / 7.0f, 1.0f);
    int ei = (int)floorf(n * (0.3f + hash(e) * 0.7f));
    wsk_pt es;
    float ea;
    if (ei > n - 1) ei = n - 1;
    es = S[ei];
    ea = es.a + PI_F + (hash(e * 3) - 0.5f) * 1.6f;
    glow_dot(es.x + cosf(ea) * rr * ef2 * 4, es.y + sinf(ea) * rr * ef2 * 4, rr * 0.35f, 255, 180, 60,
             0.9f * (1 - ef2));
  }
  (void)alpha;
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    for (i = 0; i < 3; ++i) {
      float ca = PI_F + (i - 1) * 0.35f + sinf(t * 6 + i) * 0.1f;
      bp();
      mt(0, 0);
      lt(cosf(ca) * rr * 1.8f, sinf(ca) * rr * 1.8f);
      ss(i == 1 ? H(0xffd24a) : H(0xff5a00));
      lw(fmaxf(1, rr * 0.28f));
      sk();
    }
    bp();
    el(0, 0, rr * 0.85f, rr * 0.75f, 0, 0, TAU_F, false);
    fs(H(0xff8c1a));
    fl();
    bp();
    mt(rr * 0.7f, -rr * 0.3f);
    lt(rr * 1.6f, 0);
    lt(rr * 0.7f, rr * 0.3f);
    cp();
    fs(H(0xffd24a));
    fl();
    for (sd = -1; sd <= 1; sd += 2) {
      bp();
      circ(rr * 0.25f, sd * rr * 0.35f, rr * 0.14f);
      fs(H(0x2a0a00));
      fl();
    }
    rs();
  }
}

static void ice(const wsk_pt* S, int n, float rr, float t, int boost, float alpha) {
  int i, sd;
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.1f ? 0.8f + u * 2 : 1 - (u - 0.1f) * 0.72f);
  }
  cap(true);
  for (i = 0; i < 8; ++i) {
    float mf = fmodf(t * 0.4f + i / 8.0f, 1.0f);
    int mi = (int)floorf(hash(i + 3) * n);
    v2 mp;
    if (mi > n - 1) mi = n - 1;
    mp = side2(S[mi], hash(i) > 0.5f ? 1 : -1, W[mi] + rr * mf * 1.5f);
    glow_dot(mp.x, mp.y, rr * (0.6f + mf), 200, 240, 255, 0.35f * (1 - mf));
  }
  outline(S, n);
  {
    wpaint g = lin(S[0].x, S[0].y, S[n - 1].x, S[n - 1].y);
    stop(&g, 0, H(0xbfe9fb));
    stop(&g, 1, H(0x7cc3e6));
    fp(g);
    fl();
  }
  lw(fmaxf(1, rr * 0.1f));
  ss(H(0xe8fbff));
  sk();
  ss(RGBA(60, 140, 190, .45f));
  lw(fmaxf(1, rr * 0.08f));
  for (i = 2; i < n - 1; ++i) {
    wsk_pt s = S[i];
    float w = W[i];
    sv();
    tr(s.x, s.y);
    ro(s.a);
    bp();
    mt(-w * 0.3f, -w * 0.7f);
    lt(w * 0.1f, 0);
    lt(-w * 0.3f, w * 0.7f);
    sk();
    rs();
  }
  for (i = 2; i < n - 1; i += 2) {
    wsk_pt s = S[i];
    float sz = W[i] * 1.6f;
    int cs = (i % 4 == 0) ? 1 : -1;
    float ba = s.a + PI_F - cs * (0.75f + (hash(i) - 0.5f) * 0.3f);
    v2 cpt = side2(s, cs, W[i] * 0.55f);
    sv();
    tr(cpt.x, cpt.y);
    ro(ba);
    bp();
    mt(0, 0);
    lt(sz * 0.35f, -sz * 0.18f);
    lt(sz * 1.1f, 0);
    lt(sz * 0.35f, sz * 0.18f);
    cp();
    fs(H(0xf4feff));
    fl();
    ss(H(0x2f86b8));
    lw(fmaxf(1, rr * 0.1f));
    sk();
    bp();
    mt(sz * 0.2f, 0);
    lt(sz * 0.9f, 0);
    ss(RGBA(47, 134, 184, .6f));
    lw(fmaxf(1, rr * 0.05f));
    sk();
    rs();
  }
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    if (boost) puff(rr * 0.8f, 0, 0, rr, t, 9, 0.5f, 210, 245, 255, 2.5f, 5);
    for (sd = -1; sd <= 1; sd += 2) {
      bp();
      mt(-rr * 0.1f, sd * rr * 0.45f);
      lt(-rr * 1.3f, sd * rr * 0.85f);
      lt(-rr * 0.5f, sd * rr * 0.3f);
      cp();
      fs(H(0xeafcff));
      fl();
      ss(H(0x5aaed6));
      lw(fmaxf(1, rr * 0.06f));
      sk();
    }
    bp();
    mt(-rr * 0.8f, -rr * 0.75f);
    lt(rr * 0.7f, -rr * 0.6f);
    lt(rr * 1.4f, 0);
    lt(rr * 0.7f, rr * 0.6f);
    lt(-rr * 0.8f, rr * 0.75f);
    cp();
    fs(H(0xc6ecfc));
    fl();
    lw(fmaxf(1, rr * 0.08f));
    ss(H(0x5aaed6));
    sk();
    for (sd = -1; sd <= 1; sd += 2) {
      glow_dot(rr * 0.35f, sd * rr * 0.35f, rr * 0.4f, 80, 220, 255, 0.9f);
      fs(H(0xe6fbff));
      bp();
      circ(rr * 0.35f, sd * rr * 0.35f, rr * 0.1f);
      fl();
    }
    rs();
  }
}

static void caterpillar(const wsk_pt* S, int n, float rr, float t, int boost, float alpha) {
  int i, sd;
  float sp = boost ? 16 : 7;
  (void)alpha;
  if (n < 2) return;
  cap(true);
  for (i = 1; i < n; ++i) {
    wsk_pt s = S[i];
    for (sd = -1; sd <= 1; sd += 2) {
      float lf = sinf(t * sp - i * 0.9f) * 0.3f;
      v2 b = side2(s, sd, rr * 0.75f);
      float a = s.a + sd * (PI_F / 2 + 0.3f + lf);
      ss(H(0x2b3a1a));
      lw(fmaxf(1, rr * 0.16f));
      bp();
      mt(b.x, b.y);
      lt(b.x + cosf(a) * rr * 0.45f, b.y + sinf(a) * rr * 0.45f);
      sk();
    }
  }
  for (i = n - 1; i >= 1; --i) {
    wsk_pt s = S[i];
    float bob = 1 + sinf(t * sp * 0.6f - i * 0.8f) * 0.06f, r = rr * 0.95f * bob;
    wpaint g = rad(s.x - r * 0.3f, s.y - r * 0.3f, r * 0.1f, s.x, s.y, r);
    stop(&g, 0, H(0xb8f27c));
    stop(&g, 0.7f, H(0x5fbf3a));
    stop(&g, 1, H(0x347a1f));
    fp(g);
    bp();
    circ(s.x, s.y, r);
    fl();
    lw(fmaxf(1, rr * 0.06f));
    ss(RGBA(20, 50, 10, .6f));
    sk();
    fs(H(0xffe14d));
    bp();
    circ(s.x, s.y, r * 0.18f);
    fl();
    fs(H(0x1f2a12));
    for (sd = -1; sd <= 1; sd += 2) {
      v2 dp = side2(s, sd, r * 0.55f);
      bp();
      circ(dp.x, dp.y, r * 0.08f);
      fl();
    }
  }
  {
    wsk_pt Hd = S[0];
    wpaint hg;
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    for (sd = -1; sd <= 1; sd += 2) {
      float aw = sinf(t * 5 + sd) * 0.2f, ax = rr * 1.5f, ay = sd * rr * (1.1f + aw);
      ss(H(0x2b3a1a));
      lw(fmaxf(1, rr * 0.1f));
      bp();
      mt(rr * 0.2f, sd * rr * 0.5f);
      qt(rr * 0.9f, sd * rr * 0.6f, ax, ay);
      sk();
      fs(H(0xff6b6b));
      bp();
      circ(ax, ay, rr * 0.2f);
      fl();
    }
    hg = rad(-rr * 0.3f, -rr * 0.3f, rr * 0.1f, 0, 0, rr * 1.15f);
    stop(&hg, 0, H(0xffe985));
    stop(&hg, 1, H(0xe0a92a));
    fp(hg);
    bp();
    circ(0, 0, rr * 1.15f);
    fl();
    lw(fmaxf(1, rr * 0.07f));
    ss(RGBA(90, 60, 0, .6f));
    sk();
    for (sd = -1; sd <= 1; sd += 2) {
      fs(H(0xffffff));
      bp();
      circ(rr * 0.35f, sd * rr * 0.42f, rr * 0.3f);
      fl();
      fs(H(0x111111));
      bp();
      circ(rr * 0.45f, sd * rr * 0.42f, rr * 0.16f);
      fl();
      fs(H(0xffffff));
      bp();
      circ(rr * 0.5f, sd * rr * 0.36f, rr * 0.05f);
      fl();
    }
    ss(H(0x7a3b0c));
    lw(fmaxf(1, rr * 0.08f));
    bp();
    ar(rr * 0.55f, 0, rr * 0.3f, -1.1f, 1.1f, false);
    sk();
    rs();
  }
}

static void zombie(const wsk_pt* S, int n, float rr, float t, int boost, float alpha) {
  int i, sd, q, tq;
  (void)alpha;
  if (n < 3) return;
  taper(n, rr * 0.95f, rr * 0.35f);
  cap(true);
  if (boost) {
    wsk_pt L0 = S[n - 1];
    puff(L0.x, L0.y, L0.a + PI_F, rr, t, 10, 1.2f, 120, 255, 80, 1.2f, 4);
  }
  outline(S, n);
  fs(H(0x7f9a5a));
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(H(0x2f3a1f));
  sk();
  for (i = 2; i < n - 1; ++i) {
    wsk_pt s = S[i];
    float h = hash(i), w = W[i];
    if (h < 0.3f) {
      v2 p = side2(s, h < 0.15f ? 1 : -1, w * 0.35f);
      fs(RGBA(70, 90, 40, .8f));
      bp();
      el(p.x, p.y, w * 0.45f, w * 0.3f, s.a, 0, TAU_F, false);
      fl();
    } else if (h < 0.42f) {
      fs(H(0x8a1e1e));
      bp();
      circ(s.x, s.y, w * 0.32f);
      fl();
      fs(RGBA(255, 120, 120, .4f));
      bp();
      circ(s.x - w * 0.08f, s.y - w * 0.08f, w * 0.12f);
      fl();
    } else if (h < 0.55f) {
      sv();
      tr(s.x, s.y);
      ro(s.a);
      ss(H(0xece6d6));
      lw(fmaxf(1, rr * 0.13f));
      for (sd = -1; sd <= 1; sd += 2) {
        bp();
        mt(0, 0);
        qt(-w * 0.1f, sd * w * 0.6f, -w * 0.45f, sd * w * 0.8f);
        sk();
      }
      rs();
    }
    if (i % 4 == 0) {
      sv();
      tr(s.x, s.y);
      ro(s.a);
      ss(H(0x1e2412));
      lw(fmaxf(1, rr * 0.07f));
      bp();
      mt(0, -w * 0.8f);
      lt(0, w * 0.8f);
      sk();
      for (q = -2; q <= 2; ++q) {
        bp();
        mt(-w * 0.18f, q * w * 0.3f);
        lt(w * 0.18f, q * w * 0.3f);
        sk();
      }
      rs();
    }
  }
  {
    wsk_pt Hd = S[0];
    float dang;
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    bp();
    el(0, 0, rr * 1.0f, rr * 0.9f, 0, 0, TAU_F, false);
    fs(H(0x89a462));
    fl();
    lw(fmaxf(1, rr * 0.09f));
    ss(H(0x2f3a1f));
    sk();
    fs(H(0x1a1a10));
    bp();
    mt(rr * 0.6f, -rr * 0.4f);
    lt(rr * 1.0f, 0);
    lt(rr * 0.6f, rr * 0.4f);
    cp();
    fl();
    fs(H(0xf2ecd0));
    for (tq = -1; tq <= 1; tq += 2) {
      bp();
      mt(rr * 0.65f, tq * rr * 0.2f);
      lt(rr * 0.85f, tq * rr * 0.12f);
      lt(rr * 0.68f, tq * rr * 0.05f);
      fl();
    }
    dang = sinf(t * 3) * rr * 0.1f;
    ss(H(0x8a1e1e));
    lw(fmaxf(1, rr * 0.06f));
    bp();
    mt(rr * 0.2f, -rr * 0.4f);
    lt(rr * 0.5f + dang, -rr * 0.95f);
    sk();
    fs(H(0xf4f1e0));
    bp();
    circ(rr * 0.5f + dang, -rr * 0.95f, rr * 0.26f);
    fl();
    fs(H(0xb8141e));
    bp();
    circ(rr * 0.58f + dang, -rr * 0.95f, rr * 0.1f);
    fl();
    ss(H(0x1e2412));
    lw(fmaxf(1, rr * 0.09f));
    bp();
    mt(rr * 0.05f, rr * 0.25f);
    lt(rr * 0.45f, rr * 0.55f);
    mt(rr * 0.45f, rr * 0.25f);
    lt(rr * 0.05f, rr * 0.55f);
    sk();
    rs();
  }
}

/* ---- eyes ---- */

/* A disc of radius r at (px, py), kept inside the eye (R wide, ry tall, at
   the origin): what the eye's clip leaves of it. */
static void eye_disc(float px, float py, float r, float R, float ry) {
  int k = (int)fminf(fmaxf(8.0f + r * 1.2f, 10.0f), 40.0f), s;
  bp();
  for (s = 0; s < k; ++s) {
    float th = TAU_F * (float)s / (float)k;
    float x = px + cosf(th) * r, y = py + sinf(th) * r;
    float v = (x * x) / (R * R) + (y * y) / (ry * ry);
    if (v > 1.0f) {
      float f = 1.0f / sqrtf(v);
      x *= f;
      y *= f;
    }
    if (s) lt(x, y);
    else mt(x, y);
  }
  cp();
}

/* Slither's own eye: white, dark pupil, glint. The pupil sits where the snake
   is turning (look, radians from the heading), it blinks every few seconds
   and the pupil narrows while boosting. */
static void big_eye(float x, float y, float R, float look, float t, int boost, const wcol* iris,
                    float seed) {
  float ph = fmodf(t + seed, 3.8f);
  float bl = ph > 3.62f ? sinf((ph - 3.62f) / 0.18f * PI_F) : 0;
  float ry = fmaxf(0.6f, R * (1 - 0.94f * bl));
  sv();
  tr(x, y);
  bp();
  el(0, 0, R, ry, 0, 0, TAU_F, false);
  fs(H(0xffffff));
  fl();
  lw(fmaxf(1, R * 0.08f));
  ss(HA(0x000000, .6f));
  sk();
  if (bl < 0.8f) {
    float off = R * 0.34f, px = cosf(look) * off, py = sinf(look) * off * 0.95f;
    float pr = R * (boost ? 0.3f : 0.45f) * (1 + 0.04f * sinf(t * 2.1f));
    if (iris) {
      fs(*iris);
      eye_disc(px, py, pr * 1.55f, R, ry);
      fl();
    }
    fs(H(0x0b0b10));
    eye_disc(px, py, pr, R, ry);
    fl();
    fs(RGBA(255, 255, 255, .88f));
    eye_disc(px - pr * 0.32f, py - pr * 0.36f, pr * 0.2f, R, ry);
    fl();
  }
  rs();
}

static void boost_fx(const wsk_pt* S, int n, float rr, float t, float cr, float cg, float cb) {
  wsk_pt L = S[n - 1];
  puff(L.x, L.y, L.a + PI_F, rr, t, 10, 1.2f, cr, cg, cb, 1.3f, 4);
}
/* An eye on a body segment; its pupil looks the way the head looks. */
static void eye_on(wsk_pt s, float ox, float oy, float R, float look, float headA, float t, int boost,
                   const wcol* iris, float seed) {
  sv();
  tr(s.x, s.y);
  ro(s.a);
  big_eye(ox, oy, R, look + headA - s.a, t, boost, iris, seed);
  rs();
}
static void head_blob(float rr, float rx, float ry, wcol fill, wcol edge, float dx) {
  bp();
  el(rr * dx, 0, rr * rx, rr * ry, 0, 0, TAU_F, false);
  fs(fill);
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(edge);
  sk();
}

static void cyclops(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  int i;
  const wcol iris = H(0x42d6c4);
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.08f ? 1.0f + u * 2 : 1.16f - u * 0.86f);
  }
  cap(true);
  if (boost) {
    wsk_pt L0 = S[n - 1];
    puff(L0.x, L0.y, L0.a + PI_F, rr, t, 10, 1.2f, 150, 120, 255, 1.2f, 4);
  }
  outline(S, n);
  fs(H(0x6f5be0));
  fl();
  lw(fmaxf(1, rr * 0.11f));
  ss(H(0x2a1f73));
  sk();
  for (i = 0; i < n; ++i) OFF[i] = -W[i] * 0.45f;
  line(S, 1, n - 1, true);
  ss(RGBA(190, 175, 255, .55f));
  lw(fmaxf(1, rr * 0.34f));
  sk();
  for (i = 3; i < n - 1; i += 2) {
    wsk_pt s = S[i];
    float h = hash(i);
    v2 p = side2(s, h < 0.5f ? 1 : -1, W[i] * 0.5f * (0.4f + h));
    fs(RGBA(40, 28, 120, .55f));
    bp();
    circ(p.x, p.y, fmaxf(0.8f, rr * (0.1f + h * 0.08f)));
    fl();
  }
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    bp();
    el(rr * 0.08f, 0, rr * 1.42f, rr * 1.32f, 0, 0, TAU_F, false);
    fs(H(0x7d6af0));
    fl();
    lw(fmaxf(1, rr * 0.11f));
    ss(H(0x2a1f73));
    sk();
    fs(RGBA(255, 255, 255, .18f));
    bp();
    el(-rr * 0.2f, -rr * 0.7f, rr * 0.7f, rr * 0.28f, -0.3f, 0, TAU_F, false);
    fl();
    ss(H(0x2a1f73));
    lw(fmaxf(1, rr * 0.1f));
    bp();
    ar(rr * 0.5f, 0, rr * 0.5f, -0.7f, 0.7f, false);
    sk();
    big_eye(rr * 0.02f, 0, rr * 0.95f, look, t, boost, &iris, 0);
    rs();
  }
}

static void evileye(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  int i, hs;
  const wcol iris = H(0xe22b1c);
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.08f ? 1.0f + u * 2 : 1.12f - u * 0.8f);
  }
  cap(true);
  if (boost) {
    wsk_pt L0 = S[n - 1];
    puff(L0.x, L0.y, L0.a + PI_F, rr, t, 12, 1.1f, 255, 60, 40, 1.4f, 4.5f);
  }
  for (i = 3; i < n - 1; i += 2) {
    wsk_pt s = S[i], tl = S[i + 1 < n - 1 ? i + 1 : n - 1];
    float w = W[i];
    v2 tip = side2(s, 1, w * 1.55f + sinf(t * 5 + i) * w * 0.08f), b1 = side2(s, 1, w * 0.8f),
       b2 = side2(tl, 1, w * 0.8f);
    v2 tip2 = side2(s, -1, w * 1.55f + sinf(t * 5 + i + 2) * w * 0.08f), c1 = side2(s, -1, w * 0.8f),
       c2 = side2(tl, -1, w * 0.8f);
    fs(H(0x14070b));
    bp();
    mt(b1.x, b1.y);
    lt(tip.x, tip.y);
    lt(b2.x, b2.y);
    cp();
    fl();
    bp();
    mt(c1.x, c1.y);
    lt(tip2.x, tip2.y);
    lt(c2.x, c2.y);
    cp();
    fl();
  }
  outline(S, n);
  fs(H(0x2b0d14));
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(H(0x0c0306));
  sk();
  for (i = 2; i < n - 1; ++i) {
    wsk_pt s = S[i];
    float gw = 0.35f + 0.65f * (0.5f + 0.5f * sinf(t * 3 - i * 0.6f));
    sv();
    tr(s.x, s.y);
    ro(s.a);
    ss(RGBA(255, roundf(60 + 70 * gw), 40, 0.35f + 0.5f * gw));
    lw(fmaxf(1, rr * 0.1f));
    bp();
    ar(-W[i] * 0.1f, 0, W[i] * 0.55f, -1.1f, 1.1f, false);
    sk();
    rs();
  }
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    bp();
    el(rr * 0.08f, 0, rr * 1.4f, rr * 1.3f, 0, 0, TAU_F, false);
    fs(H(0x3a1019));
    fl();
    lw(fmaxf(1, rr * 0.1f));
    ss(H(0x0c0306));
    sk();
    for (hs = -1; hs <= 1; hs += 2) {
      v2 hb = {0, hs * rr * 1.0f}; /* side2({0,0,0}, hs, rr) */
      fs(H(0x14070b));
      bp();
      mt(hb.x - rr * 0.35f, hb.y);
      lt(hb.x + rr * 0.15f + rr * 0.35f, hs * rr * 1.75f);
      lt(hb.x + rr * 0.45f, hb.y);
      cp();
      fl();
    }
    glow_dot(rr * 0.02f, 0, rr * 1.7f, 255, 40, 30, boost ? 0.35f : 0.2f);
    big_eye(rr * 0.02f, 0, rr * 0.95f, look, t, boost, &iris, 1.3f);
    fs(H(0x3a1019));
    ss(H(0x0c0306));
    lw(fmaxf(1, rr * 0.09f));
    bp();
    mt(-rr * 0.98f, -rr * 1.05f);
    lt(rr * 1.0f, -rr * 1.05f);
    lt(rr * 1.0f, -rr * 0.15f);
    lt(-rr * 0.98f, -rr * 0.72f);
    cp();
    fl();
    sk();
    rs();
  }
}

static void argus(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  int i;
  const wcol iris = H(0xffcf3a);
  wsk_pt Hd = S[0];
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.08f ? 1.0f + u * 2 : 1.12f - u * 0.78f);
  }
  cap(true);
  if (boost) boost_fx(S, n, rr, t, 90, 140, 255);
  outline(S, n);
  fs(H(0x1d2c63));
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(H(0x0a1030));
  sk();
  for (i = n - 2; i >= 2; i -= 2) {
    float w = W[i];
    int big = hash(i) > 0.55f;
    eye_on(S[i], 0, (hash(i + 3) - 0.5f) * w * 0.3f, w * (big ? 0.62f : 0.4f), look, Hd.a, t, boost,
           &iris, i * 0.41f);
  }
  sv();
  tr(Hd.x, Hd.y);
  ro(Hd.a);
  head_blob(rr, 1.4f, 1.3f, H(0x26397f), H(0x0a1030), 0.08f);
  big_eye(rr * 0.25f, 0, rr * 0.78f, look, t, boost, &iris, 0.3f);
  big_eye(-rr * 0.35f, -rr * 0.78f, rr * 0.36f, look, t, boost, &iris, 1.1f);
  big_eye(-rr * 0.35f, rr * 0.78f, rr * 0.36f, look, t, boost, &iris, 2.2f);
  big_eye(rr * 0.95f, -rr * 0.55f, rr * 0.22f, look, t, boost, &iris, 3.1f);
  big_eye(rr * 0.95f, rr * 0.55f, rr * 0.22f, look, t, boost, &iris, 4.2f);
  rs();
}

static void spider(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  static const int legs[5] = {3, 6, 9, 12, 15};
  static const float E[8][3] = {{0.62f, -0.42f, 0.46f}, {0.62f, 0.42f, 0.46f}, {0.12f, -0.88f, 0.3f},
                                {0.12f, 0.88f, 0.3f},   {-0.35f, -0.42f, 0.2f}, {-0.35f, 0.42f, 0.2f},
                                {-0.7f, -0.2f, 0.15f},  {-0.7f, 0.2f, 0.15f}};
  const wcol claw = H(0xb79bff), iris = H(0xff3b3b);
  int i, k;
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.1f ? 0.9f + u * 2 : 1.1f - u * 0.8f);
  }
  cap(true);
  if (boost) boost_fx(S, n, rr, t, 170, 90, 255);
  limbs(S, n, rr, t, boost, legs, 5, H(0x3b2266), &claw, 1.5f);
  outline(S, n);
  fs(H(0x2a1646));
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(H(0x0d0618));
  sk();
  for (i = 3; i < n - 2; i += 3) {
    wsk_pt s = S[i];
    fs(H(0xb3122e));
    bp();
    el(s.x, s.y, W[i] * 0.36f, W[i] * 0.22f, s.a, 0, TAU_F, false);
    fl();
  }
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    head_blob(rr, 1.35f, 1.25f, H(0x34195a), H(0x0d0618), 0.1f);
    for (k = 0; k < 8; ++k)
      big_eye(E[k][0] * rr, E[k][1] * rr, E[k][2] * rr, look, t, boost, &iris, k * 0.7f);
    rs();
  }
}

static void megaeye(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  int i, k;
  const wcol iris = H(0x27c2e8);
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) W[i] = rr * (0.62f - 0.3f * ((float)i / (n - 1)));
  cap(true);
  if (boost) boost_fx(S, n, rr, t, 255, 120, 170);
  outline(S, n);
  fs(H(0xe9b7c9));
  fl();
  lw(fmaxf(1, rr * 0.08f));
  ss(H(0x7a3550));
  sk();
  line(S, 1, n - 1, false);
  ss(RGBA(190, 50, 90, .55f));
  lw(fmaxf(1, rr * 0.12f));
  sk();
  {
    wsk_pt Hd = S[0];
    float R = rr * 2.3f, cx = rr * 0.35f;
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    big_eye(cx, 0, R, look, t, boost, &iris, 0.5f);
    if (fmodf(t + 0.5f, 3.8f) < 3.55f) {
      ss(RGBA(200, 40, 60, .5f));
      lw(fmaxf(1, rr * 0.06f));
      for (k = 0; k < 12; ++k) {
        float a = (float)k / 12 * TAU_F + hash(k) * 0.3f, r0 = R * 0.96f;
        float r1 = R * (0.8f + hash(k + 9) * 0.08f), am = a + 0.12f;
        bp();
        mt(cx + cosf(a) * r0, sinf(a) * r0);
        qt(cx + cosf(am) * (r0 + r1) / 2, sinf(am) * (r0 + r1) / 2, cx + cosf(a) * r1, sinf(a) * r1);
        sk();
      }
    }
    rs();
  }
}

static void bean(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  int i, sd;
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) W[i] = rr * (1.1f - 0.45f * ((float)i / (n - 1)));
  cap(true);
  if (boost) boost_fx(S, n, rr, t, 255, 200, 120);
  outline(S, n);
  fs(H(0xffd9a8));
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(H(0xa0643a));
  sk();
  for (i = 2; i < n - 1; i += 2) {
    v2 p = side2(S[i], hash(i) > 0.5f ? 1 : -1, W[i] * 0.45f);
    fs(RGBA(230, 140, 70, .6f));
    bp();
    circ(p.x, p.y, fmaxf(0.8f, W[i] * 0.22f));
    fl();
  }
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    head_blob(rr, 1.15f, 1.1f, H(0xffe3bd), H(0xa0643a), 0.05f);
    big_eye(rr * 0.55f, -rr * 0.42f, rr * 0.2f, look, t, boost, NULL, 0.2f);
    big_eye(rr * 0.55f, rr * 0.42f, rr * 0.2f, look, t, boost, NULL, 0.2f);
    fs(RGBA(255, 120, 140, .45f));
    for (sd = -1; sd <= 1; sd += 2) {
      bp();
      circ(rr * 0.25f, sd * rr * 0.78f, rr * 0.2f);
      fl();
    }
    ss(H(0xa0643a));
    lw(fmaxf(1, rr * 0.09f));
    bp();
    ar(rr * 0.62f, 0, rr * 0.22f, -1, 1, false);
    sk();
    rs();
  }
}

static void owl(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  int i, sd;
  const wcol iris = H(0xffbf1a);
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.1f ? 1.0f + u * 2 : 1.15f - u * 0.8f);
  }
  cap(true);
  if (boost) boost_fx(S, n, rr, t, 255, 190, 90);
  outline(S, n);
  fs(H(0x8c5b3b));
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(H(0x3a2414));
  sk();
  for (i = 2; i < n - 1; ++i) {
    wsk_pt s = S[i];
    sv();
    tr(s.x, s.y);
    ro(s.a);
    ss(RGBA(58, 36, 20, .7f));
    lw(fmaxf(1, rr * 0.08f));
    bp();
    ar(0, 0, W[i] * 0.6f, 2.2f, 4.1f, false);
    sk();
    rs();
  }
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    fs(H(0x6b4328));
    for (sd = -1; sd <= 1; sd += 2) {
      bp();
      mt(-rr * 0.5f, sd * rr * 1.0f);
      lt(-rr * 0.95f, sd * rr * 1.75f);
      lt(-rr * 0.05f, sd * rr * 1.2f);
      cp();
      fl();
    }
    head_blob(rr, 1.45f, 1.35f, H(0x9a6a45), H(0x3a2414), 0.05f);
    fs(H(0xf1dcb8));
    for (sd = -1; sd <= 1; sd += 2) {
      bp();
      el(rr * 0.4f, sd * rr * 0.68f, rr * 0.88f, rr * 0.88f, 0, 0, TAU_F, false);
      fl();
    }
    big_eye(rr * 0.4f, -rr * 0.68f, rr * 0.7f, look, t, boost, &iris, 0.4f);
    big_eye(rr * 0.4f, rr * 0.68f, rr * 0.7f, look, t, boost, &iris, 0.4f);
    fs(H(0xe8a23a));
    ss(H(0x7a4a12));
    lw(fmaxf(1, rr * 0.07f));
    bp();
    mt(rr * 1.0f, -rr * 0.2f);
    lt(rr * 1.6f, 0);
    lt(rr * 1.0f, rr * 0.2f);
    cp();
    fl();
    sk();
    rs();
  }
}

static void thirdeye(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  int i;
  const wcol brown = H(0x7a4b12), violet = H(0xa24cff);
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.1f ? 1.0f + u * 2 : 1.14f - u * 0.8f);
  }
  cap(true);
  if (boost) boost_fx(S, n, rr, t, 255, 215, 90);
  outline(S, n);
  fs(H(0xd9ad3f));
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(H(0x6b4d12));
  sk();
  for (i = 2; i < n - 1; i += 2) {
    wsk_pt s = S[i];
    ss(RGBA(120, 70, 12, .8f));
    lw(fmaxf(1, rr * 0.08f));
    bp();
    circ(s.x, s.y, W[i] * 0.5f);
    sk();
    fs(RGBA(120, 70, 12, .8f));
    bp();
    circ(s.x, s.y, W[i] * 0.14f);
    fl();
  }
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    head_blob(rr, 1.4f, 1.3f, H(0xe5bb4f), H(0x6b4d12), 0.08f);
    glow_dot(-rr * 0.05f, 0, rr * 1.2f, 170, 80, 255, 0.45f + 0.2f * sinf(t * 2));
    big_eye(rr * 0.55f, -rr * 0.65f, rr * 0.4f, look, t, boost, &brown, 0.2f);
    big_eye(rr * 0.55f, rr * 0.65f, rr * 0.4f, look, t, boost, &brown, 0.2f);
    big_eye(-rr * 0.05f, 0, rr * 0.34f, look, t, boost, &violet, 1.7f);
    rs();
  }
}

static void snail(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  int i, sd;
  const wcol iris = H(0x6b4a1a);
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.1f ? 0.95f + u * 1.5f : 1.1f - u * 0.95f);
  }
  cap(true);
  if (boost) boost_fx(S, n, rr, t, 170, 230, 90);
  outline(S, n);
  fs(H(0xa6d65a));
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(H(0x4a6e1e));
  sk();
  for (i = 2; i < n - 1; i += 2) {
    v2 p = side2(S[i], hash(i) > 0.5f ? 1 : -1, W[i] * 0.4f);
    fs(RGBA(90, 130, 40, .45f));
    bp();
    circ(p.x, p.y, fmaxf(0.8f, W[i] * 0.25f));
    fl();
  }
  for (i = 0; i < n; ++i) OFF[i] = -W[i] * 0.5f;
  line(S, 1, n - 1, true);
  ss(RGBA(255, 255, 255, .4f));
  lw(fmaxf(1, rr * 0.16f));
  sk();
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    for (sd = -1; sd <= 1; sd += 2) {
      float tx = rr * 1.75f + sinf(t * 2.2f + sd) * rr * 0.18f;
      float ty = sd * rr * 1.15f + cosf(t * 1.7f + sd) * rr * 0.12f;
      ss(H(0x8ebd44));
      lw(fmaxf(1.2f, rr * 0.3f));
      bp();
      mt(rr * 0.55f, sd * rr * 0.4f);
      qt(rr * 1.2f, sd * rr * 0.5f, tx, ty);
      sk();
    }
    head_blob(rr, 1.2f, 1.1f, H(0xb4e068), H(0x4a6e1e), 0.05f);
    for (sd = -1; sd <= 1; sd += 2)
      big_eye(rr * 1.75f + sinf(t * 2.2f + sd) * rr * 0.18f, sd * rr * 1.15f + cosf(t * 1.7f + sd) * rr * 0.12f,
              rr * 0.5f, look, t, boost, &iris, sd + 3);
    ss(H(0x4a6e1e));
    lw(fmaxf(1, rr * 0.08f));
    bp();
    ar(rr * 0.8f, 0, rr * 0.25f, -1, 1, false);
    sk();
    rs();
  }
}

static void mantis(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  int i, sd, q;
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.1f ? 0.7f + u * 2 : 0.9f - u * 0.5f);
  }
  cap(true);
  if (boost) boost_fx(S, n, rr, t, 120, 255, 100);
  outline(S, n);
  fs(H(0x58b043));
  fl();
  lw(fmaxf(1, rr * 0.1f));
  ss(H(0x1f4a14));
  sk();
  for (i = 2; i < n - 1; i += 2) {
    wsk_pt s = S[i];
    sv();
    tr(s.x, s.y);
    ro(s.a);
    ss(RGBA(31, 74, 20, .7f));
    lw(fmaxf(1, rr * 0.09f));
    bp();
    mt(0, -W[i] * 0.9f);
    lt(0, W[i] * 0.9f);
    sk();
    rs();
  }
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    ss(H(0x2f7a22));
    lw(fmaxf(1, rr * 0.07f));
    for (sd = -1; sd <= 1; sd += 2) {
      bp();
      mt(rr * 0.7f, sd * rr * 0.3f);
      qt(rr * 1.4f, sd * rr * 0.6f, rr * 1.9f + sinf(t * 3 + sd) * rr * 0.1f, sd * rr * 1.25f);
      sk();
    }
    head_blob(rr, 1.0f, 1.05f, H(0x6bc255), H(0x1f4a14), 0.1f);
    fs(H(0x6bc255));
    bp();
    mt(rr * 0.55f, -rr * 0.5f);
    lt(rr * 1.35f, 0);
    lt(rr * 0.55f, rr * 0.5f);
    cp();
    fl();
    sk();
    for (sd = -1; sd <= 1; sd += 2) {
      float ex = rr * 0.3f, ey = sd * rr * 0.95f;
      wpaint g = rad(ex - rr * 0.15f, ey - rr * 0.2f, 0, ex, ey, rr * 0.85f);
      float px, py;
      stop(&g, 0, H(0xe0344a));
      stop(&g, 1, H(0x7a0c1c));
      fp(g);
      bp();
      el(ex, ey, rr * 0.62f, rr * 0.8f, 0, 0, TAU_F, false);
      fl();
      ss(H(0x3a050c));
      lw(fmaxf(1, rr * 0.07f));
      sk();
      ss(RGBA(255, 170, 170, .25f));
      lw(fmaxf(0.6f, rr * 0.04f));
      for (q = -2; q <= 2; ++q) {
        bp();
        mt(ex + q * rr * 0.22f, ey - rr * 0.6f);
        lt(ex + q * rr * 0.22f, ey + rr * 0.6f);
        sk();
        bp();
        mt(ex - rr * 0.5f, ey + q * rr * 0.26f);
        lt(ex + rr * 0.5f, ey + q * rr * 0.26f);
        sk();
      }
      px = ex + cosf(look) * rr * 0.2f;
      py = ey + sinf(look) * rr * 0.26f;
      fs(H(0x120305));
      bp();
      circ(px, py, rr * (boost ? 0.14f : 0.2f));
      fl();
      fs(RGBA(255, 255, 255, .8f));
      bp();
      circ(px - rr * 0.06f, py - rr * 0.07f, rr * 0.05f);
      fl();
    }
    rs();
  }
}

static void eyechain(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  int i;
  wsk_pt Hd = S[0];
  const wcol pink = H(0xff2a6d);
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) W[i] = rr * (1.05f - 0.5f * ((float)i / (n - 1)));
  cap(true);
  if (boost) boost_fx(S, n, rr, t, 255, 255, 255);
  for (i = n - 1; i >= 1; i -= 2) {
    wcol iris = HSL((float)((i * 37) % 360), 70, 50, 1);
    eye_on(S[i], 0, 0, W[i] * 1.02f, look, Hd.a, t, 0, &iris, i * 0.3f);
  }
  eye_on(Hd, rr * 0.1f, 0, rr * 1.35f, look, Hd.a, t, boost, &pink, 0);
}

static void jelly(const wsk_pt* S, int n, float rr, float t, int boost, float alpha, float look) {
  int i, k, j;
  const wcol iris = H(0xff7ad9);
  wsk_pt L;
  (void)alpha;
  if (n < 3) return;
  for (i = 0; i < n; ++i) {
    float u = (float)i / (n - 1);
    W[i] = rr * (u < 0.1f ? 1.0f + u * 2 : 1.15f - u * 0.75f);
  }
  cap(true);
  if (boost) boost_fx(S, n, rr, t, 120, 220, 255);
  L = S[n - 1];
  ss(RGBA(190, 240, 255, .6f));
  lw(fmaxf(1, rr * 0.13f));
  for (k = -1; k <= 1; ++k) {
    bp();
    mt(L.x, L.y);
    for (j = 1; j <= 8; ++j) {
      float d = j * rr * 0.45f;
      float w = sinf(t * 4 + j * 0.8f + k * 1.7f) * rr * 0.28f * (j / 8.0f) + k * rr * 0.16f * (j / 8.0f);
      lt(L.x + cosf(L.a + PI_F) * d + cosf(L.a + PI_F / 2) * w,
         L.y + sinf(L.a + PI_F) * d + sinf(L.a + PI_F / 2) * w);
    }
    sk();
  }
  outline(S, n);
  fs(RGBA(130, 220, 255, .5f));
  fl();
  lw(fmaxf(1, rr * 0.09f));
  ss(RGBA(255, 255, 255, .7f));
  sk();
  for (i = 3; i < n - 1; i += 3) glow_dot(S[i].x, S[i].y, W[i] * 1.3f, 120, 220, 255, 0.25f);
  {
    wsk_pt Hd = S[0];
    sv();
    tr(Hd.x, Hd.y);
    ro(Hd.a);
    head_blob(rr, 1.4f, 1.3f, RGBA(150, 230, 255, .6f), RGBA(255, 255, 255, .75f), 0.05f);
    big_eye(rr * 0.5f, -rr * 0.45f, rr * 0.45f, look * 0.4f + 0.9f, t, boost, &iris, 0.2f);
    big_eye(rr * 0.5f, rr * 0.45f, rr * 0.45f, look * 0.4f - 0.9f, t, boost, &iris, 0.2f);
    rs();
  }
}

/* ------------------------------------------------------------------------ */
/* Strip looks: a flat strip in the snake's own colour at body width.       */
/* ------------------------------------------------------------------------ */

static float g_xs[MAXP], g_ys[MAXP];
static bool g_on[MAXP];
static int g_runs[MAXSUB][2];
static int g_nruns;

static void find_runs(int n) {
  int i, a = -1;
  g_nruns = 0;
  for (i = 0; i < n; ++i) {
    if (g_on[i]) {
      if (a < 0) a = i;
    } else if (a >= 0) {
      if (g_nruns < MAXSUB) g_runs[g_nruns][0] = a, g_runs[g_nruns][1] = i - 1, g_nruns++;
      a = -1;
    }
  }
  if (a >= 0 && g_nruns < MAXSUB) g_runs[g_nruns][0] = a, g_runs[g_nruns][1] = n - 1, g_nruns++;
}
/* The centre line, one subpath per visible run. */
static void strip_path(void) {
  int r, i;
  bp();
  for (r = 0; r < g_nruns; ++r) {
    int a = g_runs[r][0], b = g_runs[r][1];
    mt(g_xs[a], g_ys[a]);
    if (b == a) lt(g_xs[a] + 0.01f, g_ys[a]);
    for (i = a + 1; i <= b; ++i) lt(g_xs[i], g_ys[i]);
  }
}
/* The closed outline of a run at half-width h (round ends), added to the path. */
static void strip_outline(int a, int b, float h) {
  int m = b - a + 1, i;
  static float nx[MAXP], ny[MAXP];
  float ae, a0;
  if (m < 2) {
    mt(g_xs[a] + h, g_ys[a]);
    ar(g_xs[a], g_ys[a], h, 0, TAU_F, false);
    return;
  }
  for (i = a; i <= b; ++i) {
    int p = i > a ? i - 1 : i, q = i < b ? i + 1 : i;
    float dx = g_xs[q] - g_xs[p], dy = g_ys[q] - g_ys[p], d = sqrtf(dx * dx + dy * dy);
    if (d == 0) d = 1;
    nx[i - a] = -dy / d;
    ny[i - a] = dx / d;
  }
  mt(g_xs[a] + nx[0] * h, g_ys[a] + ny[0] * h);
  for (i = 1; i < m; ++i) lt(g_xs[a + i] + nx[i] * h, g_ys[a + i] + ny[i] * h);
  ae = atan2f(ny[m - 1], nx[m - 1]);
  ar(g_xs[b], g_ys[b], h, ae, ae - PI_F, true);
  for (i = m - 1; i >= 0; --i) lt(g_xs[a + i] - nx[i] * h, g_ys[a + i] - ny[i] * h);
  a0 = atan2f(ny[0], nx[0]);
  ar(g_xs[a], g_ys[a], h, a0 + PI_F, a0, true);
  cp();
}
typedef void (*walk_fn)(float x, float y, float tx, float ty, int k, void* data);
/* Walks the centre line, calling fn every `step` px. */
static void strip_walk(float step, walk_fn fn, void* data) {
  int k = 0, r, i;
  for (r = 0; r < g_nruns; ++r) {
    int a = g_runs[r][0], b = g_runs[r][1];
    float acc = step;
    for (i = a; i <= b; ++i) {
      if (i > a) acc += hypotf(g_xs[i] - g_xs[i - 1], g_ys[i] - g_ys[i - 1]);
      if (acc >= step) {
        int p = i > a ? i - 1 : i, q = i < b ? i + 1 : i;
        float dx = g_xs[q] - g_xs[p], dy = g_ys[q] - g_ys[p], d = sqrtf(dx * dx + dy * dy);
        acc = 0;
        if (d == 0) d = 1;
        fn(g_xs[i], g_ys[i], dx / d, dy / d, k++, data);
      }
    }
  }
}
static wcol lighten(wcol c, float amt) {
  wcol o = {c.r + (1 - c.r) * amt, c.g + (1 - c.g) * amt, c.b + (1 - c.b) * amt, 1};
  return o;
}
static wcol shade(wcol c, float amt) {
  wcol o = {c.r * (1 - amt), c.g * (1 - amt), c.b * (1 - amt), 1};
  return o;
}
static wcol tint(wcol base, wcol c, float amt) {
  wcol o = {base.r + (c.r - base.r) * amt, base.g + (c.g - base.g) * amt, base.b + (c.b - base.b) * amt, 1};
  return o;
}
/* A short piece of the centre line, points i..e. */
static void piece(int i, int e) {
  int k;
  bp();
  mt(g_xs[i], g_ys[i]);
  for (k = i + 1; k <= e; ++k) lt(g_xs[k], g_ys[k]);
}

typedef struct strip_ctx {
  float w, h, a, t;
  wcol col;
  int flip;
} strip_ctx;

static void walk_ice(float x, float y, float tx, float ty, int kk, void* d) {
  strip_ctx* c = d;
  float tw = 0.5f + 0.5f * sinf(c->t + kk * 1.7f), L = c->w * (0.18f + 0.2f * tw);
  (void)tx, (void)ty;
  ga(c->a * (0.4f + 0.6f * tw));
  bp();
  mt(x - L, y);
  lt(x + L, y);
  mt(x, y - L);
  lt(x, y + L);
  sk();
}
static void walk_galaxy(float x, float y, float tx, float ty, int kk, void* d) {
  strip_ctx* c = d;
  double hd = sin(kk * 12.9898) * 43758.5453;
  float hsh = (float)(hd - floor(hd));
  float ox, oy, tw;
  (void)tx, (void)ty;
  ox = (hsh - 0.5f) * c->w * 0.7f;
  oy = (fmodf(hsh * 7.3f, 1.0f) - 0.5f) * c->w * 0.7f;
  tw = 0.5f + 0.5f * sinf(c->t + kk * 2.3f);
  ga(c->a * (0.35f + 0.65f * tw));
  bp();
  circ(x + ox, y + oy, fmaxf(0.7f, c->w * (0.04f + 0.05f * hsh)));
  fl();
}
static void walk_dotted(float x, float y, float tx, float ty, int kk, void* d) {
  strip_ctx* c = d;
  (void)tx, (void)ty, (void)kk;
  ga(c->a);
  fs((c->flip++ & 1) ? lighten(c->col, 0.28f) : c->col);
  bp();
  circ(x, y, c->h * 0.92f);
  fl();
  ga(c->a * 0.5f);
  fs(H(0xffffff));
  bp();
  circ(x - c->h * 0.25f, y - c->h * 0.3f, c->h * 0.28f);
  fl();
}
static void walk_zigzag(float x, float y, float tx, float ty, int kk, void* d) {
  strip_ctx* c = d;
  float nxx = -ty, nyy = tx, s2 = (kk & 1) ? 1.0f : -1.0f, hx = c->h * 0.82f;
  ga(c->a);
  bp();
  mt(x + nxx * hx * s2 - tx * hx * 0.45f, y + nyy * hx * s2 - ty * hx * 0.45f);
  lt(x + nxx * -hx * s2 + tx * hx * 0.45f, y + nyy * -hx * s2 + ty * hx * 0.45f);
  sk();
}

/* Pixel cells already drawn this frame (open addressing). */
#define PIXEL_HASH 16384
static int32_t g_px_key_x[PIXEL_HASH], g_px_key_y[PIXEL_HASH];
static uint32_t g_px_stamp[PIXEL_HASH];
static uint32_t g_px_now;
static bool pixel_seen(int32_t kx, int32_t ky) {
  uint32_t hsh = ((uint32_t)kx * 73856093u) ^ ((uint32_t)ky * 19349663u);
  int probe;
  for (probe = 0; probe < 64; ++probe) {
    uint32_t at = (hsh + probe) & (PIXEL_HASH - 1);
    if (g_px_stamp[at] != g_px_now) {
      g_px_stamp[at] = g_px_now;
      g_px_key_x[at] = kx;
      g_px_key_y[at] = ky;
      return false;
    }
    if (g_px_key_x[at] == kx && g_px_key_y[at] == ky) return true;
  }
  return true;
}

static const char* const STRIP_LOOKS[WYRM_SKIN_STRIPS] = {
    "classic", "neon", "glass", "outline", "pixel", "rainbow", "candy", "tube",
    "chrome", "lava", "ice", "galaxy", "ghost", "dotted", "zigzag"};

static void strip_stroke(int n, float w, wcol col, float a, float ang, float rpx, int look, float t) {
  float h = w / 2;
  int i, r;
  strip_ctx ctx = {w, h, a, 0, col, 0};
  const char* name = STRIP_LOOKS[look];
  bool bone = true;
  find_runs(n);
  cap(true);
  if (!strcmp(name, "neon")) {
    strip_path();
    ga(a * 0.18f);
    lw(w * 2.1f);
    ss(col);
    sk();
    ga(a * 0.28f);
    lw(w * 1.45f);
    sk();
    ga(a);
    lw(w);
    ss(lighten(col, 0.25f));
    sk();
    ga(a * 0.95f);
    lw(fmaxf(1, w * 0.42f));
    ss(lighten(col, 0.75f));
    sk();
  } else if (!strcmp(name, "glass") || !strcmp(name, "outline")) {
    bp();
    for (r = 0; r < g_nruns; ++r) strip_outline(g_runs[r][0], g_runs[r][1], h);
    if (!strcmp(name, "glass")) {
      ga(a * 0.3f);
      fs(col);
      fl();
      ga(a * 0.9f);
      lw(fmaxf(1.2f, w * 0.1f));
      ss(lighten(col, 0.55f));
      sk();
    } else {
      ga(a * 0.1f);
      fs(col);
      fl();
      ga(a);
      lw(fmaxf(1.6f, w * 0.16f));
      ss(col);
      sk();
    }
  } else if (!strcmp(name, "pixel")) {
    float p = fmaxf(3, roundf(w / 3.2f)), rad2 = h * 0.98f;
    int cells = (int)ceilf(rad2 / p), ix, iy;
    ImU32 c32 = pack(col, a);
    g_px_now++;
    if (g_px_now == 0) g_px_now = 1;
    for (i = 0; i < n; ++i) {
      int32_t gx, gy;
      if (!g_on[i]) continue;
      gx = (int32_t)roundf(g_xs[i] / p);
      gy = (int32_t)roundf(g_ys[i] / p);
      for (ix = -cells; ix <= cells; ++ix)
        for (iy = -cells; iy <= cells; ++iy) {
          int32_t kx = gx + ix, ky = gy + iy;
          ImVec2 lo, hi;
          if ((ix * p) * (ix * p) + (iy * p) * (iy * p) > rad2 * rad2) continue;
          if (pixel_seen(kx, ky)) continue;
          lo.x = kx * p - p / 2;
          lo.y = ky * p - p / 2;
          hi.x = lo.x + p - 0.6f;
          hi.y = lo.y + p - 0.6f;
          ImDrawList_AddRectFilled(g_dl, lo, hi, c32, 0, 0);
        }
    }
  } else if (!strcmp(name, "rainbow")) {
    float tt = t / 1.4f;
    lw(w);
    for (r = 0; r < g_nruns; ++r)
      for (i = g_runs[r][0]; i < g_runs[r][1]; i += 2) {
        int e = i + 2 < g_runs[r][1] ? i + 2 : g_runs[r][1];
        piece(i, e);
        ga(a);
        ss(HSL(fmodf(i * 5 - tt * 120, 360), 85, 60, 1));
        sk();
      }
  } else if (!strcmp(name, "candy")) {
    float dash = w * 0.55f, gap = w * 0.85f, period = dash + gap;
    float offset = -fmodf(t * 1000 / 90, w * 1.4f);
    strip_path();
    ga(a);
    lw(w);
    ss(col);
    sk();
    /* The white bands: dashes along each run, offset over time. */
    cap(false);
    ga(a * 0.85f);
    lw(w * 0.92f);
    ss(H(0xffffff));
    for (r = 0; r < g_nruns; ++r) {
      float along = offset;
      int a0 = g_runs[r][0], b0 = g_runs[r][1];
      for (i = a0; i < b0; ++i) {
        float x0 = g_xs[i], y0 = g_ys[i], x1 = g_xs[i + 1], y1 = g_ys[i + 1];
        float seg = hypotf(x1 - x0, y1 - y0), u = 0;
        while (seg > 0 && u < seg) {
          float ph = fmodf(along + u, period), left;
          if (ph < 0) ph += period;
          if (ph < dash) {
            left = fminf(dash - ph, seg - u);
            bp();
            mt(x0 + (x1 - x0) * u / seg, y0 + (y1 - y0) * u / seg);
            lt(x0 + (x1 - x0) * (u + left) / seg, y0 + (y1 - y0) * (u + left) / seg);
            sk();
          } else {
            left = fminf(period - ph, seg - u);
          }
          u += fmaxf(left, 0.01f);
        }
        along += seg;
      }
    }
    cap(true);
  } else if (!strcmp(name, "tube")) {
    strip_path();
    ga(a);
    lw(w);
    ss(shade(col, 0.55f));
    sk();
    lw(w * 0.86f);
    ss(col);
    sk();
    lw(w * 0.55f);
    ss(lighten(col, 0.3f));
    sk();
    lw(w * 0.26f);
    ss(lighten(col, 0.7f));
    ga(a * 0.9f);
    sk();
  } else if (!strcmp(name, "chrome")) {
    strip_path();
    ga(a);
    lw(w);
    ss(H(0x4b5563));
    sk();
    lw(w * 0.82f);
    ss(tint(H(0xc9ced6), col, 0.18f));
    sk();
    lw(w * 0.3f);
    ss(H(0xffffff));
    sk();
    lw(w * 0.16f);
    ss(RGBA(40, 48, 60, .7f));
    sk();
  } else if (!strcmp(name, "lava")) {
    strip_path();
    ga(a);
    lw(w);
    ss(H(0x5a1304));
    sk();
    for (r = 0; r < g_nruns; ++r)
      for (i = g_runs[r][0]; i < g_runs[r][1]; i += 3) {
        int e2 = i + 3 < g_runs[r][1] ? i + 3 : g_runs[r][1];
        float f = 0.5f + 0.5f * sinf(i * 0.28f - t * 3.2f);
        piece(i, e2);
        ga(a);
        lw(w * (0.62f + 0.18f * f));
        ss(HSL(roundf(10 + 22 * f), 100, roundf(46 + 10 * f), 1));
        sk();
        lw(w * (0.22f + 0.12f * f));
        ss(HSL(48, 100, roundf(62 + 18 * f), 1));
        sk();
      }
  } else if (!strcmp(name, "ice")) {
    strip_path();
    ga(a);
    lw(w);
    ss(H(0x7cc7ee));
    sk();
    lw(w * 0.78f);
    ss(H(0xbfe9ff));
    sk();
    lw(w * 0.34f);
    ss(RGBA(255, 255, 255, .85f));
    sk();
    ss(H(0xffffff));
    lw(fmaxf(1, w * 0.08f));
    ctx.t = t / 0.6f;
    strip_walk(w * 2.2f, walk_ice, &ctx);
  } else if (!strcmp(name, "galaxy")) {
    strip_path();
    ga(a);
    lw(w);
    ss(H(0x0a0b26));
    sk();
    ga(a * 0.5f);
    lw(w * 0.7f);
    ss(col);
    sk();
    ga(a * 0.35f);
    lw(w * 0.3f);
    ss(H(0xff8bd9));
    sk();
    fs(H(0xffffff));
    ctx.t = t / 0.7f;
    strip_walk(w * 0.9f, walk_galaxy, &ctx);
  } else if (!strcmp(name, "ghost")) {
    for (r = 0; r < g_nruns; ++r) {
      int ra = g_runs[r][0], rb = g_runs[r][1];
      float len = (float)(rb - ra > 1 ? rb - ra : 1);
      for (i = ra; i < rb; i += 3) {
        int e3 = i + 3 < rb ? i + 3 : rb;
        float f2 = 1 - (i - ra) / len;
        piece(i, e3);
        ga(a * powf(f2, 1.4f) * 0.9f);
        lw(w * (0.55f + 0.45f * f2));
        ss(lighten(col, 0.35f));
        sk();
      }
    }
  } else if (!strcmp(name, "dotted")) {
    strip_walk(w * 0.72f, walk_dotted, &ctx);
  } else if (!strcmp(name, "zigzag")) {
    strip_path();
    ga(a);
    lw(w);
    ss(col);
    sk();
    cap(false);
    ss(RGBA(255, 255, 255, .88f));
    lw(fmaxf(1.4f, w * 0.16f));
    strip_walk(w * 0.7f, walk_zigzag, &ctx);
    cap(true);
  } else {
    strip_path();
    ga(a);
    lw(w);
    ss(col);
    sk();
  }
  if (bone) {
    strip_path();
    ga(a * (!strcmp(name, "glass") || !strcmp(name, "outline") ? 0.7f : 0.85f));
    lw(fmaxf(1, w * 0.12f));
    ss(!strcmp(name, "pixel") ? RGBA(255, 255, 255, .9f) : H(0xffffff));
    sk();
  }
  if (g_on[0]) {
    bp();
    circ(g_xs[0] + cosf(ang) * rpx * 0.25f, g_ys[0] + sinf(ang) * rpx * 0.25f, fmaxf(1.5f, w * 0.28f));
    ga(a);
    fs(H(0xffffff));
    fl();
  }
}

/* ------------------------------------------------------------------------ */
/* The catalogue                                                            */
/* ------------------------------------------------------------------------ */

/* The nearest slither preset to each creature's colours: what the arena and
   every other client shows. */
static const int CREATURE_PRESET[WYRM_SKIN_CREATURES + 1] = {
    -1, 29, 63, 65, 56, 64, 29, 44, 56, 49, 27, 29, 64, 63, 64, 29, 65, 56, 56, 29, 27, 27, 65, 49};

bool wyrm_skin_valid(int skin) {
  return (skin >= 1 && skin <= WYRM_SKIN_CREATURES) ||
         (skin > WYRM_SKIN_STRIP_BASE && skin <= WYRM_SKIN_STRIP_BASE + WYRM_SKIN_STRIPS);
}

int wyrm_skin_preset(int skin) {
  if (skin >= 1 && skin <= WYRM_SKIN_CREATURES) return CREATURE_PRESET[skin];
  return -1;
}

int wyrm_skin_from_corner(const uint8_t* corner) {
  if (corner[0] != WYRM_SKIN_MARK || corner[1] != WYRM_SKIN_KIND) return 0;
  if (corner[3] || corner[4] || corner[5]) return 0;
  if (corner[7] != (uint8_t)(corner[6] ^ WYRM_SKIN_CHECK)) return 0;
  return wyrm_skin_valid(corner[6]) ? corner[6] : 0;
}

static wsk_pt g_S[MAXS];

void wyrm_skin_draw(int skin, const float* px, const float* py, const uint8_t* vis, int n,
                    float view_x, float view_y, float zoom, float cx, float cy, float radius,
                    float head, float want, float* look, bool boosting, float alpha, float red,
                    float green, float blue) {
  int i, seen = 0;
  float t;
  if (!wyrm_skin_valid(skin) || n < 2 || alpha <= 0.01f || zoom <= 0 || radius <= 0) return;
  for (i = 0; i < n && !seen; ++i) seen = vis[i] >= 1;
  if (!seen) return;
  if (n > MAXP) n = MAXP;
  g_dl = igGetWindowDrawList();
  igGetFontTexUvWhitePixel(&g_uv);
  memset(&g_st, 0, sizeof(g_st));
  identity();
  g_st.alpha = alpha;
  g_st.width = 1;
  g_st.fill = solid(H(0x000000));
  g_st.stroke = solid(H(0x000000));
  g_depth = 0;
  bp();
  t = (float)fmod((double)SDL_GetTicks() / 1000.0, 7200.0);

  if (skin > WYRM_SKIN_STRIP_BASE) {
    wcol col = {red, green, blue, 1};
    for (i = 0; i < n; ++i) {
      g_xs[i] = cx + (px[i] - view_x) * zoom;
      g_ys[i] = cy + (py[i] - view_y) * zoom;
      g_on[i] = vis[i] >= 1;
    }
    strip_stroke(n, fmaxf(2, 2 * radius * zoom), col, alpha, head, radius * zoom,
                 skin - WYRM_SKIN_STRIP_BASE - 1, t);
    return;
  }

  {
    /* Samples along the centre line, one per body segment (r * 1.05). */
    float step = radius * 1.05f, dist = 0, need = 0, rel, rr = radius * zoom;
    int m = 0;
    g_S[m].x = cx + (px[0] - view_x) * zoom;
    g_S[m].y = cy + (py[0] - view_y) * zoom;
    g_S[m].a = 0;
    m++;
    for (i = 1; i < n && m < 600; ++i) {
      float x0 = px[i - 1], y0 = py[i - 1], x1 = px[i], y1 = py[i];
      float L = sqrtf((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
      while (L > 0 && dist + L >= need + step && m < 600) {
        float f;
        need += step;
        f = (need - dist) / L;
        g_S[m].x = cx + (x0 + (x1 - x0) * f - view_x) * zoom;
        g_S[m].y = cy + (y0 + (y1 - y0) * f - view_y) * zoom;
        g_S[m].a = 0;
        m++;
      }
      dist += L;
    }
    for (i = 1; i < m; ++i) g_S[i].a = atan2f(g_S[i - 1].y - g_S[i].y, g_S[i - 1].x - g_S[i].x);
    g_S[0].a = head;
    /* Where the eyes look: the turn the snake is making, eased so the pupils
       glide like slither's own. */
    rel = atan2f(sinf(want - head), cosf(want - head));
    if (look) {
      if (isnan(*look)) *look = rel;
      *look += (rel - *look) * 0.18f;
      rel = *look;
    }
    switch (skin) {
      case 1: centipede(g_S, m, rr, t, boosting, alpha, rel); break;
      case 2: dragon(g_S, m, rr, t, boosting, alpha); break;
      case 3: skeleton(g_S, m, rr, t, boosting, alpha); break;
      case 4: chinese(g_S, m, rr, t, boosting, alpha); break;
      case 5: eel(g_S, m, rr, t, boosting, alpha); break;
      case 6: train(g_S, m, rr, t, boosting, alpha); break;
      case 7: robot(g_S, m, rr, t, boosting, alpha); break;
      case 8: phoenix(g_S, m, rr, t, boosting, alpha); break;
      case 9: ice(g_S, m, rr, t, boosting, alpha); break;
      case 10: caterpillar(g_S, m, rr, t, boosting, alpha); break;
      case 11: zombie(g_S, m, rr, t, boosting, alpha); break;
      case 12: cyclops(g_S, m, rr, t, boosting, alpha, rel); break;
      case 13: evileye(g_S, m, rr, t, boosting, alpha, rel); break;
      case 14: argus(g_S, m, rr, t, boosting, alpha, rel); break;
      case 15: spider(g_S, m, rr, t, boosting, alpha, rel); break;
      case 16: megaeye(g_S, m, rr, t, boosting, alpha, rel); break;
      case 17: bean(g_S, m, rr, t, boosting, alpha, rel); break;
      case 18: owl(g_S, m, rr, t, boosting, alpha, rel); break;
      case 19: thirdeye(g_S, m, rr, t, boosting, alpha, rel); break;
      case 20: snail(g_S, m, rr, t, boosting, alpha, rel); break;
      case 21: mantis(g_S, m, rr, t, boosting, alpha, rel); break;
      case 22: eyechain(g_S, m, rr, t, boosting, alpha, rel); break;
      case 23: jelly(g_S, m, rr, t, boosting, alpha, rel); break;
      default: break;
    }
  }
}
