#ifndef ANDROID_VOICE_H
#define ANDROID_VOICE_H

/** Publishes only changed minimap geometry; no media or UI call runs on the renderer. */
void android_voice_publish_hud(float left, float top, float diameter);

#endif
