/*
 * Live Wyrm skin preview (OM, 2026-10-25).
 *
 * The Skin page showed a creature or strip look as a 32-frame picture loop.
 * Here the arena's own drawing (wyrm_skins.c, compiled a second time under
 * other names) draws a snake that swims, turns and now and then boosts, for as
 * long as the page is open. The ImGui calls it makes go to a small CPU list
 * instead of the GPU, and the app draws the triangles itself (Android
 * Canvas.drawVertices, iOS Canvas), on its own thread, never touching the
 * engine's ImGui context.
 *
 * The stand-ins are the ones tools/wyrm-skins/check.py proved against the
 * original pictures.
 */

#define wyrm_skin_valid pv_wyrm_skin_valid
#define wyrm_skin_preset pv_wyrm_skin_preset
#define wyrm_skin_from_corner pv_wyrm_skin_from_corner
#define wyrm_skin_draw pv_wyrm_skin_draw
#define igGetWindowDrawList pv_igGetWindowDrawList
#define igGetFontTexUvWhitePixel pv_igGetFontTexUvWhitePixel
#define ImDrawList_PrimReserve pv_PrimReserve
#define ImDrawList_PrimWriteVtx pv_PrimWriteVtx
#define ImDrawList_PrimWriteIdx pv_PrimWriteIdx
#define ImDrawList_AddCircleFilled pv_AddCircleFilled
#define ImDrawList_AddRectFilled pv_AddRectFilled
#define ImDrawList_AddPolyline pv_AddPolyline
#define ImDrawList_AddConvexPolyFilled pv_AddConvexPolyFilled
#define ImDrawList_AddConcavePolyFilled pv_AddConcavePolyFilled

#include "wyrm_skins.c"

#include <stdint.h>

#include "wyrm_skin_preview.h"

/* Android's drawVertices takes 16-bit indices. */
#define PV_MAXV 30000
#define PV_MAXI (PV_MAXV * 3)

static ImDrawVert pv_v[PV_MAXV];
static uint32_t pv_i[PV_MAXI];
static int pv_ni;
static ImDrawList pv_list;

ImDrawList* pv_igGetWindowDrawList(void) { return &pv_list; }
void pv_igGetFontTexUvWhitePixel(ImVec2* out) { out->x = out->y = 0; }

void pv_PrimReserve(ImDrawList* d, int idx_count, int vtx_count) {
  (void)idx_count;
  (void)vtx_count;
  d->_VtxCurrentIdx = (unsigned int)d->VtxBuffer.Size;
}

void pv_PrimWriteVtx(ImDrawList* d, const ImVec2 pos, const ImVec2 uv, ImU32 col) {
  if (d->VtxBuffer.Size >= PV_MAXV) return;
  ImDrawVert* v = pv_v + d->VtxBuffer.Size++;
  v->pos = pos;
  v->uv = uv;
  v->col = col;
}

void pv_PrimWriteIdx(ImDrawList* d, ImDrawIdx idx) {
  (void)d;
  if (pv_ni < PV_MAXI) pv_i[pv_ni++] = idx;
}

static int pv_vtx(ImVec2 p, ImU32 c) {
  int k = pv_list.VtxBuffer.Size;
  pv_PrimWriteVtx(&pv_list, p, p, c);
  return k;
}

static void pv_tri(int a, int b, int c) {
  if (a >= PV_MAXV || b >= PV_MAXV || c >= PV_MAXV) return;
  if (pv_ni + 3 > PV_MAXI) return;
  pv_i[pv_ni++] = (uint32_t)a;
  pv_i[pv_ni++] = (uint32_t)b;
  pv_i[pv_ni++] = (uint32_t)c;
}

void pv_AddConvexPolyFilled(ImDrawList* d, const ImVec2* p, int n, ImU32 c) {
  (void)d;
  int b = pv_list.VtxBuffer.Size;
  for (int i = 0; i < n; i++) pv_vtx(p[i], c);
  for (int i = 1; i + 1 < n; i++) pv_tri(b, b + i, b + i + 1);
}

/* Ear clipping (simple polygons). */
static int pv_ear[8192];
static float pv_cross(ImVec2 a, ImVec2 b, ImVec2 c) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

