#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
SHADOW_PRESENTER="$ROOT/native/Sources/Presentation/ShadowPreview/ShadowPreviewPresenter.swift"

if rg -n 'candidatePreviewCoordinator|candidatePreviewRuntime|productCandidateRuntime' "$COORDINATOR"; then
  echo "CandidatePreviewRetirementBoundaryCheck failed: candidate preview runtime still exists." >&2
  exit 1
fi

grep -Fq 'private let shadowPreviewCoordinator = ShadowPreviewCoordinator()' "$COORDINATOR"
grep -Fq 'private var shadowPreviewRuntime: ShadowTranscriptionRuntime?' "$COORDINATOR"
grep -Fq 'beginShadowAudioFrameDelivery(runtime: runtime, taskID: taskID)' "$COORDINATOR"
grep -Fq 'ShadowPreviewLayout.frame(' "$SHADOW_PRESENTER"
grep -Fq 'OnlineASRProviderFactory(' "$COORDINATOR"
grep -Fq 'MiMoSnapshotProvider(apiKey: key)' "$COORDINATOR"
grep -Fq 'DoubaoStreamingTransport(apiKey: key)' "$COORDINATOR"
grep -Fq 'let shadowRuntimeSnapshot = await runtime?.completeForDelivery()' "$COORDINATOR"
grep -Fq 'return (shadow: shadowRuntimeSnapshot, realtimePreviewDelivery: realtimePreviewDeliverySnapshot)' "$COORDINATOR"

test ! -d "$ROOT/native/Sources/Presentation/CandidatePreview"
test ! -f "$ROOT/native/Sources/Presentation/ShadowPreview/ThreeCapsuleLayout.swift"
test -f "$ROOT/native/Sources/Presentation/MinimalBlackPreview/MinimalBlackPreviewPresenter.swift"

if rg -n 'CandidatePreview(View|Presenter|Coordinator)|ThreeCapsuleLayout' "$ROOT/native/Sources"; then
  echo "CandidatePreviewRetirementBoundaryCheck failed: retired Presentation types remain." >&2
  exit 1
fi

if rg -n 'Candidate' "$ROOT/native/Sources/Presentation/MinimalBlackPreview"; then
  echo "CandidatePreviewRetirementBoundaryCheck failed: minimal-black production UI retained candidate naming." >&2
  exit 1
fi

if find "$ROOT/native/Tests" -maxdepth 1 -type f \
  \( -name 'CandidatePreview*' -o -name 'CandidateContentProjectionCheck.swift' \
     -o -name 'CandidatePresentationModelCheck.swift' -o -name 'CandidateProviderMatrixCheck.swift' \
     -o -name 'CandidateTextMotionCheck.swift' -o -name 'CandidateWindowUpdatePolicyCheck.swift' \
     -o -name 'ThreeCapsule*' -o -name 'Stage9AManualGateBoundaryCheck.sh' \) \
  ! -name 'CandidatePreviewRetirementBoundaryCheck.sh' \
  | grep -q .; then
  echo "CandidatePreviewRetirementBoundaryCheck failed: retired candidate UI tests remain." >&2
  exit 1
fi

echo "CandidatePreviewRetirementBoundaryCheck passed"
