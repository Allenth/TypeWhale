# TypeWhale 遥控器动作平台 R0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 TypeWhale Pro Build 913 的 10 项动作、13 键默认值、已保存配置和任何输入行为的前提下，建立可版本化扩展的 Remote action descriptor、catalog、binding、trigger、executor port 与 v1→v2 迁移骨架。

**Architecture:** 保留 `RemoteButtonAction`、`setAction(_:for:)` 和现有 UI 回调作为 Build 913 兼容外壳；Domain 内将 `RemoteButtonMapping` 的内部真源改为 `RemoteBinding`，通过 `RemoteActionCatalog` 在稳定 action ID 与现有执行语义间转换。Application 的 dispatcher 只按动作 family 路由到分类型 executor port，既有闭包由小型 adapter 承接。Infrastructure 的 settings store 先读 v2、失败时迁移 v1，R0 正常保存同时写 v2 和可回滚的 v1，但迁移读取绝不覆盖原始 v1 数据。

**Tech Stack:** Swift 6 / AppKit / ApplicationServices、Foundation Codable/UserDefaults、zsh 独立可执行测试、TypeWhale 唯一本机构建入口。

## Global Constraints

- 基线：TypeWhale Pro 2.0.58 (Build 913)，代码提交 `d176bd59`，规格提交 `0b1cc8d`。
- R0 不新增用户可见动作、开关、搜索、风险弹窗或触发选项；菜单顺序、标题、默认值与执行结果必须逐项等同 Build 913。
- 不修改电脑 Fn 450ms 分类、RC003 F5 120ms/310s 抑制、ATVV `AUDIO_STOP`、电脑麦克风、ASR、正文写回、粘贴或自动发送取消语义。
- 不删除 `typewhale.remote.button-mapping.v1`；v2 根数据损坏时回退 v1，单个 v2 binding 损坏时只回退对应按钮。
- 不引入 `AnyCodable`、字符串 shell、任意 URL、48 项空 descriptor、手势计时器或新权限；payload 只提供当前无参数的版本化形状。
- Domain 不包含用户界面文案或系统 API；Presentation 不接触 UserDefaults、HID usage 或 CGEvent；Dispatcher 不承载动作 API 实现。
- 代码改动后必须更新现行文档和应用内版本历史，再仅运行一次 `./native/build_and_log.sh`，覆盖安装、验签、启动并提交对应 Build。
- 不 stage、修改或提交现存 `.artifacts/`、`.claude/`、`.superpowers/`、`docs/stories/`、`docs/talks/PPT_OUTLINE.md`、`docs/talks/ppt-sample/` 用户内容。

---

## File Structure

