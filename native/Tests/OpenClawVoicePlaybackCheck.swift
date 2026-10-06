import Foundation

@main
struct OpenClawVoicePlaybackCheck {
    static func main() {
        let settings = OpenClawVoiceSettings(
            enabled: true,
            volume: 0.8,
            speechRate: 1.25,
            engine: .zipVoice,
            voiceID: "zipvoice-serena",
            playbackPolicy: .finalReplyOnly,
            interruptPolicy: .stopPreviousAndPlayLatest
        )
        let request = OpenClawVoiceSynthesisRequest(
            text: "**深圳天气**\n---\n访问 [官网](https://example.com) 或 https://example.com。",
            settings: settings,
            workerScriptURL: URL(fileURLWithPath: "/tmp/tts_benchmark_worker.py"),
            modelsRoot: URL(fileURLWithPath: "/tmp/models", isDirectory: true),
            outputURL: URL(fileURLWithPath: "/tmp/openclaw.wav")
        )

        precondition(request.speechText == "深圳天气\n访问 官网 或 https://example.com。")
        precondition(request.packDirectory.path == "/tmp/models/tts/zipvoice-distill-int8-zh-en-emilia")
        precondition(OpenClawVoiceRuntime.sidecarArguments(
            workerScriptURL: request.workerScriptURL!,
            engine: request.settings.engine,
            packDirectory: request.packDirectory
        ).contains("sherpa-zipvoice"))

        let shortSegments = OpenClawVoiceRuntime.speechSegments(
            from: "第一句很短。第二句也应该马上开始合成！第三句继续排队播放。"
        )
        precondition(shortSegments == ["第一句很短。第二句也应该马上开始合成！第三句继续排队播放。"])

        let openClawSample = """
        好，讲一个。

        ---

        海里有一只小蚌壳，它最大的秘密是——它的壳里藏着一颗沙子。

        那颗沙子很硬，磨得它难受。它问妈妈："我能把它弄出去吗？"

        妈妈说："别急，过几年它就会变成珍珠。"

        小蚌壳不信："沙子怎么可能变成珍珠？"

        妈妈说："珍珠不是沙子变成的，是你自己包裹它的方式。你讨厌它，它就是沙粒。你接纳它，它就是宝贝。"

        小蚌壳半信半疑，每天忍着疼，包裹着那颗沙子。

        一年、两年、三年。

        有一天，一个潜水员打开它的壳——里面躺着一颗圆润的珍珠，在阳光下闪着光。

        潜水员惊叹："太美了！"

        小蚌壳低头看那颗陪伴了它三年的沙子，忽然明白了——妈妈说的是真的。痛苦本身不是财富，你对痛苦的态度才是。

        ---

        🦞 讲完了，效果怎么样？
        """
        let storySegments = OpenClawVoiceRuntime.speechSegments(from: openClawSample)
        precondition((4...6).contains(storySegments.count))
        precondition(storySegments.allSatisfy { (40...100).contains($0.count) })
        precondition(!storySegments.contains("\""))
        precondition(storySegments.joined().contains("好，讲一个。海里有一只小蚌壳"))
        precondition(storySegments.joined().contains("讲完了，效果怎么样？"))
        precondition(!OpenClawVoiceRuntime.isSpeakable("\""))
        precondition(!OpenClawVoiceRuntime.isSpeakable("---\n🦞"))
        precondition(OpenClawVoiceRuntime.isSpeakable("🦞 讲完了"))
        precondition(OpenClawVoiceRuntime.sidecarArguments(
            workerScriptURL: request.workerScriptURL!,
            engine: request.settings.engine,
            packDirectory: request.packDirectory
        ).contains("--pack"))
    }
}
