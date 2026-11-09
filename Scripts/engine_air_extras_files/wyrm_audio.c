/* AIR's sounds (OM, 2026-11-08): the engine decides what plays, exactly as
 * Main.as does; the apps play the files (Android data/WyrmSound.kt, iOS
 * WyrmSound.swift) from res/sounds/ (AIR's own mp3s and the SWF's sounds).
 *
 *   B<n>       a snake died on screen: bloops/<n>.mp3 (Main.as deadSnakeSound:
 *              only when one of its points is inside the view box, which
 *              follows the zoom; n = 16 - ceil(16 * sct / mscps))
 *   F<n>,<o>   your snake ate: foods_2/<n+1>.mp3 (new sounds) or
 *              foods_1/<o+1>.mp3 (old sounds), Main.as's two formulas
 *   K          your snake died (new music fades, old music slows down)
 * plus the boost state (Main.as: your snake faster than its base speed).
 */
#include "wyrm_audio.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <SDL3/SDL.h>

#define AUDIO_QUEUE 2048
static char queue[AUDIO_QUEUE];
static int queue_len;
static SDL_Mutex* queue_lock;
static float view_hw = 400.0f, view_hh = 300.0f; /* half screen, pixels */
static int boosting;
static float fk; /* Main.as `fk`: the new eat sounds climb as you keep eating */

static void push(const char* event) {
  if (!queue_lock) queue_lock = SDL_CreateMutex();
  if (!queue_lock) return;
  SDL_LockMutex(queue_lock);
  int n = (int)strlen(event);
  if (queue_len + n + 2 < AUDIO_QUEUE) {
    if (queue_len) queue[queue_len++] = ' ';
    memcpy(queue + queue_len, event, (size_t)n);
    queue_len += n;
    queue[queue_len] = '\0';
  }
  SDL_UnlockMutex(queue_lock);
}

void wyrm_audio_view(float half_w, float half_h) {
  if (half_w > 0 && half_h > 0) {
    view_hw = half_w;
    view_hh = half_h;
  }
}

void wyrm_audio_snake_died(game_data* g, snake* o, bool own) {
  if (!g || !o) return;
  if (own) push("K");
  float gsc = g->data.gsc > 0 ? g->data.gsc : 1.0f;
  float bw = view_hw / gsc + 25.0f, bh = view_hh / gsc + 25.0f;
  float x1 = g->data.view_xx - bw, x2 = g->data.view_xx + bw;
  float y1 = g->data.view_yy - bh, y2 = g->data.view_yy + bh;
  bool seen = false;
  int n = (int)tdarray_length(o->pts);
  for (int i = n - 1; i >= 0 && !seen; i--) {
    float x = o->pts[i].xx + o->pts[i].fx, y = o->pts[i].yy + o->pts[i].fy;
    seen = x >= x1 && y >= y1 && x <= x2 && y <= y2;
  }
  if (!seen) return;
  const int bpc = 16;
  int mscps = g->data.mscps > 0 ? g->data.mscps : 411;
  int index = bpc - (int)ceil(bpc * ((double)o->sct / mscps));
  if (index <= 0) index = 0;
  if (index >= bpc) index = bpc - 1;
  char event[8];
  snprintf(event, sizeof(event), "B%d", index);
  push(event);
}

void wyrm_audio_food_eaten(float size) {
  /* Main.as newFood: sz = 0.9 * ((3.6 + (s - 1.3)^2 / 23.5) / 16). */
  double sz = 0.9 * ((3.6 + (size - 1.3) * (size - 1.3) / 23.5) / 16.0);
  double t = (sz - 0.209) / (0.652 - 0.209);
  /* New sounds (foods_2, 80). */
  const int fdc = 80;
  double k = 0.15 + 0.85 * t;
  fk += (float)((fdc - 1 - fk) * 0.01 * k);
  fk += (float)(0.5 * k);
  if (fk >= fdc) fk = fdc - 1;
  int fresh = (int)(k * fdc * 0.1 + fk + ((double)rand() / RAND_MAX) * 9 - 5);
  if (fresh <= 0) fresh = 0;
  if (fresh >= fdc) fresh = fdc - 1;
  /* Old sounds (foods_1, 11). */
  const int fdoc = 11;
  double half = fdoc / 2.0;
  int old = fdoc - (int)ceil(fdoc * t);
  if (old <= 0) old = 0;
  if (old >= fdoc) old = fdoc - 1;
  double r = (double)rand() / RAND_MAX;
  if (r < 0.08) old += old < half ? 2 : -2;
  else if (r < 0.4) old += old < half ? 1 : -1;
  if (old < 0) old = 0;
  if (old >= fdoc) old = fdoc - 1;
  char event[16];
  snprintf(event, sizeof(event), "F%d,%d", fresh, old);
  push(event);
}

void wyrm_audio_frame(game_data* g) {
  /* Main.as: fk += (0 - fk) * p002[vfrb], p002[n] = 1 - 0.998^n, so a pause
     between bites lets the new eat sounds fall back down. */
  if (g && fk > 0 && g->data.vfrb > 0) {
    fk *= powf(0.998f, (float)g->data.vfrb);
    if (fk < 0) fk = 0;
  }
  int on = 0;
  if (g && g->data.snake_id >= 0) {
    int n = (int)tdarray_length(g->data.snakes);
    for (int i = 0; i < n; i++) {
      snake* o = g->data.snakes + i;
      if (o->id == g->data.snake_id) {
        on = !o->dead && o->tsp > o->fsp;
        break;
      }
    }
  }
  boosting = on;
}

/* "<boost 0/1>|<events>" and the queue empties. */
int wyrm_audio_take(char* out, int size) {
  if (!out || size < 4) return 0;
  if (!queue_lock) queue_lock = SDL_CreateMutex();
  if (queue_lock) SDL_LockMutex(queue_lock);
  int n = snprintf(out, (size_t)size, "%d|%s", boosting, queue);
  queue_len = 0;
  queue[0] = '\0';
  if (queue_lock) SDL_UnlockMutex(queue_lock);
  return n;
}

#ifdef WYRM_IOS
const char* WyrmIOSAudioTake(void) {
  static char out[AUDIO_QUEUE + 8];
  wyrm_audio_take(out, (int)sizeof(out));
  return out;
}
#endif
#ifdef WYRM_SDL_JNI
#include <jni.h>
JNIEXPORT jstring JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeAudioTake(JNIEnv* env, jclass clazz) {
  (void)clazz;
  static char out[AUDIO_QUEUE + 8];
  wyrm_audio_take(out, (int)sizeof(out));
  return (*env)->NewStringUTF(env, out);
}
#endif
