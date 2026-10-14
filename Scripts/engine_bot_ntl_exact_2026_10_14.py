"""Wyrm's bot = NTL 9.68's bot, with no Wyrm changes left (OM, 2026-10-14).

The 2026-10-13 port (engine_ntl_bot_2026_10_13.py) kept four things of
Wyrm's own; OM: the strict "surrounded = boost and flee" misbehaved, make the
whole bot the same as NTL. This removes all four, so app/src/game/sbot.c
behaves like NTL's `tf` (legacy/ntl 9.68/main-mt.js) line for line:

  1. surrounded (tf.pe): boost only when the snake around us is itself
     boosting (speed > 10) and does not fill every sector; a crowd boosts not.
  2. coiled (tf.Re): no "wrapped round" break-out with boost.
  3. no border guard: the wall is only NTL's wall points.
  4. the wall is measured from the camera (NTL's gu/iu use view_xx/view_yy),
     its points lie on 0.98 x the arena (he), or on the shrink radius (Xl =
     real_flux_grd) while the arena shrinks; wall points count as snake 0,
     as NTL tags them.
  5. the open-gap search keeps NTL's JavaScript truthiness: a gap that starts
     at sector 0 is not seen (NTL's `ab&&`).

One source for both apps: Wyrm Android's tree gets these pairs once
(`python engine_bot_ntl_exact_2026_10_14.py "<Wyrm Android>"`), and
prepare-original-engine.py applies them after engine_ntl_bot_2026_10_13.
Revert: the 2026-10-13 text is engine_ntl_bot_2026_10_13.NEW_FILES.
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


pairs("app/src/game/sbot.c",
      (""" * Wyrm keeps three things of its own:
 *  - the border guard (`avoid_border_emergency`, OM 2026-10-12): it outranks
 *    every state and turns the snake back inward before it reaches the wall;
 *  - the wall is measured from the head, not the eased camera, and obeys the
 *    server's border while a shrink is still easing on screen;
 *  - surrounded = flee with boost, always (OM): NTL boosts only when the
 *    snake surrounding it is boosting. Coiled, NTL never looked; Wyrm checks
 *    for one snake wrapped round it (its points outside our own coil) and
 *    breaks out with boost too.
 *  And one fix: NTL's open-gap search (`Xe`) loses a gap that starts at
 *  sector 0 (JavaScript treats the index 0 as false); Wyrm keeps it.
 */""",
       """ * Nothing of Wyrm's own is left (OM, 2026-10-14): no border guard, the wall
 * is measured from the camera as NTL does, surrounded boosts only when the
 * snake around is boosting, no break-out from the coil, and the open-gap
 * search keeps NTL's JavaScript truthiness (a gap starting at sector 0 is
 * not seen). See Wyrm iOS/Scripts/engine_bot_ntl_exact_2026_10_14.py.
 */"""),
      ("""/* During a shrink the renderer eases flux_grd over several frames, but the
   server's border (real_flux_grd) has already moved: the bot obeys the smaller
   (OM, 2026-10-12, from the reference client). */
static inline double safe_border_radius(const game_data* gdata) {
  double smoothed = gdata->data.flux_grd;
  double server = gdata->data.real_flux_grd;
  if (server > 0.0 && (smoothed <= 0.0 || server < smoothed)) return server;
  return smoothed;
}

