import Foundation

/// 发布渠道。当前所有构建均为本地/测试分发（见 README），故默认 `.local`。
/// TODO(P1 CI/CD)：发布流水线建立后，用编译标志或 Info.plist 注入真实渠道（beta/stable）。
enum ReleaseChannel: String {
    case local
    case beta
    case stable

    static var current: ReleaseChannel { .local }
}

/// 已登记的产品分析事件名（白名单）。新增事件必须在此登记，杜绝散落字符串。
/// 与 docs/埋点方案.md §4 事件字典一一对应。
enum AnalyticsEventName: String {
    // 激活漏斗
    case appLaunch = "app_launch"
    case permissionPrompt = "permission_prompt"
    case permissionResult = "permission_result"
    case modelDownloadStart = "model_download_start"
    case modelDownloadResult = "model_download_result"
    case firstSuccessfulTranscription = "first_successful_transcription"
    // 核心动作
    case recordStart = "record_start"
    case recordComplete = "record_complete"
    case asrComplete = "asr_complete"
    case asrFail = "asr_fail"
    case pasteResult = "paste_result"
    case smartRewriteRun = "smart_rewrite_run"
    case screenshotCapture = "screenshot_capture"
    case ocrRun = "ocr_run"
    case screenshotTranslate = "screenshot_translate"
    // 质量与性能
    case perfAsrLatency = "perf_asr_latency"
    case perfPasteLatency = "perf_paste_latency"
    // 变现漏斗（付费体系上线后启用）
    case paywallView = "paywall_view"
    case trialStart = "trial_start"
    case purchaseSuccess = "purchase_success"
    case licenseActivate = "license_activate"
    case licenseCheckFailed = "license_check_failed"
}

/// 事件参数值的封闭类型：只允许受控枚举字符串、计数/分桶、布尔。
/// 从类型层面拒绝自由文本，杜绝识别内容/剪贴板/路径等泄露（见 docs/埋点方案.md 红线）。
enum ObservabilityValue {
    /// 受控枚举值，例如 "hold"、"granted"。调用方须保证来自受控枚举的 rawValue；
    /// Redactor 仍会对疑似自由文本做兜底脱敏。
    case token(String)
    /// 计数。
    case count(Int)
    /// 预先分桶后的标签，例如 "500_1000"。
    case bucket(String)
    /// 布尔标志。
    case flag(Bool)
}
