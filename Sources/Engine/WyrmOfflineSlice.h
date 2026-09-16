#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WYRM_OFFLINE_MAX_SEGMENTS 40

typedef struct WyrmPoint {
    float x;
    float y;
} WyrmPoint;

typedef struct WyrmOfflineSnapshot {
    WyrmPoint segments[WYRM_OFFLINE_MAX_SEGMENTS];
    WyrmPoint food;
    int32_t segment_count;
    int32_t score;
    bool alive;
} WyrmOfflineSnapshot;

// Main-thread only, bounded offline prototype. Coordinates are normalized [0,1].
void WyrmOfflineReset(void);
void WyrmOfflineAim(float x, float y);
void WyrmOfflineStep(float delta_seconds);
void WyrmOfflineGetSnapshot(WyrmOfflineSnapshot *out);

#ifdef __cplusplus
}
#endif