void pv_AddConcavePolyFilled(ImDrawList* d, const ImVec2* p, int n, ImU32 c) {
  (void)d;
  if (n < 3 || n > 8192) return;
  int b = pv_list.VtxBuffer.Size, m = n, guard = 0;
  float area = 0;
  for (int i = 0; i < n; i++) {
    pv_vtx(p[i], c);
    pv_ear[i] = i;
    area += p[i].x * p[(i + 1) % n].y - p[(i + 1) % n].x * p[i].y;
  }
  float s = area > 0 ? 1.0f : -1.0f;
  while (m > 3 && guard++ < 100000) {
    int found = 0;
    for (int i = 0; i < m; i++) {
      int ia = pv_ear[(i + m - 1) % m], ib = pv_ear[i], ic = pv_ear[(i + 1) % m], inside = 0;
      if (pv_cross(p[ia], p[ib], p[ic]) * s <= 0) continue;
      for (int k = 0; k < m && !inside; k++) {
        int q = pv_ear[k];
        if (q == ia || q == ib || q == ic) continue;
        if (pv_cross(p[ia], p[ib], p[q]) * s > 0 && pv_cross(p[ib], p[ic], p[q]) * s > 0 &&
            pv_cross(p[ic], p[ia], p[q]) * s > 0)
          inside = 1;
      }
      if (inside) continue;
      pv_tri(b + ia, b + ib, b + ic);
      for (int k = i; k + 1 < m; k++) pv_ear[k] = pv_ear[k + 1];
      m--;
      found = 1;
      break;
    }
    if (!found) break;
  }
  if (m == 3) pv_tri(b + pv_ear[0], b + pv_ear[1], b + pv_ear[2]);
}

void pv_AddCircleFilled(ImDrawList* d, const ImVec2 c0, float r, ImU32 c, int seg) {
  (void)d;
  (void)seg;
  int n = 24, b = pv_vtx(c0, c);
  for (int i = 0; i < n; i++) {
    ImVec2 q = {c0.x + cosf(6.2831853f * i / n) * r, c0.y + sinf(6.2831853f * i / n) * r};
    pv_vtx(q, c);
  }
  for (int i = 0; i < n; i++) pv_tri(b, b + 1 + i, b + 1 + (i + 1) % n);
}

void pv_AddRectFilled(ImDrawList* d, const ImVec2 a, const ImVec2 b2, ImU32 c, float r,
                      ImDrawFlags f) {
  (void)d;
  (void)r;
  (void)f;
  int b = pv_list.VtxBuffer.Size;
  ImVec2 p1 = {b2.x, a.y}, p3 = {a.x, b2.y};
  pv_vtx(a, c);
  pv_vtx(p1, c);
  pv_vtx(b2, c);
  pv_vtx(p3, c);
  pv_tri(b, b + 1, b + 2);
  pv_tri(b, b + 2, b + 3);
}

static void pv_seg(ImVec2 a, ImVec2 b2, float w, ImU32 c) {
  float dx = b2.x - a.x, dy = b2.y - a.y, l = sqrtf(dx * dx + dy * dy);
  if (l < 1e-6f) return;
  float nx = -dy / l * w * .5f, ny = dx / l * w * .5f;
  ImVec2 p0 = {a.x + nx, a.y + ny}, p1 = {b2.x + nx, b2.y + ny};
  ImVec2 p2 = {b2.x - nx, b2.y - ny}, p3 = {a.x - nx, a.y - ny};
  int k = pv_vtx(p0, c);
  pv_vtx(p1, c);
  pv_vtx(p2, c);
  pv_vtx(p3, c);
  pv_tri(k, k + 1, k + 2);
  pv_tri(k, k + 2, k + 3);
}

void pv_AddPolyline(ImDrawList* d, const ImVec2* p, int n, ImU32 c, ImDrawFlags flags, float w) {
  (void)d;
  if (w < 1) w = 1;
  for (int i = 0; i + 1 < n; i++) pv_seg(p[i], p[i + 1], w, c);
  if (flags & 1) pv_seg(p[n - 1], p[0], w, c);
  /* Joins: small discs so thick lines do not crack at the corners. */
  if (w > 2)
    for (int i = 1; i + ((flags & 1) ? 0 : 1) < n; i++) {
      int b = pv_vtx(p[i], c), s = 10;
      for (int k = 0; k < s; k++) {
        ImVec2 q = {p[i].x + cosf(6.2831853f * k / s) * w * .5f,
                    p[i].y + sinf(6.2831853f * k / s) * w * .5f};
        pv_vtx(q, c);
      }
      for (int k = 0; k < s; k++) pv_tri(b, b + 1 + k, b + 1 + (k + 1) % s);
    }
}

