# Local Model Health Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 TypeWhale Pro“模型”页加入一键本地模型检测，让用户能验证 Qwen3 4B 的真实导入、文件完整性、模型预热和最小生成，并复制不含用户正文的诊断信息。

**Architecture:** 新增一个与 AppKit 解耦的 `LocalModelHealthCheckService`，通过依赖注入顺序执行运行时探针、模型注册表校验、共享 Worker 预热和最小生成。运行时探针升级为真实 `import mlx_lm` 并返回结构化错误；UI 只把服务的阶段与报告投影为状态、按钮和诊断复制，不直接访问模型文件或 Python。正式整理、翻译与 ASR 路由保持不变。

**Tech Stack:** Swift/AppKit、Foundation `Process`、现有 JSONL MLX Worker 协议、CryptoKit 模型校验、shell 边界测试、`xcrun swiftc` 测试、TypeWhale 本地构建安装脚本。

## Global Constraints

- 只检测 TypeWhale 受管 Qwen3 4B；不检测 DeepSeek，不切换用户当前模型，不调用云端。
- 不自动下载、重装、升级或删除 Python、SciPy、MLX、模型文件或 Worker。
- 复用生产 Worker，避免第二份约 3 GB 模型；正式请求繁忙时立即返回 `runtime_busy`，不排队、不取消用户任务。
- 检测提示和生成正文不进入日志、诊断、剪贴板、最近转录或用量账本。
- 仅在用户点击“复制诊断”时写剪贴板。
- ASR、VAD、录音、翻译、截图、粘贴、自动发送和遥控器逻辑不改。
- 每个实现任务先看见针对性测试失败，再写最小实现并让测试通过。
- UI 完成后必须运行 `design-review`，并安排独立 subagent 做 UI/交互复核。
- 构建前重新检查分支、dirty 文件、构建进程和关键文件 mtime；发现并发重叠则停止写入和构建。
- 日常构建使用 `./native/build_and_log.sh`，递增 build 号、安装到 `/Applications/TypeWhale Pro.app`、打开验证；最终只提交本轮文件，不纳入受保护的未跟踪目录。

---

### Task 1: 把运行时校验升级为结构化真实导入探针

**Files:**

- Modify: `native/Sources/Infrastructure/SmartRewrite/ManagedMLXRuntimeLocator.swift`
- Modify: `native/Tests/ManagedMLXRuntimeLocatorCheck.swift`
- Create: `native/Tests/run_managed_mlx_runtime_locator_check.sh`

- [ ] **Step 1: 写失败测试**

  在 `ManagedMLXRuntimeLocatorCheck.swift` 中把注入验证器从 `Bool` 改为结构化结果，并覆盖：Python 缺失、包版本不匹配、`import mlx_lm` 动态库加载失败、真实导入成功。断言动态加载错误得到稳定码 `runtime_import_failed`、用户文案“运行环境与当前 macOS 不兼容”，且技术详情保留有界 stderr。

- [ ] **Step 2: 新建单测 runner 并确认 RED**

  `run_managed_mlx_runtime_locator_check.sh` 使用临时目录编译 `ManagedMLXRuntimeLocator.swift` 和测试文件：

  ```bash
  bash native/Tests/run_managed_mlx_runtime_locator_check.sh
  ```

  预期：因结构化探针类型和 `probe()` 尚不存在而编译失败。

- [ ] **Step 3: 实现最小结构化探针**

  在 locator 中加入：

  ```swift
  struct ManagedMLXRuntimeProbeResult: Equatable {
      let pythonURL: URL?
      let errorCode: String?
      let userMessage: String?
      let technicalDetail: String?
      var isReady: Bool { pythonURL != nil && errorCode == nil }
  }
  ```

  `probe()` 遍历原有两个候选目录；`verifyModules` 使用受管 Python 同时核对固定版本并执行 `import mlx_lm`。捕获非零退出码和最多 8 KB stderr，归类 `runtime_python_missing`、`runtime_version_mismatch`、`runtime_import_failed`、`runtime_probe_launch_failed`。动态库加载、`dlopen`、`Library not loaded` 等导入错误映射为面向用户的 macOS 不兼容文案。`state` 继续映射为现有 `.missing/.invalid/.ready`，保持调用方兼容。

