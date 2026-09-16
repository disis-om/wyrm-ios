#ifndef SBOT_H
#define SBOT_H

#include <thermite.h>

// Implementation of Saya's bot: https://github.com/saya-0x0efe/Slither.io-bot
// Courtesy of Claude and NumerOus
// Note: This has not been tested extensively.

typedef struct sbot {
  struct {
    float xm;
    float ym;
    bool accel;
  } output;
} sbot;

typedef struct sbot_decision {
  float heading;
  bool accel;
} sbot_decision;

void sbot_init(tenv* env);
void sbot_go(tenv* env);
void sbot_destroy(tenv* env);
void sbot_reset_ai_contexts(void);
void sbot_forget_ai_snake(int snake_id);
bool sbot_decide_for_snake(tenv* env, int snake_id, sbot_decision* decision);

#endif
