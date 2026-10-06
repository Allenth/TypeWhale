#ifndef TYPEWHALE_SYSTEM_MEDIA_REMOTE_BRIDGE_H
#define TYPEWHALE_SYSTEM_MEDIA_REMOTE_BRIDGE_H

#import <Foundation/Foundation.h>
#include <stdint.h>
#include <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(int32_t, TWSystemMediaPlaybackState) {
    TWSystemMediaPlaybackStateUnknown = 0,
    TWSystemMediaPlaybackStatePaused = 1,
    TWSystemMediaPlaybackStatePlaying = 2,
};

typedef void (^TWSystemMediaPlaybackSnapshotCompletion)(
    TWSystemMediaPlaybackState state,
    pid_t processID
);

FOUNDATION_EXPORT void TWSystemMediaFetchPlaybackSnapshot(
    TWSystemMediaPlaybackSnapshotCompletion completion
);

NS_ASSUME_NONNULL_END

#endif
