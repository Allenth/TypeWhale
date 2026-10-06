# GPT-OSS 本地 MLX 隔离准入报告

- 综合默认模型准入：**REJECT**
- TypeWhale 自管 MLX 直驱架构：**PASS**
- 模型：`mlx-community/gpt-oss-20b-MXFP4-Q8`
- 来源：`~/.lmstudio/models/mlx-community/gpt-oss-20b-MXFP4-Q8`（只读）
- 运行方式：TypeWhale 受管 Python 中的独立 MLX worker，完全离线

## 结论

独立运行时、Harmony 安全解析、性能、连续调用、取消恢复和 APFS 无重复下载导入均通过，证明 TypeWhale 不依赖 Ollama/LM Studio 服务、直接管理 MLX 模型的架构可行。

该模型在开发需求、禁止代答、短指令、中英翻译和技术名词样本中通过，但在与生产提示词对齐后，仍把明确口吃“一下下”保留为正文。因此当前版本不进入“整理 + 翻译综合默认模型”的生产接入计划；可以保留为后续专业档或翻译单项 A/B 候选。

测试期间 LM Studio 已将同一模型保持为 IDLE。本报告的加载时间代表新进程、新 MLX 模型实例和新 Metal 状态的启动时间，但操作系统文件页缓存可能已经预热，不能当作重启机器后的冷盘读取时间。

## 性能

| 阶段 | 加载 ms | 首 token ms | 完成 ms | tok/s | 峰值 RSS |
|---|---:|---:|---:|---:|---:|
| 冷启动与首个样本 | 1658.523 | 473.761 | 1146.502 | 121.627 | 13046824960 |

## 合成样本

| ID | 状态 | 断言 | 输出 |
|---|---|---|---|
| short-chat-repetition | ok | forbidden:一下下 | 我们再回顾一下下这个问题。 |
| development-requirements | ok | 通过 | 先验证本地模型能不能加载，然后测试取消恢复，但是不要修改现有的 Ollama 主链路。 |
| no-answer-request | ok | 通过 | 帮我回复用户，说我们先确认原因，不要承诺今天上线。 |
| short-instruction | ok | 通过 | 先别动代码，先测试模型。 |
| translate-zh-to-en | ok | 通过 | TypeWhale must remain completely offline, and must not answer the questions in the original text. |
| translate-en-to-zh | ok | 通过 | 保持 TypeWhale 本地运行，保留技术术语，并且不要回答原文中的问题。 |
| technical-terms | ok | 通过 | SwiftUI 这块不要走 Ollama，Qwen3-ASR 继续保持热加载。 |

## 稳定性与导入

- 同进程连续调用：ok
- 取消并终止自有 worker：ok
- 新 worker 恢复：ok
- APFS clone-on-write：ok
- 外部模型源文件保持不变：True

## 决策边界

本报告只决定该模型是否有资格进入后续生产接入计划；不会改变当前默认模型、Ollama 路由或 TypeWhale 安装版。
