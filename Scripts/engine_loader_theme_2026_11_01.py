"""The screen after Play (OM, 2026-11-01): the loader and its Back to lobby
button in the player's theme on phones too (Paper, dark and the colour themes,
arena_theme_set), as Wyrm Desktop already had. Same text on Wyrm Android's
tree (run once) and the prepared Apple tree (prepare-original-engine.py).
"""
from pathlib import Path
import sys

PAIRS = {'app/src/game/loop.c': [
    ('#include "loop.h"\n', '#include "loop.h"\n#include "arena_theme.h"\n'),
    ('  const ImU32 paper = igColorConvertFloat4ToU32((ImVec4){0.969f, 0.965f, 0.953f, 1});\n'
     '  const ImU32 ink = igColorConvertFloat4ToU32((ImVec4){0.216f, 0.208f, 0.184f, 1});\n'
     '  const ImU32 rule = igColorConvertFloat4ToU32((ImVec4){0.216f, 0.208f, 0.184f, .08f});\n'
     '  const ImU32 faint = igColorConvertFloat4ToU32((ImVec4){0.471f, 0.467f, 0.455f, 1});\n',
     '  /* The player\'s theme on phones too (OM, 2026-11-01). */\n'
     '  const ImU32 paper = arena_theme_colour(ARENA_THEME_PAPER, 1);\n'
     '  const ImU32 ink = arena_theme_colour(ARENA_THEME_INK, 1);\n'
     '  const ImU32 rule = arena_theme_colour(ARENA_THEME_RULE, 1);\n'
     '  const ImU32 faint = arena_theme_colour(ARENA_THEME_QUIET, 1);\n'),
    ('  const ImU32 dim = igColorConvertFloat4ToU32((ImVec4){0.216f, 0.208f, 0.184f, 0.20f});\n',
     '  const ImU32 dim = arena_theme_colour(ARENA_THEME_INK, 0.20f);\n'),
    ('  igPushStyleColor_Vec4(ImGuiCol_Text, (ImVec4){.216f, .208f, .184f, 1});\n'
     '  igPushStyleColor_Vec4(ImGuiCol_Button, (ImVec4){1, 1, 1, 1});\n'
     '  igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, (ImVec4){.941f, .933f, .914f, 1});\n'
     '  igPushStyleColor_Vec4(ImGuiCol_ButtonActive, (ImVec4){.910f, .898f, .871f, 1});\n'
     '  igPushStyleColor_Vec4(ImGuiCol_Border, (ImVec4){.216f, .208f, .184f, .10f});\n',
     '  /* The player\'s theme on phones too (OM, 2026-11-01). */\n'
     '  ImVec4 card, well, track, ink, rule;\n'
     '  igColorConvertU32ToFloat4(&card, arena_theme_colour(ARENA_THEME_CARD, 1));\n'
     '  igColorConvertU32ToFloat4(&well, arena_theme_colour(ARENA_THEME_WELL, 1));\n'
     '  igColorConvertU32ToFloat4(&track, arena_theme_colour(ARENA_THEME_TRACK, 1));\n'
     '  igColorConvertU32ToFloat4(&ink, arena_theme_colour(ARENA_THEME_INK, 1));\n'
     '  igColorConvertU32ToFloat4(&rule, arena_theme_colour(ARENA_THEME_RULE, 1));\n'
     '  igPushStyleColor_Vec4(ImGuiCol_Text, ink);\n'
     '  igPushStyleColor_Vec4(ImGuiCol_Button, card);\n'
     '  igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, well);\n'
     '  igPushStyleColor_Vec4(ImGuiCol_ButtonActive, track);\n'
     '  igPushStyleColor_Vec4(ImGuiCol_Border, rule);\n'),
]}


def apply(root, label='engine loader theme 2026-11-01', dry=False):
    edits = 0
    for file, pairs in PAIRS.items():
        path = Path(root) / file
        raw = path.read_bytes().decode('utf-8')
        crlf = '\r\n' in raw
        text = raw.replace('\r\n', '\n')
        for old, new in pairs:
            if text.count(old) != 1:
                raise SystemExit(f'{label}: {file}: {text.count(old)} anchors: {old[:70]!r}')
            if old in new and new in text:
                raise SystemExit(f'{label}: {file}: already applied')
            text = text.replace(old, new, 1)
            edits += 1
        if not dry:
            path.write_bytes((text.replace('\n', '\r\n') if crlf else text).encode('utf-8'))
    print(f'{label}: {edits} edits{" (dry run)" if dry else ""}')


if __name__ == '__main__':
    apply(sys.argv[1], dry='--dry' in sys.argv)
