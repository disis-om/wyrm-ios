
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
