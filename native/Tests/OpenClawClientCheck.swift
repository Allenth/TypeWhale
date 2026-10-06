import Foundation

@main
struct OpenClawClientCheck {
    static func main() {
        let direct = OpenClawCommandClient.extractReplyText(from: #"{"replyText":"好的，我在。"}"#)
        precondition(direct == "好的，我在。", "replyText should be preferred")

        let nested = OpenClawCommandClient.extractReplyText(from: #"{"result":{"message":{"content":"已收到"}}}"#)
        precondition(nested == "已收到", "nested content should be extracted")

        let plain = OpenClawCommandClient.extractReplyText(from: "纯文本回复")
        precondition(plain == "纯文本回复", "plain output should be preserved")

        let openClawEnvelope = OpenClawCommandClient.extractReplyText(from: #"""
        {
          "runId": "probe",
          "status": "ok",
          "summary": "completed",
          "result": {
            "payloads": [
              {
                "text": "收到 🦞\n数字也识别得到，没掉线。",
                "mediaUrl": null
              }
            ],
            "finalAssistantVisibleText": "收到 🦞\n数字也识别得到，没掉线。"
          }
        }
        """#)
        precondition(
            openClawEnvelope == "收到 🦞\n数字也识别得到，没掉线。",
            "OpenClaw envelope extraction should prefer assistant payload text over status/summary fields"
        )

        let nestedJSONString = OpenClawCommandClient.extractReplyText(from: #"""
        {
          "replyText": "{\"finalAssistantVisibleText\":\"真正可显示的回复\",\"status\":\"ok\"}"
        }
        """#)
        precondition(
            nestedJSONString == "真正可显示的回复",
            "OpenClaw display extraction should parse JSON strings and extract their assistant text"
        )

        let metadataOnlyJSON = OpenClawCommandClient.extractReplyText(from: #"""
        {
          "status": "ok",
          "summary": "completed",
          "usage": {"inputTokens": 12, "outputTokens": 3}
        }
        """#)
        precondition(
            metadataOnlyJSON.isEmpty,
            "OpenClaw display extraction should not show metadata-only JSON objects"
        )

        let rawJSONString = OpenClawCommandClient.extractReplyText(from: #"""
        {
          "replyText": "{\"status\":\"ok\",\"summary\":\"completed\",\"usage\":{\"inputTokens\":12}}"
        }
        """#)
        precondition(
            rawJSONString.isEmpty,
            "OpenClaw display extraction should not show raw JSON strings when they contain no assistant text"
        )

        let displayEvents = OpenClawCommandClient.extractDisplayEvents(from: #"""
        {
          "status": "running",
          "livenessState": "executing",
          "progress": {"message": "正在查询天气", "percent": 0.42},
          "executionTrace": [
            {"toolName": "weather.lookup", "summary": "查询深圳天气"}
          ],
          "result": {
            "finalAssistantVisibleText": "深圳明天多云。"
          }
        }
        """#)
        precondition(
            displayEvents.map(\.text).contains("OpenClaw 正在执行"),
            "OpenClaw display events should expose a readable execution state"
        )
        precondition(
            displayEvents.map(\.text).contains("正在查询天气"),
            "OpenClaw display events should expose safe progress text"
        )
        precondition(
            displayEvents.map(\.text).contains("工具：weather.lookup · 查询深圳天气"),
            "OpenClaw display events should expose safe tool summaries"
        )
        precondition(
            !displayEvents.map(\.text).joined(separator: "\n").contains("{"),
            "OpenClaw display events should never show raw JSON"
        )

        let staleNVMPath = "/Users/test/.nvm/versions/node/v24.13.0/bin"
        let sharedChildEnvironment = OpenClawCommandClient.processEnvironment(base: [
            "HOME": "/Users/test",
            "PATH": "\(staleNVMPath):/usr/bin:/bin:/usr/sbin:/sbin"
        ])
        let sharedPathComponents = (sharedChildEnvironment["PATH"] ?? "").split(separator: ":").map(String.init)
        precondition(
            sharedPathComponents.first == staleNVMPath,
            "Shared TTS child-process environment should preserve the inherited PATH order"
        )
        precondition(
            sharedPathComponents.firstIndex(of: staleNVMPath)! < sharedPathComponents.firstIndex(of: "/usr/bin")!,
            "Shared child-process environment should preserve relative ordering of inherited tools"
        )
        precondition(sharedPathComponents.contains("/opt/homebrew/bin"), "Shared child-process PATH should include Homebrew bin for GUI launches")
        precondition(sharedPathComponents.contains("/opt/homebrew/opt/node@24/bin"), "Shared child-process PATH should include Homebrew node@24")
        precondition(sharedPathComponents.contains("/usr/local/bin"), "Shared child-process PATH should include Intel Homebrew bin")
        precondition(sharedChildEnvironment["HOME"] == "/Users/test", "Shared child-process environment should preserve existing variables")

        let preferredNodeDirectory = "/opt/homebrew/opt/node@24/bin"
        let openClawEnvironment = OpenClawCommandClient.openClawCLIEnvironment(
            base: [
                "HOME": "/Users/test",
                "PATH": "\(staleNVMPath):/usr/bin:/bin:/usr/sbin:/sbin"
            ],
            preferredNodeDirectory: preferredNodeDirectory
        )
        let openClawPathComponents = (openClawEnvironment["PATH"] ?? "").split(separator: ":").map(String.init)
        precondition(
            openClawPathComponents.first == preferredNodeDirectory,
            "OpenClaw CLI should prefer a compatible Node runtime over an inherited stale NVM Node"
        )
        precondition(
            Array(openClawPathComponents.dropFirst().prefix(5)) == [staleNVMPath, "/usr/bin", "/bin", "/usr/sbin", "/sbin"],
            "OpenClaw CLI should preserve the complete relative order of inherited tool paths after the Node override"
        )
        precondition(
            openClawPathComponents.filter { $0 == preferredNodeDirectory }.count == 1,
            "OpenClaw CLI should deduplicate the preferred Node runtime path"
        )
        precondition(openClawPathComponents.contains("/opt/homebrew/bin"), "OpenClaw CLI should retain Homebrew tool fallbacks")
        precondition(openClawPathComponents.contains("/usr/local/bin"), "OpenClaw CLI should retain Intel Homebrew tool fallbacks")

        let acceptedNodeVersions = ["v22.22.3", "24.15.0", "v24.99.1", "v25.9.0", "v26.0.0"]
        for version in acceptedNodeVersions {
            precondition(
                OpenClawCommandClient.isSupportedOpenClawNodeVersion(version),
                "OpenClaw should accept supported Node version \(version)"
            )
        }
        let rejectedNodeVersions = ["v22.22.2", "v23.11.0", "v24.14.9", "v25.8.9", "not-a-version"]
        for version in rejectedNodeVersions {
            precondition(
                !OpenClawCommandClient.isSupportedOpenClawNodeVersion(version),
                "OpenClaw should reject unsupported Node version \(version)"
            )
        }

        let selectedFallbackNode = OpenClawCommandClient.preferredOpenClawNodeDirectory(
            candidates: [
                "/opt/homebrew/opt/node@24/bin",
                staleNVMPath,
                "/Users/test/.nvm/versions/node/v22.22.3/bin",
            ],
            versionAtPath: { path in
                switch path {
                case staleNVMPath:
                    return "v24.13.0"
                case "/Users/test/.nvm/versions/node/v22.22.3/bin":
                    return "v22.22.3"
                default:
                    return nil
                }
            }
        )
        precondition(
            selectedFallbackNode == "/Users/test/.nvm/versions/node/v22.22.3/bin",
            "OpenClaw should skip a missing Homebrew keg and an incompatible inherited Node, then select the first compatible runtime"
        )

        let intelNodeDirectory = "/usr/local/opt/node@24/bin"
        let selectedIntelNode = OpenClawCommandClient.preferredOpenClawNodeDirectory(
            candidates: [intelNodeDirectory, staleNVMPath],
            versionAtPath: { path in
                path == intelNodeDirectory ? "v24.15.0" : "v24.13.0"
            }
        )
        precondition(
            selectedIntelNode == intelNodeDirectory,
            "OpenClaw should select a compatible Intel Homebrew Node 24 before an incompatible inherited NVM Node"
        )

        let probeStartedAt = Date()
        let timedOutProbe = OpenClawCommandClient.commandOutput(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            timeoutSeconds: 0.05
        )
        precondition(timedOutProbe == nil, "A timed-out Node version probe should fail closed")
        precondition(
            Date().timeIntervalSince(probeStartedAt) < 0.8,
            "A hung Node version probe should be terminated within its bounded timeout"
        )

        print("OpenClawClientCheck passed")
    }
}
