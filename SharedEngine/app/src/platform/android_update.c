#include "android_update.h"

#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef VLITHER_ANDROID
#include <SDL3/SDL.h>
#include <SDL3/SDL_system.h>
#include <jni.h>

#include "../user.h"
#include "android_home.h"
#include "android_skin.h"

static tenv* update_env = NULL;
static SDL_Mutex* update_mutex = NULL;
static android_update_snapshot update_snapshot = {0};
static user_settings pending_restored_settings = {0};
static bool restore_waiting_for_engine = false;

static void copy_text(char* destination, size_t capacity, const char* value) {
  if (!destination || capacity == 0) return;
  snprintf(destination, capacity, "%s", value ? value : "");
}

static bool get_activity(JNIEnv** out_env, jclass* out_class) {
  *out_env = (JNIEnv*)SDL_GetAndroidJNIEnv();
  if (!*out_env) {
    SDL_Log("Vlither updater: JNI environment unavailable");
    return false;
  }
  JNIEnv* env = *out_env;
  *out_class = (*env)->FindClass(env, "com/wyrm/omrajput/WyrmActivity");
  if (!*out_class) {
    (*env)->ExceptionClear(env);
    SDL_Log("Vlither updater: activity class unavailable");
    return false;
  }
  return true;
}

static void call_static_void(const char* method_name) {
  JNIEnv* env = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&env, &activity_class)) return;
  jmethodID method =
      (*env)->GetStaticMethodID(env, activity_class, method_name, "()V");
  if (!method) {
    (*env)->ExceptionClear(env);
    SDL_Log("Vlither updater: Java method %s unavailable", method_name);
    (*env)->DeleteLocalRef(env, activity_class);
    return;
  }
  (*env)->CallStaticVoidMethod(env, activity_class, method);
  if ((*env)->ExceptionCheck(env)) {
    (*env)->ExceptionDescribe(env);
    (*env)->ExceptionClear(env);
  }
  (*env)->DeleteLocalRef(env, activity_class);
}

static void call_static_backup_method(const char* method_name,
                                      const void* settings,
                                      size_t settings_size) {
  if (!settings || settings_size == 0 || settings_size > 1024 * 1024) return;
  JNIEnv* env = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&env, &activity_class)) return;
  jmethodID method =
      (*env)->GetStaticMethodID(env, activity_class, method_name, "([B[B)V");
  if (!method) {
    (*env)->ExceptionClear(env);
    (*env)->DeleteLocalRef(env, activity_class);
    return;
  }
  jbyteArray payload = (*env)->NewByteArray(env, (jsize)settings_size);
  if (payload) {
    (*env)->SetByteArrayRegion(env, payload, 0, (jsize)settings_size,
                               (const jbyte*)settings);
    (*env)->CallStaticVoidMethod(env, activity_class, method, payload, NULL);
    (*env)->DeleteLocalRef(env, payload);
  }
  if ((*env)->ExceptionCheck(env)) {
    (*env)->ExceptionDescribe(env);
    (*env)->ExceptionClear(env);
  }
  (*env)->DeleteLocalRef(env, activity_class);
}

static void call_static_settings_method(const char* method_name,
                                        const void* settings,
                                        size_t settings_size) {
  if (!settings || settings_size == 0 || settings_size > 1024 * 1024) return;
  JNIEnv* env = NULL;
  jclass activity_class = NULL;
  if (!get_activity(&env, &activity_class)) return;
  jmethodID method =
      (*env)->GetStaticMethodID(env, activity_class, method_name, "([B)V");
  if (!method) {
    (*env)->ExceptionClear(env);
    (*env)->DeleteLocalRef(env, activity_class);
    return;
  }
  jbyteArray payload = (*env)->NewByteArray(env, (jsize)settings_size);
  if (payload) {
    (*env)->SetByteArrayRegion(env, payload, 0, (jsize)settings_size,
                               (const jbyte*)settings);
    (*env)->CallStaticVoidMethod(env, activity_class, method, payload);
    (*env)->DeleteLocalRef(env, payload);
  }
  if ((*env)->ExceptionCheck(env)) {
    (*env)->ExceptionDescribe(env);
    (*env)->ExceptionClear(env);
  }
  (*env)->DeleteLocalRef(env, activity_class);
}

