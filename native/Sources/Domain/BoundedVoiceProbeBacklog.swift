struct BoundedVoiceProbeBacklog<Element> {
    let capacity: Int
    private var elements: [Element] = []

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var isEmpty: Bool {
        elements.isEmpty
    }

    @discardableResult
    mutating func enqueue(_ element: Element) -> Bool {
        guard elements.count < capacity else { return false }
        elements.append(element)
        return true
    }

    mutating func dequeue() -> Element? {
        guard !elements.isEmpty else { return nil }
        return elements.removeFirst()
    }

    mutating func removeAll() {
        elements.removeAll(keepingCapacity: true)
    }
}
