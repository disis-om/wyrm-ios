#include "android_skin.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>

#ifdef VLITHER_ANDROID
#include <jni.h>
#include <SDL3/SDL.h>
#include <SDL3/SDL_system.h>

#include "../game/backgrounds.h"
#include "../rendering/renderer.h"
#include "../ui/skin_editor.h"
#include "../user.h"

static tenv* skin_env = NULL;
static SDL_Mutex* skin_mutex = NULL;

/* The mailbox. Only the latest request of each kind survives. */
static int pending_preset = -1;
static int pending_accessory = -2; /* -1 is a legitimate "none" */
static int pending_mode = -1;      /* 0 default, 1 custom */
static bool pending_commit = false;
static bool pending_code = false;
static char pending_code_value[MAX_SKIN_CODE_LEN + 1] = {0};
static int pending_background = -1;
static bool pending_colors = false;
static uint32_t pending_colors_value[MAX_SKIN_CODE_LEN] = {0};
static int pending_postcard = -1;

static bool get_activity(JNIEnv** out_env, jclass* out_class) {
  *out_env = (JNIEnv*)SDL_GetAndroidJNIEnv();
  if (!*out_env) return false;
  JNIEnv* env = *out_env;
  *out_class = (*env)->FindClass(env, "com/wyrm/omrajput/WyrmActivity");
  if (!*out_class) {
    (*env)->ExceptionClear(env);
    return false;
  }
  return true;
}

static void clear_exception(JNIEnv* env) {
  if ((*env)->ExceptionCheck(env)) {
    (*env)->ExceptionDescribe(env);
    (*env)->ExceptionClear(env);
  }
}

void android_skin_bind_env(tenv* env) {
  skin_env = env;
  if (!skin_mutex) skin_mutex = SDL_CreateMutex();
}

void android_skin_publish_tables(tenv* env_ptr) {
  if (!env_ptr) return;
  game_data* gdata = &env_ptr->usr->gdata;

  JNIEnv* env = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&env, &activity_class)) return;
  jmethodID method = (*env)->GetStaticMethodID(
      env, activity_class, "setSkinTablesFromNative", "([I[B[B)V");
  if (!method) {
    (*env)->ExceptionClear(env);
    SDL_Log("Wyrm skin: setSkinTablesFromNative unavailable");
    (*env)->DeleteLocalRef(env, activity_class);
    return;
  }

  /* Palette as packed 0xRRGGBB, so Compose can draw the real colours rather
   * than an approximation of them. */
  jint palette[NUM_COLOR_GROUPS];
  for (int i = 0; i < NUM_COLOR_GROUPS; i++) {
    int r = (int)(gdata->cg_colors[i].r * 255.0f + 0.5f);
    int g = (int)(gdata->cg_colors[i].g * 255.0f + 0.5f);
    int b = (int)(gdata->cg_colors[i].b * 255.0f + 0.5f);
    palette[i] = (r << 16) | (g << 8) | b;
  }
  jintArray jpalette = (*env)->NewIntArray(env, NUM_COLOR_GROUPS);
  if (jpalette)
    (*env)->SetIntArrayRegion(env, jpalette, 0, NUM_COLOR_GROUPS, palette);

  /* The character each colour group is spelled with inside a skin code. */
  jbyteArray jmap = (*env)->NewByteArray(env, NUM_COLOR_GROUPS);
  if (jmap)
    (*env)->SetByteArrayRegion(env, jmap, 0, NUM_COLOR_GROUPS,
                               (const jbyte*)gdata->ntl_cg_map);

  /* Presets flattened as [length, cg, cg, ...] per skin, fixed stride 64. */
  jbyteArray jpresets =
      (*env)->NewByteArray(env, (jsize)(NUM_DEFAULT_SKINS * 64));
  if (jpresets)
    (*env)->SetByteArrayRegion(env, jpresets, 0, (jsize)(NUM_DEFAULT_SKINS * 64),
                               (const jbyte*)gdata->default_skins);

  if (jpalette && jmap && jpresets)
    (*env)->CallStaticVoidMethod(env, activity_class, method, jpalette, jmap,
                                 jpresets);
  clear_exception(env);
  if (jpalette) (*env)->DeleteLocalRef(env, jpalette);
  if (jmap) (*env)->DeleteLocalRef(env, jmap);
  if (jpresets) (*env)->DeleteLocalRef(env, jpresets);
  (*env)->DeleteLocalRef(env, activity_class);
}

