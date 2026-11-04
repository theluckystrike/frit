import Foundation

/// Finds GlazeCore's resource bundle.
///
/// SwiftPM's generated `Bundle.module` looks only at `<main bundle>/Glaze_GlazeCore.bundle` (the .app root, which
/// code signing does not allow) and then at an absolute .build path (blocked by the sandbox), and calls fatalError
/// when both fail. In the .app the bundle is in Contents/Resources, so look there first.
enum ResourceBundle {
    static let name = "Glaze_GlazeCore.bundle"

    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name), let b = Bundle(url: url) {
            return b
        }
        return Bundle.module // swift test and swift run
    }()

    static func url(_ resource: String, _ ext: String) -> URL? {
        bundle.url(forResource: resource, withExtension: ext)
    }
}
