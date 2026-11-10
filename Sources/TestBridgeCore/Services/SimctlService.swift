import Foundation

/// A place a plan can run: a simulator, or this Mac.
public struct DeviceTarget: Identifiable, Hashable, Codable, Sendable {
    public var udid: String
    public var name: String
    public var runtime: String
    public var platform: Platform
    public var state: String
    public var isAvailable: Bool

    public var id: String { udid.isEmpty ? "this-mac" : udid }
    public var isHostMac: Bool { platform == .macOS }
    public var isBooted: Bool { state.lowercased() == "booted" || isHostMac }

    public var destination: Destination {
        isHostMac ? .thisMac : Destination(udid: udid, name: name)
    }

    public static let thisMac = DeviceTarget(udid: "", name: "This Mac", runtime: "macOS",
                                             platform: .macOS, state: "Booted", isAvailable: true)

    public var displayLine: String {
        "\(name) · \(runtime) · \(state)"
    }
}

public enum SimctlService {
    private struct Payload: Decodable {
        let devices: [String: [RawDevice]]
    }

    private struct RawDevice: Decodable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool?
    }

    /// Lists available simulators plus `This Mac`. Grouped so iPads land under `.iPadOS`.
    public static func listDevices() async throws -> [DeviceTarget] {
        let result = try await ShellRunner.run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "-j"])
        guard result.succeeded else {
            throw ShellError(description: "simctl failed: \(result.stderr)")
        }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(result.stdout.utf8))

        var targets: [DeviceTarget] = [.thisMac]
        for (runtimeKey, devices) in payload.devices {
            guard let parsed = parseRuntime(runtimeKey) else { continue }
            let (platform, runtimeName) = parsed
            for d in devices where d.isAvailable ?? true {
                let resolvedPlatform: Platform = (platform == .iOS && d.name.localizedCaseInsensitiveContains("iPad")) ? .iPadOS : platform
                targets.append(DeviceTarget(udid: d.udid, name: d.name, runtime: runtimeName,
                                            platform: resolvedPlatform, state: d.state, isAvailable: true))
            }
        }
        return targets.sorted { lhs, rhs in
            if lhs.platform != rhs.platform { return lhs.platform.rawValue < rhs.platform.rawValue }
            if lhs.isBooted != rhs.isBooted { return lhs.isBooted }
            return lhs.name < rhs.name
        }
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-18-1` → (.iOS, "iOS 18.1")
    private static func parseRuntime(_ key: String) -> (Platform, String)? {
        guard let last = key.split(separator: ".").last else { return nil }
        let parts = last.split(separator: "-", maxSplits: 1).map(String.init)
        guard let osName = parts.first else { return nil }
        let version = parts.count > 1 ? parts[1].replacingOccurrences(of: "-", with: ".") : ""
        let platform: Platform
        switch osName {
        case "iOS": platform = .iOS
        case "watchOS": platform = .watchOS
        default: return nil // tvOS, visionOS are not supported by the Runner yet
        }
        return (platform, version.isEmpty ? osName : "\(osName) \(version)")
    }

    public static func boot(udid: String) async throws {
        let result = try await ShellRunner.run("/usr/bin/xcrun", ["simctl", "boot", udid])
        // "Unable to boot device in current state: Booted" is fine.
        if !result.succeeded && !result.stderr.contains("Booted") {
            throw ShellError(description: "simctl boot failed: \(result.stderr)")
        }
    }

    public static func openSimulatorApp() async {
        _ = try? await ShellRunner.run("/usr/bin/open", ["-a", "Simulator"])
    }

    /// Installed app bundle identifiers on a booted simulator — handy for picking a target.
    public static func installedApps(udid: String) async -> [String] {
        guard let result = try? await ShellRunner.run("/usr/bin/xcrun", ["simctl", "listapps", udid]),
              result.succeeded else { return [] }
        // Output is an old-style plist; pull CFBundleIdentifier values with a regex.
        let pattern = #"CFBundleIdentifier\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = result.stdout
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let ids = matches.compactMap { m -> String? in
            guard let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
        return Array(Set(ids)).filter { !$0.hasPrefix("com.apple.") }.sorted()
    }
}
