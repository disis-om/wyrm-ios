#include "../Sources/Engine/WyrmOfflineSlice.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    WyrmOfflineSnapshot before, after;
    WyrmOfflineReset();
    WyrmOfflineGetSnapshot(&before);
    assert(before.alive && before.score == 0 && before.segment_count == 16);
    assert(before.food.x >= 0.10f && before.food.x <= 0.90f);
    assert(before.food.y >= 0.22f && before.food.y <= 0.74f);
    WyrmOfflineAim(NAN, NAN);
    WyrmOfflineStep(1.0f / 30.0f);
    WyrmOfflineGetSnapshot(&after);
    assert(after.alive && after.segments[0].x > before.segments[0].x);
    for (int i = 0; i < 1000 && after.alive; ++i) {
        WyrmOfflineAim(0.75f, 0.48f);
        WyrmOfflineStep(1.0f / 30.0f);
        WyrmOfflineGetSnapshot(&after);
        assert(after.segment_count >= 16 &&
               after.segment_count <= WYRM_OFFLINE_MAX_SEGMENTS);
        assert(isfinite(after.segments[0].x) && isfinite(after.segments[0].y));
    }
    assert(!after.alive);
    WyrmOfflineReset();
    WyrmOfflineGetSnapshot(&after);
    assert(after.alive && after.score == 0 && after.segment_count == 16);
    puts("PASS: offline C reset, movement, bounded state, death, restart");
    return 0;
}
