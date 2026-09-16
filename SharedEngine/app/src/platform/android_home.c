#include "android_home.h"

#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#ifdef VLITHER_ANDROID
#include <jni.h>
#include <SDL3/SDL.h>
#include <SDL3/SDL_system.h>

#include "../network/server.h"
#include "../network/arena_protocol.h"
#include "../game/ai_mode.h"
#include "../game/ui_overlay.h"
#include "../ui/lobby.h"
#include "../user.h"
#include "android_team.h"

static tenv* home_env = NULL;
static SDL_Mutex* home_mutex = NULL;

/*
 * The mailbox. Compose writes it from the Android main thread, the engine
 * drains it once a frame, and it only ever holds the most recent request of
 * each kind — a second tap on Play before the first is applied is the same
 * intent, not a queue of matches.
 */
static bool pending_enter = false;
static bool pending_ai_enter = false;
static bool pending_ai_editor_enter = false;
static bool pending_ai_editor_exit = false;
static bool pending_editor_leaderboard_toggle = false;
static char pending_nickname[MAX_NICKNAME_LEN + 1] = {0};
static bool pending_nickname_save = false;
static char pending_saved_nickname[MAX_NICKNAME_LEN + 1] = {0};
static char pending_enter_arena[MAX_IPV4_LEN + 1] = {0};
static uint64_t pending_enter_id = 0;
static uint64_t last_enter_id = 0;
static int pending_screen = -1;
static bool pending_death_play = false;
static bool pending_death_home = false;
/* -1 nothing asked, 0 off, 1 on. Written by Compose from the card. */
static int pending_auto_respawn = -1;
static char pending_arena[MAX_IPV4_LEN + 1] = {0};

/* Source death wait, then frame-scaled login fade. No automatic respawn. */
static bool death_active = false;
static bool death_watching = false;
static Uint64 death_began_at = 0;
static float death_opacity = 1;
static bool run_recorded = false;

static bool get_activity(JNIEnv** out_env, jclass* out_class) {
  *out_env = (JNIEnv*)SDL_GetAndroidJNIEnv();
  if (!*out_env) {
    SDL_Log("Wyrm home: JNI environment unavailable");
    return false;
  }
  JNIEnv* env = *out_env;
  *out_class = (*env)->FindClass(env, "com/wyrm/omrajput/WyrmActivity");
  if (!*out_class) {
    (*env)->ExceptionClear(env);
    SDL_Log("Wyrm home: activity class unavailable");
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

void android_home_begin_life(void) { run_recorded = false; }

void android_home_reset_death(void) {
  death_opacity = 1;
  death_watching = false;
  death_active = false;
  run_recorded = false;
}

static void record_finished_run(tenv* env) {
  user_settings* settings = &env->usr->usrs;
  JNIEnv* jni = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&jni, &activity_class)) return;
  jmethodID method = (*jni)->GetStaticMethodID(
      jni, activity_class, "recordRunFromNative", "(II)V");
  if (method) {
    (*jni)->CallStaticVoidMethod(jni, activity_class, method,
                                 (jint)settings->score,
                                 (jint)settings->kills);
    clear_exception(jni);
  } else {
    (*jni)->ExceptionClear(jni);
    SDL_Log("Wyrm home: recordRunFromNative unavailable");
  }
  (*jni)->DeleteLocalRef(jni, activity_class);
}

void android_home_bind_env(tenv* env) {
  home_env = env;
  if (!home_mutex) home_mutex = SDL_CreateMutex();
}

void android_home_set_screen(int screen) {
  JNIEnv* env = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&env, &activity_class)) return;
  jmethodID method = (*env)->GetStaticMethodID(env, activity_class,
                                               "setScreenFromNative", "(I)V");
  if (!method) {
    (*env)->ExceptionClear(env);
    SDL_Log("Wyrm home: setScreenFromNative unavailable");
    (*env)->DeleteLocalRef(env, activity_class);
    return;
  }
  (*env)->CallStaticVoidMethod(env, activity_class, method, (jint)screen);
  clear_exception(env);
  (*env)->DeleteLocalRef(env, activity_class);
}

