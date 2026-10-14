"""One-time grey key fill, append-only ABI; only fill gains palette option 9."""
import sys
from pathlib import Path
import re

PAIRS = {
    "app/src/game/user_settings.h": [
        ("  bool keys_white_v1;\n} user_settings_ext;",
         "  bool keys_white_v1;\n  /* Skip padding written by 723/724; never interpret it as a flag. */\n  uint8_t reserved_grey_alignment[3];\n  bool keys_grey_fill_v1;\n} user_settings_ext;")],
    "app/src/game/user_settings.c": [
        ("  x->keys_white_v1 = true;", "  x->keys_white_v1 = true;\n  x->keys_grey_fill_v1 = true;\n  for (int i = 0; i < 20; ++i) x->key_fill[i] = 9;"),
        ("ext->key_fill[i] > 8", "ext->key_fill[i] > 9"),
        ("      ext->keys_white_v1 = true;\n      fixed = 1;\n    }\n  }",
         "      ext->keys_white_v1 = true;\n      fixed = 1;\n    }\n  }\n"
         "  {\n    unsigned char grey = 0;\n"
         "    size_t grey_at = offsetof(user_settings_ext, keys_grey_fill_v1);\n"
         "    if (written >= grey_at + 1 && bytes_read >= ext_at + grey_at + 1)\n"
         "      memcpy(&grey, &ext->keys_grey_fill_v1, 1);\n"
         "    if (grey != 1) {\n"
         "      for (int i = 0; i < 20; ++i) ext->key_fill[i] = 9;\n"
         "      ext->keys_grey_fill_v1 = true;\n      fixed = 1;\n    }\n  }")],
    "app/src/mobile/mobile_hotkeys.c": [
        ("  return key_palette(env->usr->usrs.ext.key_fill[action], r, g, b);",
         "  if (env->usr->usrs.ext.key_fill[action] == 9) {\n    *r = *g = *b = 128.0f / 255.0f;\n    return true;\n  }\n  return key_palette(env->usr->usrs.ext.key_fill[action], r, g, b);")],
}

def apply(root, label="grey fill", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root)/relative
        text = path.read_text(encoding="utf-8")
        for old, new in pairs:
            if skip_applied and new in text: continue
            if text.count(old) != 1: raise SystemExit(f"{label}: anchor x{text.count(old)} {relative}")
            text = text.replace(old,new)
        path.write_text(text,encoding="utf-8",newline="\n")
    path = Path(root)/"app/src/platform/android_settings.c"
    text = path.read_text(encoding="utf-8")
    text, n = re.subn(r'("layout\.key_\d+_fill", "layout", "", "", SETTING_INT, 0, )8', r'\g<1>9',text)
    if n != 11 and not (skip_applied and len(re.findall(r'"layout\.key_\d+_fill", "layout", "", "", SETTING_INT, 0, 9',text))==11):
        raise SystemExit(f"{label}: expected 11 fill settings, got {n}")
    path.write_text(text,encoding="utf-8",newline="\n")

if __name__ == "__main__": apply(sys.argv[1],skip_applied=True)
