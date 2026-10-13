"""Wyrm skins (OM, 2026-10-13).

One source for both apps (the engine_sync_2026_10_12.py pattern): Wyrm
Android's tree gets these pairs once
(`python engine_wyrm_skins_2026_10_13.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree.
The drawing itself is game/wyrm_skins.c/.h, the same file in Wyrm Android's
tree and in SharedEngine (hash in SharedEngine/SHA256.json).

23 creatures and 15 strip looks, drawn over a snake instead of its beads,
eyes and boost glow. The worn skin is `ext.wyrm_skin` (user.dat ext block,
appended after `arena`; settings row `skin.wyrm`). It travels in the join's
skin-block corner, where tags go:
    254, 86 ('V'), preset or 255, 0, 0, 0, n, n ^ 0x5C
so it takes the tag's place (no tag and no accessory are sent with it). A
creature goes out as its nearest preset; a strip look keeps the player's own
skin. Every other reader takes kind 86 as "no tag" and shows the preset.
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


pairs("app/src/game/snake.h",
      ("  int skin_tag;\n  bool local_player;\n",
       "  int skin_tag;\n"
       "  /* The Wyrm skin in this snake's corner (game/wyrm_skins.h), 0 for none;\n"
       "     and where its eyes look, eased (NAN until the first frame). */\n"
       "  int wyrm_skin;\n"
       "  float wyrm_skin_look;\n"
       "  bool local_player;\n"))

pairs("app/src/game/user_settings.h",
      ("""  char arena[MAX_ARENA_LEN + 1];
} user_settings_ext;
""", """  char arena[MAX_ARENA_LEN + 1];
  /* Wyrm skin (OM, 2026-10-13): a creature or strip look worn over the snake
     (game/wyrm_skins.h), 0 for none. Phones: offset 108; Wyrm Desktop: 112.
     Read through user_settings_wyrm_skin. */
  int32_t wyrm_skin;
} user_settings_ext;
"""),
      ("""const char* user_settings_arena(const user_settings* settings);
""", """const char* user_settings_arena(const user_settings* settings);
/* The Wyrm skin worn, or 0 (an unknown number reads as none). */
int user_settings_wyrm_skin(const user_settings* settings);
"""))

pairs("app/src/game/user_settings.c",
      ("""#include "../mobile/mobile_hotkeys.h"
""", """#include "../mobile/mobile_hotkeys.h"
#include "wyrm_skins.h"
"""),
      ("""#ifdef WYRM_DESKTOP
_Static_assert(offsetof(user_settings_ext, arena) == 48,
               "Wyrm Desktop's ext.arena moved");
#else
_Static_assert(offsetof(user_settings_ext, arena) == 44,
               "the phones' ext.arena moved");
#endif
""", """#ifdef WYRM_DESKTOP
_Static_assert(offsetof(user_settings_ext, arena) == 48,
               "Wyrm Desktop's ext.arena moved");
_Static_assert(offsetof(user_settings_ext, wyrm_skin) == 112,
               "Wyrm Desktop's ext.wyrm_skin moved");
#else
_Static_assert(offsetof(user_settings_ext, arena) == 44,
               "the phones' ext.arena moved");
_Static_assert(offsetof(user_settings_ext, wyrm_skin) == 108,
               "the phones' ext.wyrm_skin moved");
#endif

int user_settings_wyrm_skin(const user_settings* settings) {
  int skin = settings->ext.wyrm_skin;
  return wyrm_skin_valid(skin) ? skin : 0;
}
"""),
      ("""      memset(ext->arena, 0, sizeof(ext->arena));
  }
""", """      memset(ext->arena, 0, sizeof(ext->arena));
  }
  {
    /* The Wyrm skin (OM, 2026-10-13). A file without it, or with a number
       this build does not know, wears none. */
    size_t skin_at = offsetof(user_settings_ext, wyrm_skin);
    if (written < skin_at + 4 ||
        (ext->wyrm_skin != 0 && !wyrm_skin_valid(ext->wyrm_skin))) {
      ext->wyrm_skin = 0;
      fixed = 1;
    }
  }
