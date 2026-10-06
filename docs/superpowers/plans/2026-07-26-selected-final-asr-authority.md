# Selected Final ASR Authority Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the ASR model selected in the UI actually owns final recognition.

**Architecture:** SenseVoice remains the low-latency realtime preview provider. Final recognition becomes selected-backend aware: SenseVoice may reuse its own complete cache, while selecting Fun-ASR Nano or another non-SenseVoice backend always runs only that backend on the completed recording. A selected model's failure is surfaced as failure with no SenseVoice or realtime-cache fallback.

**Tech Stack:** Swift 6/AppKit, FunASR managed worker, sherpa-onnx SenseVoice realtime cache, executable Swift/Python regression checks, TypeWhale native build scripts.

## Global Constraints

- Choosing `Fun-ASR Nano` must never silently deliver SenseVoice cache as if Fun-ASR produced it.
- SenseVoice remains responsible for realtime preview; do not increase capsule preview latency.
- This plan does not change Qwen rewrite behavior.
- Non-SenseVoice models are evaluation targets: preserve their real text, real failure, and real latency without fallback.
- If the selected model fails, show “识别失败”, deliver no text, and perform no automatic paste.
- Do not require the user to start Terminal or install Python; the managed worker remains internal to the App.
- Do not commit the user recording `recording_20260726_090909_259A29C0.wav`.
- Code changes require RED → GREEN checks, review, build-number increment, installed-App verification, documentation update, and a scoped commit.

---

### Task 1: Make final recognition authority depend on the selected backend

**Files:**
- Create: `native/Sources/Application/FinalRecognitionAuthorityPolicy.swift`
- Create: `native/Tests/FinalRecognitionAuthorityPolicyCheck.swift`
- Modify: `native/Sources/Application/FinalRecognitionUseCase.swift`
- Modify: `native/Tests/FinalRecognitionUseCaseCheck.swift`
- Modify: `native/Sources/Application/ProviderAwareFinalASR.swift`
- Modify: `native/Tests/ProviderAwareFinalASRCheck.swift`

**Interfaces:**
- Consumes: `ASRConfiguration.backend`, `reRecognizeWholeRecordingAfterStop`, and whether the SenseVoice realtime cache is meaningful.
- Produces: `FinalRecognitionAuthorityPolicy.Action`.
- Routes: `.runSelectedBackend` through the existing `ProviderAwareFinalASR`, which already maps `.funASRNano` to the Fun-ASR provider.
- Fails closed: a non-SenseVoice provider error returns `.failed` and never invokes SenseVoice.

- [x] **Step 1: Write the failing authority-policy check**

  Define a minimal test-only `ASRBackend` enum and assert:

  ```swift
  precondition(action(backend: .senseVoice, forceFull: false, cacheReady: true) == .useRealtimeCache)
  precondition(action(backend: .senseVoice, forceFull: true, cacheReady: true) == .runSelectedBackend)
  precondition(action(backend: .funASRNano, forceFull: false, cacheReady: true) == .runSelectedBackend)
  precondition(action(backend: .funASRNano, forceFull: false, cacheReady: false) == .runSelectedBackend)
  ```

- [x] **Step 2: Run the new check and verify RED**

  ```bash
  xcrun swiftc -parse-as-library \
    native/Sources/Application/FinalRecognitionAuthorityPolicy.swift \
    native/Tests/FinalRecognitionAuthorityPolicyCheck.swift \
    -o /tmp/FinalRecognitionAuthorityPolicyCheck
  ```

  Expected: compilation fails because the production policy does not exist.

- [x] **Step 3: Implement the pure authority policy**

  ```swift
  enum FinalRecognitionAuthorityPolicy {
      enum Action: Equatable {
          case useRealtimeCache
          case runSelectedBackend
      }

      static func action(
          backend: ASRBackend,
          reRecognizeWholeRecordingAfterStop: Bool,
          realtimeCacheReady: Bool
      ) -> Action {
          guard backend == .senseVoice,
                !reRecognizeWholeRecordingAfterStop,
                realtimeCacheReady else {
              return .runSelectedBackend
          }
          return .useRealtimeCache
      }
  }
  ```

- [x] **Step 4: Replace the unconditional realtime-cache shortcut**

  In `FinalRecognitionUseCase.recognize`, replace the current condition based only on
  `reRecognizeWholeRecordingAfterStop` with:

  ```swift
  let authority = FinalRecognitionAuthorityPolicy.action(
      backend: request.configuration.backend,
      reRecognizeWholeRecordingAfterStop: request.reRecognizeWholeRecordingAfterStop,
      realtimeCacheReady: isMeaningfulRecognitionText(completeCacheText)
  )

  if authority == .useRealtimeCache {
      completion(.recognized(FinalRecognitionResult(
          text: completeCacheText,
          recognitionSeconds: 0,
          engine: request.completeRealtimeCacheEngine
      )))
      return
  }

  transcriber.transcribe(
      audio: request.audioURL,
      configuration: request.configuration
  ) { response in
      completion(Self.resolve(
          response,
          languageMode: request.configuration.languageMode,
          completeRealtimeCacheText: completeCacheText
      ))
  }
  ```

  Remove the old `guard request.reRecognizeWholeRecordingAfterStop else` branch.

