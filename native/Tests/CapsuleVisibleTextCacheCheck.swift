import Foundation

@main
struct CapsuleVisibleTextCacheCheck {
    static func main() {
        var cache = CapsuleVisibleTextCache(maxCharacters: 80)
        var measurementCalls = 0

        let first = cache.resolve(source: "abcdefghijklmnopqrstuvwxyz", width: 80) { candidate in
            measurementCalls += 1
            return Double(candidate.count * 10)
        }
        precondition(first == "stuvwxyz", "the cache must preserve the widest fitting suffix")
        let callsAfterFirstResolution = measurementCalls
        precondition(callsAfterFirstResolution > 0)

        let repeated = cache.resolve(source: "abcdefghijklmnopqrstuvwxyz", width: 80) { _ in
            measurementCalls += 1
            return 0
        }
        precondition(repeated == first)
        precondition(measurementCalls == callsAfterFirstResolution, "identical draw inputs must not remeasure text")

        let resized = cache.resolve(source: "abcdefghijklmnopqrstuvwxyz", width: 100) { candidate in
            measurementCalls += 1
            return Double(candidate.count * 10)
        }
        precondition(resized == "qrstuvwxyz", "a width change must invalidate the cached suffix")
        precondition(measurementCalls > callsAfterFirstResolution)

        let callsAfterResize = measurementCalls
        let changedSource = cache.resolve(source: "1234567890", width: 100) { candidate in
            measurementCalls += 1
            return Double(candidate.count * 10)
        }
        precondition(changedSource == "1234567890", "a source change must resolve the new suffix")
        precondition(measurementCalls > callsAfterResize, "a source change must invalidate the cached suffix")

        print("CapsuleVisibleTextCacheCheck passed")
    }
}
