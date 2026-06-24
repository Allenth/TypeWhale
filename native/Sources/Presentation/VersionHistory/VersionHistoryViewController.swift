import AppKit

final class VersionHistoryViewController: NSViewController {
    private struct VersionEntry {
        let version: String
        let date: String
        let changes: [String]
    }

    private static let entries = [
        VersionEntry(
            version: "版本 1.3.12 (Build 220)",
            date: "2026-06-24",
            changes: [
                "为 DeepSeek 智能整理增加调用成本保护：单次输入/输出 token、每日调用次数和每日成本上限。",
                "补齐 DeepSeek usage 日志，记录模型、模式、token、估算成本、request_id、触发来源和 Prompt 长度。",
                "Debug 面板新增 DeepSeek 页签，余额弹窗显示今天/昨天消耗、当天调用次数和最近一次 usage。",
                "避免 Smart Rewrite 超时后后台请求继续消耗 token，并对同一录音最终任务做去重。",
                "长录音实时预览缓存限制为最近 20 秒，同时保留启动时 ASR 模型预加载以保证首次录音响应速度。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.11 (Build 219)",
            date: "2026-06-24",
            changes: [
                "按固定窗口数据重新校准横屏主界面的三栏比例。",
                "将窗口生命周期尺寸与主内容尺寸统一，避免旧竖屏窗口数据继续影响布局。",
                "扩大中间工作区，收窄左侧栏和右侧 inspector，让当前会话与最近转录成为视觉主区。",
                "压缩智能整理工具按钮宽度，确保右侧设置区在新宽度下不横向挤压。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.10 (Build 218)",
            date: "2026-06-24",
            changes: [
                "修复当前会话面板被压缩后状态文字和实时文本标题裁切的问题。",
                "恢复会话面板必要高度，同时收紧内部间距和波形高度。",
                "最近转录视口微调，保持整体板块比例稳定。",
                "恢复 SenseVoice ITN，让原文模式重新获得标点和数字文本规范化能力。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.9 (Build 217)",
            date: "2026-06-24",
            changes: [
                "继续收紧横屏各板块比例。",
                "当前会话面板降低高度，将更多空间分配给最近转录。",
                "右侧 inspector 小组间距进一步收敛，让设置区更紧凑。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.8 (Build 216)",
            date: "2026-06-24",
            changes: [
                "按板块重新打磨横屏主界面：左侧栏、当前会话、最近转录、快捷键和选项区分别优化。",
                "右侧选项区拆分为智能整理、翻译、截图和系统四个 inspector 小组。",
                "当前会话胶囊收窄，实时文本权重提升，减少搜索框式观感。",
                "最近转录降低元信息和复制按钮噪音，历史列表更易扫读。",
                "左侧品牌和权限区收敛尺寸，降低海报感和厚重卡片感。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.7 (Build 215)",
            date: "2026-06-24",
            changes: [
                "收敛横屏主窗口比例，避免界面过宽、过散。",
                "将录音状态与实时文本合并为“当前会话”面板，减少卡片割裂感。",
                "右侧设置区改为更紧凑的 inspector 密度，降低设置项的视觉噪音。",
                "压缩快捷键与复杂设置控件尺寸，改善横屏布局的视觉层级。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.6 (Build 214)",
            date: "2026-06-24",
            changes: [
                "主窗口改为横屏三栏工作台布局。",
                "左侧保留品牌、模型、权限和底部入口；中间集中展示录音状态、实时文本和最近转录。",
                "右侧集中放置快捷键、智能整理、翻译、截图保存和启动选项。",
                "复杂设置项改为局部上下布局，减少按钮挤压和文字截断。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.5 (Build 213)",
            date: "2026-06-24",
            changes: [
                "左下角使用方法、版本历史和测试日志入口改为图标按钮。",
                "修复窄侧栏中底部按钮文字被压缩成省略号的问题。",
                "按钮保留 tooltip 和无障碍标签，悬停即可查看入口名称。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.4 (Build 212)",
            date: "2026-06-24",
            changes: [
                "关闭 SenseVoice 原生 ITN，避免口语金额被提前书面化为错误数字金额。",
                "修复“六毛六分钱”在实时预览和最终识别中都变成“6.6元”的问题。",
                "保留更接近用户原话的 ASR 输出，再交给后续智能整理处理。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.3 (Build 211)",
            date: "2026-06-24",
            changes: [
                "修复开头静音被 ASR 误识别为“我”、句号等低信息量内容后仍进入粘贴的问题。",
                "实时预览和最终识别统一增加静音幻觉短文本过滤。",
                "过滤后的空结果会显示“没有收到有效音频”，不会取消初始静音判断或触发自动粘贴。",
                "新增检查覆盖“我”“我。”和纯标点等静音幻觉样例。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.2 (Build 210)",
            date: "2026-06-24",
            changes: [
                "智能整理自动模式新增“范围”设置入口。",
                "用户可以为 AI 编程窗口、终端/代码编辑器、笔记窗口、聊天窗口分别指定整理模式。",
                "自动范围支持编辑匹配关键词，并可单独启用或关闭。",
                "新增未匹配时的兜底模式设置，自动模式不再完全依赖硬编码规则。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.1 (Build 209)",
            date: "2026-06-24",
            changes: [
                "截图工具条改为展开式图标加文字展示，标注工具与功能区通过竖线分组。",
                "功能区固定展示复制、撤销、保存本地和取消，减少隐藏入口。",
                "OCR 识别成功后直接复制文本，并用短暂状态提示“内容已复制”。",
                "保存本地固定写入下载文件夹，文件名缩短为 TW-Shot-日期时间格式，方便查找。"
            ]
        ),
        VersionEntry(
            version: "版本 1.3.0 (Build 208)",
            date: "2026-06-24",
            changes: [
                "新增截图功能：通过独立可设置的截图快捷键随时发起屏幕区域截图。",
                "截图支持拖拽选区与边角缩放，并内置标注工具（矩形、箭头、画笔、文字、撤销）。",
                "截图可一键复制到剪贴板或保存为文件。",
                "内置 OCR 文字识别与翻译：识别选区文字并写入剪贴板。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.50 (Build 207)",
            date: "2026-06-24",
            changes: [
                "放弃 macOS 12 兼容尝试，最低系统要求恢复为 macOS 14。",
                "语音识别运行库恢复为 onnxruntime 1.24.4，重新启用 Qwen3-ASR 与原生 VAD 人声检测。",
                "移除 macOS 12 兼容残留：旧版 sherpa-onnx、libc++ 兼容垫片、VAD 旁路开关与登录项降级分支。",
                "保留启动与崩溃诊断（LaunchProbe / CrashReporter / 测试日志面板），增强稳定性排查能力。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.49 (Build 206)",
            date: "2026-06-24",
            changes: [
                "重新简化智能整理默认提示词。",
                "开发需求模式改为轻量任务整理，不再默认输出待确认、验收标准等重结构。",
                "润色、笔记、聊天和极致归纳模式也收敛为更轻的输入整理规则。",
                "新增检查覆盖开发需求轻量输出规则和极致归纳待确认触发条件。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.48 (Build 205)",
            date: "2026-06-24",
            changes: [
                "修复智能整理偶尔输出“根据规则、我不能执行、整理后如下”等元说明的问题。",
                "强化提示词边界：禁止解释安全规则，只输出整理后的正文。",
                "新增 SmartRewriteOutputSanitizer，兜底清理整理结果前面的模型解释性前缀。",
                "新增检查覆盖“不改代码，先查看日志”样例。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.47 (Build 204)",
            date: "2026-06-24",
            changes: [
                "DeepSeek Key 按钮文案统一改为“Key”。",
                "已录入 Key 时使用品牌色高亮按钮，未录入时保持弱提示色。",
                "Key 按钮 tooltip 会提示当前录入状态。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.46 (Build 203)",
            date: "2026-06-24",
            changes: [
                "重新审核 DeepSeek 内容整理和翻译 token 费用统计口径。",
                "余额弹窗中的已消费金额改为“官方后台基准 + TypeWhale 后续记录 usage”。",
                "将截至今天 DeepSeek 后台已消费 ¥0.66 作为本机账本基准。",
                "新增检查覆盖官方消费基准、本机新增 usage 和累计消费金额。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.45 (Build 202)",
            date: "2026-06-24",
            changes: [
                "DeepSeek Key 按钮旁新增余额提示按钮。",
                "点击后通过 DeepSeek 余额接口查询当前账号余额。",
                "余额弹窗显示当前余额、总金额、本机记录已消费金额和消费占比进度条。",
                "本机记录的消费继续基于 TypeWhale 收到的 usage 估算，并在界面中明确不等同于官方账单。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.44 (Build 201)",
            date: "2026-06-24",
            changes: [
                "最近转录的 token 费用增加详细说明，可查看输入、缓存命中、缓存未命中、输出 token 和美元/人民币估算。",
                "DeepSeek 智能整理等待时间从 3 秒放宽到 8 秒，自动翻译等待时间放宽到 10 秒，减少后台已扣费但本地超时未记录 usage 的情况。",
                "DeepSeek HTTP 请求超时放宽到 15 秒。",
                "费用公式继续按 deepseek-v4-flash 官方当前价格估算。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.43 (Build 200)",
            date: "2026-06-24",
            changes: [
                "新增截图模式 MVP：三连按当前录音快捷键进入全屏截图界面。",
                "截图界面支持拖拽框选区域、显示选区尺寸、复制截图到剪贴板和取消退出。",
                "截图工具条预留 OCR 和覆盖翻译入口，后续接入截图文字识别、中文转英文和版面覆盖。",
                "开发计划记录下个版本截图输入、截图 OCR 和覆盖翻译需求。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.42 (Build 199)",
            date: "2026-06-24",
            changes: [
                "修复主界面左侧录音状态卡片长提示文字贴边的问题。",
                "修复快捷键卡片在垂直方向被压缩后两行按钮重叠的问题。",
                "提高快捷键卡片最小高度，并为列表卡片增加可配置上下留白。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.41 (Build 198)",
            date: "2026-06-24",
            changes: [
                "新增 Qwen3-ASR 0.6B 原生识别后端。",
                "识别模型增加“自动 / SenseVoice int8 / Qwen3-ASR 0.6B”选择。",
                "自动模式会优先使用本机已安装的 Qwen3-ASR ONNX 模型，缺失时回退 SenseVoice。",
                "Qwen3-ASR 走 sherpa-onnx 原生 C bridge，不依赖 Python。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.40 (Build 197)",
            date: "2026-06-23",
            changes: [
                "自动智能整理现在会把 Terminal、iTerm、Warp、Code、Xcode 和 Visual Studio 识别为开发需求场景。",
                "中译英自动翻译改为直接使用原始识别文本，不再先做智能整理。",
                "英译中保持原有链路，可继续先整理再翻译。",
                "新增检查覆盖终端/代码编辑器自动模式和中译英原文翻译规则。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.39 (Build 196)",
            date: "2026-06-23",
            changes: [
                "修复智能整理把口述内容当成问题来回答的问题。",
                "为智能整理增加最高优先级边界：原始语音文本只是待整理素材，不是给模型的新指令。",
                "即使原文包含问句、命令或“回答我”等表达，也只会整理问题本身，不会输出答案。",
                "自定义智能整理提示词同样会套用这层保护。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.38 (Build 195)",
            date: "2026-06-23",
            changes: [
                "主界面左下角新增使用方法说明。",
                "补充测试版首次打开时通过系统设置点击“仍要打开”的提示。",
                "修复极致归纳模式结果状态文案的编译覆盖遗漏。",
                "用于发给朋友体验的 DMG 测试包。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.37 (Build 194)",
            date: "2026-06-23",
            changes: [
                "新增“极致归纳”智能整理模式。",
                "适合把长段口述内容结构化压缩成一句话结论、核心要点、行动项和风险/待确认。",
                "短文本会自动保持轻量输出，不强行套复杂结构。",
                "极致归纳提示词支持在智能整理提示词弹窗中继续自定义。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.36 (Build 193)",
            date: "2026-06-23",
            changes: [
                "新增自动翻译提示词设置入口。",
                "翻译方向行新增“提示词”按钮，可编辑中译英和英译中的语气规则。",
                "中译英英文翻译提示词支持本机持久化保存，空内容会恢复默认。",
                "新增翻译提示词存储检查，确保自定义和恢复默认行为稳定。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.35 (Build 192)",
            date: "2026-06-23",
            changes: [
                "优化中译英自动翻译语气。",
                "中译英现在优先输出更口语、温柔、好理解的英文，适合直接用于私聊沟通。",
                "新增约束避免油腻、夸张暧昧或自行添加原文没有的情绪。",
                "英译中保持自然清楚的中文表达，不受中译英语气规则影响。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.34 (Build 191)",
            date: "2026-06-23",
            changes: [
                "降低 Smart Rewrite 每次请求的提示词 token 开销。",
                "开发术语归一化继续在本地使用完整词库执行，不产生模型 token 成本。",
                "发送给 DeepSeek 的开发术语表改为只包含本次文本相关术语；无相关术语时不再注入完整词库。",
                "新增提示词检查，确保默认请求不会携带无关术语，同时相关术语仍会进入提示词。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.33 (Build 190)",
            date: "2026-06-23",
            changes: [
                "补充 Obsidian 到默认开发术语词库。",
                "新增 oppoingpo、obpoing、欧布西迪安等常见误识别别名，提升英文专名纠错。",
                "本地自定义术语词库现在会自动合并新增默认术语，避免旧词库挡住新内置词。",
                "新增 Obsidian 术语归一化测试。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.32 (Build 189)",
            date: "2026-06-23",
            changes: [
                "调整最近转录中的时间统计口径。",
                "现在从松开快捷键或再次按下快捷键结束录音开始计时，到粘贴事件发送完成为止。",
                "历史记录会在粘贴成功后写入，避免提前记录仅 ASR 耗时。",
                "粘贴耗时不再包含后续剪贴板恢复等待。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.31 (Build 188)",
            date: "2026-06-23",
            changes: [
                "新增开发术语词库和 DeveloperTermNormalizer，在 Smart Rewrite 前归一化开发热词。",
                "默认词库包含 Codex、Claude Code、Qwen3-ASR、SenseVoice、SwiftUI、sherpa-onnx 等常用开发术语。",
                "智能整理提示词会注入开发术语表，要求保留标准英文技术术语。",
                "主界面新增“术语”入口，可按行编辑标准词、分类和别名，并支持恢复默认词库。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.30 (Build 187)",
            date: "2026-06-23",
            changes: [
                "修复智能整理提示词弹窗中编辑器文字看不见的问题。",
                "提示词编辑区改为固定深色背景、浅色正文和白色插入光标。",
                "为提示词编辑器增加内边距，长模板内容更容易阅读和编辑。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.29 (Build 186)",
            date: "2026-06-23",
            changes: [
                "新增智能整理提示词设置入口，可在主界面直接打开编辑。",
                "支持分别调整开发需求、润色、笔记和聊天四类提示词模板。",
                "提示词模板保存到本机设置，支持恢复默认；空模板会自动回退默认提示词。",
                "自定义模板若遗漏原始语音占位符，会自动补入原始语音文本，避免整理内容丢失。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.28 (Build 185)",
            date: "2026-06-23",
            changes: [
                "最近转录中的 token 费用展示从美元改为人民币估算。",
                "费用内部仍保留 DeepSeek 官方美元计价字段，展示时按固定汇率折算为 ¥。",
                "旧历史记录无需迁移，会在界面刷新时自动按人民币格式显示。",
                "新增费用展示检查，确保历史记录费用不再显示美元符号。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.27 (Build 184)",
            date: "2026-06-23",
            changes: [
                "新增固定快捷键 Shift + \\，可快速打开或关闭自动翻译。",
                "快捷键触发后会立即保存自动翻译开关状态，并在主状态详情中提示当前状态。",
                "自动翻译开关增加提示文案，说明可用 Shift + \\ 快速切换。",
                "该快捷键不占用主录音快捷键或备用录音快捷键配置。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.26 (Build 183)",
            date: "2026-06-23",
            changes: [
                "将快捷键展示和录入入口合并为同一个按钮，按钮直接显示当前快捷键。",
                "点击当前快捷键按钮即可重新录入，录入完成后按钮标题自动更新为新快捷键。",
                "快捷键区域回到两行并排按钮布局，减少右侧空间占用。",
                "最近转录复制按钮在翻译记录中会复制界面展示的双语内容。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.25 (Build 182)",
            date: "2026-06-23",
            changes: [
                "修复快捷键卡片两层布局在右侧总高度不足时被压缩裁切的问题。",
                "快捷键卡片增加垂直抗压缩约束，确保主快捷键和备用快捷键按钮完整显示。",
                "最近转录列表高度调整为 210，为快捷键区域留出稳定空间。",
                "保持窗口尺寸不变。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.24 (Build 181)",
            date: "2026-06-23",
            changes: [
                "将快捷键卡片改为上下两层结构，上层展示快捷键名称和键帽，下层展示操作按钮。",
                "主快捷键和备用快捷键不再挤在同一条横线上，按钮文字保留完整可读空间。",
                "最近转录列表高度调整为 258，仍高于早期版本，同时给快捷键区域让出舒适高度。",
                "保留窗口整体尺寸不变。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.23 (Build 180)",
            date: "2026-06-23",
            changes: [
                "优化快捷键卡片的横向空间分配，主快捷键行不再显得拥挤。",
                "缩短键帽固定宽度，同时给“恢复 Fn”操作按钮保留更宽文本空间。",
                "左侧实时草稿卡片固定为正常高度，避免空内容时被撑成长条。",
                "保持窗口尺寸和最近转录列表高度不变。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.22 (Build 179)",
            date: "2026-06-23",
            changes: [
                "自动翻译链路改为先按智能整理设置处理文本，再执行中英翻译。",
                "自动翻译不再绕过智能整理，Codex 等场景会先整理成更清晰的需求文本再翻译。",
                "如果整理和翻译都调用 DeepSeek，最近转录中的 token 与费用统计改为两次调用合计。",
                "翻译超时时回退为整理后文本，并在状态中明确提示“翻译未完成”。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.21 (Build 178)",
            date: "2026-06-23",
            changes: [
                "将实时草稿移入左侧边栏，和状态、模型入口放在同一列。",
                "右侧内容区移除实时草稿段落，减少信息拥挤。",
                "增大最近转录列表视口，让历史记录一次能展示更多内容。",
                "保持原有录音、识别、粘贴和 DeepSeek 处理逻辑不变，仅调整主界面布局。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.20 (Build 177)",
            date: "2026-06-23",
            changes: [
                "新增 DeepSeek token 和费用统计，使用接口返回的 usage 字段计算。",
                "智能整理和自动翻译记录会保存 total tokens 与估算费用。",
                "最近转录每条记录标题右侧展示 token 数和美元费用。",
                "费用按 deepseek-v4-flash 当前官方价格估算，区分缓存命中输入、缓存未命中输入和输出 token。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.19 (Build 176)",
            date: "2026-06-23",
            changes: [
                "新增自动翻译开关，可独立于智能整理启用。",
                "新增翻译方向选择：中译英、英译中。",
                "自动翻译开启后粘贴译文，最近转录同时展示原始语音文本和译文。",
                "DeepSeek Key 文案更新为同时用于智能整理和自动翻译。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.18 (Build 175)",
            date: "2026-06-23",
            changes: [
                "将 Smart Rewrite 的开发需求、润色、笔记和聊天提示词全部改为中文。",
                "新增强约束：中文输入必须中文输出，不要翻译成英文，除非用户明确要求翻译。",
                "DeepSeek system prompt 同步改为中文，避免英文系统提示诱导模型输出英文。",
                "新增 Prompt 检查，防止后续误删语言保持规则。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.17 (Build 174)",
            date: "2026-06-23",
            changes: [
                "新增 AI 整理过程进度态，DeepSeek 润色或开发需求整理时主状态卡显示不确定进度条。",
                "识别完成后仅在确实需要调用 AI 整理时显示“AI 整理中”，原文模式不再误显示处理过程。",
                "整理过程中胶囊保留“整理中”提示，避免用户误以为应用卡住。",
                "AI 整理过程文案展示模型名称和最长等待时间。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.16 (Build 173)",
            date: "2026-06-23",
            changes: [
                "DeepSeek 智能整理默认模型从兼容名 deepseek-chat 切换为 deepseek-v4-flash。",
                "请求体显式设置 thinking disabled，避免进入默认 thinking 模式，提高短文本整理响应速度。",
                "智能整理完成后的状态文案展示实际使用模型名称，例如 DeepSeek v4 flash。",
                "将 DeepSeek 输出上限收敛到 400 tokens，减少无谓生成开销。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.15 (Build 172)",
            date: "2026-06-23",
            changes: [
                "接入 DeepSeek 作为 Smart Rewrite 远程整理引擎，使用 deepseek-chat，不使用 thinking/reasoner 模型。",
                "新增 DeepSeek API Key 弹窗录入入口，Key 保存到 macOS Keychain，不写入 UserDefaults 或日志。",
                "Key 缺失、请求失败或 3 秒超时时自动回退原始识别文本，保证粘贴流程不被远程服务阻塞。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.14 (Build 171)",
            date: "2026-06-23",
            changes: [
                "新增最终识别后的 Smart Rewrite 后处理层，保留实时预览原始速度，不改变 SenseVoice ASR 管线。",
                "新增智能整理模式：自动、原文、润色、开发需求，并保存用户选择。",
                "新增 SmartInputRouter、RewriteProfile、SmartRewriteEngine 和 PromptBuilder，为后续本地或远程 LLM 改写预留扩展点。",
                "当前默认使用 NoopRewriteEngine，失败或超时时自动回退原始最终识别文本，确保粘贴流程不被阻塞。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.13 (Build 170)",
            date: "2026-06-18",
            changes: [
                "提交 cc 优化后的双栏深色 dashboard 主界面，保留左侧品牌、状态、模型入口和右侧权限、快捷键、选项、实时草稿、最近转录。",
                "新增共享 UI 组件，用于卡片、分区标题、按键胶囊、自绘开关和主界面小波形。",
                "主界面状态点跟随录音、检测、识别、完成和错误状态变色，录音结束后重置小波形。",
                "为自绘开关补充无障碍标签，并清理不应提交的系统缩略图缓存文件。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.12 (Build 169)",
            date: "2026-06-18",
            changes: [
                "修正主界面 logo 的视觉对齐：裁剪图标透明边距后显示，使可见黄块与使用说明左侧对齐。",
                "保持标题和版本信息距离可见 logo 右边缘 24 像素。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.11 (Build 168)",
            date: "2026-06-18",
            changes: [
                "补齐版本递增规则：每次 Build 递增时，第三位版本号同步递增。",
                "补录 Build 165、166、167 对应的 1.2.8、1.2.9、1.2.10 版本历史。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.10 (Build 167)",
            date: "2026-06-18",
            changes: [
                "新增开机自动启动开关，可在主界面运行选项中注册或移除 macOS 登录项。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.9 (Build 166)",
            date: "2026-06-18",
            changes: [
                "调整主界面品牌区对齐，logo 与使用说明左侧对齐，标题区距 logo 24 像素。",
                "标题和版本信息距 logo 调整为 24 像素。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.8 (Build 165)",
            date: "2026-06-18",
            changes: [
                "移除主界面的高级诊断入口和隐藏的输入设备选择行。",
                "回退深色 dashboard 卡片实验，恢复稳定的单栏主界面。",
                "恢复主界面原有权限、快捷键、本地模型和最近转录布局。",
                "恢复中文状态文案和最近转录列表样式，避免不可用的卡片错位。",
                "将主界面品牌 logo 放大到红框标注的主视觉尺寸。",
                "直接输入实验后，默认文本写入方式恢复为剪贴板粘贴通道。",
                "新增直接 Unicode 输入实验通道，测试不经过剪贴板写入识别文本。",
                "状态栏图标按 22x14 精确尺寸重绘。",
                "将状态栏图标尺寸收敛到接近系统输入法图标大小。",
                "进一步放大主界面 logo 和状态栏横向徽标。",
                "状态栏图标改为更大的横向圆角徽标。",
                "放大主界面左上角品牌图标，提升应用内 logo 识别度。",
                "替换应用图标为极简黄色圆角方块样式。",
                "发布 1.2.8，优化录音胶囊七频段波形动效。",
                "提高波形对轻声输入的响应灵敏度，同时降低静音起始高度，扩大动态变化空间。",
                "调整波形视觉权重，让中间频段更高、两侧更收敛，动作更有力度。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.7 (Build 147)",
            date: "2026-06-15",
            changes: [
                "发布 1.2.7，提交设置边界和电脑声音恢复体验优化。",
                "录音结束后延迟并渐进恢复电脑声音，减少声音突然恢复的突兀感。",
                "抽出主界面设置存储，减少 ViewController 直接读写 UserDefaults。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.6 (Build 144)",
            date: "2026-06-15",
            changes: [
                "发布 1.2.6，合并连续录音、通话场景和系统音频体验修复。",
                "优化录音期间降低电脑声音的恢复策略，用户手动调音量后不再被强行改回。",
                "接入录音任务状态机门禁，旧任务识别完成后不会在新录音过程中抢焦点粘贴。",
                "新增可选的录音期间降低电脑声音，减少外放内容进入麦克风影响识别。",
                "完成 P0 第一阶段会话状态收敛，使用 SpeechSession 管理单次录音上下文。",
                "输入设备入口移入高级诊断，默认不在主界面展示。",
                "恢复输入设备选择入口，通话场景继续支持手动选择麦克风。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.5 (Build 136)",
            date: "2026-06-15",
            changes: [
                "发布 1.2.5，提交版本历史视觉层级优化。",
                "版本历史条目标题改为柔和金色，增强版本号和日期与正文的区分。",
                "新增输入设备选择，可在通话场景下锁定 iPhone、耳机或 MacBook 麦克风。",
                "移除输入设备列表的每秒刷新，降低通话场景下的主线程卡顿和操作延迟。",
                "优化空录音提示文案和右上角详情换行，避免关键操作被截断。",
                "增加麦克风输入诊断，通话中无输入或近似静音时给出更明确提示。",
                "提高胶囊实时预览首段响应速度，并保留 realtime VAD 过滤。",
                "优化胶囊宽度动画，单次录音内只增不缩，减少慢速说话时的抽动。",
                "停顿自动完成等待时长调整为 1.5 秒，并增加 3 秒初始静音自动结束。",
                "长按录音不受停顿自动完成影响，仍保持松手结束。",
                "修复模型校验缓存并发保护，首次模型校验移到后台执行。",
                "修复模型下载 fallback、安装入口和用户目录模型识别。",
                "第三方组件与模型授权窗口改为左对齐展示。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.2 (Build 126)",
            date: "2026-06-15",
            changes: [
                "应用主界面固定使用黑色主题，不再跟随系统外观切换。",
                "新增备用快捷键入口，同一录音功能可由两个快捷键触发。",
                "录音结束后隐藏胶囊中的“检测中”状态，减少底部浮窗干扰。",
                "优化麦克风释放路径，停止录音后销毁 AVAudioEngine 输入会话。",
                "修复 macOS 重启、关机或注销时应用后台驻留逻辑阻止系统退出的问题。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.1",
            date: "2026-06-14",
            changes: [
                "发布 Lite 架构合并候选版本。",
                "保留 SenseVoice 单模型轻量形态，并内置 Silero VAD。",
                "final ASR 前先检测人声，录音为空时不进入识别和粘贴。",
                "实时预览快照也先经过 VAD，降低静音和噪音触发胶囊吐字的概率。"
            ]
        ),
        VersionEntry(
            version: "版本 1.2.0",
            date: "2026-06-14",
            changes: [
                "将架构重构成果迁移到 Lite 主线，作为新的轻量版基线。",
                "完成 Domain、Infrastructure、Presentation 和 Application Coordinator 分层。",
                "移除旧 Python worker、Windows MVP 和未采用的预览实验链路。",
                "保持 SenseVoice-only 产品形态，完整音频 final 识别仍是唯一粘贴来源。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.13",
            date: "2026-06-13",
            changes: [
                "新增顶部状态栏常驻入口，应用关闭窗口后仍可后台运行。",
                "隐藏 Dock 栏图标，让 TypeWhale 以菜单栏应用方式工作。",
                "状态栏仅显示应用图标，点击后可打开主界面或完全退出应用。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.11",
            date: "2026-06-13",
            changes: [
                "最终录音文件末尾追加短静音，降低 Qwen3-ASR 偶发尾字丢失。",
                "适度提高 Qwen3-ASR 最大生成 token 数，改善较长句子的收尾完整性。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.10",
            date: "2026-06-13",
            changes: [
                "统一清理实时预览和最终识别中的模型特殊标记残留。",
                "修复实时预览偶发显示 system 标记的问题。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.9",
            date: "2026-06-13",
            changes: [
                "最近转录历史增加每条识别时间标题。",
                "历史记录保存文本和本地识别耗时，并兼容旧版纯文本历史。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.8",
            date: "2026-06-13",
            changes: [
                "关闭 Qwen3-ASR 模型级热词注入，避免热词列表被模型直接输出。",
                "保留开发者词库资源，但默认不参与识别链路，优先恢复转录可靠性。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.7",
            date: "2026-06-13",
            changes: [
                "限制 Qwen3-ASR 热词注入数量，避免超过模型上下文上限。",
                "保留完整开发者词库文件，同时只向 Qwen 注入高优先级热词。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.6",
            date: "2026-06-13",
            changes: [
                "改用 sherpa-onnx 官方热词能力增强开发者词库。",
                "Qwen3-ASR 使用模型级 hotwords 导入开发者词库。",
                "移除最终文本的词库后处理替换，避免误伤正常识别结果。",
                "确认当前 SenseVoice 后端不支持 contextual biasing，避免接入不可用热词路径。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.5",
            date: "2026-06-13",
            changes: [
                "补充 SenseVoice 常见英文误识别纠正规则。",
                "降低 Thanks, voice 这类专有名词误识别对最终粘贴结果的影响。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.4",
            date: "2026-06-13",
            changes: [
                "内置开发者词库，覆盖常见中英文开发术语。",
                "最终识别文本在粘贴前自动做词库增强纠错。",
                "词库随 App 资源打包，后续可扩展为导入用户词库。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.3",
            date: "2026-06-13",
            changes: [
                "增加 Qwen3-ASR 0.6B 实验模型作为备选识别引擎。",
                "默认启动回到 SenseVoice，Qwen3 仅在本次运行中手动切换启用。",
                "模型切换选中态改为黄色，并调整顶部状态区到页面右侧。",
                "扩大最近转录列表空间，改善主界面信息层级。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.2",
            date: "2026-06-12",
            changes: [
                "完善版本历史弹窗排版。",
                "发版前记录统一改为 Build 编号。",
                "缓存历史内容并预热弹窗，提升问号入口打开速度。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.1",
            date: "2026-06-12",
            changes: [
                "主页面增加应用标志、版本号和使用说明。",
                "使用说明移动到权限区上方。",
                "版本号旁增加历史版本入口。"
            ]
        ),
        VersionEntry(
            version: "版本 1.1.0",
            date: "2026-06-12",
            changes: [
                "优化录音胶囊为更紧凑的小浮窗。",
                "实时预览支持两行展示与小到大过渡。",
                "加入界面缓存层，历史文字原位替换，尾巴逐字吐出。",
                "去除识别完成后的固定停留。"
            ]
        ),
        VersionEntry(
            version: "版本 1.0.0",
            date: "2026-06-12",
            changes: [
                "首个封版版本。",
                "原生苹果桌面主程序，内置本地语音识别模型。",
                "支持功能键全局录音、完整识别、自动粘贴和最近转录。",
                "支持自定义快捷键与胶囊实时预览。"
            ]
        ),
        VersionEntry(
            version: "Build 33",
            date: "2026-06-12",
            changes: [
                "将本地语音识别模型直接内置到应用包内。"
            ]
        ),
        VersionEntry(
            version: "Build 32",
            date: "2026-06-12",
            changes: [
                "打通原生语音输入流程。"
            ]
        ),
        VersionEntry(
            version: "Build 31",
            date: "2026-06-04",
            changes: [
                "把独立识别运行环境打包进应用。"
            ]
        ),
        VersionEntry(
            version: "Build 30",
            date: "2026-06-04",
            changes: [
                "让已安装应用不再依赖源码目录运行。"
            ]
        ),
        VersionEntry(
            version: "Build 29",
            date: "2026-06-04",
            changes: [
                "将实时预览移动到有尺寸边界的胶囊浮窗中。"
            ]
        ),
        VersionEntry(
            version: "Build 28",
            date: "2026-06-04",
            changes: [
                "加固跨应用文本写入和粘贴兜底流程。"
            ]
        ),
        VersionEntry(
            version: "Build 27",
            date: "2026-06-04",
            changes: [
                "恢复主窗口左对齐的紧凑布局。"
            ]
        ),
        VersionEntry(
            version: "Build 26",
            date: "2026-06-04",
            changes: [
                "收紧主窗口各功能板块的布局。"
            ]
        ),
        VersionEntry(
            version: "Build 25",
            date: "2026-06-04",
            changes: [
                "诊断功能键系统动作冲突，并增加禁用提示。"
            ]
        ),
        VersionEntry(
            version: "Build 24",
            date: "2026-06-04",
            changes: [
                "修复最近转录列表的固定视口布局。"
            ]
        ),
        VersionEntry(
            version: "Build 23",
            date: "2026-06-04",
            changes: [
                "实现跨应用实时输入能力。"
            ]
        ),
        VersionEntry(
            version: "Build 22",
            date: "2026-06-04",
            changes: [
                "增加功能键单击切换录音、长按录音的手势。"
            ]
        ),
        VersionEntry(
            version: "Build 21",
            date: "2026-06-04",
            changes: [
                "修复实时草稿区域高度导致的布局问题。"
            ]
        ),
        VersionEntry(
            version: "Build 20",
            date: "2026-06-04",
            changes: [
                "限制主窗口尺寸，并优化最近转录排版。"
            ]
        ),
        VersionEntry(
            version: "Build 19",
            date: "2026-06-04",
            changes: [
                "加入独立的实验性实时转录能力。"
            ]
        ),
        VersionEntry(
            version: "Build 18",
            date: "2026-06-04",
            changes: [
                "把独立分发能力加入开发优先级。"
            ]
        ),
        VersionEntry(
            version: "Build 17",
            date: "2026-06-04",
            changes: [
                "增强录音波形，并增加最近转录历史。"
            ]
        ),
        VersionEntry(
            version: "Build 16",
            date: "2026-06-04",
            changes: [
                "抽离独立录音任务模型，增强音频处理线程安全。"
            ]
        ),
        VersionEntry(
            version: "Build 15",
            date: "2026-06-04",
            changes: [
                "用真实频段数据驱动录音波形。"
            ]
        ),
        VersionEntry(
            version: "Build 14",
            date: "2026-06-04",
            changes: [
                "优化录音胶囊的视觉效果。"
            ]
        ),
        VersionEntry(
            version: "Build 13",
            date: "2026-06-04",
            changes: [
                "拆分权限状态和全局快捷键监听状态。"
            ]
        ),
        VersionEntry(
            version: "Build 12",
            date: "2026-06-04",
            changes: [
                "修复应用重新打开时可能崩溃的问题。"
            ]
        ),
        VersionEntry(
            version: "Build 11",
            date: "2026-06-04",
            changes: [
                "修复应用失焦后全局控制键监听不可用的问题。"
            ]
        ),
        VersionEntry(
            version: "Build 10",
            date: "2026-06-04",
            changes: [
                "将主程序迁移到原生苹果桌面技术。"
            ]
        ),
        VersionEntry(
            version: "Build 09",
            date: "2026-06-04",
            changes: [
                "按苹果电脑系统视觉规范重新调整应用图标尺寸。"
            ]
        ),
        VersionEntry(
            version: "Build 08",
            date: "2026-06-04",
            changes: [
                "修复原生权限检测和应用生命周期崩溃问题。"
            ]
        ),
        VersionEntry(
            version: "Build 07",
            date: "2026-06-04",
            changes: [
                "移除应用图标边角白边。"
            ]
        ),
        VersionEntry(
            version: "Build 06",
            date: "2026-06-04",
            changes: [
                "增加语音输入应用图标和苹果电脑启动器。"
            ]
        ),
        VersionEntry(
            version: "Build 05",
            date: "2026-06-03",
            changes: [
                "收紧主页面布局，并让输入电平变化更平滑。"
            ]
        ),
        VersionEntry(
            version: "Build 04",
            date: "2026-06-03",
            changes: [
                "增加可切换的另一套中文识别选项。"
            ]
        ),
        VersionEntry(
            version: "Build 03",
            date: "2026-06-03",
            changes: [
                "将权限诊断升级为主页面，并恢复麦克风权限检测。"
            ]
        ),
        VersionEntry(
            version: "Build 02",
            date: "2026-06-03",
            changes: [
                "重构应用控制器，并加固识别后粘贴流程。"
            ]
        ),
        VersionEntry(
            version: "Build 01",
            date: "2026-06-03",
            changes: [
                "建立语音输入项目基础版本。"
            ]
        )
    ]

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 390))

        let title = label("版本历史", size: 15, weight: .semibold)
        title.alignment = .left
        let subtitle = label("包含正式版本和 37 个 Build 记录，向下滚动查看。", size: 12)
        subtitle.alignment = .left
        subtitle.textColor = NSColor(calibratedWhite: 1, alpha: 0.82)

        let historyText = NSTextView()
        historyText.isEditable = false
        historyText.isSelectable = true
        historyText.drawsBackground = false
        historyText.textContainerInset = NSSize(width: 0, height: 4)
        historyText.textContainer?.lineFragmentPadding = 0
        historyText.textContainer?.widthTracksTextView = true
        historyText.isHorizontallyResizable = false
        historyText.isVerticallyResizable = true
        historyText.autoresizingMask = [.width]
        historyText.minSize = NSSize(width: 0, height: 0)
        historyText.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        historyText.textStorage?.setAttributedString(Self.cachedHistoryText)

        let scroll = NSScrollView()
        scroll.documentView = historyText
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        DispatchQueue.main.async {
            historyText.scrollToBeginningOfDocument(nil)
        }

        let stack = NSStackView(views: [title, subtitle, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private static let cachedHistoryText: NSAttributedString = {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 6

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.50, alpha: 0.96),
            .paragraphStyle: paragraph,
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.78),
            .paragraphStyle: paragraph,
        ]
        let separatorAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.35),
            .paragraphStyle: paragraph,
        ]

        for entry in entries {
            result.append(NSAttributedString(string: "\(entry.version)  \(entry.date)\n", attributes: headerAttrs))
            for change in entry.changes {
                result.append(NSAttributedString(string: "- \(change)\n", attributes: bodyAttrs))
            }
            result.append(NSAttributedString(string: "──────────────\n", attributes: separatorAttrs))
        }
        return result
    }()
}
