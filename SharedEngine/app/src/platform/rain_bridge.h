#ifndef WYRM_RAIN_BRIDGE_H
#define WYRM_RAIN_BRIDGE_H
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
struct mg_connection;
struct tenv;
void wyrm_rain_init(void);
void wyrm_rain_capture(struct mg_connection* connection, const void* data, size_t length);
void wyrm_rain_tick(struct tenv* env);
void wyrm_rain_read(char* out, size_t capacity);
void wyrm_rain_enable(bool enabled);
void wyrm_rain_rotate(int direction);
bool wyrm_rain_rotating(void);
/* Rain key (OM, 2026-10-14): shown while Rain is on; a tap asks for the panel. */
bool wyrm_rain_enabled(void);
void wyrm_rain_key_press(void);
#endif