void android_update_bind_env(tenv* env) {
  update_env = env;
  if (!update_mutex) update_mutex = SDL_CreateMutex();
}

void android_update_notify_title_ready(const void* settings,
                                       size_t settings_size) {
  call_static_settings_method("notifyTitleScreenReadyFromNative", settings,
                              settings_size);
}

void android_update_check(void) {
  call_static_void("checkForUpdatesFromNative");
}

void android_update_download(const void* settings, size_t settings_size) {
  call_static_backup_method("downloadAvailableUpdateFromNative", settings,
                            settings_size);
}

void android_update_create_backup(const void* settings, size_t settings_size) {
  call_static_backup_method("createBackupFromNative", settings, settings_size);
}

void android_update_check_backups(void) {
  call_static_void("checkBackupsFromNative");
}

void android_update_restore_latest(void) {
  call_static_void("restoreLatestBackupFromNative");
}

void android_update_choose_backup_folder(void) {
  call_static_void("chooseBackupFolderFromNative");
}

bool android_update_apply_pending_settings(tenv* env) {
  if (!env || !env->usr || !update_mutex) return false;

  user_settings restored = {0};
  bool should_apply = false;
  SDL_LockMutex(update_mutex);
  if (restore_waiting_for_engine) {
    restored = pending_restored_settings;
    restore_waiting_for_engine = false;
    should_apply = true;
  }
  SDL_UnlockMutex(update_mutex);
  if (!should_apply) return false;

  /* Java validates and writes the archive on a worker thread. The live struct

   * belongs to the render/input thread, so the hand-off happens here at the

   * top of a frame instead of racing gameplay from JNI. */
  env->usr->usrs = restored;
  env->config.vsync = restored.vsync;
  android_home_publish_state(env);
  android_skin_publish_state(env);
  return true;
}

void android_update_get_snapshot(android_update_snapshot* snapshot) {
  if (!snapshot) return;
  if (update_mutex) SDL_LockMutex(update_mutex);
  *snapshot = update_snapshot;
  if (update_mutex) SDL_UnlockMutex(update_mutex);
}

JNIEXPORT void JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeOnUpdateState(
    JNIEnv* env, jclass clazz, jint status, jint progress, jstring title,
    jstring detail, jlong version_code, jstring version_name) {
  (void)clazz;
  const char* title_text =
      title ? (*env)->GetStringUTFChars(env, title, NULL) : "";
  const char* detail_text =
      detail ? (*env)->GetStringUTFChars(env, detail, NULL) : "";
  const char* version_text =
      version_name ? (*env)->GetStringUTFChars(env, version_name, NULL) : "";
  if (update_mutex) SDL_LockMutex(update_mutex);
  update_snapshot.update_status = status;
  update_snapshot.update_progress = progress;
  update_snapshot.available_version_code = (long long)version_code;
  copy_text(update_snapshot.update_title, sizeof(update_snapshot.update_title),
            title_text);
  copy_text(update_snapshot.update_detail,
            sizeof(update_snapshot.update_detail), detail_text);
  copy_text(update_snapshot.available_version_name,
            sizeof(update_snapshot.available_version_name), version_text);
  if (update_mutex) SDL_UnlockMutex(update_mutex);
  if (title) (*env)->ReleaseStringUTFChars(env, title, title_text);
  if (detail) (*env)->ReleaseStringUTFChars(env, detail, detail_text);
  if (version_name)
    (*env)->ReleaseStringUTFChars(env, version_name, version_text);
}