void android_skin_publish_state(tenv* env_ptr) {
  if (!env_ptr) return;
  user_settings* settings = &env_ptr->usr->usrs;

  JNIEnv* env = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&env, &activity_class)) return;
  jmethodID method =
      (*env)->GetStaticMethodID(env, activity_class, "setSkinStateFromNative",
                                "(ZILjava/lang/String;I[II)V");
  if (!method) {
    (*env)->ExceptionClear(env);
    (*env)->DeleteLocalRef(env, activity_class);
    return;
  }

  /* Only as many colours as the code has positions: the editor pairs them by
   * index, and a trailing tail of a longer previous code would pair wrongly. */
  jsize length = (jsize)strlen(settings->skin_code);
  if (length > MAX_SKIN_CODE_LEN) length = MAX_SKIN_CODE_LEN;
  jintArray colors = (*env)->NewIntArray(env, length);
  if (colors && length > 0)
    (*env)->SetIntArrayRegion(env, colors, 0, length,
                              (const jint*)settings->skin_rgba);

  jstring code = (*env)->NewStringUTF(env, settings->skin_code);
  (*env)->CallStaticVoidMethod(
      env, activity_class, method, settings->custom_skin ? JNI_TRUE : JNI_FALSE,
      (jint)settings->default_skin, code,
      (jint)(settings->accessory < NUM_ACCESSORIES ? settings->accessory : -1),
      colors, (jint)background_clamp(settings->arena_background));
  clear_exception(env);
  if (code) (*env)->DeleteLocalRef(env, code);
  if (colors) (*env)->DeleteLocalRef(env, colors);
  (*env)->DeleteLocalRef(env, activity_class);
}

/*
 * Arena skins.
 *
 * The engine is the only thing that knows the arena's own snake ids, so it is
 * the engine that says who is worth asking about. Both of these publish only
 * when the answer changes: the point of the whole feature is that a crowded
 * arena settles into no traffic at all.
 */
/*
 * Nothing here may run on the frame clock.
 *
 * The first version of this asked once per frame. Its list of already-asked ids
 * was the same size as the skin table, so as soon as a populated arena filled
 * it, every remaining snake looked new on every frame and the engine thread
 * spent each one in FindClass and a cross-thread post. Mongoose stopped being
 * polled often enough to answer the arena's pings, and the arena dropped us at
 * around 0.7s — every attempt, five attempts, back to Home. It read exactly
 * like a protocol fault and was not one.
 *
 * So the engine only samples visible ids on a bounded 250 ms tick. Kotlin owns
 * pending, in-flight, resolved and retry state; this function never performs
 * network I/O and never changes the arena socket or its clocks.
 */
#define ARENA_SKIN_TICK_MS 250
#define ARENA_SKIN_SETTLE_MS 250

static int published_snake_id = -1;
static char published_arena[MAX_IPV4_LEN + 1] = {0};
static uint64_t playing_since_ms = 0;
static uint64_t next_request_ms = 0;