void android_home_publish_state(tenv* env_ptr) {
  if (!env_ptr) return;
  user_settings* settings = &env_ptr->usr->usrs;

  JNIEnv* env = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&env, &activity_class)) return;
  jmethodID method = (*env)->GetStaticMethodID(
      env, activity_class, "setHomeStateFromNative",
      "(Ljava/lang/String;Ljava/lang/String;II)V");
  if (!method) {
    (*env)->ExceptionClear(env);
    SDL_Log("Wyrm home: setHomeStateFromNative unavailable");
    (*env)->DeleteLocalRef(env, activity_class);
    return;
  }

  jstring nickname = (*env)->NewStringUTF(env, settings->nickname);
  jstring arena = (*env)->NewStringUTF(env, settings->ipv4);
  /* Score and kills come along so the profile has something true to show even
   * before an account exists to sync them to. */
  (*env)->CallStaticVoidMethod(env, activity_class, method, nickname, arena,
                               (jint)settings->score, (jint)settings->kills);
  clear_exception(env);
  if (nickname) (*env)->DeleteLocalRef(env, nickname);
  if (arena) (*env)->DeleteLocalRef(env, arena);
  (*env)->DeleteLocalRef(env, activity_class);
}

void android_home_arena_refused(const char* endpoint, int seconds) {
  if (!endpoint || !endpoint[0] || seconds <= 0) return;

  JNIEnv* env = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&env, &activity_class)) return;
  jmethodID method = (*env)->GetStaticMethodID(
      env, activity_class, "setArenaRefusedFromNative",
      "(Ljava/lang/String;I)V");
  if (!method) {
    /* Additive on the Java side, so an engine running against an older shell
       simply keeps the mark to itself rather than failing the join. */
    (*env)->ExceptionClear(env);
    (*env)->DeleteLocalRef(env, activity_class);
    return;
  }

  jstring arena = (*env)->NewStringUTF(env, endpoint);
  (*env)->CallStaticVoidMethod(env, activity_class, method, arena,
                               (jint)seconds);
  clear_exception(env);
  if (arena) (*env)->DeleteLocalRef(env, arena);
  (*env)->DeleteLocalRef(env, activity_class);
}

bool android_home_death_active(void) { return death_active; }

/**
 * Puts the card up. Nothing spawns behind it.
 *
 * It used to hand the arena to the bot and take a fresh snake immediately, so
 * the card sat over a live game. That is gone: the player asked for the
 * spawning to stop, and it was the spawning that made death feel like being
 * shoved back in before you had looked at what happened. The arena is left as
 * it is — usually already hung up — and the card covers it.
 */
static void raise_death_card(tenv* env) {
  tuser_data* user = env->usr;
  game_data* gdata = &user->gdata;
  user_settings* settings = &user->usrs;

  death_active = true;
  gdata->restart_req = false;

  if (gdata->connection) game_close_connection(gdata, "died");

  JNIEnv* jni = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&jni, &activity_class)) return;
  jmethodID method = (*jni)->GetStaticMethodID(jni, activity_class,
                                               "setDeathFromNative", "(ZIIDZ)V");
  if (!method) {
    (*jni)->ExceptionClear(jni);
    SDL_Log("Wyrm home: setDeathFromNative unavailable");
    (*jni)->DeleteLocalRef(jni, activity_class);
    return;
  }
  (*jni)->CallStaticVoidMethod(jni, activity_class, method, JNI_TRUE,
                               (jint)settings->score, (jint)settings->kills,
                               (jdouble)settings->play_time,
                               settings->auto_respawn ? JNI_TRUE : JNI_FALSE);
  clear_exception(jni);
  (*jni)->DeleteLocalRef(jni, activity_class);
}