JNIEXPORT void JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeOnBackupState(
    JNIEnv* env, jclass clazz, jint status, jint count, jstring title,
    jstring detail) {
  (void)clazz;
  const char* title_text =
      title ? (*env)->GetStringUTFChars(env, title, NULL) : "";
  const char* detail_text =
      detail ? (*env)->GetStringUTFChars(env, detail, NULL) : "";
  if (update_mutex) SDL_LockMutex(update_mutex);
  update_snapshot.backup_status = status;
  update_snapshot.backup_count = count;
  copy_text(update_snapshot.backup_title, sizeof(update_snapshot.backup_title),
            title_text);
  copy_text(update_snapshot.backup_detail,
            sizeof(update_snapshot.backup_detail), detail_text);
  if (update_mutex) SDL_UnlockMutex(update_mutex);
  if (title) (*env)->ReleaseStringUTFChars(env, title, title_text);
  if (detail) (*env)->ReleaseStringUTFChars(env, detail, detail_text);
}

static bool terminated(const char* value, size_t capacity) {
  return memchr(value, '\0', capacity) != NULL;
}

static bool normalized(float value) {
  return isfinite(value) && value >= 0.0f && value <= 1.0f;
}

static bool profile_valid(const user_settings* settings) {
  return terminated(settings->nickname, sizeof(settings->nickname)) &&
         terminated(settings->ipv4, sizeof(settings->ipv4)) &&
         terminated(settings->skin_code, sizeof(settings->skin_code)) &&
         settings->default_skin < NUM_DEFAULT_SKINS &&
         (settings->accessory == NO_ACCESSORY ||
          settings->accessory < NUM_ACCESSORIES);
}

static bool stats_valid(const user_settings* settings) {
  return settings->score >= 0 && settings->kills >= 0 &&
         isfinite(settings->play_time) && settings->play_time >= 0.0;
}

static bool display_valid(const user_settings* settings) {
  if (settings->ui_font_size < 0 || settings->ui_font_size >= NUM_FONT_SIZES ||
      settings->lb_font_size < 0 || settings->lb_font_size >= NUM_FONT_SIZES ||
      settings->snake_names_font_size < 0 ||
      settings->snake_names_font_size >= NUM_FONT_SIZES ||
      settings->stats_font_size < 0 ||
      settings->stats_font_size >= NUM_FONT_SIZES ||
      settings->laser_thickness < 1 || settings->laser_thickness > 4 ||
      settings->cursor_size < 16 || settings->cursor_size > 64 ||
      settings->minimap_size < 128 || settings->minimap_size > 512 ||
      !isfinite(settings->zoom_step) || settings->zoom_step < 0.05f ||
      settings->zoom_step > 0.5f || settings->bot_radius_mult < 10 ||
      settings->bot_radius_mult > 40 || settings->bot_follow_circle_score < 0 ||
      !isfinite(settings->death_hold_s) || settings->death_hold_s < 0.0f ||
      settings->death_hold_s > 4.0f)
    return false;
  for (int i = 0; i < 3; ++i)
    if (!normalized(settings->bd_color[i])) return false;
  for (int i = 0; i < 4; ++i)
    if (!normalized(settings->laser_color[i])) return false;
  return true;
}

static bool hud_layout_valid(const user_settings* settings) {
  const float values[] = {
      settings->hud_minimap_x, settings->hud_minimap_y,
      settings->hud_leaderboard_x, settings->hud_leaderboard_y,
      settings->hud_stats_x, settings->hud_stats_y,
      settings->hud_team_x, settings->hud_team_y,
      settings->hud_chat_x, settings->hud_chat_y,
  };
  for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); ++i)
    if (!normalized(values[i])) return false;
  return true;
}

