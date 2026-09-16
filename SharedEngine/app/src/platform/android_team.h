#ifndef ANDROID_TEAM_H
#define ANDROID_TEAM_H

#include <stdbool.h>

typedef struct tenv tenv;

/**
 * The team, as far as the arena is concerned.
 *
 * The service, the polling and the parsing all live on the app side; the
 * engine's only jobs are to say where this player is and to draw where the
 * others are. It holds no connection, no credentials and no timer, which is
 * why nothing here can stall a frame or take a finger away from the game.
 */
void android_team_bind_env(tenv* env);

/**
 * Periodically writes down where this player is, on the engine's own thread.
 *
 * The app asks for this from its polling thread, and the snake array it used
 * to read directly is grown and moved by the engine while a match is running.
 * Reading it from another thread was a race that could hand back nonsense or
 * fault outright, so the engine leaves a copy behind instead.
 */
void android_team_poll(tenv* env);

/** Takes one immutable member snapshot for everything drawn this frame. */
void android_team_begin_frame(void);

/** Teammates on the minimap, for those in the same arena as this player. */
void android_team_draw_minimap(tenv* env, float left, float top,
                               float diameter);

/** The roster block, placed by its screen-space centre. Returns its height. */
float android_team_draw_roster_centered(tenv* env, float centre_x,
                                        float centre_y);

/*
 * Chat during a match, and the bot that covers for you.
 *
 * Opening chat hands the snake to the bot at once — a player reading messages
 * is not steering. Closing it does not take the snake back the same instant:
 * a countdown runs first and says so, because coming back to a snake already
 * mid-turn is how you die reading a message.
 */
/**
 * Where the chat button should hang, in the frame being drawn.
 *
 * The button belongs beside the leaderboard, and only the code that draws the
 * leaderboard knows how wide it came out — it is measured from its own type,
 * so it is a different width with a different font size or a longer name. The
 * board hands its left edge over each frame; without one the button falls back
 * to the corner of the display.
 */
void android_team_set_chat_centre(float centre_x, float centre_y);
void android_team_draw_chat_button(tenv* env);
bool android_team_chat_button_hit(tenv* env, float x, float y);

/* Auto respawn, beside the chat button. Only drawn while it is on, because the
   death card is where it is turned back on. */
void android_team_draw_respawn_toggle(tenv* env);

/* What the chat button said when it refused, and the bot key it offers to a
   player who has none of their own. */
void android_team_draw_chat_help(tenv* env);
bool android_team_respawn_toggle_hit(tenv* env, float x, float y);
void android_team_close_chat(float seconds);
bool android_team_chat_open(void);

/**
 * Gives the snake back at once and forgets that chat was ever open.
 *
 * Dying with chat open used to leave this still holding the bot. The death
 * card takes the bot for its own background run, and when it looked to see
 * what the player's own setting was it found a bot that was already on — this
 * one's doing — and handed *that* back as the preference. The next life then
 * started under a bot that could not be switched off, with no chat button to
 * be seen, because as far as this file knew the chat was still open. So the
 * hold is dropped before anything else is allowed to read it.
 */
void android_team_release_chat(tenv* env);

/** Runs the bot handover and draws the countdown. Called once a frame. */
void android_team_tick(tenv* env);

#endif