- Create `native/Sources/Domain/Remote/RemoteButton.swift`: 13 个稳定物理按钮 ID，从 mapping 文件拆出。
- Create `native/Sources/Domain/Remote/RemoteActionID.swift`: 10 个 namespaced 稳定 action ID 与单值 Codable。
- Create `native/Sources/Domain/Remote/RemoteActionDescriptor.swift`: family、受支持按钮、替代系统事件和语音会话能力元数据。
- Create `native/Sources/Domain/Remote/RemoteTrigger.swift`: 当前唯一 `.press` trigger 的版本化 Codable 边界。
- Create `native/Sources/Domain/Remote/RemoteBinding.swift`: binding schema、action ID、trigger 与版本化无参数 payload。
- Create `native/Sources/Domain/Remote/RemoteActionCatalog.swift`: 10 项 descriptor 的唯一注册表与兼容转换。
- Modify `native/Sources/Domain/Remote/RemoteButtonAction.swift`: 保留旧枚举，转换与 allowed action 由 Catalog 提供。
- Modify `native/Sources/Domain/Remote/RemoteButtonMapping.swift`: 内部保存 binding，同时保留现有 action API。
- Create `native/Sources/Domain/Remote/RemoteMappingMigration.swift`: v1 逐键读取、未知动作回退和旧格式编码。
- Modify `native/Sources/Domain/Remote/RemoteButtonActionCycleTracker.swift`: 一次按下周期锁定 binding，而不是锁定旧枚举。
- Create `native/Sources/Application/RemoteActionExecutor.swift`: keyboard、system、TypeWhale 三类 executor port 与统一结果。
- Create `native/Sources/Application/ClosureRemoteActionExecutors.swift`: 兼容现有闭包的分类型 adapter。
- Modify `native/Sources/Application/RemoteButtonActionDispatcher.swift`: binding/descriptor 校验与 family 路由，保留旧 action 调用入口。
- Modify `native/Sources/Application/RemoteInputCoordinator.swift`: 抑制、PTT 和执行从同一个 cycle binding 读取。
- Modify `native/Sources/Infrastructure/Remote/RemoteInputSettingsStore.swift`: v2 优先、v1 回退迁移、逐键恢复与双写。
- Modify `native/Sources/Presentation/Remote/RemoteButtonActionPresentation.swift`: 动作候选来自 Catalog，分组与顺序不变。
- Modify `native/Sources/Presentation/Remote/RemoteButtonMappingView.swift`: 菜单项携带稳定 action ID，回调仍输出旧 action 外壳。
- Create `native/Tests/RemoteActionCatalogCheck.swift`: ID、descriptor、payload/binding 和 Catalog 不变量。
- Create `native/Tests/RemoteMappingMigrationCheck.swift`: 纯 v1/v2 迁移与逐键恢复矩阵。
- Modify `native/Tests/RemoteButtonMappingCheck.swift`: v2 binding 真源与兼容 action API。
- Modify `native/Tests/RemoteButtonActionCycleCheck.swift`: 周期内 binding 不漂移。
- Modify `native/Tests/RemoteInputSettingsStoreCheck.swift`: v2 优先、v1 保留、双写、损坏回退。
- Modify `native/Tests/RemoteButtonActionDispatcherCheck.swift`: family 唯一路由、未知 binding 与旧入口兼容。
- Create `native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh`: R0 聚合编译、结构边界和 10 项行为锁定。
- Modify `native/Tests/run_remote_domain_checks.sh`, `native/Tests/TypeWhaleRemoteFeatureCheck.sh`, `native/Tests/TypeWhaleRemoteCustomizationFeatureCheck.sh`: 加入新源和新目录真源断言。
- Modify `docs/current/ARCHITECTURE.md`, `docs/current/RELEASE_QA.md`, `docs/current/DEVELOPMENT_LOG.md`, `docs/current/README.md`: 记录 R0 架构、迁移、回滚和实测边界。
- Modify `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`: 写入下一个 Build 的用户可理解版本说明。
- Modify automatically `native/build_native_app.sh`, `README.md`, `macos/README.md`, `docs/构建日志.md`: 由唯一构建脚本生成并校验。

---

### Task 1: 建立稳定 ID、Descriptor、Trigger、Payload 与 Binding

**Files:**
- Create: `native/Sources/Domain/Remote/RemoteButton.swift`
- Create: `native/Sources/Domain/Remote/RemoteActionID.swift`
- Create: `native/Sources/Domain/Remote/RemoteActionDescriptor.swift`
- Create: `native/Sources/Domain/Remote/RemoteTrigger.swift`
- Create: `native/Sources/Domain/Remote/RemoteBinding.swift`
- Create: `native/Sources/Domain/Remote/RemoteActionCatalog.swift`
- Modify: `native/Sources/Domain/Remote/RemoteButtonAction.swift`
- Create: `native/Tests/RemoteActionCatalogCheck.swift`
- Create: `native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh`

**Interfaces:**
- `RemoteActionID`: raw string, single-value Codable, exactly 10 R0 constants.
- `RemoteActionDescriptor`: `id`, `legacyAction`, `family`, `supportedButtons`, `replacesSystemEvent`, `startsRemoteSpeech`.
- `RemoteTrigger`: schema version + namespaced `remote.primaryPress`; no duration or multi-click state in R0.
- `RemoteActionPayload`: schema version + `.none`; unknown kind/version is invalid for R0.
- `RemoteBinding`: schema version 2 + action ID + trigger + payload; validation is delegated to Catalog and target button.
- `RemoteActionCatalog.builtIn`: unique ordered descriptors, ID/action lookup, allowed descriptors and binding factory.

- [ ] **Step 1: Write the failing Catalog test**

Assert all exact pairs:

