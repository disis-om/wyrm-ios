"""Our snake's NTL id when it spawns after packet S (OM, 2026-11-07: "sometimes
the team cannot see where I am").

The id NTL knows a snake by (`sid`, ((session & 63) << 10) | arena_id & 1023)
was written only when packet S arrived and found our snake already there. On
a join or respawn the snake is often added after S, so it kept its raw arena
id, android_team.c published that as `sid`, and teammates on NTL could not
match the report to our snake (and our own name check fell back to names).
Now a snake added with the id S named takes the NTL id at once.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

PAIRS = {
    "app/src/network/callback.c": [
        ("""      o.ntl_id = id;
""", """      o.ntl_id = id;
      /* Packet S may have come before our snake (a join or a respawn): our
         snake then takes NTL's id now (2026-11-07,
         Wyrm iOS/Scripts/engine_team_sid_2026_11_07.py). */
      if (id == gdata->data.session_snake_id && gdata->data.session_id)
        o.ntl_id = snake_ntl_id(id, gdata->data.session_id);
"""),
    ],
}


def apply(root, label="team sid 2026-11-07", skip_applied=False):
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
