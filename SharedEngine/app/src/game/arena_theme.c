#include "arena_theme.h"

#include <jni.h>
#include <stdatomic.h>

/* Paper defaults keep native startup deterministic before Compose attaches. */
static _Atomic uint32_t colours[ARENA_THEME_ROLE_COUNT] = {
    0xFFF7F6F3u, 0xFFFFFFFFu, 0xFF37352Fu, 0xFFFFFFFFu,
    0xFF787774u, 0xFF6B6660u, 0x1437352Fu, 0xFF448361u,
    0xFF2F6FDEu, 0xFFF0EEE9u, 0xFFEFEDE8u, 0xFFC4554Du,
};
static _Atomic bool dark_theme = false;

static uint8_t byte(float value) {
  if (value <= 0.0f) return 0;
  if (value >= 255.0f) return 255;
  return (uint8_t)(value + 0.5f);
}

uint32_t arena_theme_colour(arena_theme_role role, float alpha) {
  if (role < 0 || role >= ARENA_THEME_ROLE_COUNT) role = ARENA_THEME_INK;
  uint32_t argb = atomic_load_explicit(&colours[role], memory_order_relaxed);
  uint8_t a = byte((float)((argb >> 24) & 0xffu) * alpha);
  uint8_t r = (uint8_t)((argb >> 16) & 0xffu);
  uint8_t g = (uint8_t)((argb >> 8) & 0xffu);
  uint8_t b = (uint8_t)(argb & 0xffu);
  return ((uint32_t)a << 24) | ((uint32_t)b << 16) | ((uint32_t)g << 8) | r;
}

uint32_t arena_theme_overlay_text(float alpha) {
  return arena_theme_colour(
      atomic_load_explicit(&dark_theme, memory_order_relaxed)
          ? ARENA_THEME_INK
          : ARENA_THEME_PAPER,
      alpha);
}

void arena_theme_set(const uint32_t next[ARENA_THEME_ROLE_COUNT], bool dark) {
  if (!next) return;
  for (int i = 0; i < ARENA_THEME_ROLE_COUNT; ++i)
    atomic_store_explicit(&colours[i], next[i], memory_order_relaxed);
  atomic_store_explicit(&dark_theme, dark, memory_order_release);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetArenaTheme(JNIEnv* env,
                                                         jclass clazz,
                                                         jintArray packed,
                                                         jboolean dark) {
  (void)clazz;
  if (!packed || (*env)->GetArrayLength(env, packed) < ARENA_THEME_ROLE_COUNT)
    return;
  jint incoming[ARENA_THEME_ROLE_COUNT];
  (*env)->GetIntArrayRegion(env, packed, 0, ARENA_THEME_ROLE_COUNT, incoming);
  if ((*env)->ExceptionCheck(env)) return;
  uint32_t next[ARENA_THEME_ROLE_COUNT];
  for (int i = 0; i < ARENA_THEME_ROLE_COUNT; ++i)
    next[i] = (uint32_t)incoming[i];
  arena_theme_set(next, dark == JNI_TRUE);
}