```swift
let expected: [(RemoteButtonAction, RemoteActionID)] = [
    (.pushToTalk, .pushToTalk),
    (.keyboardEscape, .keyboardEscape),
    (.keyboardDelete, .keyboardDeleteBackward),
    (.keyboardReturn, .keyboardReturn),
    (.lockMac, .lockMac),
    (.send, .typeWhaleSend),
    (.cancel, .typeWhaleCancel),
    (.toggleMainWindow, .typeWhaleToggleMainWindow),
    (.none, .none),
    (.system, .systemPassThrough),
]
```

Also assert: IDs and legacy actions are unique; PTT is allowed only for `.voice`; descriptor/binding Codable round-trip is exact; unknown ID, schema, payload kind and trigger cannot validate; family counts remain 3 remote, 3 keyboard, 3 TypeWhale, 1 system.

- [ ] **Step 2: Run the new R0 check and verify RED**

Run: `./native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh`

Expected: FAIL because the new test/script or Domain types do not exist.

- [ ] **Step 3: Add the Domain types without changing product behavior**

Move only `RemoteButton` from `RemoteButtonMapping.swift`. Implement stable IDs from the approved specification. Keep UI strings out of all new Domain files. `RemoteButtonAction.allowedActions(for:)` must derive from `RemoteActionCatalog.builtIn`, so the Catalog becomes the only action eligibility source while the old enum remains source-compatible.

- [ ] **Step 4: Run the Catalog test and current domain regression**

Run:

```bash
./native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh
./native/Tests/run_remote_domain_checks.sh
```

Expected: new Catalog check passes; old mapping checks may still pass through the compatibility shell; no UI or runtime behavior changes.

- [ ] **Step 5: Commit the stable Domain boundary**

```bash
git add native/Sources/Domain/Remote/RemoteButton.swift native/Sources/Domain/Remote/RemoteActionID.swift native/Sources/Domain/Remote/RemoteActionDescriptor.swift native/Sources/Domain/Remote/RemoteTrigger.swift native/Sources/Domain/Remote/RemoteBinding.swift native/Sources/Domain/Remote/RemoteActionCatalog.swift native/Sources/Domain/Remote/RemoteButtonAction.swift native/Tests/RemoteActionCatalogCheck.swift native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh
git commit -m "refactor: add versioned remote action catalog"
```

---

### Task 2: 将映射真源迁移到 v2 Binding 并保留 v1 回滚

**Files:**
- Modify: `native/Sources/Domain/Remote/RemoteButtonMapping.swift`
- Create: `native/Sources/Domain/Remote/RemoteMappingMigration.swift`
- Modify: `native/Sources/Infrastructure/Remote/RemoteInputSettingsStore.swift`
- Modify: `native/Tests/RemoteButtonMappingCheck.swift`
- Create: `native/Tests/RemoteMappingMigrationCheck.swift`
- Modify: `native/Tests/RemoteInputSettingsStoreCheck.swift`
- Modify: `native/Tests/run_remote_domain_checks.sh`
- Modify: `native/Tests/TypeWhaleRemoteFeatureCheck.sh`
- Modify: `native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh`

**Interfaces:**
- `RemoteButtonMapping.binding(for:)` is the v2 read path; `action(for:)` remains an exact compatibility projection.
- `RemoteButtonMapping.set(_:RemoteBinding,for:)` validates per button; `set(_:RemoteButtonAction,for:)` converts through Catalog.
- `RemoteMappingMigration.decodeV1(_:)` and `encodeV1(_:)` own only the legacy `actions` JSON shape.
- `RemoteInputSettingsStore.mappingV2Key = "typewhale.remote.button-mapping.v2"`; existing `mappingKey` remains the v1 key alias for source/test compatibility.

- [ ] **Step 1: Write failing migration and persistence tests**

Cover:

1. v2 exact round-trip preserves all 13 binding IDs, `.press` and payload schema.
2. Partial v2 resolves each missing/invalid button from valid v1, then from that button's default.
3. One unknown action ID, binding schema, trigger or payload kind falls back only that button.
4. Valid v2 wins over conflicting v1.
5. Invalid v2 root falls back to v1.
6. First v1 load writes v2 but preserves the v1 bytes exactly.
7. Normal save writes equivalent v2 and v1 for all 10 R0 actions.
8. Invalid v1 root returns defaults; current flattened v1 representation remains readable.

