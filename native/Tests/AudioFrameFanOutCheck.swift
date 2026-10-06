import Foundation

@main
struct AudioFrameFanOutCheck {
    static func main() async {
        let fanOut = AudioFrameFanOut()
        let fast = fanOut.subscribe(capacity: 8)
        let slow = fanOut.subscribe(capacity: 2)

        let fastCollector = Task { () -> [Int64] in
            var starts: [Int64] = []
            for await event in fast.events {
                if case .frame(let frame) = event {
                    starts.append(frame.startFrame)
                    if starts.count == 4 { break }
                }
            }
            return starts
        }

        // slow 完全不消费；offer 必须同步、非等待地继续，且只关闭 slow。
        for index in 0..<4 {
            fanOut.offer(AudioFrame(
                samples: [Float(index)],
                sampleRate: 16_000,
                channelCount: 1,
                startFrame: Int64(index)
            ))
        }

        let fastFrames = await fastCollector.value
        precondition(fastFrames == [0, 1, 2, 3])
        precondition(fanOut.isSubscribed(fast.id))
        precondition(!fanOut.isSubscribed(slow.id))

        var slowSawOverflow = false
        for await event in slow.events {
            if case .overflow(let droppedFrames) = event {
                precondition(droppedFrames >= 1)
                slowSawOverflow = true
            }
        }
        precondition(slowSawOverflow)

        // 一个消费者溢出后，其他消费者仍能继续收到新帧。
        let next = Task { () -> Int64? in
            for await event in fast.events {
                if case .frame(let frame) = event { return frame.startFrame }
            }
            return nil
        }
        fanOut.offer(AudioFrame(
            samples: [9],
            sampleRate: 16_000,
            channelCount: 1,
            startFrame: 9
        ))
        let nextFrame = await next.value
        precondition(nextFrame == 9)

        fanOut.finish()
        precondition(fanOut.subscriberCount == 0)
        print("AudioFrameFanOutCheck passed")
    }
}
