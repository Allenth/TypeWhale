#include "TypeSpeakerNativeASR.h"

#include <stdlib.h>
#include <string.h>

#include "sherpa-onnx/c-api/c-api.h"

typedef struct TypeSpeakerNativeRecognizerState {
  const SherpaOnnxOfflineRecognizer *recognizer;
  char *hotwords;
} TypeSpeakerNativeRecognizerState;

static void set_error(char **error_message, const char *message) {
  if (error_message == NULL) {
    return;
  }
  *error_message = strdup(message);
}

static const char *sense_voice_language(void) {
  const char *language = getenv("TYPEWHALE_SENSEVOICE_LANGUAGE");
  if (language != NULL && language[0] != '\0') {
    return language;
  }
  return "auto";
}

static char *join_path(const char *directory, const char *relative_path) {
  size_t directory_length = strlen(directory);
  size_t relative_length = strlen(relative_path);
  int needs_slash = directory_length > 0 && directory[directory_length - 1] != '/';
  char *result = (char *)calloc(directory_length + relative_length + (needs_slash ? 2 : 1), sizeof(char));
  if (result == NULL) {
    return NULL;
  }
  strcpy(result, directory);
  if (needs_slash) {
    strcat(result, "/");
  }
  strcat(result, relative_path);
  return result;
}

static int vad_accept_samples(
    const SherpaOnnxVoiceActivityDetector *vad,
    const float *samples,
    int32_t num_samples) {
  const int32_t window_size = 512;
  int32_t offset = 0;
  while (offset + window_size <= num_samples) {
    SherpaOnnxVoiceActivityDetectorAcceptWaveform(
        vad, samples + offset, window_size);
    offset += window_size;
  }
  if (offset < num_samples) {
    float tail[512];
    memset(tail, 0, sizeof(tail));
    memcpy(tail, samples + offset, sizeof(float) * (num_samples - offset));
    SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, tail, window_size);
  }
  SherpaOnnxVoiceActivityDetectorFlush(vad);
  int has_speech = SherpaOnnxVoiceActivityDetectorDetected(vad);
  while (!SherpaOnnxVoiceActivityDetectorEmpty(vad)) {
    const SherpaOnnxSpeechSegment *segment =
        SherpaOnnxVoiceActivityDetectorFront(vad);
    if (segment != NULL && segment->n > 0) {
      has_speech = 1;
    }
    if (segment != NULL) {
      SherpaOnnxDestroySpeechSegment(segment);
    }
    SherpaOnnxVoiceActivityDetectorPop(vad);
  }
  return has_speech;
}