static void return_to_lobby_after_death(tenv* env) {
  death_watching = false;
  death_active = false;
  env->usr->gdata.restart_req = false;
  env->usr->gdata.leaving = false;
  env->usr->gdata.stay_in_lobby = true;
  env->usr->gdata.curr_screen = LOBBY;
  /* A champion's socket remains open for the separate victory exchange. */
  if (!env->usr->gdata.data.victory_message_requested ||
      env->usr->gdata.data.want_close_socket) {
    env->usr->gdata.leaving = true;
    game_close_connection(&env->usr->gdata, "died — back to lobby");
  }
  SDL_Log("Wyrm death: returning to lobby");
}

void android_home_notify_death(tenv* env) {
  if (!env) return;
  /* The reference refreshes dead_mtm on another 'v' or an in-game close.
     Keep its presentation clock separate from our once-per-life receipt. */
  if (!death_watching) death_opacity = 1;
  android_team_release_chat(env);
  if (!run_recorded) {
    game_capture_final_score(env);
    if (env->usr->gdata.join_spawned) record_finished_run(env);
    run_recorded = true;
  }
  env->usr->gdata.data.follow_view = false;
  env->usr->gdata.data.lagging = false;
  env->usr->gdata.data.lag_mult = 1;
  env->usr->gdata.restart_req = false;
  env->usr->gdata.leaving = false;
  death_watching = true;
  death_began_at = SDL_GetTicks();
  SDL_Log("Wyrm death: 1600 ms wait, then source-rate fade");
}

bool android_home_death_pending(void) { return death_watching || death_active; }
float android_home_death_opacity(void) { return death_watching ? death_opacity : 1; }

void android_home_advance_death(tenv* env, float vfr) {
  if (!death_watching) return;
  death_opacity = arena_death_step(death_opacity,
      SDL_GetTicks() - death_began_at, vfr);
  if (death_opacity <= 0) return_to_lobby_after_death(env);
}

/** Takes the card down, restoring whatever bot setting the player had. */
static void dismiss_death(tenv* env) {
  /* A watch still running belongs to this death and goes with it — leaving one
     armed would raise a card over the match the player just asked for. */
  death_watching = false;
  if (!death_active) return;
  death_active = false;
  /* The bot is not restored here any more, because nothing forces it on any
     more. It was this line, fed by a value chat had already changed, that left
     a new match starting with the bot driving and no way to stop it. */

  JNIEnv* jni = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&jni, &activity_class)) return;
  jmethodID method = (*jni)->GetStaticMethodID(jni, activity_class,
                                               "setDeathFromNative", "(ZIIDZ)V");
  if (method) {
    (*jni)->CallStaticVoidMethod(jni, activity_class, method, JNI_FALSE, 0, 0,
                                 (jdouble)0, JNI_FALSE);
    clear_exception(jni);
  } else {
    (*jni)->ExceptionClear(jni);
  }
  (*jni)->DeleteLocalRef(jni, activity_class);
}