static void publish_arena_identity(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  /* This side channel is online-arena-only. AI play and every layout editor
   * deliberately use PLAYING too, so screen state alone is not authority. */
  bool playing = !gdata->ai_mode && gdata->curr_screen == PLAYING &&
                 gdata->conn == CONNECTED && gdata->arena_ready &&
                 gdata->connection && !gdata->connection->is_closing &&
                 !gdata->data.dead && gdata->data.snake_id >= 0;
  int snake_id = playing ? gdata->data.snake_id : -1;
  const char* arena = playing ? usr->usrs.ipv4 : "";

  if (snake_id == published_snake_id && strcmp(arena, published_arena) == 0)
    return;
  published_snake_id = snake_id;
  snprintf(published_arena, sizeof(published_arena), "%s", arena);
  playing_since_ms = playing ? (uint64_t)SDL_GetTicks() : 0;
  next_request_ms = playing_since_ms + ARENA_SKIN_SETTLE_MS;

  /* Compose is told the worn skin only on its way into the editor, so a player
   * who never opened it this session has an empty skin state — and the publish
   * below reads exactly that and finds nothing worth sending. Refreshing first
   * is what makes a built skin visible to anyone at all. Both calls land on the
   * UI thread in order, so the state is there before it is read. */
  android_skin_publish_state(env);

  JNIEnv* env_jni = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&env_jni, &activity_class)) return;
  jmethodID method = (*env_jni)->GetStaticMethodID(
      env_jni, activity_class, "publishArenaSkinFromNative",
      "(Ljava/lang/String;ILjava/lang/String;)V");
  if (!method) {
    (*env_jni)->ExceptionClear(env_jni);
    (*env_jni)->DeleteLocalRef(env_jni, activity_class);
    return;
  }
  jstring jarena = (*env_jni)->NewStringUTF(env_jni, arena);
  jstring jnick = (*env_jni)->NewStringUTF(env_jni, usr->usrs.nickname);
  (*env_jni)->CallStaticVoidMethod(env_jni, activity_class, method, jarena,
                                   (jint)snake_id, jnick);
  clear_exception(env_jni);
  if (jarena) (*env_jni)->DeleteLocalRef(env_jni, jarena);
  if (jnick) (*env_jni)->DeleteLocalRef(env_jni, jnick);
  (*env_jni)->DeleteLocalRef(env_jni, activity_class);
}

static void request_visible_skins(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  if (gdata->ai_mode || gdata->curr_screen != PLAYING ||
      gdata->conn != CONNECTED || !gdata->arena_ready ||
      !gdata->connection || gdata->connection->is_closing ||
      gdata->data.dead || published_snake_id < 0) return;
  /* Admission owns the first seconds of a match. Nothing decorative may share
   * the engine thread with it. */
  if (!playing_since_ms) return;
  uint64_t now_ms = (uint64_t)SDL_GetTicks();
  if (now_ms < next_request_ms) return;
  next_request_ms = now_ms + ARENA_SKIN_TICK_MS;
  int ids[MAX_REMOTE_SKINS];
  int count = 0;
  int snakes_len = tdarray_length(gdata->data.snakes);
  for (int i = 0; i < snakes_len && count < MAX_REMOTE_SKINS; ++i) {
    snake* o = gdata->data.snakes + i;
    if (o->dead || !o->cusk || o->id == gdata->data.snake_id) continue;
    ids[count++] = o->id;
  }
  if (!count) return;

  JNIEnv* env_jni = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&env_jni, &activity_class)) return;
  jmethodID method = (*env_jni)->GetStaticMethodID(
      env_jni, activity_class, "requestArenaSkinsFromNative", "([I)V");
  if (!method) {
    (*env_jni)->ExceptionClear(env_jni);
    (*env_jni)->DeleteLocalRef(env_jni, activity_class);
    return;
  }
  jintArray jids = (*env_jni)->NewIntArray(env_jni, count);
  if (jids) {
    (*env_jni)->SetIntArrayRegion(env_jni, jids, 0, count, (const jint*)ids);
    (*env_jni)->CallStaticVoidMethod(env_jni, activity_class, method, jids);
    clear_exception(env_jni);
    (*env_jni)->DeleteLocalRef(env_jni, jids);
  }
  (*env_jni)->DeleteLocalRef(env_jni, activity_class);
}

