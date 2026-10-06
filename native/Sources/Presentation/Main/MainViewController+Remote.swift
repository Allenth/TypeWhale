import AppKit

@MainActor
extension MainViewController {
    func buildRemoteInspectorPage() -> NSView {
        let page = RemoteInspectorView()
        page.onEnabledChange = { [weak self] enabled in self?.onRemoteEnabledChange?(enabled) }
        page.onPrimaryAction = { [weak self] in self?.onRemotePrimaryAction?() }
        page.onMappingChange = { [weak self] button, action in
            self?.onRemoteMappingChange?(button, action)
        }
        page.onResetMappings = { [weak self] in self?.onRemoteResetMappings?() }
        remoteInspectorView = page
        page.apply(snapshot: latestRemoteInputSnapshot)
        return page
    }

    func updateRemoteInputSnapshot(_ snapshot: RemoteInputSnapshot) {
        latestRemoteInputSnapshot = snapshot
        remoteInspectorView?.apply(snapshot: snapshot)
    }
}