int TypeSpeakerNativeVadHasSpeech(
    const char *audio_path,
    const char *model_path,
    char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (audio_path == NULL || audio_path[0] == '\0') {
    set_error(error_message, "缺少需要检测的人声音频文件");
    return -1;
  }
  if (model_path == NULL || model_path[0] == '\0') {
    set_error(error_message, "缺少 Silero VAD 模型");
    return -1;
  }

  const SherpaOnnxWave *wave = SherpaOnnxReadWave(audio_path);
  if (wave == NULL) {
    set_error(error_message, "无法读取录音 WAV 文件");
    return -1;
  }

  SherpaOnnxVadModelConfig config;
  memset(&config, 0, sizeof(config));
  config.silero_vad.model = model_path;
  config.silero_vad.threshold = 0.50f;
  config.silero_vad.min_silence_duration = 0.30f;
  config.silero_vad.min_speech_duration = 0.25f;
  config.silero_vad.max_speech_duration = 10.0f;
  config.silero_vad.window_size = 512;
  config.sample_rate = 16000;
  config.num_threads = 1;
  config.provider = "cpu";
  config.debug = 0;

  const SherpaOnnxVoiceActivityDetector *vad =
      SherpaOnnxCreateVoiceActivityDetector(&config, 30.0f);
  if (vad == NULL) {
    SherpaOnnxFreeWave(wave);
    set_error(error_message, "无法创建 Silero VAD 检测器");
    return -1;
  }

  int has_speech = 0;
  if (wave->sample_rate == 16000) {
    has_speech = vad_accept_samples(vad, wave->samples, wave->num_samples);
  } else {
    const int32_t input_rate = wave->sample_rate;
    const int32_t output_rate = 16000;
    const int32_t min_rate = input_rate < output_rate ? input_rate : output_rate;
    const SherpaOnnxLinearResampler *resampler =
        SherpaOnnxCreateLinearResampler(
            input_rate, output_rate, 0.99f * 0.5f * (float)min_rate, 6);
    if (resampler == NULL) {
      SherpaOnnxDestroyVoiceActivityDetector(vad);
      SherpaOnnxFreeWave(wave);
      set_error(error_message, "无法创建 VAD 重采样器");
      return -1;
    }
    const SherpaOnnxResampleOut *resampled =
        SherpaOnnxLinearResamplerResample(
            resampler, wave->samples, wave->num_samples, 1);
    if (resampled == NULL) {
      SherpaOnnxDestroyLinearResampler(resampler);
      SherpaOnnxDestroyVoiceActivityDetector(vad);
      SherpaOnnxFreeWave(wave);
      set_error(error_message, "无法重采样录音以进行 VAD 检测");
      return -1;
    }
    has_speech = vad_accept_samples(vad, resampled->samples, resampled->n);
    SherpaOnnxLinearResamplerResampleFree(resampled);
    SherpaOnnxDestroyLinearResampler(resampler);
  }

  SherpaOnnxDestroyVoiceActivityDetector(vad);
  SherpaOnnxFreeWave(wave);
  return has_speech ? 1 : 0;
}

TypeSpeakerNativeRecognizer TypeSpeakerNativeRecognizerCreate(
    const char *model_path,
    const char *tokens_path,
    const char *hotwords,
    char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }

  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.sense_voice.model = model_path;
  config.model_config.sense_voice.language = sense_voice_language();
  config.model_config.sense_voice.use_itn = 1;
  config.model_config.tokens = tokens_path;
  config.model_config.num_threads = 4;
  config.model_config.provider = "cpu";
  config.decoding_method = "greedy_search";

  const SherpaOnnxOfflineRecognizer *recognizer =
      SherpaOnnxCreateOfflineRecognizer(&config);
  if (recognizer == NULL) {
    set_error(error_message, "无法创建原生 SenseVoice 识别器");
    return NULL;
  }
  TypeSpeakerNativeRecognizerState *state =
      (TypeSpeakerNativeRecognizerState *)calloc(1, sizeof(TypeSpeakerNativeRecognizerState));
  if (state == NULL) {
    SherpaOnnxDestroyOfflineRecognizer(recognizer);
    set_error(error_message, "无法分配原生识别器状态");
    return NULL;
  }
  state->recognizer = recognizer;
  state->hotwords = hotwords != NULL && hotwords[0] != '\0' ? strdup(hotwords) : NULL;
  return (TypeSpeakerNativeRecognizer)state;
}

