import Foundation

/// One of the developer's own apps, so the target can be picked by name instead of typing a bundle identifier.
/// The list lives in `Apps.json` next to the plans: `[{"name": "…", "bundleIdentifier": "…", "platform": "ios"}]`.
public struct AppPreset: Codable, Identifiable, Hashable, Sendable {
    public var name: String
    public var bundleIdentifier: String
    public var platform: Platform

    public var id: String { "\(platform.rawValue):\(bundleIdentifier)" }

    public static func load(from url: URL = Paths.apps) -> [AppPreset] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AppPreset].self, from: data)) ?? []
    }
}
