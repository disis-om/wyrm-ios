#ifndef ANDROID_UPDATE_H
#define ANDROID_UPDATE_H

#include <stddef.h>
#include <stdbool.h>

typedef struct tenv tenv;

typedef enum android_update_status {
  ANDROID_UPDATE_IDLE = 0,
  ANDROID_UPDATE_CHECKING = 1,
  ANDROID_UPDATE_UP_TO_DATE = 2,
  ANDROID_UPDATE_AVAILABLE = 3,
  ANDROID_UPDATE_DOWNLOADING = 4,
  ANDROID_UPDATE_VERIFYING = 5,
  ANDROID_UPDATE_READY_TO_INSTALL = 6,
  ANDROID_UPDATE_INSTALLING = 7,
  ANDROID_UPDATE_ERROR = 8
} android_update_status;

typedef enum android_backup_status {
  ANDROID_BACKUP_IDLE = 0,
  ANDROID_BACKUP_SELECTING_FOLDER = 1,
  ANDROID_BACKUP_SAVING = 2,
  ANDROID_BACKUP_SAVED = 3,
  ANDROID_BACKUP_SCANNING = 4,
  ANDROID_BACKUP_FOUND = 5,
  ANDROID_BACKUP_NONE = 6,
  ANDROID_BACKUP_RESTORING = 7,
  ANDROID_BACKUP_RESTORED = 8,
  ANDROID_BACKUP_ERROR = 9,
  ANDROID_BACKUP_RESTORE_AVAILABLE = 10,
  ANDROID_BACKUP_CURRENT = 11,
  ANDROID_BACKUP_RESTARTING = 12,
  ANDROID_BACKUP_PARTIAL = 13
} android_backup_status;

typedef struct android_update_snapshot {
  int update_status;
  int update_progress;
  long long available_version_code;
  char available_version_name[64];
  char update_title[96];
  char update_detail[384];
  int backup_status;
  int backup_count;
  char backup_title[96];
  char backup_detail[1024];
} android_update_snapshot;

void android_update_bind_env(tenv* env);
void android_update_notify_title_ready(const void* settings,
                                       size_t settings_size);
void android_update_check(void);
void android_update_download(const void* settings, size_t settings_size);
void android_update_create_backup(const void* settings, size_t settings_size);
void android_update_check_backups(void);
void android_update_restore_latest(void);
void android_update_choose_backup_folder(void);
/** Applies a validated restore on the engine thread, never on Java's worker. */
bool android_update_apply_pending_settings(tenv* env);
void android_update_get_snapshot(android_update_snapshot* snapshot);

#endif