- [x] **Step 5: Remove provider-level SenseVoice fallback**

  Replace `ProviderAwareFinalASR.fallback(...)` for non-SenseVoice backends with an
  explicit failure:

  ```swift
  private func failSelectedProvider(
      backend: ASRBackend,
      reason: String,
      completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
      LaunchDiagnostics.mark(
          "final_asr_failed selected_backend=\(String(describing: backend)) reason=\(reason)"
      )
      completion(.failure(NSError(
          domain: "com.waykingah.typewhale.provider-aware-asr",
          code: 3,
          userInfo: [
              NSLocalizedDescriptionKey:
                  "所选识别模型运行失败：\(reason)"
          ]
      )))
  }
  ```

  Use this path for model unavailable, worker unavailable, warm-up failure, and
  transcription failure. Do not call `senseVoice.transcribe` from these branches.

- [x] **Step 6: Add authority and failure regressions**

  Extend the lightweight test configuration with `backend: ASRBackend`, then assert:

  ```swift
  // Fun-ASR selected: full final transcriber must run even when the switch is off.
  precondition(funASRFake.transcribeCallCount == 1)
  precondition(funASRResult.engine == "fun-asr-nano-2512/funasr-python")

  // SenseVoice selected: valid realtime cache may remain the fast final path.
  precondition(senseVoiceFake.transcribeCallCount == 0)
  precondition(senseVoiceResult.engine == "realtime-preview-delivery-cache")

  // Fun-ASR failure must remain a failure and must not invoke SenseVoice.
  guard case .failure = failedFunASRResult else {
      preconditionFailure("selected provider failure must be surfaced")
  }
  precondition(senseVoice.callCount == 1, "only the explicit SenseVoice test may call SenseVoice")
  ```

- [x] **Step 7: Run the focused checks and verify GREEN**

  ```bash
  xcrun swiftc -parse-as-library \
    native/Sources/Application/FinalRecognitionAuthorityPolicy.swift \
    native/Tests/FinalRecognitionAuthorityPolicyCheck.swift \
    -o /tmp/FinalRecognitionAuthorityPolicyCheck &&
    /tmp/FinalRecognitionAuthorityPolicyCheck

  xcrun swiftc -parse-as-library \
    native/Sources/Domain/Text/RecognitionTextFilter.swift \
    native/Sources/Domain/Text/RecognitionTextNormalizer.swift \
    native/Sources/Application/FinalRecognitionAuthorityPolicy.swift \
    native/Sources/Application/FinalRecognitionUseCase.swift \
    native/Tests/FinalRecognitionUseCaseCheck.swift \
    -o /tmp/FinalRecognitionUseCaseCheck &&
    /tmp/FinalRecognitionUseCaseCheck

  xcrun swiftc -parse-as-library \
    native/Sources/Domain/ASRBenchmarkDomain.swift \
    native/Sources/Infrastructure/ASR/ASRHotwordEncoder.swift \
    native/Sources/Infrastructure/ASR/FunASRRuntimeManifest.swift \
    native/Sources/Infrastructure/ASR/ManagedFunASRRuntime.swift \
    native/Sources/Infrastructure/ASR/FunASRSidecarProtocol.swift \
    native/Sources/Infrastructure/ASR/FunASRSidecar.swift \
    native/Sources/Application/UnifiedLocalASRAdapter.swift \
    native/Sources/Application/ProviderAwareFinalASR.swift \
    native/Tests/ProviderAwareFinalASRCheck.swift \
    -o /tmp/ProviderAwareFinalASRCheck &&
    /tmp/ProviderAwareFinalASRCheck
  ```

  Expected: all checks print `passed`.

- [ ] **Step 8: Commit the authority change**

  ```bash
  git add \
    native/Sources/Application/FinalRecognitionAuthorityPolicy.swift \
    native/Sources/Application/FinalRecognitionUseCase.swift \
    native/Sources/Application/ProviderAwareFinalASR.swift \
    native/Tests/FinalRecognitionAuthorityPolicyCheck.swift \
    native/Tests/FinalRecognitionUseCaseCheck.swift \
    native/Tests/ProviderAwareFinalASRCheck.swift
  git commit -m "fix: honor selected final ASR backend"
  ```

---

### Task 2: Preserve the selected model's real result and timing

**Files:**
- Modify: `native/Sources/Application/FinalRecognitionUseCase.swift`
- Modify: `native/Tests/FinalRecognitionUseCaseCheck.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`

**Interfaces:**
- Consumes: completed WAV and the selected non-SenseVoice backend.
- Produces: the selected model's own text, empty result, or explicit failure.
- Logs: `selected_backend`, `executed_engine`, elapsed time, and failure reason without transcript plaintext.