void android_home_poll(tenv* env) {
  if (!env || !home_mutex) return;


  bool enter = false;
  bool ai_enter = false;
  bool ai_editor_enter = false;
  bool ai_editor_exit = false;
  bool editor_leaderboard_toggle = false;
  char nickname[MAX_NICKNAME_LEN + 1] = {0};
  bool save_nickname = false;
  char saved_nickname[MAX_NICKNAME_LEN + 1] = {0};
  char arena[MAX_IPV4_LEN + 1] = {0};
  char enter_arena[MAX_IPV4_LEN + 1] = {0};
  uint64_t enter_id = 0;
  int requested = -1;
  bool death_play, death_home;

  SDL_LockMutex(home_mutex);
  enter = pending_enter;
  ai_enter = pending_ai_enter;
  ai_editor_enter = pending_ai_editor_enter;
  ai_editor_exit = pending_ai_editor_exit;
  editor_leaderboard_toggle = pending_editor_leaderboard_toggle;
  if (enter || ai_enter || ai_editor_enter) {
    memcpy(nickname, pending_nickname, sizeof(nickname));
  }
  if (enter) {
    memcpy(enter_arena, pending_enter_arena, sizeof(enter_arena));
    enter_id = pending_enter_id;
  }
  save_nickname = pending_nickname_save;
  if (save_nickname) {
    memcpy(saved_nickname, pending_saved_nickname, sizeof(saved_nickname));
  }
  memcpy(arena, pending_arena, sizeof(arena));
  requested = pending_screen;
  death_play = pending_death_play;
  death_home = pending_death_home;
  int auto_respawn = pending_auto_respawn;
  pending_auto_respawn = -1;
  pending_enter = false;
  pending_ai_enter = false;
  pending_ai_editor_enter = false;
  pending_ai_editor_exit = false;
  pending_editor_leaderboard_toggle = false;
  pending_nickname_save = false;
  pending_enter_arena[0] = '\0';
  pending_enter_id = 0;
  pending_arena[0] = '\0';
  pending_screen = -1;
  pending_death_play = false;
  pending_death_home = false;
  SDL_UnlockMutex(home_mutex);

  tuser_data* user = env->usr;
  user_settings* settings = &user->usrs;

  if (editor_leaderboard_toggle && ai_mode_is_editor())
    ui_overlay_toggle_leaderboard(env);

  if (ai_editor_exit) {
    if (user->gdata.ai_mode) ai_mode_finish_editor(env);
    return;
  }

  if (ai_editor_enter) {
    snprintf(settings->nickname, sizeof(settings->nickname), "%s", nickname);
    ai_mode_start_editor(env, nickname);
    return;
  }

  if (ai_enter) {
    snprintf(settings->nickname, sizeof(settings->nickname), "%s", nickname);
    save_user_settings(settings);
    ai_mode_start(env, nickname);
    return;
  }

  if (save_nickname &&
      strncmp(settings->nickname, saved_nickname, sizeof(settings->nickname)) != 0) {
    snprintf(settings->nickname, sizeof(settings->nickname), "%s", saved_nickname);
    save_user_settings(settings);
    SDL_Log("Wyrm home: in-game name saved");
    android_home_publish_state(env);
  }

  if (auto_respawn >= 0 && settings->auto_respawn != auto_respawn) {
    settings->auto_respawn = auto_respawn;
    save_user_settings(settings);
    SDL_Log("Wyrm: auto respawn %s", auto_respawn ? "on" : "off");
  }

  if (death_play) {
    dismiss_death(env);
    /*
     * Play on the card is the restart hotkey, pressed for the player.
     *
     * It used to be its own copy of the entry sequence, which is how the two
     * came to disagree about pacing — the hotkey went through the loop and this
     * dialled on the spot. There is one way into an arena now and both use it,
     * so a rule added to entry cannot apply to only half of the ways in.
     *
     * The socket is already closed by the time the card is up: `raise_death_card`
     * hangs up, so there is nothing to hand back first.
     */
    if (user->gdata.connection && user->gdata.conn == CONNECTED) {
      user->gdata.restart_req = true;
      game_close_connection(&user->gdata, "play again");
    } else {
      arena_request_join(env, ARENA_CONNECT_COOLDOWN_MS);
    }
  }

  if (death_home) {
    dismiss_death(env);
    user->gdata.leaving = true;
    user->gdata.restart_req = false;
    game_close_connection(&user->gdata, "home from the death card");
    user->gdata.curr_screen = TITLE_SCREEN;
  }

  if (arena[0]) {
    /* Chosen in Compose, persisted here: the engine owns the settings file, and
     * writing it now means the choice survives even if the app is killed on the
     * way into the match. */
    if (server_address_is_valid(arena)) {
      SDL_Log("Wyrm home: arena set to '%s'", arena);
      snprintf(settings->ipv4, sizeof(settings->ipv4), "%s", arena);
      save_user_settings(settings);
      android_home_publish_state(env);
    } else {
      SDL_Log("Wyrm home: invalid arena ignored: '%s'", arena);
    }
  }

  if (requested >= 0) {
    user->gdata.curr_screen = (screen)requested;
    if (requested == LOBBY) {
      user->gdata.stay_in_lobby = true;
      user->gdata.leaving = false;
      user->gdata.restart_req = false;
    }
  }

  if (enter) {
    game_data* gdata = &user->gdata;
    /*
     * A join that is still running owns the button — but only while it is
     * actually getting somewhere.
     *
     * This used to refuse a press outright whenever a socket existed. An arena
     * that accepts a TCP connection and then says nothing leaves one existing
     * for the whole timeout, and every press inside that window was swallowed
     * with nothing on screen to explain it: measured on device as a press that
     * blinked, a second that blinked, and a third that sat on "ENTERING" while
     * the socket it was waiting behind had already been dead for seconds.
     *
     * So a stalled attempt is stood down rather than obeyed. The player asked
     * twice; the second ask is the more recent information.
     */
    /*
     * Measured off when the player asked, not off when a socket last dialled.
     *
     * `attempt_started_ms` is only stamped by a dial that actually went out, so
     * while a join was held — waiting out the pacing window, or waiting for the
     * previous socket to finish — it still held the last attempt's value, which
     * was already older than the timeout. Every press then read as "the running
     * join has stalled", dropped it, and dialled again. That is the burst of
     * connections the arena was rate-limiting: the guard meant to stop it was
     * the thing producing it.
     */
    bool busy = gdata->connection || gdata->conn != DISCONNECTED;
    if (busy && gdata->conn == CONNECTING && !gdata->join_spawned &&
        SDL_GetTicks() - gdata->join_started_ms > TIMEOUT * 1000) {
      SDL_Log("Wyrm home: the running join had stalled — dropping it for "
              "attempt %llu",
              (unsigned long long)enter_id);
      game_close_connection(gdata, "the player asked again");
      gdata->conn = DISCONNECTED;
      gdata->closed = false;
      busy = false;
    }
    if (enter_id <= last_enter_id) {
      SDL_Log("Wyrm home: stale arena attempt %llu ignored",
              (unsigned long long)enter_id);
      return;
    }
    last_enter_id = enter_id;
    if (!server_address_is_valid(enter_arena)) {
      SDL_Log("Wyrm home: arena attempt %llu has invalid address '%s'",
              (unsigned long long)enter_id, enter_arena);
      return;
    }
    if (busy) {
      SDL_Log("Wyrm home: arena attempt %llu ignored; a join is already active",
              (unsigned long long)enter_id);
      return;
    }

    SDL_Log("Wyrm home: entering '%s' as '%s' (attempt %llu)", enter_arena,
            nickname, (unsigned long long)enter_id);
    /* Compose owns the name, so the engine takes it as given and persists it
     * before the match rather than after, in case the match never ends well. */
    snprintf(settings->nickname, sizeof(settings->nickname), "%s", nickname);
    snprintf(settings->ipv4, sizeof(settings->ipv4), "%s", enter_arena);
    save_user_settings(settings);

    ui_lobby_play(env);
  }
}

