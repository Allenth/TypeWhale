import Foundation

struct RemoteButtonMapping: Equatable {
    private var bindings: [RemoteButton: RemoteBinding]
    private var opaqueBindings: [String: Data]

    fileprivate init(
        bindings: [RemoteButton: RemoteBinding],
        opaqueBindings: [String: Data] = [:]
    ) {
        self.bindings = bindings
        self.opaqueBindings = opaqueBindings
    }

    static let defaults = RemoteButtonMapping(bindings: [
        .voice: RemoteActionCatalog.builtIn.binding(for: .pushToTalk),
        .dpadUp: RemoteActionCatalog.builtIn.binding(for: .system),
        .dpadDown: RemoteActionCatalog.builtIn.binding(for: .system),
        .dpadLeft: RemoteActionCatalog.builtIn.binding(for: .system),
        .dpadRight: RemoteActionCatalog.builtIn.binding(for: .system),
        .center: RemoteActionCatalog.builtIn.binding(for: .system),
        .back: RemoteActionCatalog.builtIn.binding(for: .system),
        .home: RemoteActionCatalog.builtIn.binding(for: .toggleMainWindow),
        .menu: RemoteActionCatalog.builtIn.binding(for: .none),
        .volumeUp: RemoteActionCatalog.builtIn.binding(for: .system),
        .volumeDown: RemoteActionCatalog.builtIn.binding(for: .system),
        .tv: RemoteActionCatalog.builtIn.binding(for: .system),
        .power: RemoteActionCatalog.builtIn.binding(for: .system),
    ])

    func binding(for button: RemoteButton) -> RemoteBinding {
        let fallback = Self.defaults.bindings[button]
            ?? RemoteActionCatalog.builtIn.binding(for: .none)
        guard let binding = bindings[button],
              RemoteActionCatalog.builtIn.resolve(binding, for: button) != nil else {
            return fallback
        }
        return binding
    }

    func action(for button: RemoteButton) -> RemoteButtonAction {
        RemoteActionCatalog.builtIn.resolve(binding(for: button), for: button)
            ?? Self.defaults.actionWithoutFallback(for: button)
    }

    func canEdit(_ button: RemoteButton) -> Bool {
        RemoteButton.allCases.contains(button)
    }

    mutating func set(_ action: RemoteButtonAction, for button: RemoteButton) {
        set(RemoteActionCatalog.builtIn.binding(for: action), for: button)
    }

    mutating func set(_ binding: RemoteBinding, for button: RemoteButton) {
        guard canEdit(button) else { return }
        opaqueBindings.removeValue(forKey: button.rawValue)
        bindings[button] = RemoteActionCatalog.builtIn.resolve(binding, for: button) == nil
            ? Self.defaults.binding(for: button)
            : binding
    }

    var storedBindings: [RemoteButton: RemoteBinding] {
        Dictionary(uniqueKeysWithValues: RemoteButton.allCases.map { button in
            (button, binding(for: button))
        })
    }

    var storedOpaqueBindings: [String: Data] {
        opaqueBindings
    }

    static func recovering(
        _ bindings: [RemoteButton: RemoteBinding],
        opaqueBindings: [String: Data] = [:]
    ) -> Self {
        var mapping = Self(
            bindings: Self.defaults.bindings,
            opaqueBindings: opaqueBindings
        )
        for (button, binding) in bindings {
            mapping.bindings[button] = binding
        }
        return mapping
    }

    private func actionWithoutFallback(for button: RemoteButton) -> RemoteButtonAction {
        guard let binding = bindings[button],
              let action = RemoteActionCatalog.builtIn.resolve(binding, for: button) else {
            return .none
        }
        return action
    }
}
