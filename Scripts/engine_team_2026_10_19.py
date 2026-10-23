"""Roster rendering fixes, applied to the generated Apple engine too."""
from pathlib import Path


def apply(root: Path):
    path = root / 'app/src/game/redraw.c'
    text = path.read_text(encoding='utf-8')
    anchor = '            wyrm_name_inks(name_floor_luma, *scolor, a, &name_ink, &name_shadow);'
    addition = '''
            if (o->id != gdata->data.snake_id &&
                android_team_is_teammate(env, o->ntl_id, o->nk)) {
              name_ink = igColorConvertFloat4ToU32((ImVec4){0.224f, 1.0f, 0.353f, a});
              name_shadow = igColorConvertFloat4ToU32((ImVec4){0, 0, 0, 0.9f * a});
            }'''
    if addition not in text:
        assert anchor in text, 'name batch anchor moved'
        text = text.replace(anchor, anchor + addition, 1)
    # A snapshot precedes name drawing, even when the HUD is hidden.
    anchor = 'void redraw(tenv* env) {'
    added = '\n  android_team_begin_frame();'
    if anchor + added not in text:
        assert anchor in text
        text = text.replace(anchor, anchor + added, 1)
    if '#include "../platform/android_team.h"' not in text:
        text = text.replace('#include "redraw.h"', '#include "redraw.h"\n#include "../platform/android_team.h"', 1)
    path.write_text(text, encoding='utf-8')