/* ---- The swimming snake ---------------------------------------------- */

/* The head's trail, newest first, one point every PV_STEP world units. */
#define PV_TRAIL 400
#define PV_STEP 4.0f
static float pv_tx[PV_TRAIL], pv_ty[PV_TRAIL];
static int pv_tn;
static float pv_hx, pv_hy, pv_ang, pv_want, pv_look = NAN, pv_since;
static double pv_last;
static float pv_w, pv_h;
static int pv_skin;

/* World = preview pixels at a fixed zoom of 1, the box from (0, 0) to (w, h). */
static void pv_reset(float w, float h) {
  pv_w = w;
  pv_h = h;
  pv_hx = w * 0.62f;
  pv_hy = h * 0.5f;
  pv_ang = 3.14159f;
  pv_want = pv_ang;
  pv_look = NAN;
  pv_since = 0;
  pv_tn = 0;
  /* A straight body already in place, trailing behind the head. */
  for (int i = 0; i < PV_TRAIL; i++) {
    pv_tx[i] = pv_hx - cosf(pv_ang) * PV_STEP * i;
    pv_ty[i] = pv_hy - sinf(pv_ang) * PV_STEP * i;
  }
  pv_tn = PV_TRAIL;
}

/* Steers like a player idling in the arena: a slow wandering turn, kept
   inside the box by turning toward its middle near the edges. */
static void pv_step(float dt, float t, float radius, bool boosting) {
  float margin = radius * 4.0f;
  float cx = pv_w * 0.5f, cy = pv_h * 0.5f;
  float wander = sinf(t * 0.7f) * 1.1f + sinf(t * 1.9f + 1.3f) * 0.55f;
  pv_want = pv_ang + wander;
  if (pv_hx < margin || pv_hx > pv_w - margin || pv_hy < margin || pv_hy > pv_h - margin)
    pv_want = atan2f(cy - pv_hy, cx - pv_hx);
  /* Slither's turn rate, eased. */
  float d = atan2f(sinf(pv_want - pv_ang), cosf(pv_want - pv_ang));
  float turn = 2.6f * dt;
  if (d > turn) d = turn;
  if (d < -turn) d = -turn;
  pv_ang += d;
  float speed = radius * (boosting ? 9.0f : 4.6f);
  float moved = speed * dt;
  pv_hx += cosf(pv_ang) * moved;
  pv_hy += sinf(pv_ang) * moved;
  /* Lay trail points one step apart behind the head. */
  pv_since += moved;
  while (pv_since >= PV_STEP) {
    pv_since -= PV_STEP;
    memmove(pv_tx + 1, pv_tx, sizeof(float) * (PV_TRAIL - 1));
    memmove(pv_ty + 1, pv_ty, sizeof(float) * (PV_TRAIL - 1));
    pv_tx[0] = pv_hx;
    pv_ty[0] = pv_hy;
  }
}

