#ifndef TYPESPEAKER_NATIVE_ASR_H
#define TYPESPEAKER_NATIVE_ASR_H

#include <stdint.h>

#ifdef __OBJC__
#include "SystemMediaRemoteBridge.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void *TypeSpeakerNativeRecognizer;

typedef struct TypeSpeakerNativeRecognitionResult {
    char *text;
    char **tokens;
    float *timestamps;
    int32_t count;
} TypeSpeakerNativeRecognitionResult;

TypeSpeakerNativeRecognizer TypeSpeakerNativeRecognizerCreate(
    const char *model_path,
    const char *tokens_path,
    const char *hotwords,
    char **error_message
);

TypeSpeakerNativeRecognizer TypeSpeakerNativeParakeetRecognizerCreate(
    const char *encoder_path,
    const char *decoder_path,
    const char *joiner_path,
    const char *tokens_path,
    const char *hotwords,
    char **error_message
);

char *TypeSpeakerNativeRecognizerTranscribe(
    TypeSpeakerNativeRecognizer recognizer,
    const char *audio_path,
    const char *language,
    char **error_message
);

char *TypeSpeakerNativeRecognizerTranscribeSamples(
    TypeSpeakerNativeRecognizer recognizer,
    const float *samples,
    int num_samples,
    int sample_rate,
    const char *language,
    char **error_message
);

TypeSpeakerNativeRecognitionResult *TypeSpeakerNativeRecognizerTranscribeDetailed(
    TypeSpeakerNativeRecognizer recognizer,
    const char *audio_path,
    const char *language,
    char **error_message
);

void TypeSpeakerNativeRecognitionResultFree(TypeSpeakerNativeRecognitionResult *result);

int TypeSpeakerNativeVadHasSpeech(
    const char *audio_path,
    const char *model_path,
    char **error_message
);

int TypeSpeakerNativeVadHasSpeechSamples(
    const float *samples,
    int num_samples,
    int sample_rate,
    const char *model_path,
    char **error_message
);

void TypeSpeakerNativeRecognizerDestroy(TypeSpeakerNativeRecognizer recognizer);
void TypeSpeakerNativeReleaseCachedResources(void);
void TypeSpeakerNativeStringFree(char *value);

// Defined in LaunchProbe.c. Declared here so Swift (via this bridging header)
// can funnel crash-handler output through the same dependency-free POSIX logger.
void typewhale_launch_probe_log(const char *message);

#ifdef __cplusplus
}
#endif

#endif