/** Compose asking for auto respawn on or off, from the death card. */
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetAutoRespawn(JNIEnv* env,
                                                          jclass clazz,
                                                          jboolean on) {
  (void)env;
  (void)clazz;
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  pending_auto_respawn = on ? 1 : 0;
  SDL_UnlockMutex(home_mutex);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetNickname(JNIEnv* env,
                                                       jclass clazz,
                                                       jstring nickname) {
  (void)clazz;
  if (!home_mutex) return;
  const char* text = nickname ? (*env)->GetStringUTFChars(env, nickname, NULL)
                              : NULL;
  SDL_LockMutex(home_mutex);
  snprintf(pending_saved_nickname, sizeof(pending_saved_nickname), "%s",
           text ? text : "");
  pending_nickname_save = true;
  SDL_UnlockMutex(home_mutex);
  if (text) (*env)->ReleaseStringUTFChars(env, nickname, text);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeEnterArena(JNIEnv* env, jclass clazz,
                                                     jstring nickname,
                                                     jstring address,
                                                     jlong attempt_id) {
  (void)clazz;
  if (!home_mutex) return;

  const char* text = nickname ? (*env)->GetStringUTFChars(env, nickname, NULL)
                              : NULL;
  const char* arena = address ? (*env)->GetStringUTFChars(env, address, NULL)
                              : NULL;
  SDL_Log("Wyrm home: nativeEnterArena reached (attempt %llu)",
          (unsigned long long)attempt_id);
  SDL_LockMutex(home_mutex);
  snprintf(pending_nickname, sizeof(pending_nickname), "%s", text ? text : "");
  snprintf(pending_enter_arena, sizeof(pending_enter_arena), "%s",
           arena ? arena : "");
  pending_enter_id = (uint64_t)attempt_id;
  pending_enter = true;
  SDL_UnlockMutex(home_mutex);
  if (text) (*env)->ReleaseStringUTFChars(env, nickname, text);
  if (arena) (*env)->ReleaseStringUTFChars(env, address, arena);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeEnterAiMode(JNIEnv* env,
                                                       jclass clazz,
                                                       jstring nickname) {
  (void)clazz;
  if (!home_mutex) return;
  const char* text = nickname ? (*env)->GetStringUTFChars(env, nickname, NULL)
                              : NULL;
  SDL_LockMutex(home_mutex);
  snprintf(pending_nickname, sizeof(pending_nickname), "%s", text ? text : "");
  pending_ai_enter = true;
  SDL_UnlockMutex(home_mutex);
  if (text) (*env)->ReleaseStringUTFChars(env, nickname, text);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeEnterAiLayoutEditor(
    JNIEnv* env, jclass clazz, jstring nickname) {
  (void)clazz;
  if (!home_mutex) return;
  const char* text = nickname ? (*env)->GetStringUTFChars(env, nickname, NULL)
                              : NULL;
  SDL_LockMutex(home_mutex);
  snprintf(pending_nickname, sizeof(pending_nickname), "%s", text ? text : "");
  pending_ai_editor_enter = true;
  SDL_UnlockMutex(home_mutex);
  if (text) (*env)->ReleaseStringUTFChars(env, nickname, text);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeExitAiLayoutEditor(JNIEnv* env,
                                                              jclass clazz) {
  (void)env;
  (void)clazz;
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  pending_ai_editor_exit = true;
  SDL_UnlockMutex(home_mutex);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeToggleEditorLeaderboard(
    JNIEnv* env, jclass clazz) {
  (void)env;
  (void)clazz;
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  pending_editor_leaderboard_toggle = true;
  SDL_UnlockMutex(home_mutex);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSelectArena(JNIEnv* env, jclass clazz,
                                                      jstring address) {
  (void)clazz;
  if (!home_mutex) return;

  const char* text = address ? (*env)->GetStringUTFChars(env, address, NULL)
                             : NULL;
  SDL_LockMutex(home_mutex);
  snprintf(pending_arena, sizeof(pending_arena), "%s", text ? text : "");
  SDL_UnlockMutex(home_mutex);
  if (text) (*env)->ReleaseStringUTFChars(env, address, text);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeDeathPlay(JNIEnv* env, jclass clazz) {
  (void)env;
  (void)clazz;
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  pending_death_play = true;
  SDL_UnlockMutex(home_mutex);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeDeathHome(JNIEnv* env, jclass clazz) {
  (void)env;
  (void)clazz;
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  pending_death_home = true;
  SDL_UnlockMutex(home_mutex);
}

JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeOpenScreen(JNIEnv* env, jclass clazz,
                                                     jint screen) {
  (void)env;
  (void)clazz;
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  pending_screen = (int)screen;
  SDL_UnlockMutex(home_mutex);
}

#else

void android_home_bind_env(tenv* env) { (void)env; }
void android_home_poll(tenv* env) { (void)env; }
void android_home_begin_life(void) {}
void android_home_reset_death(void) {}
void android_home_set_screen(int screen) { (void)screen; }
void android_home_publish_state(tenv* env) { (void)env; }
void android_home_notify_death(tenv* env) { (void)env; }
bool android_home_death_active(void) { return false; }
bool android_home_death_pending(void) { return false; }
float android_home_death_opacity(void) { return 1; }
void android_home_advance_death(tenv* env, float vfr) { (void)env; (void)vfr; }
void android_home_arena_refused(const char* endpoint, int seconds) {
  (void)endpoint;
  (void)seconds;
}

#endif
