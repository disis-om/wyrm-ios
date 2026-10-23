"""Teammates on the minimap, as the reference client shows them (OM, 2026-10-23).

OM: NTL teammates' locations went missing from the minimap on both apps. The
engine part (this file) fixes what the engine drew wrongly; the apps fix what
they handed it (iOS read NTL's float `valx`/`valy` as 0, Android/iOS packing
notes in the AGENTS logs).

- Same frame as the map: your own mark, the cells and the last-death dot sit
  at 0.9 of the radius (mm.slang, wyrm_draw_minimap); teammates were at 0.8,
  so a teammate showed somewhere else than where they were.
- A teammate past the map's current border used to be dropped (a box test on
  -1..1, with the border shrinking below the arena); now the mark stays on the
  edge, as the reference client's ntl_team_draw_minimap does.
- A teammate this client can see uses its live place (found by NTL's snake id,
  `sid` = `snake.ntl_id`): the service's copy is up to a poll old.
- Bright green instead of the theme's green (OM), over the dark ring.
- Near Original's map has your mark at the full radius: the team is drawn on
  that frame there.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree (the function is the same text in both).
"""
import sys
from pathlib import Path

START = ("void android_team_draw_minimap(tenv* env, float left, float top,\n"
         "                               float diameter) {\n"
         "  int count = frame_member_count;\n")
OLD_MARK = "    ImVec2 point = {centre_x + nx * diameter * 0.40f,\n"

NEW = """void android_team_draw_minimap(tenv* env, float left, float top,
                               float diameter) {
  int count = frame_member_count;
  if (count <= 0 || diameter <= 0.0f) return;

  game_data* game = &env->usr->gdata;
  float world_radius = game->data.flux_grd;
  if (world_radius <= 1.0f) return;

  float centre_x = left + diameter * 0.5f;
  float centre_y = top + diameter * 0.5f;
  /* The map's own frame (OM, 2026-10-23): your mark and the cells sit at 0.9
     of the radius (mm.slang, wyrm_draw_minimap). Teammates were at 0.8 and
     showed somewhere else than where they were. */
  float reach = diameter * 0.5f * 0.9f;
  float radius = diameter * 0.026f;
  if (radius < 4.0f) radius = 4.0f;
  if (radius > 7.0f) radius = 7.0f;
  int snakes = tdarray_length(game->data.snakes);

  ImDrawList* draw = igGetForegroundDrawList_ViewportPtr(NULL);
  for (int i = 0; i < count; ++i) {
    const team_member* member = frame_members + i;
    if (!team_member_here(env, member)) continue;
    if (team_member_is_me(env, member)) continue;

    /* The service's copy is up to a poll old: a teammate this client can see
       uses its live place, found by NTL's snake id (the reference client
       does the same). */
    float x = (float)member->x;
    float y = (float)member->y;
    if (member->sid > 0 && snakes > 0) {
      snake* live = snake_find_by_ntl_id(game->data.snakes, snakes, member->sid);
      if (live && !live->dead && live->id != game->data.snake_id) {
        x = live->xx;
        y = live->yy;
      }
    }
    if (!isfinite(x) || !isfinite(y) || (x == 0.0f && y == 0.0f)) continue;

    /* Past the map's current border the mark stays on its edge; it used to be
       dropped, and a teammate near the border vanished. */
    float nx = (x - game->data.grd) / world_radius;
    float ny = (y - game->data.grd) / world_radius;
    float far = sqrtf(nx * nx + ny * ny);
    if (far > 1.0f) {
      nx /= far;
      ny /= far;
    }

    ImVec2 point = {centre_x + nx * reach, centre_y + ny * reach};
    /* A dark ring under the mark so it survives a pale patch of map, then a
       bright green (OM, 2026-10-23: brighter than the theme's green). */
    ImDrawList_AddCircleFilled(draw, point, radius + 2.0f,
                               team_colour(0, 0, 0, 0.70f), 20);
    ImDrawList_AddCircleFilled(draw, point, radius,
                               team_colour(0.20f, 1.0f, 0.36f, 1.0f), 20);
  }
}
"""

NEAR_OLD = "  android_team_draw_minimap(env, c.x - R, c.y - R, R * 2.0f);\n"
NEAR_NEW = ("  /* Your mark is at the full radius here; the team draws at 0.9 of the\n"
            "     radius it is given, so it is given R / 0.9 (2026-10-23). */\n"
            "  android_team_draw_minimap(env, c.x - R / 0.9f, c.y - R / 0.9f,\n"
            "                            R * 2.0f / 0.9f);\n")


def _edit(path, change):
    raw = path.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = change(raw.replace("\r\n", "\n"))
    if crlf:
        text = text.replace("\n", "\r\n")
    path.write_bytes(text.encode("utf-8"))


def _team(text, label):
    if "drawn wrongly" in text or "brighter than the theme's green" in text:
        return text  # applied
    if text.count(START) != 1:
        raise SystemExit(f"{label}: minimap function x{text.count(START)}")
    a = text.index(START)
    b = text.index("\n}\n", a) + 3
    body = text[a:b]
    if OLD_MARK not in body:
        raise SystemExit(f"{label}: unexpected minimap function body")
    if "team_colour(" not in text or "static bool team_member_is_me" not in text:
        raise SystemExit(f"{label}: helpers missing")
    out = text[:a] + NEW + text[b:]
    if "#include <math.h>" not in out:
        out = out.replace("#include <stdio.h>\n", "#include <math.h>\n#include <stdio.h>\n", 1)
    return out


def _overlay(text, label):
    if NEAR_NEW in text:
        return text
    if text.count(NEAR_OLD) != 1:
        raise SystemExit(f"{label}: Near Original team call x{text.count(NEAR_OLD)}")
    return text.replace(NEAR_OLD, NEAR_NEW)


def apply(root, label="team map 2026-10-23"):
    _edit(Path(root) / "app/src/platform/android_team.c", lambda t: _team(t, label))
    _edit(Path(root) / "app/src/game/ui_overlay.c", lambda t: _overlay(t, label))


if __name__ == "__main__":
    apply(sys.argv[1])