TypeSpeakerNativeRecognizer TypeSpeakerNativeQwen3RecognizerCreate(
    const char *model_dir,
    const char *hotwords,
    char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (model_dir == NULL || model_dir[0] == '\0') {
    set_error(error_message, "缺少 Qwen3-ASR 模型目录");
    return NULL;
  }

  char *conv_frontend = join_path(model_dir, "conv_frontend.onnx");
  char *encoder = join_path(model_dir, "encoder.int8.onnx");
  char *decoder = join_path(model_dir, "decoder.int8.onnx");
  char *tokenizer = join_path(model_dir, "tokenizer");
  if (conv_frontend == NULL || encoder == NULL || decoder == NULL || tokenizer == NULL) {
    free(conv_frontend);
    free(encoder);
    free(decoder);
    free(tokenizer);
    set_error(error_message, "无法分配 Qwen3-ASR 模型路径");
    return NULL;
  }

  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.qwen3_asr.conv_frontend = conv_frontend;
  config.model_config.qwen3_asr.encoder = encoder;
  config.model_config.qwen3_asr.decoder = decoder;
  config.model_config.qwen3_asr.tokenizer = tokenizer;
  config.model_config.qwen3_asr.max_total_len = 512;
  config.model_config.qwen3_asr.max_new_tokens = 256;
  config.model_config.qwen3_asr.hotwords =
      hotwords != NULL && hotwords[0] != '\0' ? hotwords : NULL;
  config.model_config.num_threads = 4;
  config.model_config.provider = "cpu";
  config.model_config.debug = 0;
  config.decoding_method = "greedy_search";

  const SherpaOnnxOfflineRecognizer *recognizer =
      SherpaOnnxCreateOfflineRecognizer(&config);
  free(conv_frontend);
  free(encoder);
  free(decoder);
  free(tokenizer);
  if (recognizer == NULL) {
    set_error(error_message, "无法创建原生 Qwen3-ASR 识别器");
    return NULL;
  }

  TypeSpeakerNativeRecognizerState *state =
      (TypeSpeakerNativeRecognizerState *)calloc(1, sizeof(TypeSpeakerNativeRecognizerState));
  if (state == NULL) {
    SherpaOnnxDestroyOfflineRecognizer(recognizer);
    set_error(error_message, "无法分配原生 Qwen3-ASR 状态");
    return NULL;
  }
  state->recognizer = recognizer;
  state->hotwords = hotwords != NULL && hotwords[0] != '\0' ? strdup(hotwords) : NULL;
  return (TypeSpeakerNativeRecognizer)state;
}

char *TypeSpeakerNativeRecognizerTranscribe(
    TypeSpeakerNativeRecognizer recognizer,
    const char *audio_path,
    const char *language,
    char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (recognizer == NULL) {
    set_error(error_message, "原生 SenseVoice 识别器尚未初始化");
    return NULL;
  }
  TypeSpeakerNativeRecognizerState *state =
      (TypeSpeakerNativeRecognizerState *)recognizer;
  if (state->recognizer == NULL) {
    set_error(error_message, "原生识别器状态无效");
    return NULL;
  }

  const SherpaOnnxWave *wave = SherpaOnnxReadWave(audio_path);
  if (wave == NULL) {
    set_error(error_message, "无法读取录音 WAV 文件");
    return NULL;
  }

  const SherpaOnnxOfflineStream *stream =
      state->hotwords != NULL && state->hotwords[0] != '\0'
          ? SherpaOnnxCreateOfflineStreamWithHotwords(state->recognizer, state->hotwords)
          : SherpaOnnxCreateOfflineStream(state->recognizer);
  if (stream == NULL) {
    SherpaOnnxFreeWave(wave);
    set_error(error_message, "无法创建原生识别任务");
    return NULL;
  }
  const char *stream_language = language != NULL && language[0] != '\0'
                                    ? language
                                    : sense_voice_language();
  SherpaOnnxOfflineStreamSetOption(stream, "language", stream_language);

  SherpaOnnxAcceptWaveformOffline(
      stream, wave->sample_rate, wave->samples, wave->num_samples);
  SherpaOnnxDecodeOfflineStream(state->recognizer, stream);
  const SherpaOnnxOfflineRecognizerResult *result =
      SherpaOnnxGetOfflineStreamResult(stream);
  char *text = result != NULL && result->text != NULL ? strdup(result->text) : strdup("");

  if (result != NULL) {
    SherpaOnnxDestroyOfflineRecognizerResult(result);
  }
  SherpaOnnxDestroyOfflineStream(stream);
  SherpaOnnxFreeWave(wave);
  return text;
}

void TypeSpeakerNativeRecognizerDestroy(TypeSpeakerNativeRecognizer recognizer) {
  if (recognizer != NULL) {
    TypeSpeakerNativeRecognizerState *state =
        (TypeSpeakerNativeRecognizerState *)recognizer;
    if (state->recognizer != NULL) {
      SherpaOnnxDestroyOfflineRecognizer(state->recognizer);
    }
    free(state->hotwords);
    free(state);
  }
}

void TypeSpeakerNativeStringFree(char *value) {
  free(value);
}
