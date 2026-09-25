
/* Apple UI submits into the same original mailbox drained by android_home_poll.
 * Bounded copied strings; no retained UI pointers. SDL mutex owns each command.
 */
void WyrmIOSRequestPlay(const char* name, const char* address, bool offline) {
  if (!home_mutex || !name || !address) return;
  WyrmIOSSetEnginePresentation(true);
  SDL_LockMutex(home_mutex);
  snprintf(pending_nickname, sizeof(pending_nickname), "%s", name);
  snprintf(pending_enter_arena, sizeof(pending_enter_arena), "%s", address);
  pending_ai_enter = offline;
  pending_enter = !offline;
  static uint64_t next_id = 0;
  pending_enter_id = ++next_id;
  SDL_UnlockMutex(home_mutex);
}

void WyrmIOSRequestLobby(const char* name, const char* address) {
  if (!home_mutex || !name || !address) return;
  SDL_LockMutex(home_mutex);
  snprintf(pending_saved_nickname, sizeof(pending_saved_nickname), "%s", name);
  pending_nickname_save = true;
  if (address[0]) snprintf(pending_arena, sizeof(pending_arena), "%s", address);
  pending_screen = LOBBY;
  SDL_UnlockMutex(home_mutex);
}

void WyrmIOSSaveNickname(const char* name) {
  if (!home_mutex || !name) return;
  SDL_LockMutex(home_mutex);
  snprintf(pending_saved_nickname, sizeof(pending_saved_nickname), "%s", name);
  pending_nickname_save = true;
  SDL_UnlockMutex(home_mutex);
}

/* Android's layout editor: a bot-driven AI arena drawing the real controls
 * and HUD while the editor above it only captures the drags. */
void WyrmIOSEnterLayoutEditor(const char* name) {
  if (!home_mutex || !name) return;
  SDL_LockMutex(home_mutex);
  snprintf(pending_nickname, sizeof(pending_nickname), "%s", name);
  pending_ai_editor_enter = true;
  SDL_UnlockMutex(home_mutex);
}

void WyrmIOSExitLayoutEditor(void) {
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  pending_ai_editor_exit = true;
  SDL_UnlockMutex(home_mutex);
}

void WyrmIOSToggleEditorLeaderboard(void) {
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  pending_editor_leaderboard_toggle = true;
  SDL_UnlockMutex(home_mutex);
}

/* Engine-thread refusal publication for the Apple product shell. The native
 * engine remains the authority for deciding that an attempt failed and for
 * applying the 120-second taint. Swift receives only an immutable event copy
 * and chooses another directory endpoint; it never touches live game state.
 */
static uint64_t apple_refusal_sequence = 0;
static char apple_refused_endpoint[MAX_IPV4_LEN + 1] = {0};
static int apple_refused_seconds = 0;

void WyrmIOSPublishArenaRefusal(const char* endpoint, int seconds) {
  if (!home_mutex || !endpoint || !endpoint[0] || seconds <= 0) return;
  SDL_LockMutex(home_mutex);
  snprintf(apple_refused_endpoint, sizeof(apple_refused_endpoint), "%s", endpoint);
  apple_refused_seconds = seconds;
  apple_refusal_sequence++;
  SDL_UnlockMutex(home_mutex);
}

const char* WyrmIOSArenaRefusalSnapshot(void) {
  static char snapshot[MAX_IPV4_LEN + 64];
  if (!home_mutex) return "0\t\t0";
  SDL_LockMutex(home_mutex);
  snprintf(snapshot, sizeof(snapshot), "%llu\t%s\t%d",
           (unsigned long long)apple_refusal_sequence,
           apple_refused_endpoint, apple_refused_seconds);
  SDL_UnlockMutex(home_mutex);
  return snapshot;
}

const char* WyrmIOSHomeSnapshot(void) {
  static char snapshot[256];
  if (!home_env) return "\t\t0\t0";
  user_settings* settings = &home_env->usr->usrs;
  snprintf(snapshot, sizeof(snapshot), "%s\t%s\t%d\t%d",
           settings->nickname, settings->ipv4, settings->score, settings->kills);
  return snapshot;
}

/* ---------------------------------------------------------------------------
 * Finished runs and arena skins for the Apple shell.
 *
 * Android hands both to Kotlin through JNI; here they wait in bounded, mutex-
 * guarded mailboxes that SwiftUI drains on its own timer. The engine thread
 * never performs network I/O and never touches the arena socket or its clocks.
 * ------------------------------------------------------------------------- */

#define APPLE_RUN_OUTBOX 16
static int apple_run_scores[APPLE_RUN_OUTBOX];
static int apple_run_kills[APPLE_RUN_OUTBOX];
static int apple_run_count = 0;

