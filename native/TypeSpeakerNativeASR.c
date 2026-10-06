#include "TypeSpeakerNativeASR.h"

#include <stdlib.h>
#include <string.h>

#include "sherpa-onnx/c-api/c-api.h"

typedef struct TypeSpeakerNativeRecognizerState {
  const SherpaOnnxOfflineRecognizer *recognizer;
  const SherpaOnnxOnlineRecognizer *online_recognizer;
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

// 缓存 Silero VAD 检测器：录音时每秒会多次判断有无人声，逐次 Create/Destroy 会话开销大。
// 这里按模型路径缓存复用，每次使用前 Reset 清空内部状态。所有调用都走同一个串行队列，无并发问题。
static const SherpaOnnxVoiceActivityDetector *g_cached_vad = NULL;
static char *g_cached_vad_model = NULL;

static const SherpaOnnxVoiceActivityDetector *acquire_cached_vad(const char *model_path) {
  if (g_cached_vad != NULL && g_cached_vad_model != NULL &&
      strcmp(g_cached_vad_model, model_path) == 0) {
    SherpaOnnxVoiceActivityDetectorReset(g_cached_vad);
    return g_cached_vad;
  }
  if (g_cached_vad != NULL) {
    SherpaOnnxDestroyVoiceActivityDetector(g_cached_vad);
    g_cached_vad = NULL;
  }
  if (g_cached_vad_model != NULL) {
    free(g_cached_vad_model);
    g_cached_vad_model = NULL;
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
    return NULL;
  }
  g_cached_vad = vad;
  g_cached_vad_model = strdup(model_path);
  return vad;
}

// 在指定采样率的 PCM 上跑一次 Silero VAD，必要时重采样到 16k。返回 1=有人声 0=无 -1=出错。
static int vad_detect_at_rate(
    const SherpaOnnxVoiceActivityDetector *vad,
    const float *samples,
    int32_t num_samples,
    int32_t sample_rate,
    char **error_message) {
  if (sample_rate == 16000) {
    return vad_accept_samples(vad, samples, num_samples);
  }
  const int32_t input_rate = sample_rate;
  const int32_t output_rate = 16000;
  const int32_t min_rate = input_rate < output_rate ? input_rate : output_rate;
  const SherpaOnnxLinearResampler *resampler =
      SherpaOnnxCreateLinearResampler(
          input_rate, output_rate, 0.99f * 0.5f * (float)min_rate, 6);
  if (resampler == NULL) {
    set_error(error_message, "无法创建 VAD 重采样器");
    return -1;
  }
  const SherpaOnnxResampleOut *resampled =
      SherpaOnnxLinearResamplerResample(resampler, samples, num_samples, 1);
  if (resampled == NULL) {
    SherpaOnnxDestroyLinearResampler(resampler);
    set_error(error_message, "无法重采样音频以进行 VAD 检测");
    return -1;
  }
  int has_speech = vad_accept_samples(vad, resampled->samples, resampled->n);
  SherpaOnnxLinearResamplerResampleFree(resampled);
  SherpaOnnxDestroyLinearResampler(resampler);
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

  const SherpaOnnxVoiceActivityDetector *vad = acquire_cached_vad(model_path);
  if (vad == NULL) {
    SherpaOnnxFreeWave(wave);
    set_error(error_message, "无法创建 Silero VAD 检测器");
    return -1;
  }

  int has_speech = vad_detect_at_rate(
      vad, wave->samples, wave->num_samples, wave->sample_rate, error_message);
  SherpaOnnxFreeWave(wave);
  return has_speech;
}

// 实时门控：在内存中的一小段 PCM（通常为最近 ~0.7s 的单声道）上跑 Silero，
// 用作录音过程中"当前是否有人声"的权威信号，驱动停顿/自动结束。无需写文件。
int TypeSpeakerNativeVadHasSpeechSamples(
    const float *samples,
    int32_t num_samples,
    int32_t sample_rate,
    const char *model_path,
    char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (samples == NULL || num_samples <= 0) {
    set_error(error_message, "缺少需要检测的人声音频数据");
    return -1;
  }
  if (sample_rate <= 0) {
    set_error(error_message, "无效的采样率");
    return -1;
  }
  if (model_path == NULL || model_path[0] == '\0') {
    set_error(error_message, "缺少 Silero VAD 模型");
    return -1;
  }
  const SherpaOnnxVoiceActivityDetector *vad = acquire_cached_vad(model_path);
  if (vad == NULL) {
    set_error(error_message, "无法创建 Silero VAD 检测器");
    return -1;
  }
  return vad_detect_at_rate(vad, samples, num_samples, sample_rate, error_message);
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
  config.model_config.num_threads = 3;
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

TypeSpeakerNativeRecognizer TypeSpeakerNativeParakeetRecognizerCreate(
    const char *encoder_path,
    const char *decoder_path,
    const char *joiner_path,
    const char *tokens_path,
    const char *hotwords,
    char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (encoder_path == NULL || encoder_path[0] == '\0' ||
      decoder_path == NULL || decoder_path[0] == '\0' ||
      joiner_path == NULL || joiner_path[0] == '\0' ||
      tokens_path == NULL || tokens_path[0] == '\0') {
    set_error(error_message, "缺少 Parakeet TDT 模型文件");
    return NULL;
  }

  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.transducer.encoder = encoder_path;
  config.model_config.transducer.decoder = decoder_path;
  config.model_config.transducer.joiner = joiner_path;
  config.model_config.tokens = tokens_path;
  config.model_config.model_type = "nemo_transducer";
  config.model_config.num_threads = 3;
  config.model_config.provider = "cpu";
  config.decoding_method = "greedy_search";

  const SherpaOnnxOfflineRecognizer *recognizer =
      SherpaOnnxCreateOfflineRecognizer(&config);
  if (recognizer == NULL) {
    set_error(error_message, "无法创建原生 Parakeet TDT 识别器");
    return NULL;
  }
  TypeSpeakerNativeRecognizerState *state =
      (TypeSpeakerNativeRecognizerState *)calloc(1, sizeof(TypeSpeakerNativeRecognizerState));
  if (state == NULL) {
    SherpaOnnxDestroyOfflineRecognizer(recognizer);
    set_error(error_message, "无法分配原生 Parakeet TDT 状态");
    return NULL;
  }
  state->recognizer = recognizer;
  state->hotwords = hotwords != NULL && hotwords[0] != '\0' ? strdup(hotwords) : NULL;
  return (TypeSpeakerNativeRecognizer)state;
}

static char *transcribe_online(
    TypeSpeakerNativeRecognizerState *state,
    const float *samples,
    int32_t num_samples,
    int32_t sample_rate,
    char **error_message) {
  if (state->online_recognizer == NULL) {
    set_error(error_message, "原生在线识别器状态无效");
    return NULL;
  }

  const SherpaOnnxOnlineStream *stream =
      state->hotwords != NULL && state->hotwords[0] != '\0'
          ? SherpaOnnxCreateOnlineStreamWithHotwords(state->online_recognizer, state->hotwords)
          : SherpaOnnxCreateOnlineStream(state->online_recognizer);
  if (stream == NULL) {
    set_error(error_message, "无法创建原生在线识别任务");
    return NULL;
  }

  SherpaOnnxOnlineStreamAcceptWaveform(
      stream, sample_rate, samples, num_samples);
  int32_t tail_samples = sample_rate > 0 ? sample_rate / 2 : 8000;
  float *tail = (float *)calloc((size_t)tail_samples, sizeof(float));
  if (tail != NULL) {
    SherpaOnnxOnlineStreamAcceptWaveform(stream, sample_rate, tail, tail_samples);
    free(tail);
  }

  int32_t guard = 0;
  while (SherpaOnnxIsOnlineStreamReady(state->online_recognizer, stream) && guard < 10000) {
    SherpaOnnxDecodeOnlineStream(state->online_recognizer, stream);
    guard += 1;
  }
  const SherpaOnnxOnlineRecognizerResult *result =
      SherpaOnnxGetOnlineStreamResult(state->online_recognizer, stream);
  char *text = result != NULL && result->text != NULL ? strdup(result->text) : strdup("");

  if (result != NULL) {
    SherpaOnnxDestroyOnlineRecognizerResult(result);
  }
  SherpaOnnxDestroyOnlineStream(stream);
  return text;
}

static char *transcribe_offline(
    TypeSpeakerNativeRecognizerState *state,
    const float *samples,
    int32_t num_samples,
    int32_t sample_rate,
    const char *language,
    char **error_message) {
  if (state->recognizer == NULL) {
    return transcribe_online(state, samples, num_samples, sample_rate, error_message);
  }

  const SherpaOnnxOfflineStream *stream =
      state->hotwords != NULL && state->hotwords[0] != '\0'
          ? SherpaOnnxCreateOfflineStreamWithHotwords(state->recognizer, state->hotwords)
          : SherpaOnnxCreateOfflineStream(state->recognizer);
  if (stream == NULL) {
    set_error(error_message, "无法创建原生识别任务");
    return NULL;
  }
  const char *stream_language = language != NULL && language[0] != '\0'
                                    ? language
                                    : sense_voice_language();
  SherpaOnnxOfflineStreamSetOption(stream, "language", stream_language);

  SherpaOnnxAcceptWaveformOffline(stream, sample_rate, samples, num_samples);
  SherpaOnnxDecodeOfflineStream(state->recognizer, stream);
  const SherpaOnnxOfflineRecognizerResult *result =
      SherpaOnnxGetOfflineStreamResult(stream);
  char *text = result != NULL && result->text != NULL ? strdup(result->text) : strdup("");

  if (result != NULL) {
    SherpaOnnxDestroyOfflineRecognizerResult(result);
  }
  SherpaOnnxDestroyOfflineStream(stream);
  return text;
}

char *TypeSpeakerNativeRecognizerTranscribeSamples(
    TypeSpeakerNativeRecognizer recognizer,
    const float *samples,
    int num_samples,
    int sample_rate,
    const char *language,
    char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (recognizer == NULL) {
    set_error(error_message, "原生 SenseVoice 识别器尚未初始化");
    return NULL;
  }
  if (samples == NULL || num_samples <= 0 || sample_rate <= 0) {
    set_error(error_message, "原生语音识别 samples 无效");
    return NULL;
  }
  TypeSpeakerNativeRecognizerState *state =
      (TypeSpeakerNativeRecognizerState *)recognizer;
  return transcribe_offline(
      state, samples, (int32_t)num_samples, (int32_t)sample_rate, language, error_message);
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
  const SherpaOnnxWave *wave = SherpaOnnxReadWave(audio_path);
  if (wave == NULL) {
    set_error(error_message, "无法读取录音 WAV 文件");
    return NULL;
  }
  char *text = transcribe_offline(
      state,
      wave->samples,
      wave->num_samples,
      wave->sample_rate,
      language,
      error_message);
  SherpaOnnxFreeWave(wave);
  return text;
}

TypeSpeakerNativeRecognitionResult *TypeSpeakerNativeRecognizerTranscribeDetailed(
    TypeSpeakerNativeRecognizer recognizer,
    const char *audio_path,
    const char *language,
    char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (recognizer == NULL || audio_path == NULL) {
    set_error(error_message, "原生 SenseVoice 识别器或音频路径无效");
    return NULL;
  }
  TypeSpeakerNativeRecognizerState *state =
      (TypeSpeakerNativeRecognizerState *)recognizer;
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

  TypeSpeakerNativeRecognitionResult *native_result =
      (TypeSpeakerNativeRecognitionResult *)calloc(1, sizeof(TypeSpeakerNativeRecognitionResult));
  if (native_result == NULL) {
    set_error(error_message, "无法分配结构化识别结果");
  } else {
    native_result->text = strdup(result != NULL && result->text != NULL ? result->text : "");
    if (native_result->text == NULL) {
      TypeSpeakerNativeRecognitionResultFree(native_result);
      native_result = NULL;
      set_error(error_message, "无法分配识别文本结果");
    } else if (result != NULL && result->count > 0 && result->tokens_arr != NULL) {
      native_result->count = result->count;
      native_result->tokens = (char **)calloc((size_t)result->count, sizeof(char *));
      if (native_result->tokens == NULL) {
        TypeSpeakerNativeRecognitionResultFree(native_result);
        native_result = NULL;
        set_error(error_message, "无法分配识别词元结果");
      } else {
        int allocation_failed = 0;
        for (int32_t i = 0; i < result->count; ++i) {
          native_result->tokens[i] = strdup(result->tokens_arr[i] != NULL ? result->tokens_arr[i] : "");
          if (native_result->tokens[i] == NULL) {
            allocation_failed = 1;
            break;
          }
        }
        if (!allocation_failed && result->timestamps != NULL) {
          native_result->timestamps = (float *)calloc((size_t)result->count, sizeof(float));
          if (native_result->timestamps != NULL) {
            memcpy(native_result->timestamps, result->timestamps, (size_t)result->count * sizeof(float));
          } else {
            allocation_failed = 1;
          }
        }
        if (allocation_failed) {
          TypeSpeakerNativeRecognitionResultFree(native_result);
          native_result = NULL;
          set_error(error_message, "无法分配结构化识别词元或时间戳");
        }
      }
    }
  }

  if (result != NULL) {
    SherpaOnnxDestroyOfflineRecognizerResult(result);
  }
  SherpaOnnxDestroyOfflineStream(stream);
  SherpaOnnxFreeWave(wave);
  return native_result;
}

void TypeSpeakerNativeRecognitionResultFree(TypeSpeakerNativeRecognitionResult *result) {
  if (result == NULL) {
    return;
  }
  free(result->text);
  if (result->tokens != NULL) {
    for (int32_t i = 0; i < result->count; ++i) {
      free(result->tokens[i]);
    }
  }
  free(result->tokens);
  free(result->timestamps);
  free(result);
}

void TypeSpeakerNativeRecognizerDestroy(TypeSpeakerNativeRecognizer recognizer) {
  if (recognizer != NULL) {
    TypeSpeakerNativeRecognizerState *state =
        (TypeSpeakerNativeRecognizerState *)recognizer;
    if (state->recognizer != NULL) {
      SherpaOnnxDestroyOfflineRecognizer(state->recognizer);
    }
    if (state->online_recognizer != NULL) {
      SherpaOnnxDestroyOnlineRecognizer(state->online_recognizer);
    }
    free(state->hotwords);
    free(state);
  }
}

void TypeSpeakerNativeReleaseCachedResources(void) {
  if (g_cached_vad != NULL) {
    SherpaOnnxDestroyVoiceActivityDetector(g_cached_vad);
    g_cached_vad = NULL;
  }
  if (g_cached_vad_model != NULL) {
    free(g_cached_vad_model);
    g_cached_vad_model = NULL;
  }
}

void TypeSpeakerNativeStringFree(char *value) {
  free(value);
}