- [ ] **Step 4: 运行测试并确认 GREEN**

  ```bash
  bash native/Tests/run_managed_mlx_runtime_locator_check.sh
  ```

- [ ] **Step 5: 检查探针隐私和边界**

  确认命令只导入固定模块，不读取用户目录正文；技术详情去除 NUL、控制字符并截断；不把 stderr 自动写入剪贴板或 UI。

---

### Task 2: 为 Worker 增加无抢占的忙碌状态和统一响应校验

**Files:**

- Modify: `native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMRuntime.swift`
- Create: `native/Sources/Infrastructure/SmartRewrite/ManagedLLMResponseValidator.swift`
- Modify: `native/Tests/ManagedMLXLLMRuntimeCheck.swift`
- Create: `native/Tests/ManagedLLMResponseValidatorCheck.swift`
- Create: `native/Tests/run_managed_llm_runtime_checks.sh`

- [ ] **Step 1: 写忙碌状态与响应校验失败测试**

  在运行时测试中启动一个会等待的 fake Worker 请求，断言请求执行期间 `hasActiveRequest == true`、取消或完成后恢复 `false`。在 validator 测试中覆盖协议版本错误、取消、`ok=false`、要求正文但为空，以及有效 warmup / generation。

- [ ] **Step 2: 运行测试并确认 RED**

  ```bash
  bash native/Tests/run_managed_llm_runtime_checks.sh
  ```

  预期：缺少 `ManagedLLMRuntimeActivityReporting`、`hasActiveRequest` 和 validator。

- [ ] **Step 3: 实现只读活动报告接口**

  新增可选协议，避免破坏所有测试 fake：

  ```swift
  protocol ManagedLLMRuntimeActivityReporting: AnyObject {
      var hasActiveRequest: Bool { get }
  }
  ```

  让 `ManagedMLXLLMRuntime` 遵守该协议；用现有 `stateLock` 读取 `activeRequestID`。不改变串行队列、取消、超时和崩溃重试语义。

- [ ] **Step 4: 实现统一响应校验器**

  `ManagedLLMResponseValidator.validate(_:requireFinalText:)` 依次检查协议版本、取消、`ok`、正文要求，返回 trim 后正文或抛出带 `errorCode/errorMessage` 的稳定错误。不得把 final text 拼进错误信息。

- [ ] **Step 5: 运行测试并确认 GREEN**

  ```bash
  bash native/Tests/run_managed_llm_runtime_checks.sh
  ```

---

### Task 3: TDD 实现本地模型健康检测服务

**Files:**

- Create: `native/Sources/Infrastructure/SmartRewrite/LocalModelHealthCheckService.swift`
- Create: `native/Tests/LocalModelHealthCheckServiceCheck.swift`
- Create: `native/Tests/run_local_model_health_check_service.sh`

- [ ] **Step 1: 定义测试所需的领域接口**

  测试先按以下公共语义编写：

  ```swift
  enum LocalModelHealthCheckStage: String {
      case runtimeImport, modelIntegrity, modelWarmup, minimalGeneration
  }

  struct LocalModelHealthCheckReport {
      let passed: Bool
      let failedStage: LocalModelHealthCheckStage?
      let errorCode: String?
      let userMessage: String
      let technicalDetail: String?
      let elapsedMS: Double
      let metrics: ManagedLLMMetrics?
      let diagnosticText: String
  }
  ```

  用 closures/fake runtime 注入四个阶段，记录阶段顺序和请求。

- [ ] **Step 2: 写完整失败测试并确认 RED**

  覆盖：

  - 顺序严格为 runtime → integrity → warmup → generation；
  - 任一阶段失败后不再执行后续阶段；
  - Worker 已忙返回 `runtime_busy`，零请求；
  - warmup `ok=false` 返回 `warmup_rejected`；
  - generation `ok=false` 返回 `generation_rejected`；
  - generation 空正文返回 `generation_empty`；
  - 成功保留总耗时及 metrics；
  - 请求固定使用受管模型目录和无用户正文的常量提示；
  - `diagnosticText` 不包含固定提示正文、生成正文、测试注入的用户文本或 `sk-` Key。

  ```bash
  bash native/Tests/run_local_model_health_check_service.sh
  ```

