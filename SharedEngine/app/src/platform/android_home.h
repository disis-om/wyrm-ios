#ifndef ANDROID_HOME_H
#define ANDROID_HOME_H

#include <stdbool.h>

typedef struct tenv tenv;

/*
 * The bridge between Compose Home and the engine.
 *
 * Wyrm's Home is a Compose screen; the engine draws nothing while it is up.
 * Compose asks for things from the Android main thread, the engine answers on
 * its own thread, so every request is parked in a small mailbox here and
 * applied by android_home_poll at the top of a frame.
 */

void android_home_bind_env(tenv* env);

/** Applies anything Compose asked for. Engine thread, once per frame. */
void android_home_poll(tenv* env);

/**
 * Tells Java which screen the engine is on.
 *
 * Java decides from this what Compose shows and which way the phone is held:
 * Home and the skin editor are Compose and portrait. The native lobby and the
 * arena belong to the engine and are landscape.
 */
void android_home_set_screen(int screen);

/** Pushes the persisted nickname and the selected arena up to Compose. */
void android_home_publish_state(tenv* env);

/**
 * Tells Compose that an arena would not take us, and for how long to say so.
 *
 * The picker is a few hundred machines that differ only in numbers, and a
 * refusal is a number it has no other way to know: an arena can answer a TCP
 * ping in twenty milliseconds and still hang up on every join. `seconds` is how
 * long the mark has left to run, so the mark expires on Compose's own clock
 * without the engine having to keep telling it.
 */
void android_home_arena_refused(const char* endpoint, int seconds);

/*
 * Death.
 *
 * There is no death card. The native lobby is the return from a match, and
 * Play lives there so connect never crosses JNI.
 */
void android_home_notify_death(tenv* env);

/** Opens a new once-per-life run receipt when the player's snake spawns. */
void android_home_begin_life(void);

/**
 * Play from the lobby is a new life.
 *
 * Death flags outlive the socket: `run_recorded` is only cleared on spawn,
 * and a join that never spawned left it set, so the next `'v'` was ignored.
 * Lobby Play must start clean, like slither resetting `dead_mtm` before
 * `connect()`.
 */
void android_home_reset_death(void);

/** Whether the death card is currently up. */
bool android_home_death_active(void);

/** Whether a death is still being dealt with — the wait, or the card itself. */
bool android_home_death_pending(void);
float android_home_death_opacity(void);
void android_home_advance_death(tenv* env, float vfr);

#endif