/* Engine thread, once per life that actually spawned in a real arena. */
void WyrmIOSRecordFinishedRun(int score, int kills) {
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  if (apple_run_count < APPLE_RUN_OUTBOX) {
    apple_run_scores[apple_run_count] = score < 0 ? 0 : score;
    apple_run_kills[apple_run_count] = kills < 0 ? 0 : kills;
    apple_run_count++;
  }
  SDL_UnlockMutex(home_mutex);
  SDL_Log("Wyrm run finished: score=%d kills=%d", score, kills);
}

/* Main thread: one "score\tkills\n" line per run, and the outbox is emptied. */
const char* WyrmIOSDrainFinishedRuns(void) {
  static char buffer[APPLE_RUN_OUTBOX * 32];
  buffer[0] = '\0';
  if (!home_mutex) return buffer;
  SDL_LockMutex(home_mutex);
  size_t used = 0;
  for (int i = 0; i < apple_run_count && used < sizeof(buffer) - 32; ++i)
    used += (size_t)snprintf(buffer + used, sizeof(buffer) - used, "%d\t%d\n",
                             apple_run_scores[i], apple_run_kills[i]);
  apple_run_count = 0;
  SDL_UnlockMutex(home_mutex);
  return buffer;
}

#define APPLE_SKIN_TICK_MS 250
#define APPLE_SKIN_SETTLE_MS 250
#define APPLE_SKIN_INBOX 64

static int apple_skin_published_id = -1;
static char apple_skin_published_arena[MAX_IPV4_LEN + 1] = {0};
static uint64_t apple_skin_playing_since = 0;
static uint64_t apple_skin_next_request = 0;
static uint64_t apple_identity_sequence = 0;
static char apple_identity[MAX_IPV4_LEN + MAX_NICKNAME_LEN + MAX_SKIN_CODE_LEN * 9 + 96] = {0};
static uint64_t apple_visible_sequence = 0;
static char apple_visible[MAX_REMOTE_SKINS * 7 + 32] = {0};
static remote_skin apple_skin_inbox[APPLE_SKIN_INBOX];
static int apple_skin_inbox_count = 0;
static bool apple_skin_clear_requested = false;

/* The same authority as Android's publish_arena_identity: only a live,
 * spawned snake in a real online arena has an identity worth publishing. */
static void apple_publish_identity(tenv* env) {
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  bool playing = !gdata->ai_mode && gdata->curr_screen == PLAYING &&
                 gdata->conn == CONNECTED && gdata->arena_ready &&
                 gdata->connection && !gdata->connection->is_closing &&
                 !gdata->data.dead && gdata->data.snake_id >= 0;
  int snake_id = playing ? gdata->data.snake_id : -1;
  const char* arena = playing ? usr->usrs.ipv4 : "";
  if (snake_id == apple_skin_published_id &&
      strcmp(arena, apple_skin_published_arena) == 0) return;
  apple_skin_published_id = snake_id;
  snprintf(apple_skin_published_arena, sizeof(apple_skin_published_arena), "%s", arena);
  apple_skin_playing_since = playing ? (uint64_t)SDL_GetTicks() : 0;
  apple_skin_next_request = apple_skin_playing_since + APPLE_SKIN_SETTLE_MS;

  user_settings* s = &usr->usrs;
  size_t length = playing && s->custom_skin ? strlen(s->skin_code) : 0;
  if (length > MAX_SKIN_CODE_LEN) length = MAX_SKIN_CODE_LEN;
  SDL_LockMutex(home_mutex);
  size_t used = (size_t)snprintf(apple_identity, sizeof(apple_identity), "%llu\t%s\t%d\t%s\t",
                                 (unsigned long long)++apple_identity_sequence, arena,
                                 snake_id, playing ? s->nickname : "");
  for (size_t i = 0; i < length && used < sizeof(apple_identity) - 2; ++i)
    apple_identity[used++] = s->skin_code[i];
  if (used < sizeof(apple_identity) - 1) apple_identity[used++] = '\t';
  apple_identity[used] = '\0';
  for (size_t i = 0; i < length && used < sizeof(apple_identity) - 9; ++i)
    used += (size_t)snprintf(apple_identity + used, sizeof(apple_identity) - used, "%08X",
                             (unsigned)s->skin_rgba[i]);
  SDL_UnlockMutex(home_mutex);
}

