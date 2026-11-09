"""Every bead and every shadow at every zoom (OM, 2026-11-07: "zooming makes
the skin beads fewer and more; lower their quality, not their count", and
"the shadow sometimes vanishes mid-match").

Two things removed beads: bead_cull_apply dropped every other bead where
neighbours overlapped (more under frame-budget load) and, from budget level 2,
other snakes' shadows; and the skin-texture path dropped every other bead
when the head was under 5 px. Both are off. bead_cull_apply still clips the
hidden part of each bead under the next (less overdraw, same picture).
Quality already falls with distance: the bead atlas is mipmapped
(bead_sampler, maxLod 4), so small beads read smaller levels.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

CULL_OLD = """  const bool mine = o->id == env->usr->gdata.data.snake_id;
  static const float thin_px[4] = {0.75f, 1.5f, 2.5f, 4.0f};
  const int level = mine ? 0 : wyrm_budget_level;
  const float thin = fminf(thin_px[level], 0.25f * size);
  const bool drop_shadows = !mine && level >= 2;"""

CULL_NEW = """  /* Every bead and every shadow stays (OM, 2026-11-07: "zooming made the
     beads fewer and more; lower their quality, not their count", and
     shadows vanished mid-match). Thinning every other bead and dropping
     other snakes' shadows under load are gone; what is left only clips the
     parts of a bead hidden under the next one (less overdraw, same look).
     Quality already falls with distance by itself: the bead atlas is
     mipmapped (bead_sampler), so small beads read smaller levels.
     Wyrm iOS/Scripts/engine_bead_count_2026_11_07.py. */
  (void)o;
  const float thin = 0.0f;
  const bool drop_shadows = false;"""

THIN_OLD = """  /* Far away every other bead is enough (NTL widens its bead gap). */
  bool thin = head_px > 0 && head_px < 5.0f;"""

THIN_NEW = """  /* Every bead at every zoom (OM, 2026-11-07): the far-away "every other
     bead" thinning made the snake's beads come and go while zooming. */
  bool thin = false;
  (void)head_px;"""

PAIRS = {"app/src/game/redraw.c": [(CULL_OLD, CULL_NEW), (THIN_OLD, THIN_NEW)]}


def apply(root, label="bead count 2026-11-07", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        text = path.read_text(encoding="utf-8")
        for old, new in pairs:
            if skip_applied and new in text:
                continue
            if text.count(old) != 1:
                raise SystemExit(f"{label}: anchor x{text.count(old)} in {relative}: {old[:80]!r}")
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8", newline="\n" if "build-original-source" in str(root) else "")


if __name__ == "__main__":
    apply(sys.argv[1], skip_applied=True)
