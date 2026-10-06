import Foundation

struct RemoteButtonActionCycleTracker {
    private var activeBindings: [RemoteButton: RemoteBinding] = [:]

    mutating func begin(
        button: RemoteButton,
        mapping: RemoteButtonMapping
    ) -> RemoteBinding {
        if let active = activeBindings[button] {
            return active
        }
        let binding = mapping.binding(for: button)
        activeBindings[button] = binding
        return binding
    }

    func binding(
        for button: RemoteButton,
        fallback mapping: RemoteButtonMapping
    ) -> RemoteBinding {
        activeBindings[button] ?? mapping.binding(for: button)
    }

    mutating func end(
        button: RemoteButton,
        fallback mapping: RemoteButtonMapping
    ) -> RemoteBinding {
        activeBindings.removeValue(forKey: button) ?? mapping.binding(for: button)
    }

    mutating func reset() {
        activeBindings.removeAll()
    }
}
