// LaunchProbe.c
//
// Earliest-possible launch instrumentation, written in pure POSIX/libSystem so
// it has no dependency on AppKit, Foundation, the Swift runtime, or any bundled
// dylib. It runs as a dyld constructor: that is, AFTER dyld has finished binding
// every imported symbol but BEFORE Swift `main` executes.
//
// Why this matters for diagnosing a startup crash:
//   * If this probe's line appears in the log but the Swift "main begin" mark
//     does not, the failure is in Swift runtime / static initialization.
//   * If this probe's line does NOT appear at all, dyld aborted during symbol
//     binding (a missing-symbol / missing-library failure) before any
//     constructor could run. In that case the precise cause is named in the
//     system crash report (~/Library/Logs/DiagnosticReports/TypeWhale-*.ips).
//
// The probe also exposes typewhale_launch_probe_log() so Swift can funnel crash
// handler output through the same dependency-free path.

#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static void typewhale_probe_log_path(char *out, size_t out_size) {
    const char *home = getenv("HOME");
    if (home == NULL || home[0] == '\0') {
        home = "/tmp";
    }
    snprintf(out, out_size, "%s/Library/Logs/TypeWhale", home);
    // Best-effort directory creation; ignore errors (e.g. already exists).
    mkdir(out, 0755);
    snprintf(out, out_size, "%s/Library/Logs/TypeWhale/launch.log", home);
}

void typewhale_launch_probe_log(const char *message) {
    char path[1024];
    typewhale_probe_log_path(path, sizeof(path));

    int fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0644);
    if (fd < 0) {
        return;
    }

    char stamp[32];
    time_t now = time(NULL);
    struct tm tm_buf;
    if (localtime_r(&now, &tm_buf) != NULL) {
        strftime(stamp, sizeof(stamp), "%Y-%m-%dT%H:%M:%S", &tm_buf);
    } else {
        strncpy(stamp, "unknown-time", sizeof(stamp));
        stamp[sizeof(stamp) - 1] = '\0';
    }

    char line[2048];
    int len = snprintf(line, sizeof(line), "%s %s\n",
                       stamp, message ? message : "(null)");
    if (len > 0) {
        if (len > (int)sizeof(line)) {
            len = (int)sizeof(line);
        }
        ssize_t written = write(fd, line, (size_t)len);
        (void)written;
    }
    close(fd);
}

__attribute__((constructor))
static void typewhale_launch_probe(void) {
    typewhale_launch_probe_log(
        "native LaunchProbe constructor ran (dyld bind succeeded, pre-main)");
}
