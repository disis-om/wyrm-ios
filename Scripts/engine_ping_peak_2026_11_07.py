"""Stats: PING(ms) shows both numbers, as NTL does (OM, 2026-11-07: "ping and
ms are different; show ping(ms) with both values on the same line").

NTL's status line is "FPS: n @ ao(ro) ms" (legacy/ntl 9.68 main-mt.js, the
"p" pong handler): ao is the round trip averaged over each second, ro the
worst round trip in a 10 s window. The engine already keeps both the same way
(game/oef.c ping_mark_received: data.ping and data.ping_peak); the stats line
showed only the first. Now "42(57)". No packet or setting change.

Applied once to Wyrm Android's tree and, by prepare-original-engine.py, to the
generated iOS tree.
"""
import sys
from pathlib import Path

PAIRS = {
    "app/src/game/ui_overlay.c": [
        ('''    snprintf(ping_text, sizeof(ping_text), "%d", gdata->data.ping);''',
         '''    /* NTL's "ao(ro)": the 1 s average, then the 10 s worst (2026-11-07,
       Wyrm iOS/Scripts/engine_ping_peak_2026_11_07.py). */
    snprintf(ping_text, sizeof(ping_text), "%d(%d)", gdata->data.ping,
             gdata->data.ping_peak > gdata->data.ping ? gdata->data.ping_peak : gdata->data.ping);'''),
    ],
}


def apply(root, label="ping peak 2026-11-07", skip_applied=False):
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