static void apple_sample_visible(tenv* env) {
  game_data* gdata = &env->usr->gdata;
  if (gdata->ai_mode || gdata->curr_screen != PLAYING || gdata->conn != CONNECTED ||
      !gdata->arena_ready || !gdata->connection || gdata->connection->is_closing ||
      gdata->data.dead || apple_skin_published_id < 0 || !apple_skin_playing_since) return;
  uint64_t now = (uint64_t)SDL_GetTicks();
  if (now < apple_skin_next_request) return;
  apple_skin_next_request = now + APPLE_SKIN_TICK_MS;
  char ids[sizeof(apple_visible)];
  size_t used = 0;
  int count = 0;
  ids[0] = '\0';
  int snakes = tdarray_length(gdata->data.snakes);
  for (int i = 0; i < snakes && count < MAX_REMOTE_SKINS && used < sizeof(ids) - 8; ++i) {
    snake* o = gdata->data.snakes + i;
    if (o->dead || !o->cusk || o->id == gdata->data.snake_id) continue;
    used += (size_t)snprintf(ids + used, sizeof(ids) - used, count ? ",%d" : "%d", o->id);
    count++;
  }
  if (!count) return;
  SDL_LockMutex(home_mutex);
  snprintf(apple_visible, sizeof(apple_visible), "%llu\t%s",
           (unsigned long long)++apple_visible_sequence, ids);
  SDL_UnlockMutex(home_mutex);
}

/* Android's nativeArenaSkinSet, applied here on the engine thread. */
static void apple_store_remote(game_data* gdata, const remote_skin* incoming) {
  if (!gdata->remote_skins) gdata->remote_skins = tdarray_create(remote_skin);
  int count = (int)tdarray_length(gdata->remote_skins);
  int slot = -1;
  for (int i = 0; i < count; ++i)
    if (gdata->remote_skins[i].snake_id == incoming->snake_id) slot = i;
  if (slot < 0) {
    if (count >= MAX_REMOTE_SKINS) {
      int oldest = 0;
      for (int i = 1; i < count; ++i)
        if (gdata->remote_skins[i].last_used_ms < gdata->remote_skins[oldest].last_used_ms) oldest = i;
      tdarray_remove(gdata->remote_skins, oldest);
      count--;
    }
    remote_skin empty = {0};
    tdarray_push(&gdata->remote_skins, &empty);
    slot = count;
  }
  gdata->remote_skins[slot] = *incoming;
  gdata->remote_skins[slot].last_used_ms = SDL_GetTicks();
}

/* Engine thread, every frame. */
void WyrmIOSArenaSyncPoll(tenv* env) {
  if (!env || !home_mutex) return;
  apple_publish_identity(env);
  apple_sample_visible(env);
  static remote_skin taken[APPLE_SKIN_INBOX];
  SDL_LockMutex(home_mutex);
  int count = apple_skin_inbox_count;
  bool clear = apple_skin_clear_requested;
  if (count) memcpy(taken, apple_skin_inbox, sizeof(remote_skin) * (size_t)count);
  apple_skin_inbox_count = 0;
  apple_skin_clear_requested = false;
  SDL_UnlockMutex(home_mutex);
  game_data* gdata = &env->usr->gdata;
  if (clear && gdata->remote_skins) tdarray_clear(gdata->remote_skins);
  for (int i = 0; i < count; ++i) apple_store_remote(gdata, taken + i);
}

/* "sequence\tarena\tsnakeId\tnickname\tcode\tARGB hex"; snakeId -1 means gone. */
const char* WyrmIOSArenaIdentitySnapshot(void) {
  static char copy[sizeof(apple_identity)];
  copy[0] = '\0';
  if (!home_mutex) return copy;
  SDL_LockMutex(home_mutex);
  memcpy(copy, apple_identity, sizeof(copy));
  SDL_UnlockMutex(home_mutex);
  return copy;
}

/* "sequence\tid,id,..." of visible snakes wearing a custom skin. */
const char* WyrmIOSArenaVisibleSnapshot(void) {
  static char copy[sizeof(apple_visible)];
  copy[0] = '\0';
  if (!home_mutex) return copy;
  SDL_LockMutex(home_mutex);
  memcpy(copy, apple_visible, sizeof(copy));
  SDL_UnlockMutex(home_mutex);
  return copy;
}

void WyrmIOSArenaSkinSet(int snake_id, const char* nickname, const uint32_t* colours, int count) {
  if (!home_mutex || snake_id < 0) return;
  SDL_LockMutex(home_mutex);
  if (apple_skin_inbox_count < APPLE_SKIN_INBOX) {
    remote_skin* row = apple_skin_inbox + apple_skin_inbox_count++;
    memset(row, 0, sizeof(*row));
    row->snake_id = snake_id;
    snprintf(row->nickname, sizeof(row->nickname), "%s", nickname ? nickname : "");
    int length = count < 0 ? 0 : (count > MAX_SKIN_CODE_LEN ? MAX_SKIN_CODE_LEN : count);
    if (length && colours) memcpy(row->rgba, colours, sizeof(uint32_t) * (size_t)length);
    row->length = length;
  }
  SDL_UnlockMutex(home_mutex);
}

void WyrmIOSArenaSkinsClear(void) {
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  apple_skin_inbox_count = 0;
  apple_skin_clear_requested = true;
  SDL_UnlockMutex(home_mutex);
}