""", ""),
      ("""  B.pts_r = safe_border_radius(gdata);
  if (B.pts_r <= 0) B.pts_r = B.he;
  /* H9: the server is shrinking the arena; then its radius (Xl) is the wall. */
  bool shrinking = gdata->data.real_flux_grd > 0 &&
                   gdata->data.real_flux_grd < gdata->data.grd * 0.98 - 1.0;
  B.prox_r = shrinking ? B.pts_r : B.centre;""",
       """  /* H9: the server is shrinking the arena; then its radius (Xl) is the wall.
     NTL: wall points on (H9 ? Xl : he), nearness against (H9 ? Xl : af). */
  bool shrinking = gdata->data.real_flux_grd > 0 &&
                   gdata->data.real_flux_grd < gdata->data.grd * 0.98 - 1.0;
  B.pts_r = shrinking ? gdata->data.real_flux_grd : B.he;
  B.prox_r = shrinking ? gdata->data.real_flux_grd : B.centre;"""),
      ("""  /* gu / iu: from the head, not the eased camera (Wyrm). */
  B.gu = sqrt(dist2(B.hx, B.hy, B.centre, B.centre));
  B.iu = atan2(B.hy - B.centre, B.hx - B.centre);""",
       """  /* gu / iu: NTL measures the wall from the camera (view_xx / view_yy). */
  B.gu = sqrt(dist2(gdata->data.view_xx, gdata->data.view_yy, B.centre, B.centre));
  B.iu = atan2(gdata->data.view_yy - B.centre, gdata->data.view_xx - B.centre);"""),
      ("""  /* The wall, as NTL draws it: a point every 8 units along 2000 of it.
     Tagged -1 (NTL tagged it snake 0, which counted the wall as that snake). */""",
       """  /* The wall, as NTL draws it: a point every 8 units along 2000 of it,
     tagged snake 0 as NTL does (it counts with that snake when surrounded). */"""),
      ("""      note_sector(wx, wy, d2, 8.0, -1);
      push_se((cpt){wx, wy, d2, 8.0, -1, false});""",
       """      note_sector(wx, wy, d2, 8.0, 0);
      push_se((cpt){wx, wy, d2, 8.0, 0, false});"""),
      ("""      d = B.ie[i].d2;
      if (start >= 0) {
        opens[no++] = (gap){start, i - 1, i - 1 - start};
        start = -1;
      }""",
       """      d = B.ie[i].d2;
      /* NTL's `ab&&`: a gap starting at sector 0 is falsy, so it is kept
         open and never pushed (NTL as it is). */
      if (start > 0) {
        opens[no++] = (gap){start, i - 1, i - 1 - start};
        start = -1;
      }"""),
      ("""  if (start >= 0) {
    if (no > 0) {""",
       """  if (start > 0) {
    if (no > 0) {"""),
      ("""/* tf.pe: surrounded — by one snake over half the sectors, or by anything
   close in over half of them. Wyrm: always flee with boost. */
static bool surrounded(game_data* gdata) {
  (void)gdata;
  int count[1024];
  memset(count, 0, sizeof(count));
  int most = 0, close = 0;
  for (int i = 0; i < NTL_ARCS; i++) {
    if (!B.ie_set[i]) continue;
    int si = B.ie[i].si;
    if (si >= 0 && si < 1024 && ++count[si] > most) most = count[si];
    double near = B.radius * NTL_ENCIRCLE_DIST;
    if (B.ie[i].d2 < near * near) close++;
  }
  if (most > NTL_ARCS * NTL_ENCIRCLE_ONE || close > NTL_ARCS * NTL_ENCIRCLE_ALL) {
    widest_gap();
    B.boost = true;
    return true;
  }
  B.boost = false;
  return false;
}""",
       """/* tf.pe: surrounded, by one snake over half the sectors (boost only if that
   snake is boosting and does not fill every sector), or by anything close in
   over half of them (no boost). NTL as it is (OM, 2026-10-14). */
static bool surrounded(game_data* gdata) {
  int count[1024];
  memset(count, 0, sizeof(count));
  int most = 0, close = 0, most_si = -1;
  for (int i = 0; i < NTL_ARCS; i++) {
    if (!B.ie_set[i]) continue;
    int si = B.ie[i].si;
    if (si >= 0 && si < 1024 && ++count[si] > most) {
      most = count[si];
      most_si = si;
    }
    double near = B.radius * NTL_ENCIRCLE_DIST;
    if (B.ie[i].d2 < near * near) close++;
  }
  if (most > NTL_ARCS * NTL_ENCIRCLE_ONE) {
    widest_gap();
    int ns = tdarray_length(gdata->data.snakes);
    B.boost = most != NTL_ARCS && most_si >= 0 && most_si < ns &&
              gdata->data.snakes[most_si].sp > 10.0f;
    return true;
  }
  if (close > NTL_ARCS * NTL_ENCIRCLE_ALL) {
    widest_gap();
    B.boost = false;
    return true;
  }
  B.boost = false;
  return false;
}"""),
      ("""  if (wrapped_round(gdata, &inside)) return;

""", "\n"),
      ("""  B.boost = false;

  if (avoid_border_emergency(gdata)) return;
""", """  B.boost = false;
"""))

# Whole functions that go: the text from the first marker up to (not
# including) the second is cut (the border guard and wrapped_round).
CUTS = [
    ("app/src/game/sbot.c",
     "/* ------------------------------------------------------------ the border (Wyrm) */",
     "/* ------------------------------------------------------------ go */"),
    ("app/src/game/sbot.c",
     "/* Coiled, a snake wrapped round us (Wyrm, OM 2026-10-13): one snake's points",
     "/* tf.Re: follow our own body round, keeping the coil clear. */"),
]


def apply(root, label="engine bot NTL exact 2026-10-14", skip_applied=False):
    root = Path(root)
    for relative, start, end in CUTS:
        target = root / relative
        text = target.read_text(encoding="utf-8")
        if start not in text:
            if skip_applied:
                continue
            raise SystemExit(f"{label}: cut start missing in {relative}: {start[:60]!r}")
        s = text.index(start)
        e = text.index(end, s)
        target.write_text(text[:s] + text[e:], encoding="utf-8", newline="")
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        crlf = "\r\n" in text
        for old, new in items:
            if crlf:
                old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
            if skip_applied and new in text and old not in text:
                continue
            count = text.count(old)
            if count != 1:
                raise SystemExit(f"{label}: anchor x{count} in {relative}: {old[:70]!r}")
            text = text.replace(old, new)
        if text != original:
            target.write_text(text, encoding="utf-8", newline="")
    return len(PAIRS)


if __name__ == "__main__":
    print(apply(sys.argv[1], skip_applied=True), "files written")
