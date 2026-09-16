#ifndef AI_MODE_H
#define AI_MODE_H

#include <thermite.h>

void ai_mode_start(tenv* env, const char* nickname);
void ai_mode_start_editor(tenv* env, const char* nickname);
void ai_mode_finish_editor(tenv* env);
bool ai_mode_is_editor(void);
bool ai_mode_notice_process_event(tenv* env, const void* event);
void ai_mode_tick(tenv* env);
void ai_mode_stop(tenv* env);

#endif
