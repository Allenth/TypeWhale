#import "SystemMediaRemoteBridge.h"

#import <dlfcn.h>

typedef void (*TWMediaRemoteGetPIDFunction)(dispatch_queue_t, void (^)(int));
typedef void (*TWMediaRemoteGetIsPlayingFunction)(dispatch_queue_t, void (^)(Boolean));

static const NSTimeInterval TWSystemMediaSnapshotTimeoutSeconds = 0.25;
static const char *TWMediaRemoteFrameworkPath =
    "/System/Library/PrivateFrameworks/MediaRemote.framework/Versions/A/MediaRemote";

static dispatch_queue_t TWSystemMediaQueryQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create(
            "com.waykingah.typewhale.system-media-state",
            DISPATCH_QUEUE_SERIAL
        );
    });
    return queue;
}

static void TWLoadMediaRemoteFunctions(
    TWMediaRemoteGetPIDFunction *getPID,
    TWMediaRemoteGetIsPlayingFunction *getIsPlaying
) {
    static void *frameworkHandle;
    static TWMediaRemoteGetPIDFunction storedGetPID;
    static TWMediaRemoteGetIsPlayingFunction storedGetIsPlaying;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        frameworkHandle = dlopen(TWMediaRemoteFrameworkPath, RTLD_LAZY | RTLD_LOCAL);
        if (frameworkHandle == NULL) {
            return;
        }
        storedGetPID = (TWMediaRemoteGetPIDFunction)dlsym(
            frameworkHandle,
            "MRMediaRemoteGetNowPlayingApplicationPID"
        );
        storedGetIsPlaying = (TWMediaRemoteGetIsPlayingFunction)dlsym(
            frameworkHandle,
            "MRMediaRemoteGetNowPlayingApplicationIsPlaying"
        );
    });
    *getPID = storedGetPID;
    *getIsPlaying = storedGetIsPlaying;
}

void TWSystemMediaFetchPlaybackSnapshot(
    TWSystemMediaPlaybackSnapshotCompletion completion
) {
    if (completion == nil) {
        return;
    }

    TWMediaRemoteGetPIDFunction getPID = NULL;
    TWMediaRemoteGetIsPlayingFunction getIsPlaying = NULL;
    TWLoadMediaRemoteFunctions(&getPID, &getIsPlaying);

    dispatch_queue_t queryQueue = TWSystemMediaQueryQueue();
    TWSystemMediaPlaybackSnapshotCompletion copiedCompletion = [completion copy];
    dispatch_async(queryQueue, ^{
        if (getPID == NULL || getIsPlaying == NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                copiedCompletion(TWSystemMediaPlaybackStateUnknown, 0);
            });
            return;
        }

        __block BOOL finished = NO;
        void (^finish)(TWSystemMediaPlaybackState, pid_t) = ^(
            TWSystemMediaPlaybackState state,
            pid_t processID
        ) {
            if (finished) {
                return;
            }
            finished = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                copiedCompletion(state, processID);
            });
        };

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(TWSystemMediaSnapshotTimeoutSeconds * NSEC_PER_SEC)
            ),
            queryQueue,
            ^{
                finish(TWSystemMediaPlaybackStateUnknown, 0);
            }
        );

        getPID(queryQueue, ^(int processIDBefore) {
            if (finished) {
                return;
            }
            if (processIDBefore <= 0) {
                finish(TWSystemMediaPlaybackStateUnknown, 0);
                return;
            }

            getIsPlaying(queryQueue, ^(Boolean isPlaying) {
                if (finished) {
                    return;
                }
                getPID(queryQueue, ^(int processIDAfter) {
                    if (finished) {
                        return;
                    }
                    if (processIDAfter <= 0 || processIDAfter != processIDBefore) {
                        finish(TWSystemMediaPlaybackStateUnknown, 0);
                        return;
                    }
                    finish(
                        isPlaying
                            ? TWSystemMediaPlaybackStatePlaying
                            : TWSystemMediaPlaybackStatePaused,
                        (pid_t)processIDAfter
                    );
                });
            });
        });
    });
}
