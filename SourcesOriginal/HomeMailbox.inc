
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

/* The background-size editor (OM, 2026-10-01): only the real map and board,
 * assist off while it is open. Set before the editor is entered. */
void WyrmIOSSetEditorBare(bool bare) { ai_mode_set_editor_bare(bare); }

void WyrmIOSToggleEditorLeaderboard(void) {
  if (!home_mutex) return;
  SDL_LockMutex(home_mutex);
  pending_editor_leaderboard_toggle = true;
  SDL_UnlockMutex(home_mutex);
}

/* Engine-thread refusal publication for the Apple product shell. The native
 * engine remains the authority for deciding that an attempt failed and for
 * applying any taint. Swift receives an immutable event copy and clears the
 * pending Play state; it never selects another endpoint for this attempt.
 */
static uint64_t apple_refusal_sequence = 0;
static char apple_refused_endpoint[MAX_IPV4_LEN + 1] = {0};
static int apple_refused_seconds = 0;

void WyrmIOSPublishArenaRefusal(const char* endpoint, int seconds) {
  /* Zero means a terminal refusal without a taint interval. It still has to
   * advance the sequence so Swift clears its Entering state. */
  if (!home_mutex || !endpoint || !endpoint[0] || seconds < 0) return;
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

/* ---------------------------------------------------------------------------
 * Arena drops (OM, 2026-09-29).
 *
 * A drop is the arena socket closing while the player's own snake is alive,
 * with no death packet, no leave and no refused entry. prepare-original-
 * engine.py calls WyrmIOSArenaDropped at that moment, before the death watch
 * starts, from both close paths (callback.c MG_EV_CLOSE and loop.c CONNECTED).
 * It only reads: the match still fades out and the run still records exactly
 * as before. One snapshot per connection; SwiftUI polls it and asks the player.
 *
 * The connect ring, the close frame and the error text are engine-thread
 * only (Mongoose callbacks run inside server_poll on that thread). The
 * published snapshot is guarded by home_mutex like every other mailbox.
 * ------------------------------------------------------------------------- */
#include "../network/arena_persona.h"

#define APPLE_CONNECT_RING 64
static uint64_t apple_connect_ring[APPLE_CONNECT_RING];
static int apple_connect_next = 0;
static uint64_t apple_connect_serial = 0;
static uint64_t apple_drop_published_serial = 0;
static unsigned apple_close_code = 0;
static char apple_close_reason[121] = {0};
static char apple_error_text[121] = {0};
static uint64_t apple_drop_sequence = 0;
/* Per connection: what the join carried, and whether the configuration
   timeout (ours) closed the socket. For a pre-spawn report. */
static int apple_join_sent = 0;
static int apple_join_bytes = 0;
static int apple_join_skin_bytes = 0;
static int apple_join_skin_runs = 0;
static int apple_join_nick_bytes = 0;
static int apple_join_custom_skin = 0;
static int apple_timed_out = 0;
static char apple_drop_snapshot[1024] = {0};

/* Tabs and line breaks would split the snapshot's fields. */
static void apple_copy_clean(char* out, size_t size, const char* in, size_t length) {
  size_t used = 0;
  for (size_t i = 0; in && i < length && used + 1 < size; ++i) {
    unsigned char ch = (unsigned char)in[i];
    if (ch == 0) break;
    out[used++] = (ch < 0x20 || ch == 0x7F) ? ' ' : (char)ch;
  }
  out[used] = '\0';
}

/* Engine thread, from server_connect: one stamp per dial. */
void WyrmIOSArenaConnectStamp(void) {
  apple_connect_ring[apple_connect_next] = (uint64_t)SDL_GetTicks();
  apple_connect_next = (apple_connect_next + 1) % APPLE_CONNECT_RING;
  apple_connect_serial++;
  apple_close_code = 0;
  apple_close_reason[0] = '\0';
  apple_error_text[0] = '\0';
  apple_join_sent = apple_join_bytes = apple_join_skin_bytes = 0;
  apple_join_skin_runs = apple_join_nick_bytes = apple_join_custom_skin = 0;
  apple_timed_out = 0;
}

/* Engine thread, right after the join goes out. */
void WyrmIOSArenaJoinFacts(int packet_bytes, int skin_bytes, int skin_runs,
                           int nick_bytes, int custom_skin) {
  apple_join_sent = 1;
  apple_join_bytes = packet_bytes;
  apple_join_skin_bytes = skin_bytes;
  apple_join_skin_runs = skin_runs;
  apple_join_nick_bytes = nick_bytes;
  apple_join_custom_skin = custom_skin;
}

/* Engine thread: the configuration timeout is closing this socket. */
void WyrmIOSArenaNoteTimeout(void) { apple_timed_out = 1; }

/* Engine thread: a WebSocket CLOSE frame's payload, code big-endian first. */
void WyrmIOSArenaCloseFrame(const uint8_t* data, size_t length) {
  apple_close_code = (data && length >= 2)
      ? ((unsigned)data[0] << 8) | (unsigned)data[1] : 0;
  if (data && length > 2)
    apple_copy_clean(apple_close_reason, sizeof(apple_close_reason),
                     (const char*)data + 2, length - 2);
  else
    apple_close_reason[0] = '\0';
}

/* Engine thread: Mongoose's MG_EV_ERROR text for this connection. */
void WyrmIOSArenaNoteError(const char* text) {
  apple_copy_clean(apple_error_text, sizeof(apple_error_text), text ? text : "",
                   text ? strlen(text) : 0);
  if (!apple_error_text[0]) snprintf(apple_error_text, sizeof(apple_error_text), "error");
}

/* Engine thread, at the drop, before android_home_notify_death. */
/* A snake the arena ends within this long of spawning was dropped, not
   beaten: the arena takes it with a 'v' 0.3 to 1 s after it appears. */
#define APPLE_FAST_DEATH_SEC 1.5

static void apple_publish_drop(tenv* env, const char* reason, int death_code, double life);

void WyrmIOSArenaDropped(tenv* env) {
  if (!env) return;
  apple_publish_drop(env, apple_error_text[0] ? "error" : "closed", -1,
                     env->usr->gdata.last_life);
}

/* Engine thread, first thing in the 'v' handler (before the death watch). */
void WyrmIOSArenaFastDeath(tenv* env, int death_code) {
  if (!env) return;
  game_data* gdata = &env->usr->gdata;
  if (gdata->ai_mode || !gdata->join_spawned || gdata->closed_by_us ||
      gdata->leaving || gdata->restart_req || android_home_death_pending())
    return;
  double life = glfwGetTime() - gdata->life_started_sec;
  if (life < 0 || life >= APPLE_FAST_DEATH_SEC) return;
  apple_publish_drop(env, "death_packet", death_code, life);
}

static void apple_publish_drop(tenv* env, const char* reason, int death_code, double life) {
  if (!env || !home_mutex) return;
  if (apple_connect_serial && apple_drop_published_serial == apple_connect_serial) return;
  apple_drop_published_serial = apple_connect_serial;
  tuser_data* usr = env->usr;
  game_data* gdata = &usr->gdata;
  uint64_t now = (uint64_t)SDL_GetTicks();
  if (life < 0) life = 0;
  /* Dial to spawn: how long the arena took to hand over a snake. */
  long long since_dial = gdata->attempt_started_ms && now >= gdata->attempt_started_ms
      ? (long long)(now - gdata->attempt_started_ms) : -1;
  long long dial_to_spawn = since_dial >= 0 ? since_dial - (long long)(life * 1000.0) : -1;
  if (dial_to_spawn < 0 && since_dial >= 0) dial_to_spawn = 0;

  int connects = 0;
  for (int i = 0; i < APPLE_CONNECT_RING; ++i)
    if (apple_connect_ring[i] && now - apple_connect_ring[i] <= 60000) connects++;

  /* The same own-snake reading as game_capture_final_score, without writing. */
  int score = gdata->data.score, kills = gdata->data.kills, length = 0;
  size_t count = gdata->data.snakes ? tdarray_length(gdata->data.snakes) : 0;
  if (count && gdata->data.snakes[count - 1].local_player) {
    snake* me = gdata->data.snakes + count - 1;
    int sct = me->sct + me->rsc;
    int limit = gdata->data.fpsls ? (int)tdarray_length(gdata->data.fpsls) - 1 : -1;
    if (sct >= 0 && sct <= limit && gdata->data.fmlts[sct] > 0)
      score = (int)floorf((gdata->data.fpsls[sct] +
                           me->fam / gdata->data.fmlts[sct] - 1) * 15 - 5);
    kills = (int)me->kill_count;
    length = me->sct;
  }
  uint64_t silent = gdata->last_packet_ms && now >= gdata->last_packet_ms
      ? now - gdata->last_packet_ms : 0;
  const arena_persona* persona = arena_persona_get(gdata->persona);

  SDL_LockMutex(home_mutex);
  apple_drop_sequence++;
  snprintf(apple_drop_snapshot, sizeof(apple_drop_snapshot),
           "%llu\tdropReason=%s\tdeathPacket=%d\tdialToSpawnMs=%lld"
           "\tcloseCode=%u\tcloseReason=%s\terrorText=%s"
           "\tlifeSec=%.1f\tscore=%d\tlength=%d\tkills=%d\tpingMs=%d\tlagging=%d"
           "\tfps=%d\tlastPacketAgoMs=%llu\tconnectsLastMin=%d\tpersona=%s"
           "\tprotocol=%d\tarena=%s",
           (unsigned long long)apple_drop_sequence,
           reason, death_code, dial_to_spawn, apple_close_code,
           apple_close_reason, apple_error_text, life,
           score < 0 ? 0 : score, length, kills < 0 ? 0 : kills,
           gdata->data.ping, gdata->data.lagging ? 1 : 0, gdata->data.fps,
           (unsigned long long)silent, connects,
           persona && persona->name ? persona->name : "",
           gdata->data.protocol_version, usr->usrs.ipv4);
  SDL_UnlockMutex(home_mutex);
  SDL_Log("Wyrm arena drop: '%s' after %.1fs, %s (v %d), close code %u, %s, %d connects in 60s",
          usr->usrs.ipv4, life, reason, death_code, apple_close_code,
          apple_error_text[0] ? apple_error_text : "closed", connects);
}

/* Engine thread, from the close: turned away after the WebSocket upgrade
   and before our snake spawned, not by us. One report per connection (the
   same serial guard as a post-spawn drop, which needs a spawn anyway). */
void WyrmIOSArenaPrespawnClosed(tenv* env, const char* phase) {
  if (!env || !home_mutex) return;
  game_data* gdata = &env->usr->gdata;
  if (gdata->ai_mode || gdata->join_spawned || gdata->closed_by_us ||
      gdata->leaving || gdata->restart_req)
    return;
  if (apple_connect_serial && apple_drop_published_serial == apple_connect_serial) return;
  apple_drop_published_serial = apple_connect_serial;
  tuser_data* usr = env->usr;
  uint64_t now = (uint64_t)SDL_GetTicks();
  int connects = 0;
  for (int i = 0; i < APPLE_CONNECT_RING; ++i)
    if (apple_connect_ring[i] && now - apple_connect_ring[i] <= 60000) connects++;
  long long since_dial = gdata->attempt_started_ms && now >= gdata->attempt_started_ms
      ? (long long)(now - gdata->attempt_started_ms) : -1;
  const char* reason = apple_timed_out ? "prespawn_timeout"
                       : apple_error_text[0] ? "prespawn_error" : "prespawn_closed";
  char phase_text[64];
  apple_copy_clean(phase_text, sizeof(phase_text), phase ? phase : "",
                   phase ? strlen(phase) : 0);
  const arena_persona* persona = arena_persona_get(gdata->persona);

  SDL_LockMutex(home_mutex);
  apple_drop_sequence++;
  snprintf(apple_drop_snapshot, sizeof(apple_drop_snapshot),
           "%llu\tdropReason=%s\tphase=%s\tmsSinceDial=%lld\tjoinSent=%d"
           "\tjoinBytes=%d\tcustomSkin=%d\tskinBytes=%d\tskinRuns=%d\tnickBytes=%d"
           "\tcloseCode=%u\tcloseReason=%s\terrorText=%s\tlifeSec=0"
           "\tconnectsLastMin=%d\tpersona=%s\tarena=%s",
           (unsigned long long)apple_drop_sequence, reason, phase_text, since_dial,
           apple_join_sent, apple_join_bytes, apple_join_custom_skin,
           apple_join_skin_bytes, apple_join_skin_runs, apple_join_nick_bytes,
           apple_close_code, apple_close_reason, apple_error_text, connects,
           persona && persona->name ? persona->name : "", usr->usrs.ipv4);
  SDL_UnlockMutex(home_mutex);
  SDL_Log("Wyrm arena: turned away %s (%s) — join %d bytes, skin %d runs",
          phase_text, reason, apple_join_bytes, apple_join_skin_runs);
}

/* Main thread: "sequence\tkey=value\t…", or "0" before the first drop. */
const char* WyrmIOSArenaDropSnapshot(void) {
  static char copy[sizeof(apple_drop_snapshot)];
  snprintf(copy, sizeof(copy), "0");
  if (!home_mutex) return copy;
  SDL_LockMutex(home_mutex);
  if (apple_drop_sequence) memcpy(copy, apple_drop_snapshot, sizeof(copy));
  SDL_UnlockMutex(home_mutex);
  return copy;
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
static double apple_run_seconds[APPLE_RUN_OUTBOX];
static int apple_run_count = 0;

/* Engine thread, once per life that actually spawned in a real arena.
 * play_time is the life's length in seconds (game_capture_final_score). */
void WyrmIOSRecordFinishedRun(int score, int kills, double play_time) {
  if (!home_mutex) return;
  /* NaN and anything absurd read as 0. */
  double seconds = play_time > 0 && play_time < 1e8 ? play_time : 0;
  SDL_LockMutex(home_mutex);
  if (apple_run_count < APPLE_RUN_OUTBOX) {
    apple_run_scores[apple_run_count] = score < 0 ? 0 : score;
    apple_run_kills[apple_run_count] = kills < 0 ? 0 : kills;
    apple_run_seconds[apple_run_count] = seconds;
    apple_run_count++;
  }
  SDL_UnlockMutex(home_mutex);
  /* "Share this run": the death frame is still on screen, so the frame being
     drawn now is copied once (AppleRunCapture.inc). */
  WyrmIOSRunCaptureRequest();
  SDL_Log("Wyrm run finished: score=%d kills=%d seconds=%.1f", score, kills, seconds);
}

/* Main thread: one "score\tkills\tseconds\n" line per run (seconds with three
 * decimals), and the outbox is emptied. */
const char* WyrmIOSDrainFinishedRuns(void) {
  static char buffer[APPLE_RUN_OUTBOX * 48];
  buffer[0] = '\0';
  if (!home_mutex) return buffer;
  SDL_LockMutex(home_mutex);
  size_t used = 0;
  for (int i = 0; i < apple_run_count && used < sizeof(buffer) - 48; ++i)
    used += (size_t)snprintf(buffer + used, sizeof(buffer) - used, "%d\t%d\t%.3f\n",
                             apple_run_scores[i], apple_run_kills[i],
                             apple_run_seconds[i]);
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
