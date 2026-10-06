import Foundation

@main
struct OpenClawReplyStackPolicyCheck {
    static func main() {
        var messages: [String] = []
        for index in 1...7 {
            messages = OpenClawReplyStackPolicy.appending("reply-\(index)", to: messages)
        }

        precondition(messages.count == 7, "OpenClaw reply stack should keep all active messages instead of trimming the list by count")
        precondition(messages.first == "reply-1", "Oldest messages should remain available and scroll upward instead of being removed")
        precondition(messages.last == "reply-7", "Newest OpenClaw reply should remain at the bottom")

        var items: [OpenClawReplyStackPolicy.Item] = []
        for index in 1...7 {
            items = OpenClawReplyStackPolicy.appending(
                OpenClawReplyStackPolicy.Item(userText: "user-\(index)", replyText: "reply-\(index)"),
                to: items
            )
        }

        precondition(items.count == 7, "OpenClaw conversation stack should keep all user/reply items")
        precondition(items.first?.userText == "user-1", "Oldest user prompts should remain available while active instead of being removed by count")
        precondition(items.last?.replyText == "reply-7", "Newest OpenClaw reply should remain at the bottom")

        precondition(
            OpenClawReplyLifecyclePolicy.idleTimeoutAction == .collapseToOrb,
            "OpenClaw idle timeout should collapse to the lobster orb instead of clearing messages"
        )
        precondition(
            OpenClawReplyLifecyclePolicy.clearButtonAction == .clearMessages,
            "OpenClaw clear button should remain a destructive clear action, distinct from idle collapse"
        )
        precondition(
            OpenClawReplyLifecyclePolicy.orbClickAction == .expandMessages,
            "Clicking the OpenClaw lobster orb should expand the preserved messages"
        )

        let tallLayout = OpenClawReplyLayoutPolicy.layout(
            contentHeight: 900,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 600),
            width: 430,
            topMargin: 24,
            bottomMargin: 18,
            leftMargin: 24
        )
        precondition(tallLayout.frame.height == 558, "OpenClaw popup should cap its height at the visible screen bottom")
        precondition(tallLayout.frame.minY == 18, "OpenClaw popup should stop at the bottom margin instead of growing off-screen")
        precondition(tallLayout.requiresScrolling, "OpenClaw popup should enable scrolling when messages exceed screen height")

        let shortLayout = OpenClawReplyLayoutPolicy.layout(
            contentHeight: 160,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 600),
            width: 430,
            topMargin: 24,
            bottomMargin: 18,
            leftMargin: 24
        )
        precondition(shortLayout.frame.height == 160, "OpenClaw popup should keep compact height while content fits")
        precondition(!shortLayout.requiresScrolling, "OpenClaw popup should not show scrolling affordance while content fits")

        print("OpenClawReplyStackPolicyCheck passed")
    }
}
