"""Arena texts from every arena (OM, 2026-10-31).

Battledome's words and dome (network/battledome.c, 2026-10-24) were asked
only of the Battledome network's eight servers. Now every arena Wyrm joins is
asked for its public `http://ip:port/live.json`: an arena that serves it gets
its words and dome drawn (so Wyrm's own arenas can send texts later), one
that does not is simply played as before. To ask the others gently, a miss
waits 15 s, then 30, 60 and at most 120 s; the Battledome servers keep their
3 s poll and 15 s retry. Nothing else changes (same parser, same drawing).

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

B = "app/src/network/battledome.c"

PAIRS = {
    B: [
        (""" * Every port on those machines is asked, so a new arena there works at once.
 * No other arena is ever asked for anything.""",
         """ * Every port on those machines is asked, so a new arena there works at once.
 * Since 2026-10-31 every other arena is asked too (OM: Wyrm's own arenas will
 * send texts): one that has no live.json is asked less and less often (15 s,
 * 30, 60, then every 120 s), so the game never waits on it."""),
        ("""#define BD_RETRY_MS 15000""",
         """#define BD_RETRY_MS 15000
#define BD_RETRY_MAX_MS 120000"""),
        ("""static bool on_bd = false;            /* the arena is a Battledome server */""",
         """static bool on_bd = false;            /* an arena is joined (asked for live.json) */
static bool listed_bd = false;        /* it is one of the Battledome network's */
static int misses = 0;                /* live.json misses in a row on this arena */"""),
        ("""static void callback(struct mg_connection* c, int ev, void* ev_data) {""",
         """/* After a miss: 15 s on a Battledome server; elsewhere 15, 30, 60, then 120 s. */
static Uint64 retry_ms(void) {
  if (listed_bd) return BD_RETRY_MS;
  int shift = misses > 1 ? misses - 1 : 0;
  if (shift > 3) shift = 3;
  Uint64 wait = (Uint64)BD_RETRY_MS << shift;
  return wait > BD_RETRY_MAX_MS ? BD_RETRY_MAX_MS : wait;
}

static void callback(struct mg_connection* c, int ev, void* ev_data) {"""),
        ("""    bool ok = mg_http_status(hm) == 200;
    if (ok) parse(hm->body);
    next_fetch_ms = SDL_GetTicks() + (ok ? BD_POLL_MS : BD_RETRY_MS);""",
         """    bool ok = mg_http_status(hm) == 200;
    if (ok) parse(hm->body);
    misses = ok ? 0 : misses + 1;
    next_fetch_ms = SDL_GetTicks() + (ok ? BD_POLL_MS : retry_ms());"""),
        ("""    if (c == conn) {
      next_fetch_ms = SDL_GetTicks() + BD_RETRY_MS;
      conn = NULL;
    }""",
         """    if (c == conn) {
      misses++;
      next_fetch_ms = SDL_GetTicks() + retry_ms();
      conn = NULL;
    }"""),
        ("""    on_bd = colon && host_listed(host);
    next_fetch_ms = 0;""",
         """    listed_bd = colon && host_listed(host);
    on_bd = colon != NULL && host[0] != '\\0';
    misses = 0;
    next_fetch_ms = 0;"""),
        ("""  if (conn && ms - conn_started_ms > BD_TIMEOUT_MS) {
    drop_conn();
    next_fetch_ms = ms + BD_RETRY_MS;
  }
  if (conn || ms < next_fetch_ms) return;

  char url[160];
  snprintf(url, sizeof(url), "http://%s/live.json", arena);
  conn_started_ms = ms;
  next_fetch_ms = ms + BD_RETRY_MS;""",
         """  if (conn && ms - conn_started_ms > BD_TIMEOUT_MS) {
    drop_conn();
    misses++;
    next_fetch_ms = ms + retry_ms();
  }
  if (conn || ms < next_fetch_ms) return;

  char url[160];
  snprintf(url, sizeof(url), "http://%s/live.json", arena);
  conn_started_ms = ms;
  next_fetch_ms = ms + retry_ms();"""),
        ("""  arena[0] = '\\0';
  on_bd = false;
}""",
         """  arena[0] = '\\0';
  on_bd = false;
  listed_bd = false;
  misses = 0;
}"""),
    ],
}


def apply(root, label="arena texts 2026-10-31", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        if not path.exists():
            raise SystemExit(f"{label}: missing {relative}")
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
