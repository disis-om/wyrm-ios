#ifndef ANDROID_SKIN_H
#define ANDROID_SKIN_H

#include <stdbool.h>

typedef struct tenv tenv;

/*
 * The bridge between the Compose skin editor and the engine.
 *
 * Same shape as android_home: Compose writes from the Android main thread into
 * a guarded mailbox, the engine drains it on its own thread once a frame. The
 * colour tables go the other way exactly once, because they never change.
 */

void android_skin_bind_env(tenv* env);

/** Applies anything the editor asked for. Engine thread, once per frame. */
void android_skin_poll(tenv* env);

/** Sends the palette and the 66 preset sequences up to Compose. Once. */
void android_skin_publish_tables(tenv* env);

/** Sends what is currently worn: mode, preset, code, accessory. */
void android_skin_publish_state(tenv* env);

#endif
