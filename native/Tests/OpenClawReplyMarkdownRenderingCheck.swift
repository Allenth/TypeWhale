import AppKit

@main
struct OpenClawReplyMarkdownRenderingCheck {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        precondition(
            abs(OpenClawReplyDisplayDurationPolicy.maximum - 180) < 0.01,
            "OpenClaw left popup messages should have a maximum visible lifetime of 3 minutes"
        )
        precondition(
            abs(OpenClawReplyDisplayDurationPolicy.resolved(nil) - 180) < 0.01,
            "OpenClaw messages without a caller duration should default to the 3-minute cap"
        )
        precondition(
            abs(OpenClawReplyDisplayDurationPolicy.resolved(999) - 180) < 0.01,
            "OpenClaw messages longer than 3 minutes should be capped"
        )
        precondition(
            abs(OpenClawReplyDisplayDurationPolicy.resolved(0.30) - 0.30) < 0.01,
            "OpenClaw messages should still allow a shorter explicit duration for tests and callers"
        )
        precondition(
            OpenClawReplyPresenter.collapsesToOrbAfterIdle,
            "OpenClaw popup should collapse to the lobster orb after the shared lifetime instead of clearing messages"
        )
        precondition(
            abs(OpenClawReplyPresenter.newMessageRevealDelay - 0.5) < 0.01,
            "OpenClaw messages should wait about 0.5 seconds before revealing"
        )
        precondition(
            abs(OpenClawReplyPresenter.displayEventPlaybackDelay - 0.45) < 0.01,
            "OpenClaw returned status/progress events should be replayed with a short readable delay"
        )
        precondition(
            !OpenClawReplyPresenter.scrollsDuringRevealAnimation,
            "OpenClaw reveal animation should not trigger its own scroll pass because it makes rapid replies visibly jitter"
        )

        let markdown = """
        **深圳 7/10 周五**

        温度 26~32°C，UV 11（强）。

        | 时段 | 实温 | 体感 |
        |---|---|---|
        | 00:00 | 27° | 32° |
        """

        let rendered = OpenClawReplyMarkdownRenderer.attributedString(from: markdown)
        let plain = rendered.string

        precondition(!plain.contains("**"), "OpenClaw reply popup should render bold markdown instead of showing literal ** markers")
        precondition(!plain.contains("|---"), "OpenClaw reply popup should render markdown tables instead of showing the separator row")
        precondition(plain.contains("深圳 7/10 周五"), "OpenClaw reply popup should preserve markdown heading text")
        precondition(plain.contains("温度 26~32°C"), "OpenClaw reply popup should preserve normal markdown paragraphs")
        precondition(plain.contains("时段"), "OpenClaw reply popup should preserve markdown table headers")
        precondition(plain.contains("00:00"), "OpenClaw reply popup should preserve markdown table cells")

        let horizontalRuleMarkdown = """
        第一段

        ---

        第二段
        """
        let horizontalRulePlain = OpenClawReplyMarkdownRenderer.attributedString(from: horizontalRuleMarkdown).string
        precondition(
            !horizontalRulePlain.contains("---"),
            "OpenClaw reply popup should render Markdown horizontal rules instead of showing literal ---"
        )
        precondition(
            horizontalRulePlain.contains("────────"),
            "OpenClaw reply popup should render Markdown horizontal rules as a visible divider"
        )

        let linkMarkdown = "打开 [链接测试入口](https://openclaw.local/docs) 继续看。"
        let linkRendered = OpenClawReplyMarkdownRenderer.attributedString(from: linkMarkdown)
        let linkPlain = linkRendered.string
        let linkRange = (linkPlain as NSString).range(of: "链接测试入口")
        precondition(!linkPlain.contains("]("), "OpenClaw reply popup should render Markdown links instead of showing literal link syntax")
        precondition(linkRange.location != NSNotFound, "OpenClaw reply popup should preserve Markdown link text")
        let linkAttribute = linkRendered.attribute(.link, at: linkRange.location, effectiveRange: nil)
        precondition(
            (linkAttribute as? URL)?.absoluteString == "https://openclaw.local/docs",
            "OpenClaw reply popup should attach a clickable URL attribute to Markdown links"
        )
        let bareLinkRendered = OpenClawReplyMarkdownRenderer.attributedString(from: "继续看 https://openclaw.local/plain。")
        let bareLinkPlain = bareLinkRendered.string
        let bareLinkRange = (bareLinkPlain as NSString).range(of: "https://openclaw.local/plain")
        precondition(bareLinkRange.location != NSNotFound, "OpenClaw reply popup should preserve bare URLs as visible text")
        let bareLinkAttribute = bareLinkRendered.attribute(.link, at: bareLinkRange.location, effectiveRange: nil)
        precondition(
            (bareLinkAttribute as? URL)?.absoluteString == "https://openclaw.local/plain",
            "OpenClaw reply popup should attach clickable URL attributes to bare http/https links without trailing punctuation"
        )