void android_skin_poll(tenv* env) {
  if (!env || !skin_mutex) return;
  publish_arena_identity(env);
  request_visible_skins(env);

  int preset, accessory, mode;
  bool commit, code_changed, colors_changed;
  int background;
  int postcard;
  char code[MAX_SKIN_CODE_LEN + 1];
  uint32_t colors[MAX_SKIN_CODE_LEN];

  SDL_LockMutex(skin_mutex);
  preset = pending_preset;
  accessory = pending_accessory;
  mode = pending_mode;
  commit = pending_commit;
  code_changed = pending_code;
  colors_changed = pending_colors;
  background = pending_background;
  postcard = pending_postcard;
  if (code_changed) memcpy(code, pending_code_value, sizeof(code));
  if (colors_changed) memcpy(colors, pending_colors_value, sizeof(colors));
  pending_preset = -1;
  pending_accessory = -2;
  pending_mode = -1;
  pending_commit = false;
  pending_code = false;
  pending_colors = false;
  pending_background = -1;
  pending_postcard = -1;
  SDL_UnlockMutex(skin_mutex);

  tuser_data* user = env->usr;
  user_settings* settings = &user->usrs;
  bool touched = false;

  if (preset >= 0 && preset < NUM_DEFAULT_SKINS) {
    settings->default_skin = (uint8_t)preset;
    settings->custom_skin = false;
    touched = true;
  }
  if (mode >= 0) {
    settings->custom_skin = mode == 1;
    touched = true;
  }
  if (code_changed) {
    snprintf(settings->skin_code, sizeof(settings->skin_code), "%s", code);
    /* An empty custom code has nothing to render, so the engine treats it as
     * no custom skin at all — mirrored here so Compose and the engine agree. */
    settings->custom_skin = settings->skin_code[0] != 0;
    /* Colours are positional. A code that arrives without them is a typed or
     * pasted one, so the old mixture must not survive under the new letters. */
    if (!colors_changed)
      memset(settings->skin_rgba, 0, sizeof(settings->skin_rgba));
    touched = true;
  }
  if (colors_changed) {
    memcpy(settings->skin_rgba, colors, sizeof(settings->skin_rgba));
    touched = true;
  }
  if (background >= 0) {
    settings->arena_background = background_clamp(background);
    /* The renderer holds one background resident, so the swap happens here on
       the engine thread rather than from the mailbox writer's. */
    renderer_set_background(env->usr->r, env->ctx, settings->arena_background);
    touched = true;
  }
  if (accessory >= -1) {
    settings->accessory =
        accessory < 0 ? NO_ACCESSORY : (uint8_t)accessory;
    touched = true;
  }

  if (touched) android_skin_publish_state(env);

  if (postcard >= 0) {
    ui_skin_editor_set_postcard(postcard == 1);
    if (postcard == 1) {
      android_skin_publish_tables(env);
      android_skin_publish_state(env);
    }
  }

  if (commit) {
    save_user_settings(settings);
    user->gdata.curr_screen = TITLE_SCREEN;
  }
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSkinSetPreset(JNIEnv* env,
                                                        jclass clazz,
                                                        jint preset) {
  (void)env;
  (void)clazz;
  if (!skin_mutex) return;
  SDL_LockMutex(skin_mutex);
  pending_preset = (int)preset;
  SDL_UnlockMutex(skin_mutex);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSkinSetMode(JNIEnv* env, jclass clazz,
                                                      jboolean custom) {
  (void)env;
  (void)clazz;
  if (!skin_mutex) return;
  SDL_LockMutex(skin_mutex);
  pending_mode = custom == JNI_TRUE ? 1 : 0;
  SDL_UnlockMutex(skin_mutex);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSkinSetCode(JNIEnv* env, jclass clazz,
                                                      jstring code) {
  (void)clazz;
  if (!skin_mutex) return;
  const char* text = code ? (*env)->GetStringUTFChars(env, code, NULL) : NULL;
  SDL_LockMutex(skin_mutex);
  snprintf(pending_code_value, sizeof(pending_code_value), "%s",
           text ? text : "");
  pending_code = true;
  SDL_UnlockMutex(skin_mutex);
  if (text) (*env)->ReleaseStringUTFChars(env, code, text);
}

/**
 * The exact colours a built skin carries, one per position of the code that
 * arrives with it. Anything the array does not cover renders from the palette.
 */
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSkinSetColors(JNIEnv* env,
                                                        jclass clazz,
                                                        jintArray colors) {
  (void)clazz;
  if (!skin_mutex) return;
  jsize length = colors ? (*env)->GetArrayLength(env, colors) : 0;
  if (length > MAX_SKIN_CODE_LEN) length = MAX_SKIN_CODE_LEN;
  SDL_LockMutex(skin_mutex);
  memset(pending_colors_value, 0, sizeof(pending_colors_value));
  if (length > 0)
    (*env)->GetIntArrayRegion(env, colors, 0, length,
                              (jint*)pending_colors_value);
  pending_colors = true;
  SDL_UnlockMutex(skin_mutex);
}

/*
 * What another Wyrm player's snake looks like, as answered by Wyrm's backend.
 *
 * The backing store grows with demand and uses a bounded LRU. Kotlin owns the
 * request queue, so an id evicted here remains eligible for a later re-fetch.
 */
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeArenaSkinSet(JNIEnv* env, jclass clazz,
                                                       jint snake_id,
                                                       jstring nickname,
                                                       jintArray colors) {
  (void)clazz;
  if (!skin_env) return;
  game_data* gdata = &skin_env->usr->gdata;

  if (!gdata->remote_skins) gdata->remote_skins = tdarray_create(remote_skin);
  int count = (int)tdarray_length(gdata->remote_skins);
  int slot = -1;
  for (int i = 0; i < count; ++i)
    if (gdata->remote_skins[i].snake_id == (int)snake_id) slot = i;
  if (slot < 0) {
    if (count >= MAX_REMOTE_SKINS) {
      int oldest = 0;
      for (int i = 1; i < count; ++i)
        if (gdata->remote_skins[i].last_used_ms <
            gdata->remote_skins[oldest].last_used_ms) oldest = i;
      tdarray_remove(gdata->remote_skins, oldest);
      count--;
    }
    remote_skin empty = {0};
    tdarray_push(&gdata->remote_skins, &empty);
    slot = count;
  }

  remote_skin* skin = gdata->remote_skins + slot;
  memset(skin, 0, sizeof(*skin));
  skin->snake_id = (int)snake_id;
  const char* text = nickname ? (*env)->GetStringUTFChars(env, nickname, NULL) : NULL;
  snprintf(skin->nickname, sizeof(skin->nickname), "%s", text ? text : "");
  if (text) (*env)->ReleaseStringUTFChars(env, nickname, text);

  jsize length = colors ? (*env)->GetArrayLength(env, colors) : 0;
  if (length > MAX_SKIN_CODE_LEN) length = MAX_SKIN_CODE_LEN;
  if (length > 0)
    (*env)->GetIntArrayRegion(env, colors, 0, length, (jint*)skin->rgba);
  skin->length = (int)length;
  skin->last_used_ms = SDL_GetTicks();
}

/** Leaving an arena: nothing learned in it means anything in the next one. */
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeArenaSkinsClear(JNIEnv* env,
                                                          jclass clazz) {
  (void)env;
  (void)clazz;
  if (!skin_env) return;
  if (skin_env->usr->gdata.remote_skins)
    tdarray_clear(skin_env->usr->gdata.remote_skins);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSkinSetBackground(JNIEnv* env,
                                                            jclass clazz,
                                                            jint index) {
  (void)env;
  (void)clazz;
  if (!skin_mutex) return;
  SDL_LockMutex(skin_mutex);
  pending_background = (int)index;
  SDL_UnlockMutex(skin_mutex);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSkinSetAccessory(JNIEnv* env,
                                                           jclass clazz,
                                                           jint accessory) {
  (void)env;
  (void)clazz;
  if (!skin_mutex) return;
  SDL_LockMutex(skin_mutex);
  pending_accessory = (int)accessory;
  SDL_UnlockMutex(skin_mutex);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSkinCommit(JNIEnv* env,
                                                     jclass clazz) {
  (void)env;
  (void)clazz;
  if (!skin_mutex) return;
  SDL_LockMutex(skin_mutex);
  pending_commit = true;
  SDL_UnlockMutex(skin_mutex);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSkinSetLayout(
    JNIEnv* env, jclass clazz, jfloat preview_cy, jfloat preview_scale,
    jfloat accessory_x, jfloat accessory_y, jfloat accessory_cell,
    jfloat accessory_gap) {
  (void)env;
  (void)clazz;
  ui_skin_editor_set_layout(preview_cy, preview_scale, accessory_x, accessory_y,
                            accessory_cell, accessory_gap);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSkinSetPostcard(JNIEnv* env,
                                                          jclass clazz,
                                                          jboolean on) {
  (void)env;
  (void)clazz;
  if (!skin_mutex) return;
  SDL_LockMutex(skin_mutex);
  pending_postcard = on == JNI_TRUE ? 1 : 0;
  SDL_UnlockMutex(skin_mutex);
}

#else

void android_skin_bind_env(tenv* env) { (void)env; }
void android_skin_poll(tenv* env) { (void)env; }
void android_skin_publish_tables(tenv* env) { (void)env; }
void android_skin_publish_state(tenv* env) { (void)env; }

#endif
