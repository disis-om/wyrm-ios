#ifndef WYRM_AUDIO_H
#define WYRM_AUDIO_H

/* AIR's sounds (OM, 2026-11-08): events for the apps to play (wyrm_audio.c). */
#include <stdbool.h>
#include "../user.h"

void wyrm_audio_view(float half_w, float half_h);
void wyrm_audio_snake_died(game_data* g, snake* o, bool own);
void wyrm_audio_food_eaten(float size);
void wyrm_audio_frame(game_data* g);
int wyrm_audio_take(char* out, int size);
#ifdef WYRM_IOS
const char* WyrmIOSAudioTake(void);
#endif

#endif