- [ ] **Step 3: 实现服务和依赖注入**

  服务构造依赖包括 runtime probe、registry readiness、共享 runtime、busy reader、model directory、App/OS metadata 和 monotonic clock。`run(onProgress:)` 顺序发出四个阶段，warmup 使用 `.warmup`，生成使用 `.rewrite`、固定短 system/user prompt 和 16–32 token 上限。每次 runtime 响应都经过 Task 2 validator。

- [ ] **Step 4: 建立稳定错误映射**

  至少支持 `runtime_busy`、`runtime_python_missing`、`runtime_version_mismatch`、`runtime_import_failed`、`model_missing`、`model_integrity_failed`、`warmup_rejected`、`generation_rejected`、`generation_empty`、`runtime_timeout`、`runtime_unavailable`。用户文案是可执行的中文；technical detail 只保留类型、稳定码和有界底层错误。

- [ ] **Step 5: 构造脱敏诊断文本**

  诊断包含 TypeWhale version/build、macOS version、模型 ID、阶段、结果、错误码、耗时、可用 metrics；不包含 prompt、final text、转录、Key 或任意录音路径。加入统一 sanitizer，清除控制字符并限制长度。

- [ ] **Step 6: 运行测试并确认 GREEN**

  ```bash
  bash native/Tests/run_local_model_health_check_service.sh
  ```

---

### Task 4: 修复后台预热把失败响应记成成功的问题

**Files:**

- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/ManagedLLMPrewarmResponseBoundaryCheck.sh`

- [ ] **Step 1: 写源码边界失败测试**

  测试要求 warmup 和 prefill 在记录 `warmup_done` / `prefill_done` 前调用统一 validator；失败路径必须记录 `warmup_failed` 或 `prefill_failed`，禁止 `ok=false` 继续成功日志。

- [ ] **Step 2: 运行测试并确认 RED**

  ```bash
  bash native/Tests/ManagedLLMPrewarmResponseBoundaryCheck.sh
  ```

- [ ] **Step 3: 接入统一校验**

  对两个 `runtime.perform` 结果分别校验。warmup 不要求正文，prefill 若 Worker 协议返回正文则按协议要求校验；失败进入现有 catch，记录稳定失败事件，不停止正式链路、不卸载模型。

- [ ] **Step 4: 运行测试并确认 GREEN**

  ```bash
  bash native/Tests/ManagedLLMPrewarmResponseBoundaryCheck.sh
  ```

---

### Task 5: 在模型页接入检测状态、按钮和诊断复制

**Files:**

- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Create: `native/Sources/Presentation/Main/MainViewController+LocalModelHealthCheck.swift`
- Create: `native/Tests/LocalModelHealthCheckUIBoundaryCheck.sh`
- Modify: `native/Tests/ManagedLLMModelPanelBoundaryCheck.sh`

- [ ] **Step 1: 写 UI 边界失败测试**

  断言源码中存在：模型页内联行、初始“尚未检测”说明、“开始检测”/“再次检测”、检测中禁用、复制诊断按钮、显式 `NSPasteboard.general` 写入、两个 accessibility label、主线程 UI 更新、Task 去重和窗口销毁时取消 UI Task。断言没有自动 repair/download、没有 DeepSeek 调用。

- [ ] **Step 2: 运行测试并确认 RED**

  ```bash
  bash native/Tests/LocalModelHealthCheckUIBoundaryCheck.sh
  bash native/Tests/ManagedLLMModelPanelBoundaryCheck.sh
  ```

- [ ] **Step 3: 增加控制器状态**

  增加状态标题/详情 label、开始检测按钮、复制诊断按钮、当前 Task 和最新 `diagnosticText`。初始复制按钮隐藏；详情 label 可换行且不通过颜色单独表达状态。

- [ ] **Step 4: 构建内联布局**

  在 `buildModelTabSmartAIModelContent()` 原下拉和说明之后加入 `optionRow("本地模型检测", actions)` 与最多三行详情。保留现有 240 pt 下拉宽度、卡片宽度、系统字体和主题色；窄宽时允许详情纵向增长，不让按钮挤压下拉框。

- [ ] **Step 5: 配置交互和可访问性**

  开始按钮 target/action 为 `runLocalModelHealthCheck`，复制按钮为 `copyLocalModelHealthDiagnostic`。accessibility label 分别为“检测本地整理模型”和“复制本地模型诊断”；检测中按钮标题“检测中”并禁用，结束后恢复“再次检测”。

- [ ] **Step 6: 将服务报告投影到 UI**

  新 extension 在 `@MainActor` 上管理状态；进度分别显示检查环境、校验模型、加载模型、验证生成。成功显示“本地模型正常 · 可用于智能整理”与总耗时；失败显示具体原因、建议及复制按钮。重复点击不创建第二个 Task。只在复制 action 中清空并写入 pasteboard，然后在页内给出“诊断已复制”。

- [ ] **Step 7: 运行 UI 边界测试并确认 GREEN**

  ```bash
  bash native/Tests/LocalModelHealthCheckUIBoundaryCheck.sh
  bash native/Tests/ManagedLLMModelPanelBoundaryCheck.sh
  ```

---

### Task 6: 跑自动化回归并处理编译问题

**Files:**

- Modify only if a test exposes an in-scope defect.

- [ ] **Step 1: 运行新增测试**

  ```bash
  bash native/Tests/run_managed_mlx_runtime_locator_check.sh
  bash native/Tests/run_managed_llm_runtime_checks.sh
  bash native/Tests/run_local_model_health_check_service.sh
  bash native/Tests/ManagedLLMPrewarmResponseBoundaryCheck.sh
  bash native/Tests/LocalModelHealthCheckUIBoundaryCheck.sh
  bash native/Tests/ManagedLLMModelPanelBoundaryCheck.sh
  ```

- [ ] **Step 2: 运行相邻回归**

  ```bash
  bash native/Tests/ManagedLLMLifecycleBoundaryCheck.sh
  bash native/Tests/run_smart_rewrite_prompt_contract_checks.sh
  ```

  另外按仓库现有 Swift runner 执行 `TypeWhaleLocalLLMEngineCheck.swift` 和 `ManagedMLXLLMRuntimeCheck.swift`；若无统一 runner，以 Task 2 新 runner 作为正式入口。

- [ ] **Step 3: 全量原生编译前检查**

  使用构建脚本覆盖的源码集合做一次编译；任何 unrelated failure 记录为独立风险，不顺手重构范围外模块。

---

### Task 7: 更新现行文档、版本历史和构建叙事

**Files:**

- Modify: `docs/current/PRODUCT.md`
- Modify: `docs/current/ARCHITECTURE.md`
- Modify: `docs/current/DESIGN.md`
- Modify: `docs/current/DEVELOPMENT_LOG.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Verify/update after build: `docs/current/README.md`
- Auto-updated by build: root version fields and `docs/构建日志.md` as applicable

- [ ] **Step 1: 更新产品与体验事实**

  PRODUCT 写明入口、四阶段和不修复边界；DESIGN 写明状态文案、按钮禁用、长错误、颜色非唯一信息；ARCHITECTURE 写明探针、共享 Worker、busy 策略、脱敏边界和预热 `ok` 校验。

- [ ] **Step 2: 更新开发日志状态**

  把该事项从“已决定，待实施”推进为“已实现，待安装版验证”，列出代码、测试和当前已知 macOS/SciPy 失败场景。不得把尚未执行的安装验证写成已验证。

- [ ] **Step 3: 预写应用内下一 build 历史**

  读取构建脚本当前 short version/build，按日常 build 规则新增精确的下一 build 条目，描述：一键真实检测、明确不兼容原因、修复 warmup 假成功。若并发导致 build 变化，按脚本提示重算并只改本轮条目。

- [ ] **Step 4: 检查文档链接和版本一致性**

  核对 `docs/current/README.md` 的版本/安装/提交快照，在构建完成后再写真实 build 和 commit 状态。

