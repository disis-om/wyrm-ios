"""Arena chat tabs (OM, 2026-10-14).

The arena's chat window (team chat) gets three tabs at its top:
  TEAM   - the team chat, as before;
  GLOBAL - Wyrm's global chat, live (the app pushes it, sends to it);
  ONLINE - players seen on Wyrm in the last minutes: in-game name, then
           "@username - server" (the app pushes it; nothing says "5 minutes").
The window now shows in every online match, team or not. The ONLINE rows take
two colours of their own from the layout editor (teamhud online_name /
online_data, appended to the style list); the app can show a tab (editor
preview) and asks which tab the message box was tapped on.

One source for both apps: Wyrm Android's tree gets these pairs once
(`python engine_chat_tabs_2026_10_14.py "<Wyrm Android>"`), and
prepare-original-engine.py applies them to the generated iOS tree. Pairs
marked "android" / "ios" only exist in that tree.
"""

import sys
from pathlib import Path

PAIRS = {}


def pairs(relative, *items):
    PAIRS.setdefault(relative, []).extend(items)


F = "app/src/platform/android_team.c"

pairs(F,
      # styles: two ONLINE colours appended
      ("""  STYLE_LB_HEIGHT,   /* its row height, x its own; 1.75+ = two-line names */
  STYLE_COUNT""",
       """  STYLE_LB_HEIGHT,   /* its row height, x its own; 1.75+ = two-line names */
  STYLE_ONLINE_NAME, /* ONLINE tab names, 0 = theme (OM, 2026-10-14) */
  STYLE_ONLINE_DATA, /* ONLINE tab "@username - server" line, 0 = theme */
  STYLE_COUNT"""),
      ("""                                       1.0f,   0.0f,   1.0f, 1.0f};""",
       """                                       1.0f,   0.0f,   1.0f, 1.0f,
                                       0.0f,   0.0f};"""),
      # state
      ("""static long seen_chat_total = -1;
""", """static long seen_chat_total = -1;

/* Chat tabs (OM, 2026-10-14): TEAM, GLOBAL (Wyrm's global chat, pushed by the
   app) and ONLINE (players seen in the last minutes and their server). */
enum { CHAT_TAB_TEAM, CHAT_TAB_GLOBAL, CHAT_TAB_ONLINE, CHAT_TAB_COUNT };
static int chat_tab = CHAT_TAB_TEAM;
static team_chat_line global_lines[TEAM_CHAT_MAX];
static int global_line_count = 0;
static long global_total = 0;
static unsigned global_revision = 0;
static team_chat_line frame_global[TEAM_CHAT_MAX];
static int frame_global_count = 0;
static long frame_global_total = 0;
static unsigned frame_global_revision = 0;
static long seen_global_total = -1;
#define ONLINE_MAX 120
typedef struct online_row {
  char name[48];
  char data[112];
} online_row;
static online_row online_rows[ONLINE_MAX];
static int online_count = 0;
static unsigned online_revision = 0;
static online_row frame_online[ONLINE_MAX];
static int frame_online_count = 0;
static unsigned frame_online_revision = 0;
static float chat_tab_rect[CHAT_TAB_COUNT][4];
"""),
      # setters, before the frame snapshot
      ("""static void snapshot_chat(void) {""",
       """/* Wyrm's global chat, packed as android_team_set_chat reads it: the total,
   then one `author<TAB>body` line per message, oldest first. */
void android_team_set_global_chat(const char* packed) {
  if (!team_mutex || !packed) return;
  SDL_LockMutex(team_mutex);
  global_line_count = 0;
  global_total = strtol(packed, NULL, 10);
  const char* line = strchr(packed, '\\n');
  line = line ? line + 1 : "";
  int total_lines = 0;
  for (const char* p = line; *p;) {
    const char* e = strchr(p, '\\n');
    total_lines++;
    if (!e) break;
    p = e + 1;
  }
  int skip = total_lines > TEAM_CHAT_MAX ? total_lines - TEAM_CHAT_MAX : 0;
  while (*line && global_line_count < TEAM_CHAT_MAX) {
    const char* end = strchr(line, '\\n');
    size_t length = end ? (size_t)(end - line) : strlen(line);
    if (skip > 0) {
      skip--;
    } else {
      const char* tab = memchr(line, '\\t', length);
      team_chat_line* out = global_lines + global_line_count;
      size_t a = tab ? (size_t)(tab - line) : 0;
      if (a >= sizeof(out->author)) a = sizeof(out->author) - 1;
      memcpy(out->author, line, a);
      out->author[a] = '\\0';
      const char* body = tab ? tab + 1 : line;
      size_t b = length - (size_t)(body - line);
      if (b >= sizeof(out->body)) b = sizeof(out->body) - 1;
      memcpy(out->body, body, b);
      out->body[b] = '\\0';
      global_line_count++;
    }
    line = end ? end + 1 : "";
  }
  global_revision++;
  SDL_UnlockMutex(team_mutex);
}

/* Players online: one `name<TAB>data` line each (data = "@username - server"). */
void android_team_set_online(const char* packed) {
  if (!team_mutex || !packed) return;
  SDL_LockMutex(team_mutex);
  online_count = 0;
  const char* line = packed;
  while (*line && online_count < ONLINE_MAX) {
    const char* end = strchr(line, '\\n');
    size_t length = end ? (size_t)(end - line) : strlen(line);
    if (length > 0) {
      const char* tab = memchr(line, '\\t', length);
      online_row* out = online_rows + online_count;
      size_t a = tab ? (size_t)(tab - line) : length;
      if (a >= sizeof(out->name)) a = sizeof(out->name) - 1;
      memcpy(out->name, line, a);
      out->name[a] = '\\0';
      out->data[0] = '\\0';
      if (tab) {
        size_t b = length - (size_t)(tab + 1 - line);
        if (b >= sizeof(out->data)) b = sizeof(out->data) - 1;
        memcpy(out->data, tab + 1, b);
        out->data[b] = '\\0';
      }
      online_count++;
    }
    line = end ? end + 1 : "";
  }
  online_revision++;
  SDL_UnlockMutex(team_mutex);
}

/* Which tab the window shows: where the message box sends (0 team, 1 global,
   2 online). The app sets it to preview the ONLINE colours in the editor. */
int android_team_chat_tab(void) { return chat_tab; }
void android_team_set_chat_tab(int tab) {
  if (tab >= 0 && tab < CHAT_TAB_COUNT && tab != chat_tab) {
    chat_tab = tab;
    chat_scroll = 0.0f;
  }
}

static void snapshot_chat(void) {"""),
      ("""    memcpy(frame_chat, chat_lines,
           sizeof(team_chat_line) * (size_t)chat_line_count);
  }
  SDL_UnlockMutex(team_mutex);""",
       """    memcpy(frame_chat, chat_lines,
           sizeof(team_chat_line) * (size_t)chat_line_count);
  }
  if (global_revision != frame_global_revision) {
    frame_global_revision = global_revision;
    frame_global_count = global_line_count;
    frame_global_total = global_total;
    memcpy(frame_global, global_lines,
           sizeof(team_chat_line) * (size_t)global_line_count);
  }
  if (online_revision != frame_online_revision) {
    frame_online_revision = online_revision;
    frame_online_count = online_count;
    memcpy(frame_online, online_rows, sizeof(online_row) * (size_t)online_count);
  }
  SDL_UnlockMutex(team_mutex);"""),
      # the row a tab shows
      ("""void android_team_draw_chat_button(tenv* env) {
  /* The chat window (OM, 2026-10-04)""",
       """/* Row i of the shown tab (the editor's placeholder rows when previewing). */
static void chat_row(int i, bool preview, const char** author, const char** body) {
  static const char* chat_sample[][2] = {{"Player name", "Message"},
                                         {"Player name", "Message"},
                                         {"Key name", "Message"},
                                         {"Player name", "Message"}};
  static const char* online_sample[][2] = {{"In-game name", "@username - Server"},
                                           {"In-game name", "@username - Server"},
                                           {"In-game name", "@username - Server"},
                                           {"In-game name", "@username - Server"}};
  if (preview) {
    const char* (*s)[2] = chat_tab == CHAT_TAB_ONLINE ? online_sample : chat_sample;
    *author = s[i][0];
    *body = s[i][1];
    return;
  }
  if (chat_tab == CHAT_TAB_ONLINE) {
    *author = frame_online[i].name;
    *body = frame_online[i].data;
    return;
  }
  const team_chat_line* src = chat_tab == CHAT_TAB_GLOBAL ? frame_global : frame_chat;
  *author = src[i].author;
  *body = src[i].body;
}

void android_team_draw_chat_button(tenv* env) {
  /* The chat window (OM, 2026-10-04)"""),
      ("""  chat_button[2] = 0.0f;
  chat_button[3] = 0.0f;
  if (!env || ai_mode_editor_bare()) return;""",
       """  chat_button[2] = 0.0f;
  chat_button[3] = 0.0f;
  memset(chat_tab_rect, 0, sizeof(chat_tab_rect));
  if (!env || ai_mode_editor_bare()) return;"""),
      ("""    /* No team, no chat to show. */
    if (frame_member_count <= 0 && frame_chat_count <= 0) return;
""", """    /* Every online match (OM, 2026-10-14): GLOBAL and ONLINE need no team. */
"""),
      ("""  long unread = 0;
  if (openness > 0.5f)
    seen_chat_total = frame_chat_total;
  else if (seen_chat_total >= 0 && frame_chat_total > seen_chat_total)
    unread = frame_chat_total - seen_chat_total;
  if (seen_chat_total < 0) seen_chat_total = frame_chat_total;

  const char* label = "TEAM CHAT";""",
       """  long unread = 0;
  if (openness > 0.5f) {
    seen_chat_total = frame_chat_total;
    seen_global_total = frame_global_total;
  } else {
    if (seen_chat_total >= 0 && frame_chat_total > seen_chat_total)
      unread += frame_chat_total - seen_chat_total;
    if (seen_global_total >= 0 && frame_global_total > seen_global_total)
      unread += frame_global_total - seen_global_total;
  }
  if (seen_chat_total < 0) seen_chat_total = frame_chat_total;
  if (seen_global_total < 0) seen_global_total = frame_global_total;

  const char* label = "CHAT";
  bool online = chat_tab == CHAT_TAB_ONLINE;"""),
      ("""    /* Header rule and the fold mark stay with the text, not the plate. */
    ImDrawList_AddText_FontPtr(
        draw, bold, label_size,
        (ImVec2){left + pad, top + (header_h - label_size) * 0.5f},
        arena_theme_colour(ARENA_THEME_QUIET, body_alpha), "TEAM CHAT", NULL,
        0.0f, NULL);""",
       """    /* The tabs (OM, 2026-10-14): the shown one in ink, underlined. A header
       tap outside them still folds the window. */
    static const char* tab_names[CHAT_TAB_COUNT] = {"TEAM", "GLOBAL", "ONLINE"};
    float tab_x = left + pad;
    for (int t = 0; t < CHAT_TAB_COUNT; ++t) {
      float tw = hud_text_width(bold, label_size, tab_names[t], NULL);
      bool shown = t == chat_tab;
      ImDrawList_AddText_FontPtr(
          draw, bold, label_size,
          (ImVec2){tab_x, top + (header_h - label_size) * 0.5f},
          arena_theme_colour(shown ? ARENA_THEME_INK : ARENA_THEME_QUIET,
                             body_alpha),
          tab_names[t], NULL, 0.0f, NULL);
      if (shown)
        ImDrawList_AddLine(
            draw, (ImVec2){tab_x, top + header_h - 3.0f * scale},
            (ImVec2){tab_x + tw, top + header_h - 3.0f * scale},
            arena_theme_colour(ARENA_THEME_INK, body_alpha), 2.0f * scale);
      chat_tab_rect[t][0] = tab_x - 6.0f * scale;
      chat_tab_rect[t][1] = top;
      chat_tab_rect[t][2] = tw + 12.0f * scale;
      chat_tab_rect[t][3] = header_h;
      tab_x += tw + 18.0f * scale;
    }"""),
      ("""    ImDrawList_AddRectFilled(
        draw, input_min, input_max,
        arena_theme_colour(ARENA_THEME_WELL, 0.9f * body_alpha), 999.0f, 0);
    ImDrawList_AddText_FontPtr(
        draw, regular, text_size,
        (ImVec2){input_min.x + pad,
                 input_min.y + (input_h - text_size) * 0.5f},
        arena_theme_colour(ARENA_THEME_QUIET, body_alpha), "Message", NULL,
        0.0f, NULL);""",
       """    /* ONLINE is a list only: no message box. */
    if (!online) {
      ImDrawList_AddRectFilled(
          draw, input_min, input_max,
          arena_theme_colour(ARENA_THEME_WELL, 0.9f * body_alpha), 999.0f, 0);
      ImDrawList_AddText_FontPtr(
          draw, regular, text_size,
          (ImVec2){input_min.x + pad,
                   input_min.y + (input_h - text_size) * 0.5f},
          arena_theme_colour(ARENA_THEME_QUIET, body_alpha),
          chat_tab == CHAT_TAB_GLOBAL ? "Message everyone" : "Message", NULL,
          0.0f, NULL);
    }"""),
      ("""    float list_bottom = input_min.y - 6.0f * scale;""",
       """    float list_bottom =
        online ? top + vis_h - pad * 0.6f : input_min.y - 6.0f * scale;"""),
      ("""    static const char* sample[][2] = {{"Player name", "Message"},
                                      {"Player name", "Message"},
                                      {"Key name", "Message"},
                                      {"Player name", "Message"}};
    int lines = preview ? 4 : frame_chat_count;""",
       """    int lines = preview ? 4
                : online ? frame_online_count
                : chat_tab == CHAT_TAB_GLOBAL ? frame_global_count
                : frame_chat_count;
    int lead_colour = online ? (int)hud_style[STYLE_ONLINE_NAME] : name_colour;
    int body_colour = online ? (int)hud_style[STYLE_ONLINE_DATA] : text_colour;"""),
      ("""      const char* author = preview ? sample[i][0] : frame_chat[i].author;
      const char* body = preview ? sample[i][1] : frame_chat[i].body;
      char lead[48];
      snprintf(lead, sizeof(lead), "%s: ", author);
      float lead_w = hud_text_width(bold, text_size, lead, NULL);
      bool own_line = lead_w > list_width * 0.6f;""",
       """      const char* author = "";
      const char* body = "";
      chat_row(i, preview, &author, &body);
      char lead[64];
      snprintf(lead, sizeof(lead), online ? "%s" : "%s: ", author);
      float lead_w = hud_text_width(bold, text_size, lead, NULL);
      bool own_line = online || lead_w > list_width * 0.6f;"""),
      ("""        const char* author = preview ? sample[i][0] : frame_chat[i].author;
        const char* body = preview ? sample[i][1] : frame_chat[i].body;
        char lead[48];
        snprintf(lead, sizeof(lead), "%s: ", author);
        float lead_w = hud_text_width(bold, text_size, lead, NULL);
        bool own_line = lead_w > list_width * 0.6f;""",
       """        const char* author = "";
        const char* body = "";
        chat_row(i, preview, &author, &body);
        char lead[64];
        snprintf(lead, sizeof(lead), online ? "%s" : "%s: ", author);
        float lead_w = hud_text_width(bold, text_size, lead, NULL);
        bool own_line = online || lead_w > list_width * 0.6f;"""),
      ("""        const char* empty = "No messages yet";""",
       """        const char* empty = online ? "No one online" : "No messages yet";"""),
      ("""            hud_text_colour(name_colour, ARENA_THEME_INK, body_alpha), lead,""",
       """            hud_text_colour(lead_colour, ARENA_THEME_INK, body_alpha), lead,"""),
      ("""                 hud_text_colour(text_colour, ARENA_THEME_INK,""",
       """                 hud_text_colour(body_colour, ARENA_THEME_INK,"""),
      ("""  if (openness > 0.72f) {
    chat_input[0] = input_min.x;""",
       """  if (openness > 0.72f && !online) {
    chat_input[0] = input_min.x;"""),
      # touch: a tab switches
      ("""    if (hud_inside(chat_rect, x, y)) {
      /* Mostly closed: the whole pill toggles. Open: only the header does.
         The composer is live only once the window is mostly open. */""",
       """    if (hud_inside(chat_rect, x, y)) {
      /* A tab (OM, 2026-10-14) shows its list. */
      if (chat_openness > 0.72f)
        for (int t = 0; t < CHAT_TAB_COUNT; ++t)
          if (hud_inside(chat_tab_rect[t], x, y)) {
            android_team_set_chat_tab(t);
            return true;
          }
      /* Mostly closed: the whole pill toggles. Open: only the header does.
         The composer is live only once the window is mostly open. */"""),
      # non-mobile stubs
      ("""void android_team_set_chat(const char* packed) { (void)packed; }""",
       """void android_team_set_chat(const char* packed) { (void)packed; }
void android_team_set_global_chat(const char* packed) { (void)packed; }
void android_team_set_online(const char* packed) { (void)packed; }
int android_team_chat_tab(void) { return 0; }
void android_team_set_chat_tab(int tab) { (void)tab; }"""),
      )