static bool layout_appearance_valid(const user_settings* settings) {
  const float opacity[] = {settings->joystick_opacity,
                           settings->boost_opacity,
                           settings->zoom_opacity,
                           settings->hud_stats_opacity,
                           settings->hud_chat_opacity};
  for (size_t i = 0; i < sizeof(opacity) / sizeof(opacity[0]); ++i)
    if (!isfinite(opacity[i]) || opacity[i] < 0.05f || opacity[i] > 1.0f)
      return false;
  if (!isfinite(settings->hud_stats_scale) ||
      settings->hud_stats_scale < 0.65f || settings->hud_stats_scale > 1.60f ||
      !isfinite(settings->hud_chat_scale) ||
      settings->hud_chat_scale < 0.65f || settings->hud_chat_scale > 1.60f)
    return false;
  for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action)
    if (!isfinite(settings->hotkey_scale[action]) ||
        settings->hotkey_scale[action] < 0.65f ||
        settings->hotkey_scale[action] > 1.60f ||
        !isfinite(settings->hotkey_opacity[action]) ||
        settings->hotkey_opacity[action] < 0.05f ||
        settings->hotkey_opacity[action] > 1.0f)
      return false;
  return true;
}

static bool gameplay_valid(const gameplay_mode* mode) {
  if (mode->food_type < 0 || mode->food_type > 8 || mode->boost_type < 0 ||
      mode->boost_type > 1 || mode->render_mode < 0 || mode->render_mode > 2 ||
      !isfinite(mode->food_scale) || mode->food_scale < 0.25f ||
      mode->food_scale > 3.0f || !isfinite(mode->qsm) || mode->qsm < 1.0f ||
      mode->qsm > 4.0f || !isfinite(mode->bg_scale) || mode->bg_scale < 0.05f ||
      mode->bg_scale > 4.0f || !isfinite(mode->boost_strength) ||
      mode->boost_strength < 0.25f || mode->boost_strength > 3.0f)
    return false;
  for (int i = 0; i < 3; ++i)
    if (!normalized(mode->food_color[i])) return false;
  return true;
}

static bool mobile_valid(const mobile_control_settings* settings) {
  if (settings->handedness < MOBILE_LEFT_HANDED ||
      settings->handedness > MOBILE_RIGHT_HANDED ||
      settings->joystick_mode < MOBILE_JOYSTICK_DYNAMIC ||
      settings->joystick_mode > MOBILE_STEERING_ARROW ||
      settings->boost_mode < MOBILE_BOOST_TOUCH_ZONE ||
      settings->boost_mode > MOBILE_BOOST_FIXED ||
      settings->zoom_orientation < MOBILE_ZOOM_HORIZONTAL ||
      settings->zoom_orientation > MOBILE_ZOOM_VERTICAL)
    return false;
  const float positions[] = {settings->joystick_x, settings->joystick_y,
                             settings->boost_x,    settings->boost_y,
                             settings->zoom_x,     settings->zoom_y,
                             settings->opacity};
  for (size_t i = 0; i < sizeof(positions) / sizeof(positions[0]); ++i)
    if (!normalized(positions[i])) return false;
  return isfinite(settings->joystick_size) &&
         settings->joystick_size >= 0.65f && settings->joystick_size <= 1.45f &&
         isfinite(settings->boost_size) && settings->boost_size >= 0.65f &&
         settings->boost_size <= 1.45f && isfinite(settings->zoom_length) &&
         settings->zoom_length >= 0.65f && settings->zoom_length <= 1.55f;
}

static bool hotkeys_valid(const hotkey* hotkeys) {
  for (int i = 0; i < NUM_HOTKEYS; ++i) {
    if (hotkeys[i].key < 0 || hotkeys[i].key > 512 || hotkeys[i].mode < 0 ||
        hotkeys[i].mode > 1 ||
        !terminated(hotkeys[i].description, sizeof(hotkeys[i].description)))
      return false;
  }
  return true;
}

static bool arrow_valid(const mobile_arrow_settings* settings) {
  if (!isfinite(settings->size) || settings->size < 0.30f ||
      settings->size > 2.40f || !isfinite(settings->separation) ||
      settings->separation < 0.40f || settings->separation > 2.00f ||
      !isfinite(settings->smoothness) || settings->smoothness < 0.0f ||
      settings->smoothness > 0.85f)
    return false;
  for (int i = 0; i < 4; ++i)
    if (!normalized(settings->color[i])) return false;
  return true;
}

