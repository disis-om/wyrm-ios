/* Apple UI edge for the original settings implementation.
 * This file is text-included inside android_settings.c and intentionally uses
 * its descriptor tables and bounded mailbox instead of duplicating settings.
 */
const char* WyrmIOSSettingsSnapshot(void) {
  static char buffer[32768];
  buffer[0] = '\0';
  if (!settings_env) return buffer;
  user_settings* settings = &settings_env->usr->usrs;
  text_builder builder = {buffer, 0, sizeof(buffer)};
  for (int i = 0; i < GLOBAL_COUNT; ++i) {
    const setting_desc* desc = &GLOBAL_FIELDS[i];
    const void* field =
        (const char*)owner_base(settings, desc->owner) + desc->offset;
    append_row(&builder, desc->id, desc->group, desc->label, desc->hint,
               desc->type, desc->minimum, desc->maximum, desc->options, field);
  }
  for (int mode = 0; mode < 2; ++mode) {
    const char* prefix = mode == 0 ? "normal." : "assist.";
    for (int i = 0; i < MODE_COUNT; ++i) {
      const mode_desc* desc = &MODE_FIELDS[i];
      char id[64];
      snprintf(id, sizeof(id), "%s%s", prefix, desc->id);
      const void* field = (const char*)&settings->modes[mode] + desc->offset;
      append_row(&builder, id, mode == 0 ? "normal" : "assist", desc->label,
                 desc->hint, desc->type, desc->minimum, desc->maximum,
                 desc->options, field);
    }
  }
  return buffer;
}

const char* WyrmIOSSettingsVersion(void) {
  return settings_env ? settings_env->usr->usrs.version : "";
}

bool WyrmIOSQueueSetting(const char* id, float a, float b, float c, float d,
                         int count) {
  if (!settings_mutex || !id || !id[0]) return false;
  SDL_LockMutex(settings_mutex);
  pending_change* change = NULL;
  for (int i = pending_count - 1; i >= 0; --i) {
    if (strcmp(pending[i].id, id) == 0) {
      change = &pending[i];
      break;
    }
  }
  if (!change && pending_count < MAX_PENDING)
    change = &pending[pending_count++];
  if (change) {
    snprintf(change->id, sizeof(change->id), "%s", id);
    change->values[0] = a;
    change->values[1] = b;
    change->values[2] = c;
    change->values[3] = d;
    change->count = count < 1 ? 1 : (count > 4 ? 4 : count);
  }
  SDL_UnlockMutex(settings_mutex);
  return change != NULL;
}

void WyrmIOSSettingsAction(int action) {
  if (!settings_mutex) return;
  SDL_LockMutex(settings_mutex);
  pending_actions |= action;
  SDL_UnlockMutex(settings_mutex);
}

const char* WyrmIOSHotkeysSnapshot(void) {
  static char buffer[4096];
  buffer[0] = '\0';
  if (!settings_env) return buffer;
  user_settings* settings = &settings_env->usr->usrs;
  text_builder builder = {buffer, 0, sizeof(buffer)};
  for (int action = 0; action < NUM_MOBILE_ACTIONS; ++action) {
    if (!mobile_hotkey_is_on_screen_button(action)) continue;
    if (!WYRM_EXPERIMENTAL_ROPE_MODE && action == MOBILE_HOTKEY_ROPE_MODE)
      continue;
    bool fixed_mode = action >= NUM_HOTKEYS || action == HOTKEY_RESTART ||
                      action == HOTKEY_QUIT;
    int mode = fixed_mode
                   ? (mobile_hotkey_is_hold_action(settings, action) ? 1 : 0)
                   : settings->hotkeys[action].mode;
    bool visible = false;
    float x = 0.5f, y = 0.22f;
    mobile_hotkey_get_layout(settings, action, &visible, &x, &y);
    append_int(&builder, action); append(&builder, "\t");
    append(&builder, mobile_hotkey_action_name(action)); append(&builder, "\t");
    append_int(&builder, mobile_hotkey_get_key(settings, action)); append(&builder, "\t");
    append(&builder, mobile_hotkey_key_name(settings, action)); append(&builder, "\t");
    append_int(&builder, mode); append(&builder, "\t");
    append(&builder, fixed_mode ? "1" : "0"); append(&builder, "\t");
    append(&builder, visible ? "1" : "0"); append(&builder, "\t");
    append_float(&builder, x); append(&builder, "\t");
    append_float(&builder, y); append(&builder, "\n");
  }
  return buffer;
}

bool WyrmIOSQueueHotkey(int action, int key, int mode, bool visible,
                        float x, float y) {
  if (!settings_mutex || action < 0 || action >= NUM_MOBILE_ACTIONS)
    return false;
  SDL_LockMutex(settings_mutex);
  pending_hotkeys[action] = (pending_hotkey){true, key, mode, visible, x, y};
  SDL_UnlockMutex(settings_mutex);
  return true;
}
