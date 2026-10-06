#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HEADER="$ROOT/native/TypeSpeakerNativeASR.h"
CFILE="$ROOT/native/TypeSpeakerNativeASR.c"
SWIFT="$ROOT/native/Sources/Infrastructure/ASR/SenseVoiceASR.swift"

grep -Fq 'typedef struct TypeSpeakerNativeRecognitionResult' "$HEADER"
grep -Fq 'TypeSpeakerNativeRecognizerTranscribeDetailed' "$HEADER"
grep -Fq 'TypeSpeakerNativeRecognitionResultFree' "$HEADER"
grep -Fq 'result->tokens_arr' "$CFILE"
grep -Fq 'result->timestamps' "$CFILE"
grep -Fq 'native_result->tokens' "$CFILE"
grep -Fq 'native_result->timestamps' "$CFILE"
grep -Fq 'func transcribeDetailed(' "$SWIFT"
grep -Fq 'validatedTokenTimestamps' "$SWIFT"
grep -Fq 'markRecoveryRequested' "$ROOT/native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift"

echo "NativeStructuredRecognitionBoundaryCheck passed"
