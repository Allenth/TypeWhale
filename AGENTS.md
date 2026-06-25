# TypeWhale Agent Rules

本文件是 TypeWhale 仓库的持久协作规则。所有后续 AI/coding session 必须先遵守这里的项目级规则，再执行具体任务。

## 每次代码或文档变更后的固定动作

只要对仓库内文件做了任何代码、配置、脚本或文档修改，完成修改后必须自动执行：

```bash
./native/release_local_build.sh
```

该脚本会：

- 自动递增 `CFBundleShortVersionString` 的第三位版本号。
- 自动递增 `CFBundleVersion` build 号。
- 同步 README / macOS README 中的当前本地版本说明。
- 执行 `./native/build_native_app.sh`。
- 覆盖安装到 `/Applications/TypeWhale.app`。
- 启动最新安装版，便于用户立即测试。
- 打印安装版版本号和签名校验结果。

除非用户明确要求“只分析、不修改”或“不要构建/不要打开 App”，否则不要跳过这一步。

## 发布与记录

- 较大功能、交互、架构或发布动作完成后，继续更新 `docs/开发日志.md`。
- 若行为语义会影响后续开发判断，更新 `docs/ARCHITECTURE_DECISIONS.md`。
- 不要只在聊天里声明流程；需要持久化到本文件或项目文档。

## 内存治理策略

- ASR / VAD 模型资源不能在每次输入后立即卸载，否则会破坏连续语音输入的速度和体验。
- **已取消“空闲定时卸载”**：模型平时保持热加载，避免久未说话后开口第一句因重载卡顿（响应优先）。不要再加“空闲 N 秒后卸载”的定时器。
- 内存治理只保留**“高内存释放”这一条安全网**：仅当内存达到预警阈值（默认 1GB）且处于空闲时，才释放 ASR recognizer 和 VAD 缓存（`releaseASRResourcesIfMemoryElevated`）。
- 任何后续优化都必须保留这两个边界：
  - 录音、识别、整理、粘贴过程中不得释放模型资源；
  - 下一次输入必须能自动重新加载模型，不能要求用户手动恢复。