# Android JNI (Android tree only)
pairs(F, ("""/** The roster's and chat window's look, as android_team_set_hud_style reads it. */""",
          """/** Global chat and players online (OM, 2026-10-14), as their setters read them. */
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetGlobalChat(JNIEnv* env, jclass clazz,
                                                         jstring packed) {
  (void)clazz;
  const char* text = packed ? (*env)->GetStringUTFChars(env, packed, NULL) : "";
  android_team_set_global_chat(text);
  if (packed) (*env)->ReleaseStringUTFChars(env, packed, text);
}
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetOnlinePlayers(JNIEnv* env, jclass clazz,
                                                            jstring packed) {
  (void)clazz;
  const char* text = packed ? (*env)->GetStringUTFChars(env, packed, NULL) : "";
  android_team_set_online(text);
  if (packed) (*env)->ReleaseStringUTFChars(env, packed, text);
}
JNIEXPORT jint JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeChatTab(JNIEnv* env, jclass clazz) {
  (void)env;
  (void)clazz;
  return android_team_chat_tab();
}
JNIEXPORT void JNICALL
Java_com_wyrm_omrajput_WyrmActivity_nativeSetChatTab(JNIEnv* env, jclass clazz, jint tab) {
  (void)env;
  (void)clazz;
  android_team_set_chat_tab(tab);
}

/** The roster's and chat window's look, as android_team_set_hud_style reads it. */""", "android"))

