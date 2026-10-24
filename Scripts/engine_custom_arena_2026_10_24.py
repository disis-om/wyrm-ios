"""The custom arena id goes to every arena (OM, 2026-10-24).

engine_custom_arena_2026_10_13.py sent NTL's playerID packet ('C' + 16 of
[0-9A-Za-z], between the challenge answer and the join) only to the arenas on
NTL's online list. NTL 9.76 has no online list any more (`useplayerid.php` is
gone from main-mt.js): it sends to the player's own `!id` list, or to every
arena with `!idforce`. That list was empty, so Wyrm never sent the id.

Now the packet goes to every arena, as NTL's `!idforce` does. Checked live
first (2026-10-24, arena 8828 = 148.113.20.151:444, official): with the packet
the client joined ('a' 0.50 s), spawned and played 20 s like the control run
without it; no kick. The list argument of custom_arenas_set is kept for the
apps and ignored.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py after
engine_custom_arena_2026_10_13, to the generated iOS tree.
"""
import sys
from pathlib import Path

OLD_START = "/* True, with the packet in `out`, when `arena` is on the list. */\n"
NEW = """/* The packet for every arena (OM, 2026-10-24, NTL's `!idforce`): false only
   while the app has not handed over a valid id. `arena` is no longer used. */
static bool custom_arena_id_packet(const char* arena,
                                   uint8_t out[1 + CUSTOM_ARENA_ID_LEN]) {
  (void)arena;
  SDL_LockSpinlock(&custom_arena_lock);
  bool ready = custom_arena_id[0] != 0;
  if (ready) {
    out[0] = 'C';
    memcpy(out + 1, custom_arena_id, CUSTOM_ARENA_ID_LEN);
  }
  SDL_UnlockSpinlock(&custom_arena_lock);
  return ready;
}
"""
HEAD_OLD = (" * join, only to the arenas on the list the apps fetch\n"
            " * (ntl-slither.com/slither/useplayerid.php; official arenas are not on it),\n")
HEAD_NEW = (" * join. Since 2026-10-24 to every arena, as NTL's `!idforce` (NTL 9.76 has\n"
            " * no online list any more; the old one was ntl-slither.com/slither/useplayerid.php),\n")
CALL_OLD = ("    /* Custom arenas (OM, 2026-10-13): NTL's id packet, between the answer\n"
            "       and the join, only to an arena on the list. */\n")
CALL_NEW = ("    /* Custom arenas (OM, 2026-10-13): NTL's id packet, between the answer\n"
            "       and the join, to every arena (2026-10-24). */\n")


def _callback(text, label):
    if "NTL's `!idforce`): false only" in text:
        return text  # applied
    if text.count(OLD_START) != 1:
        raise SystemExit(f"{label}: id packet function x{text.count(OLD_START)}")
    a = text.index(OLD_START)
    b = text.index("\n}\n", a) + 3
    if "custom_arena_list" not in text[a:b]:
        raise SystemExit(f"{label}: unexpected id packet function")
    text = text[:a] + NEW + text[b:]
    for old, new in ((HEAD_OLD, HEAD_NEW), (CALL_OLD, CALL_NEW)):
        if text.count(old) != 1:
            raise SystemExit(f"{label}: comment anchor x{text.count(old)}: {old[:50]!r}")
        text = text.replace(old, new)
    return text


def apply(root, label="custom arena 2026-10-24"):
    path = Path(root) / "app/src/network/callback.c"
    raw = path.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = _callback(raw.replace("\r\n", "\n"), label)
    if crlf:
        text = text.replace("\n", "\r\n")
    path.write_bytes(text.encode("utf-8"))


if __name__ == "__main__":
    apply(sys.argv[1])