static bool mobile_hotkeys_valid(const mobile_hotkey_settings* settings,
                                 bool has_label, bool has_scale) {
  if (!normalized(settings->opacity)) return false;
  for (int i = 0; i < NUM_MOBILE_HOTKEYS; ++i)
    if (!normalized(settings->x[i]) || !normalized(settings->y[i]))
      return false;
  for (int i = 0; i < NUM_MOBILE_DIRECT_HOTKEYS; ++i)
    if (settings->direct_keys[i] < 0 || settings->direct_keys[i] > 512)
      return false;
  if (has_label && (settings->label_mode < MOBILE_HOTKEY_LABEL_KEY ||
                    settings->label_mode > MOBILE_HOTKEY_LABEL_BOTH))
    return false;
  return !has_scale ||
         (isfinite(settings->key_scale) && settings->key_scale >= 0.65f &&
          settings->key_scale <= 1.60f);
}

static void append_report(char* report, size_t capacity, const char* text) {
  size_t used = strlen(report);
  if (used < capacity - 1) snprintf(report + used, capacity - used, "%s", text);
}

static void append_restore_item(char* report, size_t capacity, int* count,
                                const char* result, const char* name,
                                const char* reason) {
  (*count)++;
  append_report(report, capacity, result);
  append_report(report, capacity, "|");
  append_report(report, capacity, name);
  if (reason) {
    append_report(report, capacity, "|");
    append_report(report, capacity, reason);
  }
  append_report(report, capacity, "\n");
}

static bool save_restored_settings(user_settings* settings) {
  const char* temporary = "user.dat.restore.tmp";
  FILE* file = fopen(temporary, "wb");
  if (!file) return false;
  bool saved = fwrite(settings, sizeof(*settings), 1, file) == 1;
  if (fflush(file) != 0 || fclose(file) != 0) saved = false;
  if (!saved) {
    remove(temporary);
    return false;
  }
  if (rename(temporary, USER_SETTINGS_FILE) != 0) {
    remove(temporary);
    return false;
  }
  return true;
}

