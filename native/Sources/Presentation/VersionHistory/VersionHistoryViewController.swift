import AppKit

final class VersionHistoryViewController: NSViewController {
    private struct VersionEntry {
        let version: String
        let date: String
        let changes: [String]
    }

    private static let entries = [
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
        let subtitle = label("包含正式版本和 33 个 Build 记录，向下滚动查看。", size: 12)
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
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
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
