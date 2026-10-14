"""White key default and append-only one-time migration, shared by both engines."""
import sys
from pathlib import Path

PAIRS = {
    "app/src/game/user_settings.h": [
        ("  bool spine_mine[2];\n} user_settings_ext;",
         "  bool spine_mine[2];\n  /* Skip the old tail padding; it must never be read as a setting. */\n  uint8_t reserved_white_alignment[2];\n  /* White keys migration; append only, never account-wide. */\n  bool keys_white_v1;\n} user_settings_ext;")],
    "app/src/game/user_settings.c": [
        ("  x->rain_opacity = 0.90f;", "  x->rain_opacity = 0.90f;\n  x->keys_white_v1 = true;"),
        ("    fixed |= ext_take_bool(&ext->spine_mine[1], written >= mine_at + 2);\n  }",
         "    fixed |= ext_take_bool(&ext->spine_mine[1], written >= mine_at + 2);\n  }\n"
         "  {\n    unsigned char white = 0;\n"
         "    size_t white_at = offsetof(user_settings_ext, keys_white_v1);\n"
         "    if (written >= white_at + 1 && bytes_read >= ext_at + white_at + 1)\n"
         "      memcpy(&white, &ext->keys_white_v1, 1);\n"
         "    if (white != 1) {\n"
         "      memset(ext->key_colour, 0, sizeof(ext->key_colour));\n"
         "      ext->keys_white_v1 = true;\n      fixed = 1;\n    }\n  }")],
    "app/src/mobile/mobile_hotkeys.c": [
        (": arena_theme_colour(ARENA_THEME_INK, 0.48f),", ": color(1.0f, 1.0f, 1.0f, 0.9f),"),
        ("    ImU32 primary = arena_theme_colour(ARENA_THEME_INK, 1.0f);", "    ImU32 primary = color(1.0f, 1.0f, 1.0f, 1.0f);")],
}

def apply(root, label="white keys", skip_applied=False):
    for relative, pairs in PAIRS.items():
        path = Path(root) / relative
        source = path.read_text(encoding="utf-8")
        for old, new in pairs:
            if skip_applied and new in source:
                continue
            if source.count(old) != 1:
                raise SystemExit(f"{label}: anchor x{source.count(old)} in {relative}")
            source = source.replace(old, new)
        path.write_text(source, encoding="utf-8", newline="\n")
    return len(PAIRS)

if __name__ == "__main__":
    print(apply(sys.argv[1], skip_applied=True), "files written")