"""))

pairs("app/src/platform/android_settings.c",
      ("""     SETTINGS_FIELD(ext.assist_hide_cosmetics)},
""", """     SETTINGS_FIELD(ext.assist_hide_cosmetics)},
    /* Wyrm skin (OM, 2026-10-13): set from the Skin tab, never listed. */
    {"skin.wyrm", "skin", "Wyrm skin",
     "A creature or strip look drawn over your snake. 0 is none.",
     SETTING_INT, 0, 255, NULL, OWNER_SETTINGS, SETTINGS_FIELD(ext.wyrm_skin)},
"""))

pairs("app/src/network/callback.c",
      ("""#include "../game/tags.h"
""", """#include "../game/tags.h"
#include "../game/wyrm_skins.h"
"""),
      ("""    uint8_t tag_mark = 0, tag_kind = 0, tag_byte = 0;
    int worn_ntl = tags_valid(usrs->tag_index) ? tags_ntl_id(usrs->tag_index) : -1;
""", """    /* A Wyrm skin (OM, 2026-10-13, game/wyrm_skins.h) takes the tag's place
       in the corner, so no tag goes with it. A creature goes out as its
       nearest preset (never a custom block); a strip look keeps the
       player's own skin. */
    int worn_skin = web_persona ? user_settings_wyrm_skin(usrs) : 0;
    int join_preset = wyrm_skin_preset(worn_skin) >= 0 ? wyrm_skin_preset(worn_skin)
                                                       : usrs->default_skin;
    if (wyrm_skin_preset(worn_skin) >= 0 && skin_compressed) {
      tdarray_destroy(skin_compressed);
      skin_compressed = NULL;
      skin_compressed_len = 0;
    }
    uint8_t tag_mark = 0, tag_kind = 0, tag_byte = 0;
    int worn_ntl = !worn_skin && tags_valid(usrs->tag_index) ? tags_ntl_id(usrs->tag_index) : -1;
"""),
      ("""    int worn_wyrm = tags_valid(usrs->tag_index) ? tags_wyrm_id(usrs->tag_index) : -1;