- [x] **Step 1: Add failing strict-source regressions**

  Add a non-SenseVoice request whose fake final text is much shorter than the realtime
  cache. Assert that the short selected-model result remains authoritative:

  ```swift
  precondition(shortFunASROutcome.text == shortFunASRText)
  precondition(shortFunASROutcome.engine == "fun-asr-nano-2512/funasr-python")
  ```

  Add a failed non-SenseVoice request with a complete realtime cache:

  ```swift
  guard case .failed(let message) = failedFunASROutcome else {
      preconditionFailure("Fun-ASR failure must remain failure")
  }
  precondition(message.contains("所选识别模型运行失败"))
  ```

- [x] **Step 2: Run the use-case check and verify RED**

  Run the `FinalRecognitionUseCaseCheck` compile command from Task 1.

  Expected: the selected non-SenseVoice result is replaced by realtime cache, or the
  failed provider does not remain a failure.

- [x] **Step 3: Disable cache substitution for non-SenseVoice results**

  When resolving a selected non-SenseVoice result, do not pass SenseVoice realtime
  cache into `FinalRecognitionUseCase.resolve`:

  ```swift
  let fallbackText = request.configuration.backend == .senseVoice
      ? completeCacheText
      : ""

  completion(Self.resolve(
      response,
      languageMode: request.configuration.languageMode,
      completeRealtimeCacheText: fallbackText
  ))
  ```

  A short or incomplete Fun-ASR success must remain visible as Fun-ASR's own result;
  do not replace it using character-count comparisons.

- [x] **Step 4: Log the selected model and its real elapsed time**

  Extend the existing metadata-only diagnostics:

  ```swift
  LaunchDiagnostics.mark(
      "final_asr_result task_id=\(task.id.uuidString) " +
      "selected_backend=\(task.configuration.backend.rawValue) " +
      "executed_engine=\(result.engine) " +
      "audio_duration_ms=\(Int(task.duration * 1000)) " +
      "recognition_ms=\(Int(result.recognitionSeconds * 1000)) " +
      "chars=\(result.text.count)"
  )
  ```

  For failure, log `selected_backend`, `reason`, and elapsed milliseconds without
  transcript text.

- [x] **Step 5: Run strict-source and diagnostic checks**

  ```bash
  /tmp/FinalRecognitionUseCaseCheck
  bash native/Tests/FinalDeliveryLogBoundaryCheck.sh
  ```

  Expected: both pass.

---

### Task 3: Installed-App acceptance

**Files:**
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Tests/FinalRecognitionPreviewCacheDefaultCheck.sh`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

- [x] **Step 1: Update the setting explanation**

  ```text
  SenseVoice 可直接使用完整实时缓存以获得更快结果；选择其他识别模型时，
  停止录音后会自动运行所选模型，确保模型选择真实生效。
  ```

- [x] **Step 2: Run the complete focused suite**

  ```bash
  bash native/Tests/FinalRecognitionPreviewCacheDefaultCheck.sh
  bash native/Tests/FinalDeliveryLogBoundaryCheck.sh
  ```

  Re-run both Swift executables from Task 1. Expected: all checks pass.

- [x] **Step 3: Update architecture and release records**

  Record:

  ```text
  SenseVoice owns realtime preview. A selected non-SenseVoice backend must execute
  on the completed recording. Its success, empty result, failure, and elapsed time
  are reported without substitution by SenseVoice or realtime cache.
  ```

- [x] **Step 4: Build and install**

  ```bash
  ./native/build_and_log.sh
  ```

  Verify the incremented build in `/Applications/TypeWhale Pro.app`, signature
  validity, model-selection explanation, and process health.

- [ ] **Step 5: Perform real microphone acceptance**

  Disable smart rewrite to isolate ASR behavior. Select `Fun-ASR Nano`, leave
  “停止后重新识别整段录音” off, and make a normal recording.

  Pass criteria:

  - Log contains `selected_backend=funASRNano`.
  - Log contains `executed_engine=fun-asr-nano-2512/funasr-python`.
  - Fun-ASR worker is invoked exactly once per completed recording.
  - Final text is Fun-ASR's own result, even when it differs from realtime preview.
  - If Fun-ASR fails, the capsule shows “识别失败”, no text is delivered, and nothing is pasted.
  - SenseVoice call count does not increase after a Fun-ASR failure.
  - No transcript plaintext is written to diagnostic logs.

- [ ] **Step 6: Independent review and final commit**

  Review final-authority routing, real timing metadata, and strict failure behavior.
  After no Critical/Important findings remain, stage only this plan's files
  and commit:

  ```bash
  git commit -m "fix: align selected final ASR authority"
  ```

## Acceptance Summary

- Selecting Fun-ASR Nano always invokes Fun-ASR for final recognition.
- SenseVoice remains the realtime preview provider.
- SenseVoice cache cannot replace a selected model's output.
- A selected model failure shows “识别失败”, delivers no text, and performs no paste.
- The user never needs Terminal, Python, or a second login.
