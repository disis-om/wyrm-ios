"""Explicit Rain observer/rotation hooks; no change to arena login bytes."""
from pathlib import Path
SOURCE = Path(__file__).resolve().parents[1] / "SharedEngine"

def apply(tree, label="Rain bridge"):
    tree = Path(tree)
    for name in ("rain_bridge.c", "rain_bridge.h"):
        source = SOURCE / "app/src/platform" / name
        destination = tree / "app/src/platform" / name
        destination.write_bytes(source.read_bytes())
    changes = {
        "app/src/network/server.c": [
            ('#include "callback.h"', '#include "callback.h"\n#include "../platform/rain_bridge.h"'),
            ('  if (!c || !data || len == 0) return;', '  if (!c || !data || len == 0) return;\n  wyrm_rain_capture(c, data, len);'),
            ('void server_init(tenv* env) {', 'void server_init(tenv* env) {\n  wyrm_rain_init();'),
            ('void server_poll(tenv* env) {', 'void server_poll(tenv* env) {\n  wyrm_rain_tick(env);'),
        ],
        "app/src/game/input.c": [
            ('#include "../network/arena_protocol.h"', '#include "../network/arena_protocol.h"\n#include "../platform/rain_bridge.h"'),
            ('    bool eyes_back = eb.on && gdata->data.protocol_version >= 5;',
             '    bool rain_rotating = wyrm_rain_rotating();\n    bool eyes_back = eb.on && gdata->data.protocol_version >= 5 && !rain_rotating;'),
            ('    if (!eyes_back && gdata->data.want_e &&', '    if (!eyes_back && !rain_rotating && gdata->data.want_e &&'),
        ],
    }
    for relative, pairs in changes.items():
        file = tree / relative
        text = file.read_text()
        for old, new in pairs:
            if new in text: continue
            if old not in text: raise SystemExit(f"{label}: missing anchor in {relative}: {old}")
            text = text.replace(old, new, 1)
        file.write_text(text)
    print(f"{label}: observer, bounded snapshot and rotation")
