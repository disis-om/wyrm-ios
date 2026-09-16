#include "WyrmOfflineSlice.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

_Static_assert(sizeof(WyrmPoint) == 8, "WyrmPoint ABI changed");
_Static_assert(offsetof(WyrmOfflineSnapshot, food) == 320,
               "Offline snapshot segment offset changed");
_Static_assert(sizeof(WyrmOfflineSnapshot) == 340,
               "Offline snapshot ABI changed");

typedef struct WyrmOfflineState {
    WyrmOfflineSnapshot snapshot;
    WyrmPoint aim;
    float heading;
    uint32_t random_state;
    bool has_aim;
} WyrmOfflineState;

static WyrmOfflineState game;

static float clampf(float value, float low, float high) {
    return value < low ? low : (value > high ? high : value);
}

static float distance_squared(WyrmPoint a, WyrmPoint b) {
    const float dx = a.x - b.x;
    const float dy = a.y - b.y;
    return dx * dx + dy * dy;
}

static float random_unit(void) {
    game.random_state = game.random_state * 1664525u + 1013904223u;
    return (float)((game.random_state >> 8) & 0x00ffffffu) / 16777216.0f;
}

static void place_food(void) {
    for (int attempt = 0; attempt < 32; ++attempt) {
        WyrmPoint candidate = {0.10f + 0.80f * random_unit(),
                               0.22f + 0.52f * random_unit()};
        if (distance_squared(candidate, game.snapshot.segments[0]) > 0.05f) {
            game.snapshot.food = candidate;
            return;
        }
    }
    game.snapshot.food = (WyrmPoint){0.75f, 0.48f};
}

void WyrmOfflineReset(void) {
    memset(&game, 0, sizeof(game));
    game.snapshot.segment_count = 16;
    game.snapshot.alive = true;
    game.heading = 0.0f;
    game.random_state = 0x57a9b17u;
    for (int i = 0; i < game.snapshot.segment_count; ++i) {
        game.snapshot.segments[i] = (WyrmPoint){0.42f - i * 0.021f, 0.48f};
    }
    place_food();
}

void WyrmOfflineAim(float x, float y) {
    if (!isfinite(x) || !isfinite(y)) return;
    game.aim = (WyrmPoint){clampf(x, 0.04f, 0.96f), clampf(y, 0.17f, 0.78f)};
    game.has_aim = true;
}

void WyrmOfflineStep(float delta_seconds) {
    if (!game.snapshot.alive || !isfinite(delta_seconds) || delta_seconds <= 0.0f) return;
    const float dt = clampf(delta_seconds, 0.0f, 0.05f);
    const WyrmPoint head = game.snapshot.segments[0];
    if (game.has_aim) {
        const float dx = game.aim.x - head.x;
        const float dy = game.aim.y - head.y;
        if (dx * dx + dy * dy > 0.0009f) {
            const float desired = atan2f(dy, dx);
            float difference = atan2f(sinf(desired - game.heading),
                                      cosf(desired - game.heading));
            game.heading += clampf(difference, -4.2f * dt, 4.2f * dt);
        }
    }

    const float speed = 0.21f + 0.005f * (float)game.snapshot.score;
    WyrmPoint next = {head.x + cosf(game.heading) * speed * dt,
                      head.y + sinf(game.heading) * speed * dt};
    if (next.x < 0.045f || next.x > 0.955f ||
        next.y < 0.17f || next.y > 0.78f) {
        game.snapshot.alive = false;
        return;
    }

    // A bounded following chain keeps the native simulation independent of UI.
    WyrmPoint prior = next;
    for (int i = 0; i < game.snapshot.segment_count; ++i) {
        WyrmPoint current = game.snapshot.segments[i];
        const float dx = prior.x - current.x;
        const float dy = prior.y - current.y;
        const float length = sqrtf(dx * dx + dy * dy);
        if (length > 0.020f) {
            game.snapshot.segments[i].x = prior.x - dx * (0.020f / length);
            game.snapshot.segments[i].y = prior.y - dy * (0.020f / length);
        }
        prior = game.snapshot.segments[i];
    }
    game.snapshot.segments[0] = next;

    if (distance_squared(next, game.snapshot.food) < 0.0014f) {
        game.snapshot.score += 1;
        const int count = game.snapshot.segment_count;
        if (count < WYRM_OFFLINE_MAX_SEGMENTS) {
            game.snapshot.segments[count] = game.snapshot.segments[count - 1];
            game.snapshot.segment_count = count + 1;
        }
        place_food();
    }
    for (int i = 9; i < game.snapshot.segment_count; ++i) {
        if (distance_squared(next, game.snapshot.segments[i]) < 0.00015f) {
            game.snapshot.alive = false;
            break;
        }
    }
}

void WyrmOfflineGetSnapshot(WyrmOfflineSnapshot *out) {
    if (out) *out = game.snapshot;
}
