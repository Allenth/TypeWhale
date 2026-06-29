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

// Injected at compile time by build_native_app.sh (-DTYPEWHALE_VERSION / -DTYPEWHALE_BUILD).
// Fallbacks keep the file compilable on its own.
#ifndef TYPEWHALE_VERSION
#define TYPEWHALE_VERSION "0.0.0"
#endif
#ifndef TYPEWHALE_BUILD
#define TYPEWHALE_BUILD "0"
#endif

// Logs live under ~/Library/Logs/TypeWhale/<YYYY-MM-DD>/<version>-<build>.log so each
// day is a folder and each build of the day is one file. A latest.log symlink in the
// base folder always points at the current build's file (stable entry point for tooling).
// Both this dependency-free C path and Swift LaunchDiagnostics must agree on this layout.
static void typewhale_probe_log_path(char *out, size_t out_size) {
    const char *home = getenv("HOME");
    if (home == NULL || home[0] == '\0') {
        home = "/tmp";
    }
    char base[700];
    snprintf(base, sizeof(base), "%s/Library/Logs/TypeWhale", home);
    mkdir(base, 0755);

    char day[16];
    time_t now = time(NULL);
    struct tm tm_buf;
    if (localtime_r(&now, &tm_buf) != NULL) {
        strftime(day, sizeof(day), "%Y-%m-%d", &tm_buf);
    } else {
        strncpy(day, "unknown", sizeof(day));
        day[sizeof(day) - 1] = '\0';
    }

    char daydir[768];
    snprintf(daydir, sizeof(daydir), "%s/%s", base, day);
    mkdir(daydir, 0755);

    snprintf(out, out_size, "%s/%s-%s.log", daydir, TYPEWHALE_VERSION, TYPEWHALE_BUILD);

    // Best-effort: refresh latest.log -> current build's file.
    char latest[768];
    snprintf(latest, sizeof(latest), "%s/latest.log", base);
    unlink(latest);
    symlink(out, latest);
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
