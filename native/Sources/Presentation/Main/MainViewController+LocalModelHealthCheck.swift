import AppKit

extension MainViewController {
    @objc func runLocalModelHealthCheck() {
        guard localModelHealthCheckTask == nil else { return }

        localModelHealthCheckButton.title = "检测中"
        localModelHealthCheckButton.isEnabled = false
        localModelHealthCopyButton.title = "复制诊断"
        localModelHealthCopyButton.isEnabled = false
        localModelHealthCopyButton.setAccessibilityValue(nil)
        localModelHealthDiagnosticText = nil
        localModelHealthStatusLabel.stringValue = "正在准备检测…"
        localModelHealthStatusLabel.textColor = UITheme.sectionTitle
        localModelHealthDetailLabel.stringValue =
            "检测不会切换模型、上传或修改文件；诊断不含录音、转录、提示词和密钥"
        postLocalModelHealthAccessibilityUpdate()

        let service = localModelHealthCheckService
        localModelHealthCheckTask = Task { [weak self] in
            let report = await service.run { [weak self] stage in
                DispatchQueue.main.async {
                    self?.renderLocalModelHealthCheckProgress(stage)
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.renderLocalModelHealthCheckReport(report)
                self.localModelHealthCheckTask = nil
            }
        }
    }

    @objc func copyLocalModelHealthDiagnostic() {
        guard let diagnostic = localModelHealthDiagnosticText,
              !diagnostic.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnostic, forType: .string)
        localModelHealthCopyButton.title = "已复制"
        localModelHealthCopyButton.setAccessibilityValue("诊断已复制")
        localModelHealthCopyButton.toolTip = "已复制脱敏诊断；不含录音、转录、提示词和密钥"
    }

    private func renderLocalModelHealthCheckProgress(
        _ stage: LocalModelHealthCheckStage
    ) {
        guard localModelHealthCheckTask != nil else { return }
        localModelHealthCheckButton.isEnabled = false
        localModelHealthCheckStatus(stage)
        localModelHealthStatusLabel.textColor = UITheme.sectionTitle
        localModelHealthDetailLabel.stringValue = "请稍候，主窗口和其他设置仍可正常使用"
        localModelHealthStatusLabel.setAccessibilityValue(
            localModelHealthStatusLabel.stringValue
        )
        postLocalModelHealthAccessibilityUpdate()
    }

    private func localModelHealthCheckStatus(_ stage: LocalModelHealthCheckStage) {
        switch stage {
        case .runtimeImport:
            localModelHealthStatusLabel.stringValue = "正在检查本地运行环境…"
        case .modelIntegrity:
            localModelHealthStatusLabel.stringValue = "正在校验 Qwen3 4B 模型文件…"
        case .modelWarmup:
            localModelHealthStatusLabel.stringValue = "正在加载本地模型…"
        case .minimalGeneration:
            localModelHealthStatusLabel.stringValue = "正在验证模型生成…"
        }
    }

    private func renderLocalModelHealthCheckReport(
        _ report: LocalModelHealthCheckReport
    ) {
        localModelHealthCheckButton.title = "再次检测"
        localModelHealthCheckButton.isEnabled = true
        localModelHealthCopyButton.title = "复制诊断"
        localModelHealthCopyButton.isHidden = false
        localModelHealthCopyButton.isEnabled = true
        localModelHealthCopyButton.setAccessibilityValue(nil)
        localModelHealthCopyButton.toolTip = "复制不含录音、转录、提示词和密钥的诊断信息"
        localModelHealthDiagnosticText = report.diagnosticText

        if report.passed {
            localModelHealthStatusLabel.stringValue = report.userMessage
            localModelHealthStatusLabel.textColor = UITheme.brandGreen
            localModelHealthDetailLabel.stringValue = successDetail(report)
        } else if report.errorCode == "runtime_busy" ||
                    report.errorCode == "check_in_progress" {
            localModelHealthStatusLabel.stringValue = "暂时无法检测：\(report.userMessage)"
            localModelHealthStatusLabel.textColor = .systemOrange
            let stage = report.failedStage.map(stageName) ?? "开始前"
            let code = report.errorCode ?? "unknown"
            localModelHealthDetailLabel.stringValue =
                "停止阶段：\(stage) · 状态码：\(code)\n\(recommendation(for: code))"
        } else {
            localModelHealthStatusLabel.stringValue = "本地模型不可用：\(report.userMessage)"
            localModelHealthStatusLabel.textColor = .systemRed
            let stage = report.failedStage.map(stageName) ?? "开始前"
            let code = report.errorCode ?? "unknown"
            localModelHealthDetailLabel.stringValue =
                "失败阶段：\(stage) · 错误码：\(code)\n\(recommendation(for: code))"
        }
        localModelHealthStatusLabel.setAccessibilityValue(
            localModelHealthStatusLabel.stringValue
        )
        localModelHealthDetailLabel.setAccessibilityValue(
            localModelHealthDetailLabel.stringValue
        )
        postLocalModelHealthAccessibilityUpdate()
    }

    private func postLocalModelHealthAccessibilityUpdate() {
        localModelHealthStatusLabel.setAccessibilityValue(
            localModelHealthStatusLabel.stringValue
        )
        NSAccessibility.post(
            element: localModelHealthStatusLabel,
            notification: .valueChanged
        )
    }

    private func successDetail(_ report: LocalModelHealthCheckReport) -> String {
        var components = [
            String(format: "总耗时 %.2f 秒", report.elapsedMS / 1_000),
        ]
        if let ttft = report.metrics?.ttftMS {
            components.append(String(format: "首 token %.0f ms", ttft))
        }
        if let tokensPerSecond = report.metrics?.tokensPerSecond {
            components.append(String(format: "%.1f token/s", tokensPerSecond))
        }
        if let peakRSSBytes = report.metrics?.peakRSSBytes {
            components.append(String(format: "峰值内存 %.0f MB", Double(peakRSSBytes) / 1_048_576))
        }
        return components.joined(separator: " · ")
    }

    private func stageName(_ stage: LocalModelHealthCheckStage) -> String {
        switch stage {
        case .runtimeImport: return "运行环境"
        case .modelIntegrity: return "模型文件"
        case .modelWarmup: return "模型加载"
        case .minimalGeneration: return "最小生成"
        }
    }

    private func recommendation(for code: String) -> String {
        switch code {
        case "runtime_busy", "check_in_progress":
            return "建议：等待当前整理或翻译完成后再次检测。"
        case "runtime_import_failed", "runtime_version_mismatch",
             "runtime_dependency_missing", "runtime_probe_timeout",
             "runtime_probe_launch_failed", "runtime_python_missing",
             "runtime_missing", "runtime_unavailable":
            return "建议：复制诊断；当前运行环境需要兼容更新，检测不会自动改动文件。"
        case "model_missing", "model_integrity_failed":
            return "建议：复制诊断并确认 TypeWhale 受管模型安装状态。"
        case "runtime_timeout":
            return "建议：等待其他高负载任务结束后再次检测。"
        default:
            return "建议：再次检测；如果仍失败，请复制诊断用于排查。"
        }
    }
}
