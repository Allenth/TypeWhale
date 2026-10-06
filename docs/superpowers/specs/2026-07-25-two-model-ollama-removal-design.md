# TypeWhale 双模型架构与 Ollama 清理设计

日期：2026-07-25
状态：已确认
本轮实施范围：第一阶段

## 产品目标

TypeWhale 的智能文本能力最终只依赖两种模型：

- 本地默认：`Qwen3-4B-Instruct-2507 4bit`
- 在线备选：`DeepSeek v4 flash`

本轮先彻底移除 TypeWhale 产品代码、页面和活动路由中的旧 Ollama 2B、9B、35B 与 35B Rewrite，同时建立稳定的双模型默认与迁移规则。

## 用户场景

- 电脑上已经存在且校验通过 Qwen3 4B 时，TypeWhale 默认使用 Qwen。
- Qwen 不存在、无效或设备未来被判定不满足要求时，TypeWhale 使用 DeepSeek。
- 用户只需要理解“本地 Qwen”和“在线 DeepSeek”，不再理解 Ollama 服务、模型标签或外部模型应用状态。
- 智能整理、语音翻译与截图 OCR 翻译统一跟随当前模型。

## 本轮范围

### In scope

- `SmartAIModel` 只保留 Qwen 与 DeepSeek。
- 删除 TypeWhale 中 Ollama 2B、9B、35B、35B Rewrite 的菜单项、下载链接、状态文案、引擎路由和专项测试。
- 删除不再被生产链路使用的 Ollama engine、server recovery 与相关代码。
- 迁移旧 Ollama 设置：
  - Qwen 完整就绪时迁移为 Qwen；
  - Qwen 未就绪时迁移为 DeepSeek。
- 新安装或无设置时采用相同的 readiness-aware 默认规则。
- Qwen 与 DeepSeek 均接管智能整理、语音翻译和截图 OCR 翻译。
- Qwen 请求失败时保留原文，不自动调用 DeepSeek。
- 保留当前 Qwen 受管目录、清单、worker 和生命周期。

### Out of scope

- 本轮不实现 DeepSeek 首次 Key 配置弹窗。
- 本轮不实现 Qwen 商用设备准入卡片和下载 UI。
- 本轮不决定最终采用 Python/MLX 还是 Swift/MLX。
- 本轮不改变 ASR、VAD、热词、录音、胶囊和自动发送。

### Do not touch

- 不删除、移动或读取用户 Ollama 模型目录。
- 不卸载 Ollama 应用，不调用 `ollama rm`。
- 不删除 LM Studio 或其他模型工具的数据。
- 不把 Qwen 失败静默转为在线请求。

## 方案

采用严格双模型状态机，不保留隐藏 Ollama 兼容路由。

### 默认解析

`SmartAIModelStore` 不再使用固定枚举默认值直接决定首次模型，而是通过可注入的 Qwen readiness provider 解析：

1. 已保存 Qwen：保持 Qwen。
2. 已保存 DeepSeek：保持 DeepSeek。
3. 已保存任一旧 Ollama raw value：
   - Qwen ready → Qwen；
   - 否则 → DeepSeek。
4. 没有保存值：
   - Qwen ready → Qwen；
   - 否则 → DeepSeek。

解析结果立即写回稳定的新 raw value，避免每次启动重复迁移。

### 路由

- `SelectedSmartAITextEngine`
  - Qwen → `TypeWhaleLocalLLMEngine`
  - DeepSeek → `DeepSeekRewriteEngine`
- `SelectedScreenshotTranslationEngine`
  - Qwen → 本地 Qwen 截图 OCR 翻译适配
  - DeepSeek → `DeepSeekRewriteEngine`

本地截图翻译继续使用 `ScreenshotTranslationPromptBuilder` 的行标记与结构保护，不能复用普通语音翻译 Prompt。

### UI

- 智能页与模型页的整理模型下拉只显示：
  - `本地直驱 Qwen3 4B Instruct`
  - `DeepSeek v4 flash`
- 模型页删除“Ollama 本地整理模型”、2B/35B 下载按钮和相关帮助文本。
- 当前阶段保留 Qwen 已下载用户的直接切换能力；未安装时仍由现有选择校验拒绝。

### 错误处理

- Qwen 未就绪时不能保存为当前模型。
- 本地整理、语音翻译或截图翻译失败时沿用原文/原布局保护。
- 不自动切 DeepSeek，不产生未授权在线费用。
- DeepSeek 未配置 Key 的既有错误保持明确，首次配置弹窗在第二阶段实现。

## 后续阶段

### 第二阶段：DeepSeek 首次配置

- DeepSeek 生效且 Key 缺失时显示一次配置弹窗。
- Key 保存至 Keychain，保存后立即生效。
- 提供 DeepSeek 开放平台链接。

### 第三阶段：Qwen 商用安装

- Apple Silicon + 16GB 统一内存硬门槛。
- 合格设备提供手动下载、进度、取消、断点续传、校验、重试与删除。
- 不合格设备只允许 DeepSeek。
- 先验证 Swift/MLX 原生路线，再决定是否需要受管 Python 运行环境。

## 验收标准

- 两个整理模型下拉只出现 Qwen 与 DeepSeek。
- 模型页不出现 Ollama 名称、2B/9B/35B/Rewrite 或 Ollama 下载按钮。
- 生产代码不存在活动 Ollama 路由或服务恢复逻辑。
- 当前机器 Qwen 已就绪，升级后仍默认并实际使用 Qwen。
- 模拟 Qwen 缺失时，旧 Ollama/无设置迁移到 DeepSeek。
- 智能整理、语音翻译、截图 OCR 翻译分别通过 Qwen 与 DeepSeek 路由测试。
- Qwen 失败不会触发 DeepSeek。
- 用户 Ollama 数据完全不变。
