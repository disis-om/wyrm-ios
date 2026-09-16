#ifndef ANDROID_SETTINGS_H
#define ANDROID_SETTINGS_H

typedef struct tenv tenv;

/**
 * The settings bridge.
 *
 * Compose owns every settings screen, so the engine's job is to describe what
 * it holds and to apply what comes back. One table describes every field —
 * its id, group, type, range and options — and the interface renders itself
 * from that description, which is why adding a setting is one line here and
 * nothing at all on the other side.
 */
void android_settings_bind_env(tenv* env);

/** Applies whatever Compose has written since the last frame. */
void android_settings_poll(tenv* env);

#endif
