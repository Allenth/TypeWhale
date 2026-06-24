import Foundation

private final class SlowRewriteEngine: SmartRewriteEngine {
    let displayName = "Slow Test Engine"

    func rewrite(
        rawText: String,
        mode: RewriteMode,
        context: SmartInputContext
    ) async throws -> SmartRewriteEngineOutput {
        try await Task.sleep(nanoseconds: 9_000_000_000)
        return SmartRewriteEngineOutput(text: "should-time-out", usage: nil)
    }
}

@main
struct SmartInputCheck {
    static func main() async {
        let noopRouter = SmartInputRouter(engine: NoopRewriteEngine())

        let codex = SmartInputContext(
            targetAppName: "Codex",
            targetBundleIdentifier: "com.openai.codex"
        )
        let codexResult = await noopRouter.rewrite(
            rawText: "  我们看一下这个模型  ",
            preference: .automatic,
            context: codex
        )
        precondition(codexResult.mode == .developerRequirement)
        precondition(codexResult.text == "我们看一下这个模型")

        let terminal = SmartInputContext(
            targetAppName: "Terminal",
            targetBundleIdentifier: "com.apple.Terminal"
        )
        let terminalResult = await noopRouter.rewrite(
            rawText: "  git status  ",
            preference: .automatic,
            context: terminal
        )
        precondition(terminalResult.mode == .developerRequirement)
        precondition(terminalResult.text == "Git status")

        let xcode = SmartInputContext(
            targetAppName: "Xcode",
            targetBundleIdentifier: "com.apple.dt.Xcode"
        )
        let xcodeResult = await noopRouter.rewrite(
            rawText: "  修一下构建失败的问题  ",
            preference: .automatic,
            context: xcode
        )
        precondition(xcodeResult.mode == .developerRequirement)

        let manualResult = await noopRouter.rewrite(
            rawText: "  随便说一句  ",
            preference: .polish,
            context: terminal
        )
        precondition(manualResult.mode == .polish)
        precondition(manualResult.text == "随便说一句")

        let summaryResult = await noopRouter.rewrite(
            rawText: "  今天讲了产品方向、风险和下一步计划  ",
            preference: .exhaustiveSummary,
            context: codex
        )
        precondition(summaryResult.mode == .exhaustiveSummary)
        precondition(summaryResult.text == "今天讲了产品方向、风险和下一步计划")

        let secureResult = await noopRouter.rewrite(
            rawText: "  secret  ",
            preference: .developerRequirement,
            context: SmartInputContext(
                targetAppName: "Any",
                targetBundleIdentifier: nil,
                isSecureTextEntry: true
            )
        )
        precondition(secureResult.mode == .raw)
        precondition(secureResult.text == "secret")

        let timeoutRouter = SmartInputRouter(engine: SlowRewriteEngine())
        let timeoutResult = await timeoutRouter.rewrite(
            rawText: "  需要回退  ",
            preference: .polish,
            context: codex
        )
        precondition(timeoutResult.didFallback)
        precondition(timeoutResult.text == "需要回退")
    }
}