- [ ] **Step 2: Run focused checks and verify RED**

Run:

```bash
./native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh
./native/Tests/TypeWhaleRemoteFeatureCheck.sh
```

Expected: FAIL because mapping still encodes legacy `actions` and store has no v2 key/precedence/migration.

- [ ] **Step 3: Implement mapping and pure migration**

`RemoteButtonMapping` encodes only `{schemaVersion:2,bindings:{...}}`. Decode the root strictly enough to detect an invalid v2 document, but wrap each dictionary value in a failable decoder so one corrupt binding cannot discard the other 12. Unknown button IDs are ignored. Defaults are always complete.

`RemoteMappingMigration` reproduces Build 913 v1 dictionary and flattened-array recovery without referring to UserDefaults. `decodeV1` returns nil only for an unreadable root; valid partial/unknown data yields a complete mapping with per-key defaults.

- [ ] **Step 4: Implement store precedence and write policy**

Load order:

```text
valid v2 → resolve each valid v2 button, then v1/default for only its missing or invalid buttons
invalid/missing v2 + valid v1 → migrate, write v2 only, preserve original v1 bytes
both unavailable → defaults
```

Normal user save pre-encodes both documents, writes v2 first and then the legacy v1 representation. It never removes either key.

- [ ] **Step 5: Run migration, domain and full remote checks**

Run:

```bash
./native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh
./native/Tests/run_remote_domain_checks.sh
./native/Tests/TypeWhaleRemoteFeatureCheck.sh
```

Expected: all pass; existing default/action assertions remain unchanged; no test requires deleting the v1 key.

- [ ] **Step 6: Commit the v2 persistence boundary**

```bash
git add native/Sources/Domain/Remote/RemoteButtonMapping.swift native/Sources/Domain/Remote/RemoteMappingMigration.swift native/Sources/Infrastructure/Remote/RemoteInputSettingsStore.swift native/Tests/RemoteButtonMappingCheck.swift native/Tests/RemoteMappingMigrationCheck.swift native/Tests/RemoteInputSettingsStoreCheck.swift native/Tests/run_remote_domain_checks.sh native/Tests/TypeWhaleRemoteFeatureCheck.sh native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh
git commit -m "refactor: migrate remote mappings to v2 bindings"
```

---

### Task 3: 让现有执行链通过 Binding 与分类型 Executor Port

**Files:**
- Modify: `native/Sources/Domain/Remote/RemoteButtonActionCycleTracker.swift`
- Create: `native/Sources/Application/RemoteActionExecutor.swift`
- Create: `native/Sources/Application/ClosureRemoteActionExecutors.swift`
- Modify: `native/Sources/Application/RemoteButtonActionDispatcher.swift`
- Modify: `native/Sources/Application/RemoteInputCoordinator.swift`
- Modify: `native/Sources/Presentation/Remote/RemoteButtonActionPresentation.swift`
- Modify: `native/Sources/Presentation/Remote/RemoteButtonMappingView.swift`
- Modify: `native/Tests/RemoteButtonActionCycleCheck.swift`
- Modify: `native/Tests/RemoteButtonActionDispatcherCheck.swift`
- Modify: `native/Tests/TypeWhaleRemoteCustomizationFeatureCheck.sh`
- Modify: `native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh`

**Interfaces:**
- `RemoteKeyboardActionExecuting`, `RemoteSystemActionExecuting`, `RemoteTypeWhaleActionExecuting` are small synchronous ports returning `Bool` for current actions.
- `RemoteActionResult` distinguishes `.passedThrough/.suppressed/.handedOff/.succeeded/.failed(code:)`; the old `.ignored/.succeeded/.failed` result remains the compatibility return type of `dispatch(_ action:)`.
- `RemoteButtonActionDispatcher.dispatch(_ binding:)` validates the descriptor and routes by family; `dispatch(_ action:)` remains a compatibility adapter used only by old tests/callers.
- `RemoteButtonActionCycleTracker` returns the same binding from down through up even if the user changes the mapping mid-cycle.