""", """    int worn_wyrm = !worn_skin && tags_valid(usrs->tag_index) ? tags_wyrm_id(usrs->tag_index) : -1;
"""),
      ("""      tag_corner = true;
      wyrm_corner = true;
    }
    bool preset_block = false;
    if (tag_corner && !skin_compressed &&
        (wyrm_corner || usrs->default_skin >= NTL_PRESET_COUNT ||
         !ntl_preset_wears(usrs->default_skin, worn_ntl))) {
      int preset = usrs->default_skin % NTL_PRESET_COUNT;
""", """      tag_corner = true;
      wyrm_corner = true;
    }
    bool skin_corner = false;
    if (worn_skin) {
      tag_mark = WYRM_SKIN_MARK;
      tag_kind = WYRM_SKIN_KIND;
      tag_byte = (uint8_t)worn_skin;
      tag_corner = true;
      skin_corner = true;
    }
    bool preset_block = false;
    if (tag_corner && !skin_compressed &&
        (wyrm_corner || skin_corner || join_preset >= NTL_PRESET_COUNT ||
         !ntl_preset_wears(join_preset, worn_ntl))) {
      int preset = join_preset % NTL_PRESET_COUNT;
"""),
      ("""    ba[24] = usrs->default_skin;
""", """    ba[24] = (uint8_t)join_preset;
"""),
      ("""    ba[m] = usrs->accessory;
""", """    ba[m] = worn_skin ? NO_ACCESSORY : usrs->accessory;
"""),
      ("""        ba[corner + 2] = preset_block ? usrs->default_skin : 255;
        ba[corner + 6] = tag_byte;
        ba[corner + 7] = wyrm_corner ? (uint8_t)(tag_byte ^ WYRM_TAG_CHECK) : 0;
        SDL_Log("Wyrm arena: %s tag %d in the skin corner (%s block, %d run bytes)",
                wyrm_corner ? "Wyrm" : "NTL", wyrm_corner ? worn_wyrm : worn_ntl,
""", """        ba[corner + 2] = preset_block ? (uint8_t)join_preset : 255;
        ba[corner + 6] = tag_byte;
        ba[corner + 7] = skin_corner   ? (uint8_t)(tag_byte ^ WYRM_SKIN_CHECK)
                         : wyrm_corner ? (uint8_t)(tag_byte ^ WYRM_TAG_CHECK)
                                       : 0;
        SDL_Log("Wyrm arena: %s %d in the skin corner (%s block, %d run bytes)",
                skin_corner ? "Wyrm skin" : wyrm_corner ? "Wyrm tag" : "NTL tag",
                skin_corner ? worn_skin : wyrm_corner ? worn_wyrm : worn_ntl,
"""),
      ("""      int corner_preset = -1;
      if (skl >= 8 && m + 8 <= alen) {
        corner_tag = ntl_tag_from_corner(a + m);
        corner_wyrm = wyrm_tag_from_corner(a + m);
        if ((a[m + 1] == NTL_TAG_FREE_KIND || a[m + 1] == NTL_TAG_PUBLIC_KIND ||
             corner_wyrm >= 0) &&
""", """      int corner_preset = -1;
      int corner_skin = 0;
      if (skl >= 8 && m + 8 <= alen) {
        corner_tag = ntl_tag_from_corner(a + m);
        corner_wyrm = wyrm_tag_from_corner(a + m);
        corner_skin = wyrm_skin_from_corner(a + m);
        if ((a[m + 1] == NTL_TAG_FREE_KIND || a[m + 1] == NTL_TAG_PUBLIC_KIND ||
             corner_wyrm >= 0 || corner_skin > 0) &&
"""),
      ("""                   : corner_tag >= 0 ? tags_from_ntl_id(corner_tag) + 1
                                     : 0;
""", """                   : corner_tag >= 0 ? tags_from_ntl_id(corner_tag) + 1
                                     : 0;
      o.wyrm_skin = corner_skin;
      o.wyrm_skin_look = NAN;
"""))

pairs("app/src/game/redraw.c",
      ("""#include "studio.h"
""", """#include "studio.h"
#include "wyrm_skins.h"
"""),
      ("""        if (rope_mode) draw_rope_backbone(env, o, bp, mww2, mhh2, a);

        if (!rope_mode) {
""", """        if (rope_mode) draw_rope_backbone(env, o, bp, mww2, mhh2, a);

        /* Wyrm skins (OM, 2026-10-13, wyrm_skins.c): a creature or strip look
           takes the place of the beads, eyes, boost glow, tag and accessory.
           Yours from your setting, everyone else's from their corner. */
        const int wyrm_skin =
            rope_mode ? 0
            : o->id == gdata->data.snake_id ? user_settings_wyrm_skin(usrs)
                                            : o->wyrm_skin;
        if (wyrm_skin) {
          float skin_r, skin_g, skin_b;
          snake_strip_colour(env, o, &skin_r, &skin_g, &skin_b);
          wyrm_skin_draw(wyrm_skin, gdata->data.pbx, gdata->data.pby,
                         gdata->data.pbu, bp, gdata->data.view_xx,
                         gdata->data.view_yy, gdata->data.gsc, mww2, mhh2, lsz,
                         fang, o->wang, &o->wyrm_skin_look, o->tsp > o->fsp,
                         o->alive_amt * (1 - o->dead_amt), skin_r, skin_g,
                         skin_b);
        } else if (!rope_mode) {
"""))


def apply(root, label="engine wyrm skins 2026-10-13", skip_applied=False):
    root = Path(root)
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        crlf = "\r\n" in text
        for old, new in items:
            if crlf:
                old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
            if skip_applied and new in text:
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