int wyrm_skin_preview_frame(int skin, float w, float h, double now, float red, float green,
                            float blue, float* out_xy, uint32_t* out_argb, int max_v,
                            uint16_t* out_idx, int max_i, int* out_ni) {
  *out_ni = 0;
  if (!pv_wyrm_skin_valid(skin) || w < 8 || h < 8) return 0;
  if (skin != pv_skin || fabsf(w - pv_w) > 0.5f || fabsf(h - pv_h) > 0.5f) {
    pv_skin = skin;
    pv_reset(w, h);
    pv_last = now;
  }
  float dt = (float)(now - pv_last);
  pv_last = now;
  if (dt < 0 || dt > 0.25f) dt = 0.016f;

  /* Body half-width and length sized to the box, like the old card. */
  float radius = h * 0.075f;
  float length = radius * 26.0f;
  float t = (float)fmod(now, 7200.0);
  bool boosting = fmodf(t, 9.0f) > 7.2f;
  pv_step(dt, t, radius, boosting);

  /* The centre line, head first, `length` long. */
  float px[PV_TRAIL + 1], py[PV_TRAIL + 1];
  uint8_t vis[PV_TRAIL + 1];
  int n = 0;
  float run = 0;
  px[n] = pv_hx;
  py[n] = pv_hy;
  vis[n++] = 2;
  for (int i = 0; i < pv_tn && run < length && n < PV_TRAIL + 1; i++) {
    float dx = pv_tx[i] - px[n - 1], dy = pv_ty[i] - py[n - 1];
    float l = sqrtf(dx * dx + dy * dy);
    if (l < 0.5f) continue;
    run += l;
    px[n] = pv_tx[i];
    py[n] = pv_ty[i];
    vis[n++] = 2;
  }
  if (n < 2) return 0;

  pv_list.VtxBuffer.Size = 0;
  pv_list.VtxBuffer.Data = pv_v;
  pv_list._VtxCurrentIdx = 0;
  pv_ni = 0;
  float look = pv_look;
  pv_wyrm_skin_draw(skin, px, py, vis, n, 0, 0, 1.0f, 0, 0, radius, pv_ang, pv_want, &look,
                    boosting, 1.0f, red, green, blue);
  pv_look = look;

  int nv = pv_list.VtxBuffer.Size;
  if (nv > max_v) nv = max_v;
  for (int i = 0; i < nv; i++) {
    out_xy[2 * i] = pv_v[i].pos.x;
    out_xy[2 * i + 1] = pv_v[i].pos.y;
    uint32_t c = pv_v[i].col; /* ImGui: A B G R from the top byte */
    out_argb[i] = (c & 0xFF000000u) | ((c & 0xFFu) << 16) | (c & 0xFF00u) | ((c >> 16) & 0xFFu);
  }
  int ni = 0;
  for (int i = 0; i + 2 < pv_ni && ni + 3 <= max_i; i += 3) {
    if (pv_i[i] >= (uint32_t)nv || pv_i[i + 1] >= (uint32_t)nv || pv_i[i + 2] >= (uint32_t)nv)
      continue;
    out_idx[ni++] = (uint16_t)pv_i[i];
    out_idx[ni++] = (uint16_t)pv_i[i + 1];
    out_idx[ni++] = (uint16_t)pv_i[i + 2];
  }
  *out_ni = ni;
  return nv;
}

#if defined(__ANDROID__) && !defined(WYRM_IOS)
#include <jni.h>

/* WyrmActivity.nativeWyrmSkinPreview: fills the arrays, returns vertex count
   in the low 16 bits and index count above them. */
JNIEXPORT jlong JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeWyrmSkinPreview(
    JNIEnv* env, jclass clazz, jint skin, jfloat w, jfloat h, jdouble now, jint rgb,
    jfloatArray xy, jintArray argb, jshortArray idx) {
  (void)clazz;
  jsize cap_v = (*env)->GetArrayLength(env, argb);
  jsize cap_xy = (*env)->GetArrayLength(env, xy) / 2;
  jsize cap_i = (*env)->GetArrayLength(env, idx);
  if (cap_xy < cap_v) cap_v = cap_xy;
  jfloat* pxy = (*env)->GetFloatArrayElements(env, xy, NULL);
  jint* pc = (*env)->GetIntArrayElements(env, argb, NULL);
  jshort* pi = (*env)->GetShortArrayElements(env, idx, NULL);
  int ni = 0, nv = 0;
  if (pxy && pc && pi)
    nv = wyrm_skin_preview_frame(skin, w, h, now, ((rgb >> 16) & 0xFF) / 255.0f,
                                 ((rgb >> 8) & 0xFF) / 255.0f, (rgb & 0xFF) / 255.0f, pxy,
                                 (uint32_t*)pc, cap_v, (uint16_t*)pi, cap_i, &ni);
  if (pi) (*env)->ReleaseShortArrayElements(env, idx, pi, 0);
  if (pc) (*env)->ReleaseIntArrayElements(env, argb, pc, 0);
  if (pxy) (*env)->ReleaseFloatArrayElements(env, xy, pxy, 0);
  return ((jlong)ni << 16) | (jlong)(nv & 0xFFFF);
}
#endif
