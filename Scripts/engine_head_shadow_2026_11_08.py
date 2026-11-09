"""One eye (skin 27): wider shadows under the swollen head beads (OM, 2026-11-08:
"the first 2-3 beads show no shadow because the beads are wider; make their
shadow wider too").

engine_air_extras_2026_11_07.py grows the first four beads from the head by
1 + (4 - p) * 0.06 and their shadows by the same amount, so the shadow stays
hidden under the bigger bead. The shadow now grows 2.5 times as much:
1 + (4 - p) * 0.15 (1.60, 1.45, 1.30, 1.15). Every other skin and bead is
unchanged. Runs after the AIR extras pass.

Applied by prepare-original-engine.py to the generated iOS tree; run
`python this.py <Wyrm Android>` to give Android's tree the same text.
"""
import sys
from pathlib import Path

HELPER = '''#include "wyrm_extras.h"
/* Skin 27's head shadows grow more than its beads (OM, 2026-11-08,
   Wyrm iOS/Scripts/engine_head_shadow_2026_11_08.py). */
static float air_head_shadow_swell(const snake* o, int bead_from_head) {
  float swell = air_looks_swell(o, bead_from_head);
  return swell > 1.0f ? 1.0f + (swell - 1.0f) * 2.5f : 1.0f;
}
'''

PAIRS = {
    "app/src/game/redraw.c": [
        ('#include "wyrm_extras.h"\n', HELPER, 1),
        ("air_half * air_looks_swell(o, (int)j - 4)", "air_half * air_head_shadow_swell(o, (int)j - 4)", 6),
        ("shsz * air_looks_swell(o, (int)k)", "shsz * air_head_shadow_swell(o, (int)k)", 6),
    ],
}


def apply(root, label="head shadow 2026-11-08", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        text = path.read_text(encoding="utf-8")
        for old, new, count in pairs:
            if skip_applied and new in text:
                continue
            if text.count(old) != count:
                raise SystemExit(f"{label}: anchor x{text.count(old)}/{count} in {relative}: {old[:80]!r}")
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8", newline="\n" if "build-original-source" in str(root) else "")


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
