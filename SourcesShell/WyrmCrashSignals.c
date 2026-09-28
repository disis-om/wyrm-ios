/*
 * The part of Wyrm's crash watch that runs while the process is dying
 * (OM, 2026-09-29). A signal handler may only call async-signal-safe
 * functions, so everything it needs is prepared at install time: the file
 * path, the frame buffer. When a fatal signal arrives it writes the signal and
 * the raw stack to that file, then lets the signal kill the app as before.
 * On the next launch WyrmCrashWatch (WyrmSupport.swift) finds the file and asks
 * the player whether to send it.
 *
 * An Objective-C exception is recorded by Swift first (it has the name, the
 * reason and the symbolled stack) and then ends in SIGABRT; the flag below
 * keeps this handler from overwriting that better record.
 */

#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

#include "WyrmCrashSignals.h"

static char wyrm_crash_path[1024];
static volatile sig_atomic_t wyrm_crash_exception_written = 0;
static volatile sig_atomic_t wyrm_crash_handling = 0;
static void *wyrm_crash_frames[128];
static const int wyrm_crash_signals[] = { SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP };

static void wyrm_crash_write(int fd, const char *text) {
    size_t length = strlen(text);
    while (length > 0) {
        ssize_t written = write(fd, text, length);
        if (written <= 0) return;
        text += written;
        length -= (size_t)written;
    }
}

static const char *wyrm_crash_signal_name(int sig) {
    switch (sig) {
    case SIGABRT: return "SIGABRT";
    case SIGSEGV: return "SIGSEGV";
    case SIGBUS: return "SIGBUS";
    case SIGILL: return "SIGILL";
    case SIGFPE: return "SIGFPE";
    case SIGTRAP: return "SIGTRAP";
    default: return "SIGNAL";
    }
}

static void wyrm_crash_handler(int sig) {
    if (!wyrm_crash_handling) {
        wyrm_crash_handling = 1;
        if (!wyrm_crash_exception_written && wyrm_crash_path[0] != '\0') {
            int fd = open(wyrm_crash_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) {
                wyrm_crash_write(fd, "signal ");
                wyrm_crash_write(fd, wyrm_crash_signal_name(sig));
                wyrm_crash_write(fd, "\n");
                int count = backtrace(wyrm_crash_frames, 128);
                backtrace_symbols_fd(wyrm_crash_frames, count, fd);
                close(fd);
            }
        }
    }
    /* Let the signal end the app exactly as it would have. */
    signal(sig, SIG_DFL);
    raise(sig);
}

void wyrm_crash_signals_install(const char *path) {
    if (path == NULL) return;
    strncpy(wyrm_crash_path, path, sizeof(wyrm_crash_path) - 1);
    wyrm_crash_path[sizeof(wyrm_crash_path) - 1] = '\0';
    /* backtrace() loads libgcc lazily on first use; do that now, not mid-crash. */
    backtrace(wyrm_crash_frames, 1);
    for (size_t i = 0; i < sizeof(wyrm_crash_signals) / sizeof(wyrm_crash_signals[0]); i++) {
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_handler = wyrm_crash_handler;
        sigemptyset(&action.sa_mask);
        sigaction(wyrm_crash_signals[i], &action, NULL);
    }
}

void wyrm_crash_mark_exception_written(void) {
    wyrm_crash_exception_written = 1;
}