JNIEXPORT jstring JNICALL Java_com_wyrm_omrajput_WyrmActivity_nativeApplyBackup(
    JNIEnv* env, jclass clazz, jbyteArray payload, jbyteArray team_payload) {
  (void)clazz;
  if (!update_env || !payload)
    return (*env)->NewStringUTF(env,
                                "FAILED\nReason: Backup data is unavailable.");

  const size_t v14_size = offsetof(user_settings, arrow_controls);
  const size_t v15_size = offsetof(user_settings, mobile_hotkeys);
  const size_t v16_size = offsetof(user_settings, mobile_hotkeys) +
                          offsetof(mobile_hotkey_settings, label_mode);
  const size_t v17_size = offsetof(user_settings, mobile_hotkeys) +
                          offsetof(mobile_hotkey_settings, key_scale);
  const size_t v19_size = offsetof(user_settings, rope_mode_key);
  const size_t v20_size = offsetof(user_settings, arrow_style);
  const jsize payload_size = (*env)->GetArrayLength(env, payload);

  /*
   * Anything this format has ever written, read as far as it goes.
   *
   * Generations used to be recognised by matching `sizeof` exactly, one
   * constant per release, and that is brittle in both directions. A field
   * appended into padding the structure already had does not change `sizeof`
   * at all — which is how a v1.9 save once read cleanly as v1.8 and was thrown
   * away whole. A field appended after it changes `sizeof` by more than the
   * field, because the trailing padding moves too, so the constant written for
   * the previous release stops matching the archives that release produced.
   * Either way a perfectly readable backup was rejected entirely, and the
   * player was told their settings were unsupported.
   *
   * The format has only ever been appended to, so every archive is a prefix of
   * the current structure. Start from defaults, copy however much the archive
   * actually has, and let the length decide which fields it meant — a field is
   * present when the payload reaches past its end, and absent fields keep the
   * default they were given. No exact size has to be predicted in advance, and
   * a generation added after this code was written still restores everything
   * it shares with it.
   */
  user_settings source;
  user_settings_default(&source);
  if (payload_size < (jsize)v14_size ||
      payload_size > (jsize)sizeof(user_settings))
    return (*env)->NewStringUTF(env,
                                "FAILED\nReason: The backup settings payload "
                                "is not a readable size.");
  (*env)->GetByteArrayRegion(env, payload, 0, payload_size, (jbyte*)&source);
  if ((*env)->ExceptionCheck(env)) {
    (*env)->ExceptionClear(env);
    return (*env)->NewStringUTF(
        env, "FAILED\nReason: Backup data could not be read.");
  }

#define REACHES(field) \
  (payload_size >= (jsize)(offsetof(user_settings, field) + \
                           sizeof(((user_settings*)0)->field)))

  const bool has_arrow_controls = payload_size >= (jsize)v15_size;
  const bool has_hotkeys = payload_size >= (jsize)v16_size;
  const bool has_label_mode = payload_size >= (jsize)v17_size;
  const bool has_key_scale = payload_size >= (jsize)v19_size;
  const bool has_rope_mode = payload_size >= (jsize)v20_size;
  const bool has_arrow_style = REACHES(arrow_style);
  const bool has_skin_rgba = REACHES(skin_rgba);
  const bool has_head_dot = REACHES(head_dot_color);
  const bool has_hud_layout = REACHES(hud_chat_y);
  const bool has_layout_appearance = REACHES(hud_chat_opacity);

  user_settings merged = {0};
  FILE* current = fopen(USER_SETTINGS_FILE, "rb");
  bool have_current =
      current && fread(&merged, sizeof(merged), 1, current) == 1;
  if (current) fclose(current);
  if (!have_current) user_settings_default(&merged);

  char restored[768] = {0};
  char skipped[768] = {0};
  int restored_count = 0;
  int skipped_count = 0;
#define RESTORED(name)                                               \
  do {                                                               \
    append_restore_item(restored, sizeof(restored), &restored_count, \
                        "RESTORED", name, NULL);                     \
  } while (0)
#define SKIPPED(name, reason)                                                \
  do {                                                                       \
    append_restore_item(skipped, sizeof(skipped), &skipped_count, "SKIPPED", \
                        name, reason);                                       \
  } while (0)

  if (profile_valid(&source)) {
    memcpy(merged.nickname, source.nickname, sizeof(merged.nickname));
    memcpy(merged.ipv4, source.ipv4, sizeof(merged.ipv4));
    memcpy(merged.skin_code, source.skin_code, sizeof(merged.skin_code));
    merged.accessory = source.accessory;
    merged.custom_skin = source.custom_skin;
    merged.default_skin = source.default_skin;
    /* Built-skin colours only exist from v2.2. An older archive carries the
     * same code without them, which restores as the palette skin it was. */
    bool built = false;
    if (has_skin_rgba) {
      memcpy(merged.skin_rgba, source.skin_rgba, sizeof(merged.skin_rgba));
      for (int i = 0; i < MAX_SKIN_CODE_LEN && !built; ++i)
        built = merged.skin_rgba[i] != 0;
    } else {
      memset(merged.skin_rgba, 0, sizeof(merged.skin_rgba));
    }
    /* Named separately so the report does not quietly imply that a skin built
     * with the picker came back in full from an archive that predates it. */
    if (built)
      RESTORED("profile, server and skin, including built colours");
    else
      RESTORED("profile, server and skin");
  } else
    SKIPPED("profile, server and skin", "invalid or damaged values");

  if (stats_valid(&source)) {
    merged.score = source.score;
    merged.play_time = source.play_time;
    merged.kills = source.kills;
    RESTORED("stats");
  } else
    SKIPPED("stats", "invalid numeric values");

  if (display_valid(&source)) {
    memcpy(
        &merged.ui_font_size, &source.ui_font_size,
        offsetof(user_settings, modes) - offsetof(user_settings, ui_font_size));
    merged.death_hold_s = source.death_hold_s;
    RESTORED("display and general settings");
  } else
    SKIPPED("display and general settings",
            "one or more values are outside safe limits");

  if (gameplay_valid(&source.modes[0]) && gameplay_valid(&source.modes[1])) {
    memcpy(merged.modes, source.modes, sizeof(merged.modes));
    RESTORED("gameplay and graphics modes");
  } else
    SKIPPED("gameplay and graphics modes",
            "one or more mode values are invalid");

  if (has_head_dot) {
    bool valid_head_dot = true;
    for (int mode = 0; mode < 2; ++mode) {
      valid_head_dot = valid_head_dot && isfinite(source.head_dot_size[mode]) &&
                       source.head_dot_size[mode] >= 4.0f &&
                       source.head_dot_size[mode] <= 32.0f;
      for (int channel = 0; channel < 3; ++channel)
        valid_head_dot =
            valid_head_dot && isfinite(source.head_dot_color[mode][channel]) &&
            source.head_dot_color[mode][channel] >= 0.0f &&
            source.head_dot_color[mode][channel] <= 1.0f;
    }
    if (valid_head_dot) {
      memcpy(merged.head_dot_size, source.head_dot_size,
             sizeof(merged.head_dot_size));
      memcpy(merged.head_dot_color, source.head_dot_color,
             sizeof(merged.head_dot_color));
      RESTORED("head-dot size and colours");
    } else {
      SKIPPED("head-dot appearance", "values are outside safe limits");
    }
  }

  if (has_hud_layout && hud_layout_valid(&source)) {
    memcpy(&merged.hud_minimap_x, &source.hud_minimap_x,
           sizeof(float) * 10);
    RESTORED("arena HUD layout");
  } else if (has_hud_layout) {
    SKIPPED("arena HUD layout", "one or more positions are invalid");
  }

  if (has_layout_appearance && layout_appearance_valid(&source)) {
    memcpy(&merged.joystick_opacity, &source.joystick_opacity,
           sizeof(user_settings) - offsetof(user_settings, joystick_opacity));
    RESTORED("per-object layout appearance");
  } else if (has_layout_appearance) {
    SKIPPED("per-object layout appearance", "values are outside safe limits");
  }

  if (mobile_valid(&source.mobile_controls)) {
    merged.mobile_controls = source.mobile_controls;
    RESTORED("mobile controls and layout");
  } else
    SKIPPED("mobile controls and layout", "control values are incompatible");

  if (hotkeys_valid(source.hotkeys)) {
    memcpy(merged.hotkeys, source.hotkeys, sizeof(merged.hotkeys));
    RESTORED("on-screen button actions");
  } else
    SKIPPED("on-screen button actions", "button data is invalid");

  bool source_arrow_style_valid =
      !has_arrow_style || (source.arrow_style >= MOBILE_ARROW_CURRENT &&
                           source.arrow_style <= MOBILE_ARROW_TRIANGLE);
  if (has_arrow_controls && arrow_valid(&source.arrow_controls) &&
      source_arrow_style_valid) {
    merged.arrow_controls = source.arrow_controls;
    if (has_arrow_style) merged.arrow_style = source.arrow_style;
    RESTORED("arrow controls");
  } else if (!has_arrow_controls) {
    SKIPPED(
        "arrow controls",
        "older backup does not contain this feature; current values were kept");
  } else {
    SKIPPED("arrow controls",
            "arrow values are invalid; current values were kept");
  }

  if (has_hotkeys && mobile_hotkeys_valid(&source.mobile_hotkeys,
                                          has_label_mode, has_key_scale)) {
    bool visible[NUM_MOBILE_HOTKEYS];
    float x[NUM_MOBILE_HOTKEYS];
    float y[NUM_MOBILE_HOTKEYS];
    int direct[NUM_MOBILE_DIRECT_HOTKEYS];
    memcpy(visible, source.mobile_hotkeys.visible, sizeof(visible));
    memcpy(x, source.mobile_hotkeys.x, sizeof(x));
    memcpy(y, source.mobile_hotkeys.y, sizeof(y));
    memcpy(direct, source.mobile_hotkeys.direct_keys, sizeof(direct));
    memcpy(merged.mobile_hotkeys.visible, visible, sizeof(visible));
    memcpy(merged.mobile_hotkeys.x, x, sizeof(x));
    memcpy(merged.mobile_hotkeys.y, y, sizeof(y));
    memcpy(merged.mobile_hotkeys.direct_keys, direct, sizeof(direct));
    merged.mobile_hotkeys.opacity = source.mobile_hotkeys.opacity;
    merged.mobile_hotkeys.label_mode = MOBILE_HOTKEY_LABEL_FUNCTION;
    if (has_key_scale)
      merged.mobile_hotkeys.key_scale = source.mobile_hotkeys.key_scale;
    if (has_rope_mode && source.rope_mode_key >= 0 &&
        source.rope_mode_key <= 512 && normalized(source.rope_mode_x) &&
        normalized(source.rope_mode_y)) {
      merged.rope_mode_key = source.rope_mode_key;
      merged.rope_mode_visible = source.rope_mode_visible;
      merged.rope_mode_x = source.rope_mode_x;
      merged.rope_mode_y = source.rope_mode_y;
    }
    for (int action = 0; action < NUM_MOBILE_HOTKEYS; ++action)
      if (!mobile_hotkey_is_on_screen_button(action))
        merged.mobile_hotkeys.visible[action] = false;
    merged.rope_mode_visible = false;
    RESTORED("on-screen button visibility, size and positions");
  } else if (!has_hotkeys) {
    SKIPPED(
        "on-screen button layout",
        "older backup does not contain this feature; current values were kept");
  } else {
    SKIPPED("on-screen button layout",
            "overlay values are invalid; current values were kept");
  }

  strcpy(merged.version, SETTINGS_VERSION);
  if (restored_count == 0)
    return (*env)->NewStringUTF(
        env,
        "FAILED\nReason: No compatible settings category could be restored.");
  if (!save_restored_settings(&merged))
    return (*env)->NewStringUTF(
        env,
        "FAILED\nReason: Restored settings could not be saved to app storage.");

  SDL_LockMutex(update_mutex);
  pending_restored_settings = merged;
  restore_waiting_for_engine = true;
  SDL_UnlockMutex(update_mutex);

  char report[1800] = {0};
  snprintf(report, sizeof(report), "%s\n%s%s",
           skipped_count ? "PARTIAL" : "SUCCESS", restored, skipped);
#undef RESTORED
#undef SKIPPED
  return (*env)->NewStringUTF(env, report);
}

#else
void android_update_bind_env(tenv* env) { (void)env; }
void android_update_notify_title_ready(const void* settings,
                                       size_t settings_size) {
  (void)settings;
  (void)settings_size;
}
void android_update_check(void) {}
void android_update_download(const void* settings, size_t settings_size) {
  (void)settings;
  (void)settings_size;
}
void android_update_create_backup(const void* settings, size_t settings_size) {
  (void)settings;
  (void)settings_size;
}
void android_update_check_backups(void) {}
void android_update_restore_latest(void) {}
void android_update_choose_backup_folder(void) {}
bool android_update_apply_pending_settings(tenv* env) {
  (void)env;
  return false;
}
void android_update_get_snapshot(android_update_snapshot* snapshot) {
  if (snapshot) memset(snapshot, 0, sizeof(*snapshot));
}
#endif
