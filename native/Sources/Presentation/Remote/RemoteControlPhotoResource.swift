import AppKit

enum RemoteControlPhotoResource {
    static let resourceName = "RC003-remote-photo"
    static let resourceExtension = "png"
    static let resourceSubdirectory = "Remote"
    static let expectedPixelSize = CGSize(width: 1024, height: 1536)

    static let image: NSImage? = load()

    static func load(bundle: Bundle = .main) -> NSImage? {
        let nested = bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: resourceSubdirectory
        )
        let flat = bundle.url(forResource: resourceName, withExtension: resourceExtension)
        guard let url = nested ?? flat else { return nil }
        return NSImage(contentsOf: url)
    }
}
