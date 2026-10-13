"""Bigger on-screen buttons (OM, 2026-10-13).

One source for both apps (the engine_sync_2026_10_12.py pattern): Wyrm
Android's tree gets these pairs once
(`python engine_key_size_2026_10_13.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree.

An on-screen button's size (Button size, and each key's SIZE in the layout
editor, Eyes Back's too) now reaches 2.5x instead of 1.6x. The smallest stays
0.65x. A file from a newer build read by an older one: the older repairs a
size above 1.6 to the default (nothing else changes).
"""

import sys
from pathlib import Path

KEY_MAX_OLD = "1.60f"
KEY_MAX = "2.50f"

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


pairs("app/src/mobile/mobile_hotkeys.c",
      ("clampf_local(key_scale ? *key_scale : 1.0f, 0.65f, 1.60f);",
       "clampf_local(key_scale ? *key_scale : 1.0f, 0.65f, 2.50f);"))

pairs("app/src/platform/android_settings.c",
      ('{"keys.key_scale", "keys", "Button size", "", SETTING_FLOAT, 0.65f, 1.60f,',
       '{"keys.key_scale", "keys", "Button size", "", SETTING_FLOAT, 0.65f, 2.50f,'),
      ('''    {"layout.key_" #action "_scale", "layout", "", "", SETTING_FLOAT,     \\
     0.65f, 1.60f, NULL, OWNER_SETTINGS,                                      \\''',
       '''    {"layout.key_" #action "_scale", "layout", "", "", SETTING_FLOAT,     \\
     0.65f, 2.50f, NULL, OWNER_SETTINGS,                                      \\'''),
      ('{"layout.key_15_scale", "layout", "", "", SETTING_FLOAT, 0.65f, 1.60f,',
       '{"layout.key_15_scale", "layout", "", "", SETTING_FLOAT, 0.65f, 2.50f,'))

pairs("app/src/game/user_settings.c",
      ('''  fixed |= ext_take_float(&ext->eyes_back_scale, written >= eb_scale_at + 4,
                          0.65f, 1.60f, settings->mobile_hotkeys.key_scale);''',
       '''  fixed |= ext_take_float(&ext->eyes_back_scale, written >= eb_scale_at + 4,
                          0.65f, 2.50f, settings->mobile_hotkeys.key_scale);'''),
      ('''      usr_settings->mobile_hotkeys.key_scale > 1.60f) {''',
       '''      usr_settings->mobile_hotkeys.key_scale > 2.50f) {'''),
      ('''    REPAIR_APPEARANCE(*key_scale, 0.65f, 1.60f,''',
       '''    REPAIR_APPEARANCE(*key_scale, 0.65f, 2.50f,'''))


def apply(root, label="engine key size 2026-10-13", skip_applied=False):
    root = Path(root)
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