        var items: [OpenClawReplyStackPolicy.Item] = [
            OpenClawReplyStackPolicy.Item(userText: "a", replyText: "reply-a"),
            OpenClawReplyStackPolicy.Item(userText: "b", replyText: "reply-b"),
            OpenClawReplyStackPolicy.Item(userText: "c", replyText: "reply-c"),
        ]
        items = OpenClawReplyStackPolicy.removingReply("reply-b", from: items)
        precondition(items.map(\.replyText) == ["reply-a", "reply-c"], "Closing one OpenClaw popup should remove only that message")

        let longReply = Array(repeating: "这是一段很长的 OpenClaw 回复，用来确认左上角回复弹窗的滚动区域高度上限已经加高。", count: 80).joined(separator: "\n")
        OpenClawReplyPresenter.shared.showConversation(userText: "高度测试", replyText: longReply, duration: nil)
        precondition(
            findScrollView(accessibilityIdentifier: "openclaw-reply-body-scroll") == nil,
            "Completed OpenClaw replies should expand to their full Markdown height instead of creating a nested body scroller"
        )
        precondition(
            findTextField(containing: "这是一段很长的 OpenClaw 回复") != nil,
            "Completed OpenClaw replies should render long Markdown content directly in the message bubble"
        )
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageRevealDelay * 2 + OpenClawReplyPresenter.newMessageFadeDuration + 0.10)

        OpenClawReplyPresenter.shared.showReply("三分钟计时-A", duration: 0.10)
        runMainLoop(seconds: 0.08)
        OpenClawReplyPresenter.shared.showReply("三分钟计时-B", duration: 0.30)
        runMainLoop(seconds: 0.16)
        precondition(
            findTextField(stringValue: "三分钟计时-A") != nil
                && findTextField(stringValue: "三分钟计时-B") != nil,
            "Adding a new OpenClaw message should restart one shared window lifetime instead of preserving per-message expiry"
        )
        runMainLoop(seconds: 0.20)
        precondition(
            findTextField(stringValue: "三分钟计时-A") == nil
                && findTextField(stringValue: "三分钟计时-B") == nil
                && findView(accessibilityIdentifier: "openclaw-reply-orb-button") != nil,
            "OpenClaw messages should collapse into a lobster orb when the shared window lifetime expires"
        )
        guard let idleOrb = findView(accessibilityIdentifier: "openclaw-reply-orb-button") as? NSButton else {
            preconditionFailure("OpenClaw idle collapse should expose a clickable lobster orb")
        }
        idleOrb.performClick(nil)
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageFadeDuration + 0.05)
        precondition(
            findTextField(stringValue: "三分钟计时-A") != nil
                && findTextField(stringValue: "三分钟计时-B") != nil,
            "Clicking the lobster orb should expand the preserved OpenClaw messages"
        )
        OpenClawReplyPresenter.shared.clearMessages()
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageFadeDuration + 0.05)

        OpenClawReplyPresenter.shared.showReply("打开 [链接测试入口](https://openclaw.local/docs) 继续看。", duration: nil)
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageRevealDelay + OpenClawReplyPresenter.newMessageFadeDuration + 0.10)
        guard let replyLinkField = findTextField(containing: "链接测试入口") else {
            preconditionFailure("Expected to find OpenClaw reply text with a Markdown link")
        }
        precondition(
            replyLinkField.isSelectable && replyLinkField.allowsEditingTextAttributes,
            "OpenClaw reply text should allow users to click rendered links"
        )
        let replyLinkPlain = replyLinkField.attributedStringValue.string
        let replyLinkRange = (replyLinkPlain as NSString).range(of: "链接测试入口")
        let replyLinkAttribute = replyLinkField.attributedStringValue.attribute(.link, at: replyLinkRange.location, effectiveRange: nil)
        precondition(
            (replyLinkAttribute as? URL)?.absoluteString == "https://openclaw.local/docs",
            "OpenClaw rendered reply fields should keep clickable Markdown link attributes"
        )
        OpenClawReplyPresenter.shared.clearMessages()
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageFadeDuration + 0.05)

        OpenClawReplyPresenter.shared.showConversation(
            userText: "明天深圳的天气怎么样？你要小细一点。",
            replyText: "**深圳 7/10 周五**\n\n温度 26~32°C，UV 11（强）。",
            duration: nil
        )
        OpenClawReplyPresenter.shared.showStatusMessage("已发送，等待 OpenClaw 回复...", duration: nil)

        guard let userCard = findView(accessibilityIdentifier: "openclaw-reply-user-card"),
              let userBubble = findView(accessibilityIdentifier: "openclaw-reply-user-bubble"),
              let userAvatarInFlow = findView(accessibilityIdentifier: "openclaw-reply-user-avatar") else {
            preconditionFailure("OpenClaw popup should show the user's spoken message as its own left-side notification item")
        }
        let userBubbleFrame = windowFrame(of: userBubble)
        let userAvatarInFlowFrame = windowFrame(of: userAvatarInFlow)
        precondition(
            userBubbleFrame.maxX <= userAvatarInFlowFrame.minX,
            "User message avatar should sit outside the right edge of the user's bubble"
        )
        precondition(
            userBubbleFrame.width < windowFrame(of: userCard).width - 72,
            "Short user messages in the OpenClaw popup should fit their content instead of being forced to the maximum width"
        )

        precondition(
            findTextField(stringValue: "OpenClaw") == nil,
            "OpenClaw popup should hide the large title header"
        )

        guard let assistantCard = findView(accessibilityIdentifier: "openclaw-reply-assistant-card"),
              let assistantBubble = findView(accessibilityIdentifier: "openclaw-reply-assistant-bubble"),
              let assistantAvatar = findView(accessibilityIdentifier: "openclaw-reply-assistant-avatar") else {
            preconditionFailure("OpenClaw reply popup should render a single assistant message bubble and avatar")
        }
        precondition(
            windowFrame(of: assistantCard).maxY <= windowFrame(of: userCard).minY,
            "User and assistant messages should enter the left popup as separate stacked items, not one combined bubble"
        )

        let assistantBubbleFrame = windowFrame(of: assistantBubble)
        let assistantAvatarFrame = windowFrame(of: assistantAvatar)

        precondition(
            assistantAvatarFrame.maxX <= assistantBubbleFrame.minX,
            "OpenClaw chat avatar should sit outside the left edge of the assistant bubble"
        )
        let assistantAvatarImage = renderImage(assistantAvatar, size: NSSize(width: 28, height: 28))
        let assistantBadgeColor = pixelColor(in: assistantAvatarImage, x: 4, y: 14)
        let assistantCenterColor = pixelColor(in: assistantAvatarImage, x: 14, y: 14)
        precondition(
            isOpenClawRedBadge(assistantBadgeColor) && isOpenClawRedBadge(assistantCenterColor),
            "OpenClaw assistant avatar should keep the red lobster badge"
        )

        NSApp.applicationIconImage = makeTestAppIcon()
        let userAvatar = OpenClawReplyAvatarView(role: .user, accessibilityIdentifier: "openclaw-reply-user-avatar-probe")
        userAvatar.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        let userAvatarImage = renderImage(userAvatar, size: NSSize(width: 28, height: 28))
        let userCenterColor = pixelColor(in: userAvatarImage, x: 14, y: 14)
        let userLeftColor = pixelColor(in: userAvatarImage, x: 4, y: 14)
        let userRightColor = pixelColor(in: userAvatarImage, x: 24, y: 14)
        precondition(
            !isNeutralGray(userCenterColor),
            "OpenClaw user avatar should render the app icon instead of the generic gray person avatar"
        )
        precondition(
            isTestIconBlue(userLeftColor) && isTestIconYellow(userRightColor),
            "OpenClaw user avatar should fill the avatar area with the app logo instead of centering a small icon"
        )

        guard let closeButton = findView(accessibilityIdentifier: "openclaw-reply-close-button") as? NSButton else {
            preconditionFailure("OpenClaw reply popup should expose a visible close button")
        }
        precondition(
            windowFrame(of: closeButton).width >= 22 && windowFrame(of: closeButton).height >= 22,
            "OpenClaw close button should be large enough to see and click"
        )
        precondition(
            (closeButton.contentTintColor?.alphaComponent ?? 0) >= 0.90,
            "OpenClaw close button should use a high-contrast tint"
        )
        guard let closeShadow = findView(accessibilityIdentifier: "openclaw-reply-close-shadow") else {
            preconditionFailure("OpenClaw close button should sit inside a dedicated surrounding shadow view")
        }
        precondition(
            (closeShadow.layer?.shadowOpacity ?? 0) >= 0.50
                && (closeShadow.layer?.shadowRadius ?? 0) >= 4
                && abs(closeShadow.layer?.shadowOffset.width ?? 99) < 0.1
                && abs(closeShadow.layer?.shadowOffset.height ?? 99) < 0.1,
            "OpenClaw close button should have a surrounding shadow halo, not just a weak one-direction shadow"
        )
        let closeButtonFrame = windowFrame(of: closeButton)
        precondition(
            abs(closeButtonFrame.midY - userAvatarInFlowFrame.midY) < 1.5
                || abs(closeButtonFrame.midY - assistantAvatarFrame.midY) < 1.5,
            "OpenClaw close button should align horizontally with the avatar center"
        )

        guard let statusCard = findView(accessibilityIdentifier: "openclaw-reply-status-card"),
              let statusBubble = findView(accessibilityIdentifier: "openclaw-reply-status-bubble"),
              findTextField(stringValue: "已发送，等待 OpenClaw 回复...") != nil else {
            preconditionFailure("OpenClaw popup should show safe status/progress messages while waiting for replies")
        }
        let timestampLabels = findViews(accessibilityIdentifier: "openclaw-reply-timestamp").compactMap { $0 as? NSTextField }
        precondition(
            timestampLabels.count >= 3,
            "Each OpenClaw popup message should show its own timestamp"
        )
        precondition(
            timestampLabels.allSatisfy { label in
                label.stringValue.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil
            },
            "OpenClaw popup timestamps should use compact HH:mm text"
        )
        precondition(
            isTypeWhaleUserWaterInkBubble(color(from: userBubble.layer?.backgroundColor)),
            "User messages in the OpenClaw popup should use the water-ink bubble palette"
        )
        guard let userTextField = findTextField(stringValue: "明天深圳的天气怎么样？你要小细一点。") else {
            preconditionFailure("Expected to find the user's message text field")
        }
        guard let currentUserCard = ancestor(
            of: userTextField,
            accessibilityIdentifier: "openclaw-reply-user-card"
        ), let currentAssistantField = findTextField(containing: "温度 26~32°C"),
           let currentAssistantCard = ancestor(
            of: currentAssistantField,
            accessibilityIdentifier: "openclaw-reply-assistant-card"
           ) else {
            preconditionFailure("Expected to find the current user and assistant message cards")
        }
        precondition(
            isWhiteText(userTextField.textColor),
            "User messages in the OpenClaw popup should use white text on the water-ink bubble"
        )
        precondition(
            userTextField.lineBreakMode != .byTruncatingTail && userTextField.maximumNumberOfLines == 0,
            "User messages in the OpenClaw popup should wrap to multiple lines instead of truncating on one line"
        )
        precondition(
            userTextField.alignment == .left,
            "Adaptive user message text in the OpenClaw popup should be left-aligned inside the right-side bubble"
        )
        for bubble in [assistantBubble, statusBubble] {
            let color = color(from: bubble.layer?.backgroundColor)
            precondition(
                isOpenClawRedBubble(color),
                "OpenClaw lobster/status messages should keep the existing red bubble palette"
            )
        }
        precondition(
            statusCard.alphaValue <= 0.05,
            "Each newly-added OpenClaw message should start hidden for the reveal delay"
        )
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageRevealDelay + OpenClawReplyPresenter.newMessageFadeDuration + 0.10)
        precondition(
            currentUserCard.alphaValue > 0.95
                && currentAssistantCard.alphaValue <= 0.05
                && statusCard.alphaValue <= 0.05,
            "OpenClaw popup messages should reveal one by one instead of appearing together"
        )
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageRevealDelay)
        precondition(
            currentAssistantCard.alphaValue > 0.95
                && statusCard.alphaValue <= 0.05,
            "OpenClaw popup should reveal the assistant message after the user's message"
        )
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageRevealDelay + OpenClawReplyPresenter.newMessageFadeDuration + 0.10)
        precondition(
            statusCard.alphaValue > 0.95 && (statusBubble.layer?.opacity ?? 1) > 0,
            "OpenClaw popup should reveal the status/loading message after earlier messages"
        )

        let assistantBubbleAlpha = assistantBubble.layer?.backgroundColor?.alpha ?? 0
        precondition(
            assistantBubbleAlpha >= 0.92,
            "OpenClaw reply bubble should be opaque enough to stay readable on dark or busy backgrounds"
        )

        let cardBackgroundAlpha = assistantCard.layer?.backgroundColor?.alpha ?? 0
        precondition(
            cardBackgroundAlpha <= 0.05 && (assistantCard.layer?.borderWidth ?? 0) == 0,
            "OpenClaw chat popup should not draw a large card background behind the message bubbles"
        )

        OpenClawReplyPresenter.shared.showReplyLoading()
        guard let loadingCard = findView(accessibilityIdentifier: "openclaw-reply-loading-card"),
              let loadingBubble = findView(accessibilityIdentifier: "openclaw-reply-loading-bubble"),
              findView(accessibilityIdentifier: "openclaw-reply-loading-spinner") is NSProgressIndicator,
              findTextField(stringValue: "OpenClaw 正在回复") != nil else {
            preconditionFailure("OpenClaw popup should show a lobster loading state before the reply content arrives")
        }
        precondition(
            isOpenClawRedBubble(color(from: loadingBubble.layer?.backgroundColor)),
            "OpenClaw loading state should keep the lobster red bubble palette"
        )
        OpenClawReplyPresenter.shared.showReply("loading 完成", duration: nil)
        precondition(
            findView(accessibilityIdentifier: "openclaw-reply-loading-card") == nil,
            "OpenClaw loading state should disappear when the final reply content arrives"
        )
        guard let shortReplyField = findTextField(stringValue: "loading 完成"),
              let shortReplyBubble = ancestor(
                of: shortReplyField,
                accessibilityIdentifier: "openclaw-reply-assistant-bubble"
              ) else {
            preconditionFailure("OpenClaw final reply should appear after replacing the loading state")
        }
        precondition(
            windowFrame(of: shortReplyBubble).width < windowFrame(of: assistantCard).width - 72,
            "OpenClaw reply bubbles should remain content-sized below the maximum width"
        )

        OpenClawReplyPresenter.shared.showReplyLoading()
        OpenClawReplyPresenter.shared.showStatusMessage("OpenClaw 已完成", duration: nil)
        precondition(
            findView(accessibilityIdentifier: "openclaw-reply-loading-card") == nil
                && loadingCard.alphaValue >= 0,
            "OpenClaw loading state should also disappear when an intermediate status message arrives"
        )

        OpenClawReplyPresenter.shared.showReplyLoading()
        OpenClawReplyPresenter.shared.showReplySequence(
            displayEvents: ["OpenClaw 丝滑完成"],
            reply: "丝滑最终回复",
            duration: nil
        )
        guard let smoothStatusField = findTextField(stringValue: "OpenClaw 丝滑完成"),
              let smoothStatusCard = ancestor(
                of: smoothStatusField,
                accessibilityIdentifier: "openclaw-reply-status-card"
              ),
              let smoothLoadingCard = findView(accessibilityIdentifier: "openclaw-reply-loading-card") else {
            preconditionFailure("OpenClaw replay should replace waiting state with visible returned content without a blank gap")
        }
        precondition(
            smoothStatusCard.alphaValue > 0.95 && smoothLoadingCard.alphaValue > 0.95,
            "OpenClaw returned status and follow-up loading should be visible immediately when replacing an existing loading state"
        )
        runMainLoop(seconds: OpenClawReplyPresenter.displayEventPlaybackDelay + 0.05)
        guard let smoothFinalField = findTextField(stringValue: "丝滑最终回复"),
              let smoothFinalCard = ancestor(
                of: smoothFinalField,
                accessibilityIdentifier: "openclaw-reply-assistant-card"
              ) else {
            preconditionFailure("OpenClaw final reply should appear after the returned status event")
        }
        precondition(
            smoothFinalCard.alphaValue > 0.95 && findView(accessibilityIdentifier: "openclaw-reply-loading-card") == nil,
            "OpenClaw final reply should replace the intermediate loading state immediately instead of waiting through another reveal delay"
        )

        OpenClawReplyPresenter.shared.showReplySequence(
            displayEvents: [
                "OpenClaw 已接收，等待处理",
                "OpenClaw 正在处理"
            ],
            reply: "递进最终回复",
            duration: nil
        )
        precondition(
            findTextField(stringValue: "OpenClaw 已接收，等待处理") != nil,
            "OpenClaw replay should show the first returned status event immediately"
        )
        precondition(
            findView(accessibilityIdentifier: "openclaw-reply-loading-card") != nil,
            "OpenClaw replay should show loading between returned events"
        )
        precondition(
            findTextField(stringValue: "OpenClaw 正在处理") == nil,
            "OpenClaw replay should delay later returned events instead of dumping every event at once"
        )
        precondition(
            findTextField(stringValue: "递进最终回复") == nil,
            "OpenClaw replay should delay the final reply until returned events have been shown"
        )
        runMainLoop(seconds: OpenClawReplyPresenter.displayEventPlaybackDelay + OpenClawReplyPresenter.newMessageFadeDuration + 0.08)
        precondition(
            findTextField(stringValue: "OpenClaw 正在处理") != nil,
            "OpenClaw replay should show the next returned event after the delay"
        )
        precondition(
            findTextField(stringValue: "递进最终回复") == nil,
            "OpenClaw replay should keep the final reply hidden until all returned events are replayed"
        )
        runMainLoop(seconds: OpenClawReplyPresenter.displayEventPlaybackDelay + OpenClawReplyPresenter.newMessageFadeDuration + 0.08)
        precondition(
            findTextField(stringValue: "递进最终回复") != nil
                && findView(accessibilityIdentifier: "openclaw-reply-loading-card") == nil,
            "OpenClaw replay should replace the final loading state with the final reply"
        )

        let firstTurnID = UUID()
        let secondTurnID = UUID()
        OpenClawReplyPresenter.shared.showUserMessage("第一句：为什么这么慢？", duration: nil, turnID: firstTurnID)
        OpenClawReplyPresenter.shared.showReplyLoading(turnID: firstTurnID)
        OpenClawReplyPresenter.shared.showUserMessage("第二句：继续追问一下。", duration: nil, turnID: secondTurnID)
        OpenClawReplyPresenter.shared.showStatusMessage("已排队，等待 OpenClaw 回复…", duration: nil, turnID: secondTurnID)
        OpenClawReplyPresenter.shared.showReplySequence(
            displayEvents: ["第一句已收到"],
            reply: "第一句最终回复",
            duration: nil,
            turnID: firstTurnID
        )
        runMainLoop(seconds: OpenClawReplyPresenter.displayEventPlaybackDelay + OpenClawReplyPresenter.newMessageFadeDuration + 0.08)
        guard let firstUserField = findTextField(stringValue: "第一句：为什么这么慢？"),
              let firstReplyField = findTextField(stringValue: "第一句最终回复"),
              let secondUserField = findTextField(stringValue: "第二句：继续追问一下。"),
              let firstUserCard = ancestor(of: firstUserField, accessibilityIdentifier: "openclaw-reply-user-card"),
              let firstReplyCard = ancestor(of: firstReplyField, accessibilityIdentifier: "openclaw-reply-assistant-card"),
              let secondUserCard = ancestor(of: secondUserField, accessibilityIdentifier: "openclaw-reply-user-card") else {
            preconditionFailure("OpenClaw popup should keep turn-scoped user, loading, status, and reply messages visible")
        }
        precondition(
            windowFrame(of: firstReplyCard).maxY <= windowFrame(of: firstUserCard).minY
                && windowFrame(of: secondUserCard).maxY <= windowFrame(of: firstReplyCard).minY,
            "OpenClaw reply events should stay attached to their original user turn instead of appearing after later queued user messages"
        )
        guard let queuedStatusField = findTextField(stringValue: "已排队，等待 OpenClaw 回复…"),
              let queuedStatusCard = ancestor(of: queuedStatusField, accessibilityIdentifier: "openclaw-reply-status-card") else {
            preconditionFailure("OpenClaw queued turns should show a replaceable queued status")
        }
        let queuedStatusFrame = windowFrame(of: queuedStatusCard)
        OpenClawReplyPresenter.shared.showReplyLoading(turnID: secondTurnID)
        runMainLoop(seconds: 0.05)
        guard let secondLoadingField = findTextField(stringValue: "OpenClaw 正在回复"),
              let secondLoadingCard = ancestor(of: secondLoadingField, accessibilityIdentifier: "openclaw-reply-loading-card") else {
            preconditionFailure("OpenClaw queued status should be replaced with the loading state when the turn starts sending")
        }
        precondition(
            findTextField(stringValue: "已排队，等待 OpenClaw 回复…") == nil,
            "OpenClaw queued status should not remain as a stale message after loading begins"
        )
        precondition(
            abs(windowFrame(of: secondLoadingCard).maxY - queuedStatusFrame.maxY) < 8,
            "OpenClaw queued status and loading state should exchange in the same visual slot"
        )

        OpenClawReplyPresenter.shared.showReplySequence(
            displayEvents: ["completed"],
            reply: "跳过完成标记后的最终回复",
            duration: nil
        )
        precondition(
            findTextField(stringValue: "completed") == nil
                && findTextField(stringValue: "跳过完成标记后的最终回复") != nil,
            "OpenClaw popup should skip completion-only returned events and show the final reply directly"
        )

        let scrollStressReply = Array(repeating: "这是一条用于撑高左侧消息列表的 OpenClaw 长回复。", count: 90).joined(separator: "\n")
        for index in 1...8 {
            OpenClawReplyPresenter.shared.showReply("滚动长回复-\(index)\n\(scrollStressReply)", duration: nil)
        }
        OpenClawReplyPresenter.shared.showStatusMessage("滚动最新消息-9", duration: nil)
        guard let messageScrollView = findScrollView(accessibilityIdentifier: "openclaw-reply-scroll-container"),
              let messageWindow = messageScrollView.window,
              let messageContainer = findView(accessibilityIdentifier: "openclaw-reply-message-container"),
              let clearButton = findView(accessibilityIdentifier: "openclaw-reply-clear-button") as? NSButton,
              let messageScreenFrame = messageWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            preconditionFailure("OpenClaw message stack should be inside a named scroll container with a clear button")
        }
        precondition(
            clearButton.isHidden == false,
            "OpenClaw clear button should be visible when messages are present"
        )
        precondition(
            isBlueGrayClearButton(color(from: clearButton.layer?.backgroundColor))
                && isWhiteText(clearButton.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor),
            "OpenClaw clear button should use a visible blue-gray background with white text"
        )
        messageWindow.contentView?.layoutSubtreeIfNeeded()
        precondition(
            isAncestor(messageContainer, of: messageScrollView),
            "OpenClaw message stack scroll view should be wrapped by the message container"
        )
        precondition(
            isTranslucentRoundedScrollContainer(messageContainer),
            "OpenClaw message scroll container should be a rounded translucent view"
        )
        precondition(
            messageWindow.frame.minY >= messageScreenFrame.minY - 1,
            "OpenClaw message stack should stop at the screen bottom instead of growing off-screen"
        )
        let documentHeight = messageScrollView.documentView?.bounds.height ?? 0
        let visibleHeight = messageScrollView.contentView.bounds.height
        precondition(
            messageScrollView.hasVerticalScroller && documentHeight > visibleHeight,
            "OpenClaw message stack should become scrollable after reaching the screen bottom"
        )
        precondition(
            findTextField(containing: "滚动长回复-1") != nil,
            "OpenClaw message stack should keep old messages instead of removing them when newer messages arrive"
        )
        precondition(
            findTextField(stringValue: "滚动最新消息-9") != nil,
            "OpenClaw message stack should keep the newest appended message visible at the bottom"
        )
        guard let newestField = findTextField(stringValue: "滚动最新消息-9"),
              let newestCard = ancestor(of: newestField, accessibilityIdentifier: "openclaw-reply-status-card") else {
            preconditionFailure("Expected to find the newest OpenClaw message card")
        }
        precondition(
            newestCard.visibleRect.height >= newestCard.bounds.height - 1,
            "OpenClaw newest message should not be clipped by the bottom of the scroll container"
        )
        let newestCardFrame = windowFrame(of: newestCard)
        let newestScrollClipFrame = windowFrame(of: messageScrollView.contentView)
        precondition(
            newestCardFrame.minY >= newestScrollClipFrame.minY - 1
                && newestCardFrame.minY <= newestScrollClipFrame.minY + 18,
            "A normal-height newest OpenClaw message should sit at the bottom of the visible list instead of forcing the list to the top"
        )
        messageScrollView.contentView.scroll(to: .zero)
        messageScrollView.reflectScrolledClipView(messageScrollView.contentView)
        OpenClawReplyPresenter.shared.showStatusMessage("滚动最新消息-10", duration: nil)
        runMainLoop(seconds: 0.10)
        guard let forcedNewestField = findTextField(stringValue: "滚动最新消息-10"),
              let forcedNewestCard = ancestor(of: forcedNewestField, accessibilityIdentifier: "openclaw-reply-status-card") else {
            preconditionFailure("Expected to find the latest OpenClaw message after appending while scrolled away")
        }
        precondition(
            forcedNewestCard.visibleRect.height >= forcedNewestCard.bounds.height - 1,
            "OpenClaw should auto-scroll a newly appended message into view even after the list was scrolled away"
        )
        let forcedNewestCardFrame = windowFrame(of: forcedNewestCard)
        precondition(
            forcedNewestCardFrame.minY >= newestScrollClipFrame.minY - 1
                && forcedNewestCardFrame.minY <= newestScrollClipFrame.minY + 18,
            "A newly appended normal-height OpenClaw message should return to the bottom, not the top, after the user had scrolled away"
        )
        let oversizedReply = Array(
            repeating: "这是一条特别长的最后消息，用来确认当单条消息本身超过一屏高度时，弹窗会先展示这条消息的顶部，而不是直接跳到消息尾部。",
            count: 120
        ).joined(separator: "\n")
        OpenClawReplyPresenter.shared.showReply("超长最后消息\n\(oversizedReply)", duration: nil, turnID: UUID())
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageRevealDelay + OpenClawReplyPresenter.newMessageFadeDuration + 0.10)
        guard let oversizedField = findTextField(containing: "超长最后消息"),
              let oversizedCard = ancestor(of: oversizedField, accessibilityIdentifier: "openclaw-reply-assistant-card") else {
            preconditionFailure("Expected to find the oversized last OpenClaw message")
        }
        let oversizedCardFrame = windowFrame(of: oversizedCard)
        let scrollClipFrame = windowFrame(of: messageScrollView.contentView)
        precondition(
            oversizedCardFrame.height > scrollClipFrame.height + 20,
            "OpenClaw oversized last-message regression should use a message taller than the visible scroll area"
        )
        precondition(
            abs(oversizedCardFrame.maxY - scrollClipFrame.maxY) < 8 && oversizedCardFrame.minY < scrollClipFrame.minY - 20,
            "An oversized final OpenClaw message should pin its top to the visible area and let its bottom continue off-screen"
        )
        clearButton.performClick(nil)
        runMainLoop(seconds: OpenClawReplyPresenter.newMessageFadeDuration + 0.05)
        precondition(
            findTextField(containing: "滚动长回复-1") == nil
                && findTextField(stringValue: "滚动最新消息-9") == nil,
            "OpenClaw clear button should remove all visible messages"
        )

        print("OpenClawReplyMarkdownRenderingCheck passed")
    }

    @MainActor
    private static func findScrollView(accessibilityIdentifier: String) -> NSScrollView? {
        findView(accessibilityIdentifier: accessibilityIdentifier) as? NSScrollView
    }

    @MainActor
    private static func findView(accessibilityIdentifier: String) -> NSView? {
        for window in NSApplication.shared.windows {
            if let found = findView(in: window.contentView, accessibilityIdentifier: accessibilityIdentifier) {
                return found
            }
        }
        return nil
    }

    private static func findView(in view: NSView?, accessibilityIdentifier: String) -> NSView? {
        guard let view else { return nil }
        if view.accessibilityIdentifier() == accessibilityIdentifier {
            return view
        }
        for subview in view.subviews {
            if let found = findView(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private static func findViews(accessibilityIdentifier: String) -> [NSView] {
        NSApplication.shared.windows.flatMap { window in
            findViews(in: window.contentView, accessibilityIdentifier: accessibilityIdentifier)
        }
    }

    private static func findViews(in view: NSView?, accessibilityIdentifier: String) -> [NSView] {
        guard let view else { return [] }
        var matches: [NSView] = []
        if view.accessibilityIdentifier() == accessibilityIdentifier {
            matches.append(view)
        }
        for subview in view.subviews {
            matches.append(contentsOf: findViews(in: subview, accessibilityIdentifier: accessibilityIdentifier))
        }
        return matches
    }

    @MainActor
    private static func findTextField(stringValue: String) -> NSTextField? {
        for window in NSApplication.shared.windows {
            if let found = findTextField(in: window.contentView, stringValue: stringValue) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private static func findTextField(containing substring: String) -> NSTextField? {
        for window in NSApplication.shared.windows {
            if let found = findTextField(in: window.contentView, containing: substring) {
                return found
            }
        }
        return nil
    }

    private static func findTextField(in view: NSView?, stringValue: String) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.stringValue == stringValue {
            return field
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview, stringValue: stringValue) {
                return found
            }
        }
        return nil
    }

    private static func findTextField(in view: NSView?, containing substring: String) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.stringValue.contains(substring) {
            return field
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview, containing: substring) {
                return found
            }
        }
        return nil
    }

    private static func ancestor(of view: NSView, accessibilityIdentifier: String) -> NSView? {
        var current = view.superview
        while let candidate = current {
            if candidate.accessibilityIdentifier() == accessibilityIdentifier {
                return candidate
            }
            current = candidate.superview
        }
        return nil
    }

    private static func isAncestor(_ ancestor: NSView, of view: NSView) -> Bool {
        var current = view.superview
        while let candidate = current {
            if candidate === ancestor {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    private static func windowFrame(of view: NSView) -> NSRect {
        view.layoutSubtreeIfNeeded()
        return view.convert(view.bounds, to: nil)
    }

    private static func runMainLoop(seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.02)))
        }
    }

    private static func renderImage(_ view: NSView, size: NSSize) -> NSBitmapImageRep {
        view.frame = NSRect(origin: .zero, size: size)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext.current!)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func pixelColor(in bitmap: NSBitmapImageRep, x: Int, y: Int) -> NSColor {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
            preconditionFailure("Missing rendered pixel at \(x),\(y)")
        }
        return color
    }

    private static func color(from cgColor: CGColor?) -> NSColor {
        guard
            let cgColor,
            let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB)
        else {
            preconditionFailure("Expected a concrete bubble color")
        }
        return color
    }

    private static func isNeutralGray(_ color: NSColor) -> Bool {
        let red = color.redComponent
        let green = color.greenComponent
        let blue = color.blueComponent
        return abs(red - green) < 0.04 && abs(green - blue) < 0.04
    }

    private static func isOpenClawRedBadge(_ color: NSColor) -> Bool {
        color.redComponent > color.greenComponent * 1.6
            && color.greenComponent < 0.35
            && color.blueComponent < 0.30
            && color.alphaComponent > 0.90
    }

    private static func isTypeWhaleUserWaterInkBubble(_ color: NSColor) -> Bool {
        color.blueComponent > color.redComponent
            && color.greenComponent > color.redComponent
            && color.blueComponent >= 0.22
            && color.blueComponent <= 0.38
            && color.greenComponent >= 0.16
            && color.greenComponent <= 0.30
            && color.alphaComponent >= 0.88
    }

    private static func isWhiteText(_ color: NSColor?) -> Bool {
        guard let color = color?.usingColorSpace(.sRGB) else { return false }
        return color.redComponent >= 0.92
            && color.greenComponent >= 0.92
            && color.blueComponent >= 0.92
            && color.alphaComponent >= 0.90
    }

    private static func isOpenClawRedBubble(_ color: NSColor) -> Bool {
        color.redComponent > 0.32
            && color.greenComponent <= 0.16
            && color.blueComponent <= 0.16
            && color.redComponent > color.greenComponent * 2.4
            && color.redComponent > color.blueComponent * 2.4
            && color.alphaComponent >= 0.86
    }

    private static func isBlueGrayClearButton(_ color: NSColor) -> Bool {
        color.blueComponent > color.redComponent
            && color.greenComponent > color.redComponent
            && color.blueComponent >= 0.34
            && color.greenComponent >= 0.28
            && color.alphaComponent >= 0.90
    }

    private static func isTranslucentRoundedScrollContainer(_ view: NSView) -> Bool {
        guard let color = NSColor(cgColor: view.layer?.backgroundColor ?? NSColor.clear.cgColor)?.usingColorSpace(.sRGB) else {
            return false
        }
        return color.alphaComponent >= 0.18
            && color.alphaComponent <= 0.55
            && (view.layer?.cornerRadius ?? 0) >= 14
            && (view.layer?.borderWidth ?? 0) >= 0.5
    }

    private static func makeTestAppIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 28, height: 28))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 28, height: 28).fill()
        NSColor(calibratedRed: 0.05, green: 0.32, blue: 0.95, alpha: 1).setFill()
        NSRect(x: 7, y: 5, width: 7, height: 18).fill()
        NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.04, alpha: 1).setFill()
        NSRect(x: 14, y: 5, width: 7, height: 18).fill()
        image.unlockFocus()
        return image
    }

    private static func isTestIconBlue(_ color: NSColor) -> Bool {
        color.blueComponent > 0.70 && color.redComponent < 0.25 && color.alphaComponent > 0.90
    }

    private static func isTestIconYellow(_ color: NSColor) -> Bool {
        color.redComponent > 0.80 && color.greenComponent > 0.55 && color.blueComponent < 0.25 && color.alphaComponent > 0.90
    }
}
