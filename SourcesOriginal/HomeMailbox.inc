
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