- [ ] **Step 1: Write failing routing and cycle tests**

Inject three spy executors and assert:

- each executable descriptor reaches exactly one matching family;
- `.systemPassThrough`, `.none` and `.pushToTalk` return distinct passed-through, suppressed and PTT-handoff results;
- unknown/invalid binding fails without calling any executor;
- existing closure initializer returns exactly the Build 913 results;
- changing a mapping after key-down does not change PTT/replacement or key-up binding in that cycle.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `./native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh`

Expected: FAIL because executor ports and binding dispatcher do not exist.

- [ ] **Step 3: Add ports and small compatibility adapters**

Do not place keyboard/system APIs in Dispatcher. The TypeWhale adapter may switch only across its current three app callbacks; keyboard/system adapters delegate to the existing emitter closure. No adapter persists state or accesses presentation.

- [ ] **Step 4: Move the coordinator and cycle tracker to binding reads**

Use one binding for suppression, voice start/stop ownership, diagnostics and dispatcher routing. Keep `setAction(_:for:)` public behavior, power neutralization order, down/up publication and `AUDIO_STOP` ownership unchanged. Every physical down emits at most one terminal diagnostic containing only button ID, stable action ID, binding schema, executor family and result/failure code.

- [ ] **Step 5: Make the current menu source its candidates from Catalog**

Keep the five visible group headings, exact item order and exact Chinese labels. Menu represented objects become stable action ID strings; callback conversion goes through Catalog and still emits `RemoteButtonAction` to avoid a UI-wide rewrite in R0.

- [ ] **Step 6: Run all protected behavior checks**

Run:

```bash
./native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh
./native/Tests/TypeWhaleRemoteCustomizationFeatureCheck.sh
./native/Tests/TypeWhaleRemoteFeatureCheck.sh
./native/Tests/TypeWhaleAutoSendCancellationFeatureCheck.sh
./native/Tests/TypeWhaleRecordingFinalizationFeatureCheck.sh
./native/Tests/TypeWhaleInputGestureFeatureCheck.sh
git diff --check
```

Expected: all pass; no test output or visible option count changes except new R0 test names.

- [ ] **Step 7: Commit the binding execution path**

```bash
git add native/Sources/Domain/Remote/RemoteButtonActionCycleTracker.swift native/Sources/Application/RemoteActionExecutor.swift native/Sources/Application/ClosureRemoteActionExecutors.swift native/Sources/Application/RemoteButtonActionDispatcher.swift native/Sources/Application/RemoteInputCoordinator.swift native/Sources/Presentation/Remote/RemoteButtonActionPresentation.swift native/Sources/Presentation/Remote/RemoteButtonMappingView.swift native/Tests/RemoteButtonActionCycleCheck.swift native/Tests/RemoteButtonActionDispatcherCheck.swift native/Tests/TypeWhaleRemoteCustomizationFeatureCheck.sh native/Tests/TypeWhaleRemoteActionPlatformR0Check.sh
git commit -m "refactor: route remote actions through bindings"
```

---

### Task 4: 记录、构建、安装并完成 R0 验收