# iOS mailbox (generated iOS tree only)
pairs(F, ("""void WyrmIOSSetTeamChat(const char* packed) { android_team_set_chat(packed); }""",
          """void WyrmIOSSetTeamChat(const char* packed) { android_team_set_chat(packed); }
/* Global chat and players online (OM, 2026-10-14). */
void WyrmIOSSetGlobalChat(const char* packed) { android_team_set_global_chat(packed); }
void WyrmIOSSetOnlinePlayers(const char* packed) { android_team_set_online(packed); }
int WyrmIOSChatTab(void) { return android_team_chat_tab(); }
void WyrmIOSSetChatTab(int tab) { android_team_set_chat_tab(tab); }""", "ios"))

pairs("app/src/platform/android_team.h",
      ("""void android_team_set_chat(const char* packed);""",
       """void android_team_set_chat(const char* packed);
/* Arena chat tabs (OM, 2026-10-14): Wyrm's global chat (same packing as the
   team chat), players online (`name<TAB>@username - server` lines), and the
   tab shown (0 team, 1 global, 2 online). */
void android_team_set_global_chat(const char* packed);
void android_team_set_online(const char* packed);
int android_team_chat_tab(void);
void android_team_set_chat_tab(int tab);"""))


def apply(root, label="engine chat tabs 2026-10-14", skip_applied=False, tree="android"):
    root = Path(root)
    for relative, items in PAIRS.items():
        target = root / relative
        text = target.read_text(encoding="utf-8")
        original = text
        crlf = "\r\n" in text
        for item in items:
            old, new = item[0], item[1]
            only = item[2] if len(item) > 2 else None
            if only and only != tree:
                continue
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
    print(apply(sys.argv[1], skip_applied=True, tree="android"), "files written")
