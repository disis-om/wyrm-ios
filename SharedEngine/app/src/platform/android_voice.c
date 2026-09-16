#include "android_voice.h"

#ifdef VLITHER_ANDROID
#include <jni.h>
#include <math.h>
#include <SDL3/SDL.h>
#include <SDL3/SDL_system.h>

void android_voice_publish_hud(float left, float top, float diameter) {
  static float last_left = -1.0f;
  static float last_top = -1.0f;
  static float last_diameter = -1.0f;
  if (fabsf(left - last_left) < 0.5f && fabsf(top - last_top) < 0.5f &&
      fabsf(diameter - last_diameter) < 0.5f)
    return;
  last_left = left;
  last_top = top;
  last_diameter = diameter;

  JNIEnv* env = (JNIEnv*)SDL_GetAndroidJNIEnv();
  if (!env) return;
  jclass activity = (*env)->FindClass(env, "com/wyrm/omrajput/WyrmActivity");
  if (!activity) {
    (*env)->ExceptionClear(env);
    return;
  }
  jmethodID method = (*env)->GetStaticMethodID(
      env, activity, "setVoiceHudAnchorFromNative", "(FFF)V");
  if (method) {
    (*env)->CallStaticVoidMethod(env, activity, method, (jfloat)left,
                                 (jfloat)top, (jfloat)diameter);
  } else {
    (*env)->ExceptionClear(env);
  }
  (*env)->DeleteLocalRef(env, activity);
}

#else

void android_voice_publish_hud(float left, float top, float diameter) {
  (void)left;
  (void)top;
  (void)diameter;
}

#endif
