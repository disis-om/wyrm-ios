#include "rain_bridge.h"
#if defined(WYRM_SDL_JNI) || defined(WYRM_IOS)
#include <SDL3/SDL.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "../user.h"
#include "../network/server.h"
#define RAIN_JOIN_MAX 1024
// Engine writes a bounded snapshot; platform readers never touch live snakes.
// No credentials here, no transport/render work, no new arena socket.
static SDL_Mutex* rain_mutex;
static SDL_AtomicInt rain_init_state;
static bool rain_enabled, rain_requested;
static int rain_rotation;
static struct mg_connection* rain_connection;
static uint64_t rain_generation, rain_turn_at, rain_updated_at;
static char rain_join[RAIN_JOIN_MAX * 2 + 1];
static char rain_snapshot[6144] = "{}";
void wyrm_rain_init(void) {
  if (SDL_CompareAndSwapAtomicInt(&rain_init_state, 0, 1)) {
    rain_mutex = SDL_CreateMutex(); SDL_SetAtomicInt(&rain_init_state, 2);
  } else while (SDL_GetAtomicInt(&rain_init_state) != 2) SDL_Delay(1);
}
void wyrm_rain_enable(bool on) {
  wyrm_rain_init();
  if (!rain_mutex) return;
  SDL_LockMutex(rain_mutex);
  rain_enabled = on; rain_requested = on;
  if (!on) { rain_rotation = 0; strcpy(rain_snapshot, "{}"); }
  SDL_UnlockMutex(rain_mutex);
}
void wyrm_rain_rotate(int direction) {
  if (!rain_mutex) return;
  SDL_LockMutex(rain_mutex);
  rain_rotation = rain_enabled && direction >= -1 && direction <= 1 ? direction : 0;
  SDL_UnlockMutex(rain_mutex);
}
bool wyrm_rain_rotating(void) {
  if (!rain_mutex) return false;
  SDL_LockMutex(rain_mutex); bool on = rain_enabled && rain_rotation != 0;
  SDL_UnlockMutex(rain_mutex); return on;
}
void wyrm_rain_capture(struct mg_connection* connection, const void* data, size_t length) {
  // A heading is one byte and can also equal 's'. The real web join has a
  // 28-byte minimum and its fixed 30 marker; the challenge answer is 27 bytes.
  if (!rain_mutex || !data || length < 28 || length > RAIN_JOIN_MAX ||
      ((const uint8_t*)data)[0] != 's' || ((const uint8_t*)data)[1] != 30) return;
  const char* hex = "0123456789abcdef";
  SDL_LockMutex(rain_mutex);
  rain_connection = connection; ++rain_generation; rain_rotation = 0;
  for (size_t i = 0; i < length; i++) {
    uint8_t byte = ((const uint8_t*)data)[i];
    rain_join[i * 2] = hex[byte >> 4]; rain_join[i * 2 + 1] = hex[byte & 15];
  }
  rain_join[length * 2] = 0;
  SDL_UnlockMutex(rain_mutex);
}
void wyrm_rain_read(char* out, size_t capacity) {
  if (!out || !capacity) return;
  if (!rain_mutex) { snprintf(out, capacity, "{}"); return; }
  SDL_LockMutex(rain_mutex);
  snprintf(out, capacity, "%s", SDL_GetTicks() - rain_updated_at > 500 ? "{}" : rain_snapshot);
  rain_requested = rain_enabled;
  SDL_UnlockMutex(rain_mutex);
}
void wyrm_rain_tick(tenv* env) {
  if (!rain_mutex || !env || !env->usr) return;
  game_data* g = &env->usr->gdata;
  size_t length = tdarray_length(g->data.snakes);
  snake* me = g->data.follow_view && length > 0 ? g->data.snakes + length - 1 : NULL;
  if (me && me->id != g->data.snake_id) me = NULL;
  SDL_LockMutex(rain_mutex);
  if (!rain_enabled) { SDL_UnlockMutex(rain_mutex); return; }
  bool alive = g->connection && !g->closed && g->arena_ready && !g->ai_mode && me && !me->dead;
  if (!alive || g->connection != rain_connection || env->usr->usrs.hotkeys[HOTKEY_BOT].active) rain_rotation = 0;
  int rotate = rain_rotation;
  bool requested = rain_requested; rain_requested = false;
  if (requested) {
    rain_updated_at = SDL_GetTicks();
    // Arena labels come from the validated endpoint, not player text.
    const char* arena = alive ? user_settings_arena(&env->usr->usrs) : "";
    float x = alive ? me->xx + me->fx : 0, y = alive ? me->yy + me->fy : 0;
    float ang = alive ? me->ang : 0;
    if (!isfinite(x) || !isfinite(y) || !isfinite(ang)) { x = y = ang = 0; alive = false; }
    int n = snprintf(rain_snapshot, sizeof(rain_snapshot),
      "{\"alive\":%s,\"generation\":%llu,\"arena\":\"%s\",\"x\":%.3f,\"y\":%.3f,\"angle\":%.6f,\"zoom\":%.6f,\"join\":\"%s\",\"targets\":[",
      alive ? "true" : "false", (unsigned long long)rain_generation, arena, x, y, ang,
      isfinite(g->data.gsc) && g->data.gsc > 0 ? g->data.gsc : 1,
      alive && g->connection == rain_connection ? rain_join : "");
    // Nearest sixteen visible snakes, bounded work only when a reader asks.
    snake* nearest[16] = {0}; float distances[16];
    for (int i = 0; i < 16; i++) distances[i] = INFINITY;
    if (alive) for (int i = 0; i < tdarray_length(g->data.snakes); i++) {
      snake* other = &g->data.snakes[i];
      if (other == me || other->dead) continue;
      float dx = other->xx - x, dy = other->yy - y, d = dx * dx + dy * dy;
      if (!isfinite(d)) continue;
      for (int at = 0; at < 16; at++) if (d < distances[at]) {
        for (int k = 15; k > at; k--) { nearest[k] = nearest[k-1]; distances[k] = distances[k-1]; }
        nearest[at] = other; distances[at] = d; break;
      }
    }
    for (int i = 0; i < 16 && nearest[i] && n > 0 && n < (int)sizeof(rain_snapshot) - 100; i++) {
      snake* target = nearest[i];
      int id = me->ntl_id != me->id ? target->ntl_id & 1023 : target->id;
      n += snprintf(rain_snapshot + n, sizeof(rain_snapshot) - n,
        "%s{\"id\":%d,\"x\":%.0f,\"y\":%.0f}", i ? "," : "", id, target->xx, target->yy);
    }
    if (n > 0 && n < (int)sizeof(rain_snapshot) - 3) strcpy(rain_snapshot + n, "]}");
    else strcpy(rain_snapshot, "{}");
  }
  SDL_UnlockMutex(rain_mutex);
  uint64_t now = SDL_GetTicks();
  if (rotate && alive && now - rain_turn_at >= 50) {
    rain_turn_at = now;
    float angle = fmodf(me->ang + rotate * (float)(PI * 0.75) + PI2, PI2);
    uint8_t byte = (uint8_t)floorf(250 * angle / PI2);
    arena_send(g->connection, &byte, 1);
  }
}
#ifdef WYRM_SDL_JNI
#include <jni.h>
JNIEXPORT jstring JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeRainRead(JNIEnv* env, jclass c) {
  (void)c; char text[6144]; wyrm_rain_read(text, sizeof(text)); return (*env)->NewStringUTF(env, text);
}
JNIEXPORT void JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeRainEnable(JNIEnv* env, jclass c, jboolean on) {
  (void)env; (void)c; wyrm_rain_enable(on);
}
JNIEXPORT void JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeRainRotate(JNIEnv* env, jclass c, jint direction) {
  (void)env; (void)c; wyrm_rain_rotate(direction);
}
#endif
#else
void wyrm_rain_init(void) {}
void wyrm_rain_capture(struct mg_connection* c, const void* d, size_t n) { (void)c; (void)d; (void)n; }
void wyrm_rain_tick(struct tenv* e) { (void)e; }
void wyrm_rain_read(char* out, size_t n) { if (out && n) out[0] = 0; }
void wyrm_rain_enable(bool on) { (void)on; }
void wyrm_rain_rotate(int d) { (void)d; }
bool wyrm_rain_rotating(void) { return false; }
#endif
