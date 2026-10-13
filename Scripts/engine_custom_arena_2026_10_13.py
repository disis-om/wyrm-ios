"""Custom arena id (OM, 2026-10-13). PACKET ADDITION asked for by OM.

One source for both apps (the engine_sync_2026_10_12.py pattern): Wyrm
Android's tree gets these pairs once
(`python engine_custom_arena_2026_10_13.py "<Wyrm Android>"`), and
prepare-original-engine.py applies the same pairs to the generated iOS tree.

Community-run arenas know a player by an id that NTL 9.68 sends
(legacy/ntl 9.68/main-mt.js, `j3`, run on the challenge packet '6'):
  - the id: 16 characters of [0-9A-Za-z], made once (crypto random, the
    62-letter alphabet, bytes >= 248 thrown away) and kept;
  - the packet: 'C' (0x43) + the 16 id bytes, 17 bytes, sent right after the
    challenge answer and before the join;
  - only to the arenas on NTL's list
    (`https://ntl-slither.com/slither/useplayerid.php?v=<version>` answers
    `{"v":N,"d":["ip:port",...]}`; official arenas are not on it), compared as
    "ip:port" in lower case.
The apps make and keep the id (account, shared key `customArenaId`), fetch
the list and hand both over with `custom_arenas_set` (Android JNI
`WyrmActivity.nativeSetCustomArenas`, iOS `WyrmIOSSetCustomArenas`). Revert: drop these
pairs (Android: delete the two blocks from network/callback.c).
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


CUSTOM_ARENA_BLOCK = r'''/*
 * Custom arenas (OM, 2026-10-13): the id community-run arenas know a player
 * by, sent the way NTL 9.68 sends it (main-mt.js `j3`): 'C' (0x43) + 16
 * characters of [0-9A-Za-z], right after the challenge answer and before the
 * join, only to the arenas on the list the apps fetch
 * (ntl-slither.com/slither/useplayerid.php; official arenas are not on it),
 * compared as "ip:port" in lower case. Set by the apps from any thread
 * (Android JNI WyrmActivity.nativeSetCustomArenas, iOS
 * WyrmIOSSetCustomArenas).
 */
#include <ctype.h>
#include <string.h>
#define CUSTOM_ARENA_ID_LEN 16
#define CUSTOM_ARENA_LIST_MAX 8192
static SDL_SpinLock custom_arena_lock;
static char custom_arena_id[CUSTOM_ARENA_ID_LEN + 1];
static char custom_arena_list[CUSTOM_ARENA_LIST_MAX]; /* lines, lower case */

/* `id`: 16 of [0-9A-Za-z], anything else turns the packet off. `list`: one
   "ip:port" a line. */
void custom_arenas_set(const char* id, const char* list) {
  char next_id[CUSTOM_ARENA_ID_LEN + 1] = {0};
  bool ok = id && strlen(id) == CUSTOM_ARENA_ID_LEN;
  for (int i = 0; ok && i < CUSTOM_ARENA_ID_LEN; i++) {
    char ch = id[i];
    ok = (ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'Z') ||
         (ch >= 'a' && ch <= 'z');
  }
  if (ok) memcpy(next_id, id, CUSTOM_ARENA_ID_LEN);
  SDL_LockSpinlock(&custom_arena_lock);
  memcpy(custom_arena_id, next_id, sizeof(next_id));
  size_t n = 0;
  if (list) {
    for (const char* p = list; *p && n + 1 < sizeof(custom_arena_list); p++)
      custom_arena_list[n++] = (char)tolower((unsigned char)*p);
  }
  custom_arena_list[n] = 0;
  SDL_UnlockSpinlock(&custom_arena_lock);
}

/* True, with the packet in `out`, when `arena` is on the list. */
static bool custom_arena_id_packet(const char* arena,
                                   uint8_t out[1 + CUSTOM_ARENA_ID_LEN]) {
  bool found = false;
  size_t len = arena ? strlen(arena) : 0;
  if (len == 0) return false;
  SDL_LockSpinlock(&custom_arena_lock);
  if (custom_arena_id[0]) {
    const char* line = custom_arena_list;
    while (*line && !found) {
      const char* end = strchr(line, '\n');
      size_t n = end ? (size_t)(end - line) : strlen(line);
      if (n == len) {
        found = true;
        for (size_t i = 0; i < n; i++) {
          if (line[i] != (char)tolower((unsigned char)arena[i])) {
            found = false;
            break;
          }
        }
      }
      line = end ? end + 1 : line + n;
    }
    if (found) {
      out[0] = 'C';
      memcpy(out + 1, custom_arena_id, CUSTOM_ARENA_ID_LEN);
    }
  }
  SDL_UnlockSpinlock(&custom_arena_lock);
  return found;
}

#ifdef WYRM_SDL_JNI
#include <jni.h>
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetCustomArenas(JNIEnv* jenv,
                                                          jclass clazz,
                                                          jstring id,
                                                          jstring list) {
  (void)clazz;
  const char* id_utf = id ? (*jenv)->GetStringUTFChars(jenv, id, NULL) : NULL;
  const char* list_utf =
      list ? (*jenv)->GetStringUTFChars(jenv, list, NULL) : NULL;
  custom_arenas_set(id_utf, list_utf);
  if (id_utf) (*jenv)->ReleaseStringUTFChars(jenv, id, id_utf);
  if (list_utf) (*jenv)->ReleaseStringUTFChars(jenv, list, list_utf);
}
#endif

void snl(game_data* gdata, snake* o) {
'''

ANSWER_OLD = '''      SDL_Log("Wyrm arena: web challenge answer 0x%02X..0x%02X (decoded packet)",
              answer[0], answer[26]);
    }
'''

ANSWER_NEW = ANSWER_OLD + '''
    /* Custom arenas (OM, 2026-10-13): NTL's id packet, between the answer
       and the join, only to an arena on the list. */
    {
      uint8_t id_packet[1 + CUSTOM_ARENA_ID_LEN];
      if (custom_arena_id_packet(user_settings_arena(usrs), id_packet)) {
        arena_send(c, id_packet, sizeof(id_packet));
        SDL_Log("Wyrm arena: custom arena id sent to %s",
                user_settings_arena(usrs));
      }
    }
'''

pairs("app/src/network/callback.c",
      ("void snl(game_data* gdata, snake* o) {\n", CUSTOM_ARENA_BLOCK),
      (ANSWER_OLD, ANSWER_NEW))


def apply(root, label="engine custom arena 2026-10-13", skip_applied=False):
    root = Path(root)
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        for old, new in items:
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
