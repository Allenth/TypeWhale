#ifndef TYPESPEAKER_NATIVE_ASR_H
#define TYPESPEAKER_NATIVE_ASR_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void *TypeSpeakerNativeRecognizer;

TypeSpeakerNativeRecognizer TypeSpeakerNativeRecognizerCreate(
    const char *model_path,
    const char *tokens_path,
    const char *hotwords,
    char **error_message
);

TypeSpeakerNativeRecognizer TypeSpeakerNativeQwen3RecognizerCreate(
    const char *model_dir,
    const char *hotwords,
    char **error_message
);

char *TypeSpeakerNativeRecognizerTranscribe(
    TypeSpeakerNativeRecognizer recognizer,
    const char *audio_path,
    const char *language,
    char **error_message
);

int TypeSpeakerNativeVadHasSpeech(
    const char *audio_path,
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