---

### Task 8: 构建、安装并验证真实故障与视觉状态

**Files:**

- Build-generated/version files only as produced by `./native/build_and_log.sh`.

- [ ] **Step 1: 执行并发安全复核**

  ```bash
  git branch --show-current
  git status --short
  pgrep -fl 'build_and_log|release_local_build|build_native_app|swiftc|xcodebuild' || true
  ```

  比较关键源文件、版本历史、构建脚本和日志 mtime。若出现另一会话进程或重叠 dirty 文件，立即停止构建并向用户报告。

- [ ] **Step 2: 执行日常构建安装**

  ```bash
  ./native/build_and_log.sh
  ```

  预期：short version 保持 2.0.58，build 从现场值递增一次，签名校验通过，覆盖 `/Applications/TypeWhale Pro.app` 并打开。

- [ ] **Step 3: 验证当前真实损坏运行时**

  打开“模型”页，点击“开始检测”。预期不进入模型文件/生成阶段，最终显示“运行环境与当前 macOS 不兼容”，并提供“复制诊断”。复制后核对 App/系统/模型/阶段/错误码存在，最近转录、固定 prompt、生成正文和 Key 不存在。

- [ ] **Step 4: 视觉与交互验证**

  深色和晨雾浅色主题各检查一次：布局无遮挡、长错误换行、按钮状态、重复点击、窗口仍可操作、VoiceOver label。截图或录屏保留在 `.artifacts/`，不提交受保护目录。

- [ ] **Step 5: 独立设计复核**

  完整执行 `design-review` skill，并按 AGENTS 要求安排独立 subagent 检查信息层级、间距、深浅主题、处理节奏、无闪烁/跳变、失败后的可理解性。只修复本功能范围内的问题并重新验证。

- [ ] **Step 6: 成功路径风险声明**

  当前机器运行时已知损坏，因此真实成功生成只能由自动化 fake Worker 覆盖；除非本轮另有兼容环境，最终明确说明成功路径未在真实模型上完成，不自动修复环境来伪造通过。

---

### Task 9: 完成最终核证与提交

**Files:**

- All files changed by Tasks 1–8, excluding protected unrelated untracked paths.

- [ ] **Step 1: 执行 verification-before-completion**

  重新运行新增与相邻回归测试，读取安装版 version/build，确认 App 进程来自 `/Applications/TypeWhale Pro.app`，核对签名和 UI 实测证据。不能依据旧输出声明通过。

- [ ] **Step 2: 复核 diff 和敏感信息**

  ```bash
  git diff --check
  git status --short
  git diff --stat
  git diff -- native/Sources native/Tests docs/current native/Sources/Presentation/VersionHistory
  ```

  搜索 prompt、用户文本、Key、绝对个人路径是否误入日志或诊断。确认 `.artifacts/`、`.claude/`、`.superpowers/`、`docs/stories/`、`docs/talks/` 未被 stage。

- [ ] **Step 3: 更新日志为真实验证状态**

  将 DEVELOPMENT_LOG 和 `docs/current/README.md` 改为最终 build、安装和验证事实；未完成项明确保留为未验证。

- [ ] **Step 4: 提交本轮交付**

  只 stage 本轮明确文件，提交信息建议：

  ```bash
  git commit -m "feat: add local model health check"
  ```

- [ ] **Step 5: 最终交付说明**

  用“改了什么 / 测试方案”说明入口、真实检测范围、当前机器实测结果、build/commit、自动化测试和真实成功路径限制。

## Plan Self-Review

- 设计稿中的四阶段、busy 策略、共享 Worker、脱敏诊断和不自动修复均有对应实现与测试任务。
- 预热假成功有独立修复和回归，不依赖 UI 测试间接覆盖。
- UI 既有源码边界测试，也有真实安装版深浅主题、长错误和可访问性复核。
- 模型成功路径由 fake Worker 自动化覆盖；当前损坏机器只用于验证准确失败，不用自动修复扩大范围。
- 文档、版本历史、build 安装、独立设计 review 和 git commit 均纳入交付门禁。
- 计划未包含占位符、未来决定或未经用户授权的自动修复动作。
