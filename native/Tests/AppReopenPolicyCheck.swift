import Foundation

@main
struct AppReopenPolicyCheck {
    static func main() {
        var policy = AppReopenPolicy()
        let now = Date(timeIntervalSince1970: 1_000)

        assert(!policy.consumeSuppression(now: now), "fresh policy must not suppress reopen")

        policy.suppress(until: now.addingTimeInterval(1.0))
        assert(policy.consumeSuppression(now: now.addingTimeInterval(0.2)), "active suppression must consume one reopen")
        assert(!policy.consumeSuppression(now: now.addingTimeInterval(0.3)), "suppression must be one-shot")

        policy.suppress(until: now.addingTimeInterval(1.0))
        assert(!policy.consumeSuppression(now: now.addingTimeInterval(1.1)), "expired suppression must not hide Dock reopen")

        policy.suppress(until: now.addingTimeInterval(2.0))
        policy.suppress(until: now.addingTimeInterval(0.5))
        assert(policy.consumeSuppression(now: now.addingTimeInterval(1.5)), "shorter suppression must not shorten an existing longer window")

        print("AppReopenPolicyCheck passed")
    }
}