**Files:**
- Modify: `docs/current/ARCHITECTURE.md`
- Modify: `docs/current/RELEASE_QA.md`
- Modify: `docs/current/DEVELOPMENT_LOG.md`
- Modify: `docs/current/README.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify automatically: `native/build_native_app.sh`
- Modify automatically: `README.md`
- Modify automatically: `macos/README.md`
- Modify automatically: `docs/构建日志.md`
- Create in AWF workspace: `docs/projects/typewhale-remote-action-platform/ACCEPTANCE-R0.md`

**Produces:** one unique daily Build after 913, expected Build 914 if concurrency has not advanced; installed at `/Applications/TypeWhale Pro.app`, signed and running. No public release.

- [ ] **Step 1: Recheck ownership and concurrency**

Run:

```bash
git branch --show-current
git status --short
pgrep -fl 'build_and_log|release_local_build|build_native_app|swiftc|xcodebuild' || true
defaults read native/build/TypeWhale\ Pro.app/Contents/Info CFBundleShortVersionString
defaults read native/build/TypeWhale\ Pro.app/Contents/Info CFBundleVersion
```

Expected: correct Pro ASR branch, only R0-owned tracked changes plus protected user untracked paths, no active build. Recalculate the target Build if the baseline advanced.

- [ ] **Step 2: Update current architecture, QA, log and in-app history before build**

Record: 10 stable IDs; v2 binding/payload schemas; v2→v1 load order; normal dual-write and migration non-overwrite; per-key recovery; family executor ports; exact do-not-touch boundaries; automated evidence; physical-device and owner acceptance boundaries. Do not claim any R1 action exists.

- [ ] **Step 3: Run the complete pre-build regression**

Run the seven commands in Task 3 Step 6 plus the current installed runtime check. Expected: all exit 0.

- [ ] **Step 4: Build exactly once through the approved entry**

Run: `./native/build_and_log.sh`

Expected: version remains `2.0.58`; build increments exactly once; source compiles, installed app is replaced and opened, signature verification passes, and one build log row is written.

- [ ] **Step 5: Verify the installed artifact and unchanged Remote page**

Run:

```bash
defaults read '/Applications/TypeWhale Pro.app/Contents/Info' CFBundleShortVersionString
defaults read '/Applications/TypeWhale Pro.app/Contents/Info' CFBundleVersion
codesign --verify --deep --strict --verbose=2 '/Applications/TypeWhale Pro.app'
pgrep -fl '/Applications/TypeWhale Pro.app/Contents/MacOS/TypeWhale Pro'
./native/Tests/TypeWhaleInputGestureRuntimeCheck.sh
```

Open the installed Remote tab and confirm: 13 rows; exact Build 913 menu labels/order/defaults; click preview still highlights only its product-photo region; no R1 actions or new controls are visible. This is a behavior-neutral R0, so visual acceptance is equivalence rather than redesign.

- [ ] **Step 6: Run post-build regression and AWF prepared checks**

Run all R0 and protected regression scripts again, then from the AWF workspace run `task:run` for every prepared check. Create `ACCEPTANCE-R0.md` with actual commands, build, commit candidates, installed evidence, known physical-device boundary and Go/No-Go. Run `task:check --phase deliver` and require `ready`.

- [ ] **Step 7: Independent maintainability review and remediation**

Review the final diff against the approved R0 scope: no duplicated catalog, no payload dictionary escape hatch, no UI/System API layering leak, no v1 deletion, no new action or trigger behavior. Fix every P0/P1 and rerun affected checks.

- [ ] **Step 8: Commit the installed R0 build**

```bash
git status --short
git add README.md macos/README.md native/build_native_app.sh docs/构建日志.md docs/current/README.md docs/current/ARCHITECTURE.md docs/current/RELEASE_QA.md docs/current/DEVELOPMENT_LOG.md native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift docs/superpowers/specs/2026-09-13-typewhale-remote-action-platform-design.md docs/superpowers/plans/2026-09-13-typewhale-remote-action-platform-r0-implementation-plan.md
git commit -m "build: install remote action platform R0"
```

Expected: protected user paths remain untracked and untouched; TypeSpeaker working tree has no uncommitted R0 tracked change; R1 remains Not started.

---

## R0 Acceptance Checklist

- [x] Exactly 10 Catalog descriptors and the approved stable IDs exist; no future placeholder descriptor is shipped.
- [x] All 13 defaults and every Build 913 allowed action remain identical.
- [x] v2 binding is the internal mapping truth; old action API remains compatible.
- [x] v2 wins over v1; invalid v2 root falls back to v1; one corrupt binding only resets one key.
- [x] v1 is retained; migration load preserves original v1 bytes; R0 normal saves remain readable by Build 913.
- [x] Dispatcher routes by family through executor ports and contains no system API implementation.
- [x] One physical press cycle uses one immutable binding; PTT and replacement semantics cannot diverge mid-cycle.
- [x] Current Remote tab labels, order, defaults, photo feedback and behavior are visually unchanged.
- [x] Fn, F5, ATVV finalization, computer mic, ASR, paste and auto-send cancellation regressions pass.
- [x] New unique Build is compiled, installed, signed, running and documented.
- [x] AWF implement/deliver gates are ready; R0 acceptance is Go before any R1 work begins.
