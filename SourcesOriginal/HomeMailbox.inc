
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

const char* WyrmIOSHomeSnapshot(void) {
  static char snapshot[256];
  if (!home_env) return "\t\t0\t0";
  user_settings* settings = &home_env->usr->usrs;
  snprintf(snapshot, sizeof(snapshot), "%s\t%s\t%d\t%d",
           settings->nickname, settings->ipv4, settings->score, settings->kills);
  return snapshot;
}
