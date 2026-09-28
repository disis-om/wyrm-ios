#ifndef WYRM_CRASH_SIGNALS_H
#define WYRM_CRASH_SIGNALS_H

/* Fatal-signal half of Wyrm's crash watch. See WyrmCrashSignals.c. */
void wyrm_crash_signals_install(const char *path);
void wyrm_crash_mark_exception_written(void);

#endif
