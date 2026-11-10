import Foundation

// MARK: - Platform

/// Apple platforms the Runner can drive. Raw values are what the JSON DSL uses.
public enum Platform: String, Codable, CaseIterable, Hashable, Sendable {
    case iOS = "ios"
    case iPadOS = "ipados"
    case watchOS = "watchos"
    case macOS = "macos"

    public var displayName: String {
        switch self {
        case .iOS: return "iOS"
        case .iPadOS: return "iPadOS"
        case .watchOS: return "watchOS"
        case .macOS: return "macOS"
        }
    }

    /// The xcodebuild `platform=` value for a simulator destination. `nil` for macOS (host).
    public var simulatorPlatformName: String? {
        switch self {
        case .iOS, .iPadOS: return "iOS Simulator"
        case .watchOS: return "watchOS Simulator"
        case .macOS: return nil
        }
    }

    /// Scheme inside the Runner Xcode project that hosts the interpreter for this platform.
    public var runnerScheme: String {
        switch self {
        case .iOS, .iPadOS: return "Runner-iOS"
        case .watchOS: return "Runner-watchOS"
        case .macOS: return "Runner-macOS"
        }
    }

    public var needsSimulator: Bool { self != .macOS }
}

// MARK: - Destination

/// Where the plan runs. For simulators pass the UDID (preferred) or a device name.
public struct Destination: Codable, Hashable, Sendable {
    public var udid: String?
    public var name: String?

    public init(udid: String? = nil, name: String? = nil) {
        self.udid = udid
        self.name = name
    }

    public static let thisMac = Destination(udid: nil, name: "This Mac")

    public func xcodebuildArgument(for platform: Platform) -> String {
        guard let simPlatform = platform.simulatorPlatformName else {
            return "platform=macOS"
        }
        if let udid, !udid.isEmpty {
            return "platform=\(simPlatform),id=\(udid)"
        }
        let fallbackName: String
        switch platform {
        case .iPadOS: fallbackName = "iPad Pro 11-inch (M4)"
        case .watchOS: fallbackName = "Apple Watch Series 10 (46mm)"
        default: fallbackName = "iPhone 16"
        }
        return "platform=\(simPlatform),name=\(name ?? fallbackName)"
    }
}

// MARK: - Element query

public enum ElementKind: String, Codable, CaseIterable, Hashable, Sendable {
    case any, button, textField, secureTextField, staticText, textView, searchField
    case cell, table, collectionView, scrollView
    case `switch`, slider, stepper, segmentedControl, picker, pickerWheel, datePicker
    case image, link, webView, map
    case navigationBar, tabBar, toolbar, menuItem, menuBarItem, popUpButton, checkBox, radioButton
    case window, sheet, alert, dialog, popover
    case other
}

/// Describes how to find one element. At least one of `id`, `label`, `labelContains`, `text` should be set
/// (or `type` alone with `index`).
public struct ElementQuery: Codable, Hashable, Sendable, CustomStringConvertible {
    public var id: String?
    public var label: String?
    public var labelContains: String?
    public var text: String?
    public var type: ElementKind?
    public var index: Int?

    public init(id: String? = nil, label: String? = nil, labelContains: String? = nil,
                text: String? = nil, type: ElementKind? = nil, index: Int? = nil) {
        self.id = id
        self.label = label
        self.labelContains = labelContains
        self.text = text
        self.type = type
        self.index = index
    }

    public var hasMatcher: Bool {
        id != nil || label != nil || labelContains != nil || text != nil || (type != nil && index != nil)
    }

    public var description: String {
        var parts: [String] = []
        if let type { parts.append("type=\(type.rawValue)") }
        if let id { parts.append("id=\"\(id)\"") }
        if let label { parts.append("label=\"\(label)\"") }
        if let labelContains { parts.append("labelContains=\"\(labelContains)\"") }
        if let text { parts.append("text=\"\(text)\"") }
        if let index { parts.append("index=\(index)") }
        return parts.isEmpty ? "<empty query>" : parts.joined(separator: " ")
    }
}

public enum SwipeDirection: String, Codable, CaseIterable, Hashable, Sendable {
    case up, down, left, right
}

// MARK: - Step

/// One action in a plan. Encoded as `{"action": "<name>", ...fields}`.
public enum Step: Hashable, Sendable {
    case launch
    case terminate
    case activate
    case tap(ElementQuery)
    case doubleTap(ElementQuery)
    case longPress(ElementQuery, seconds: Double)
    case typeText(ElementQuery, text: String, clearFirst: Bool)
    case swipe(ElementQuery?, direction: SwipeDirection)
    case scrollTo(ElementQuery, direction: SwipeDirection, maxSwipes: Int)
    case tapCoordinate(x: Double, y: Double)
    case wait(seconds: Double)
    case assertExists(ElementQuery, timeout: Double)
    case assertNotExists(ElementQuery, timeout: Double)
    case assertText(ElementQuery, equals: String?, contains: String?)
    case assertEnabled(ElementQuery, enabled: Bool)
    case pressKey(key: String, modifiers: [String])
    case rotate(orientation: String)
    case screenshot(name: String)
    case dumpTree(name: String?)
    /// Snapshot every element on screen and check it against the HIG rule catalog. `failOn == nil` never fails the step.
    case higAudit(name: String, failOn: HIGSeverity?)

    public static let knownActions: [String] = [
        "launch", "terminate", "activate",
        "tap", "doubleTap", "longPress", "typeText", "swipe", "scrollTo", "tapCoordinate",
        "wait", "assertExists", "assertNotExists", "assertText", "assertEnabled",
        "pressKey", "rotate", "screenshot", "dumpTree", "higAudit",
    ]

    public var actionName: String {
        switch self {
        case .launch: return "launch"
        case .terminate: return "terminate"
        case .activate: return "activate"
        case .tap: return "tap"
        case .doubleTap: return "doubleTap"
        case .longPress: return "longPress"
        case .typeText: return "typeText"
        case .swipe: return "swipe"
        case .scrollTo: return "scrollTo"
        case .tapCoordinate: return "tapCoordinate"
        case .wait: return "wait"
        case .assertExists: return "assertExists"
        case .assertNotExists: return "assertNotExists"
        case .assertText: return "assertText"
        case .assertEnabled: return "assertEnabled"
        case .pressKey: return "pressKey"
        case .rotate: return "rotate"
        case .screenshot: return "screenshot"
        case .dumpTree: return "dumpTree"
        case .higAudit: return "higAudit"
        }
    }

    public var target: ElementQuery? {
        switch self {
        case .tap(let q), .doubleTap(let q), .longPress(let q, _), .typeText(let q, _, _),
             .scrollTo(let q, _, _), .assertExists(let q, _), .assertNotExists(let q, _),
             .assertText(let q, _, _), .assertEnabled(let q, _):
            return q
        case .swipe(let q, _):
            return q
        default:
            return nil
        }
    }

    public var summary: String {
        switch self {
        case .launch: return "launch app"
        case .terminate: return "terminate app"
        case .activate: return "activate app"
        case .tap(let q): return "tap \(q)"
        case .doubleTap(let q): return "doubleTap \(q)"
        case .longPress(let q, let s): return "longPress \(q) for \(s)s"
        case .typeText(let q, let t, let clear): return "type \"\(t)\" into \(q)\(clear ? " (clear first)" : "")"
        case .swipe(let q, let d): return "swipe \(d.rawValue)\(q.map { " on \($0)" } ?? "")"
        case .scrollTo(let q, let d, let max): return "scroll \(d.rawValue) until \(q) (max \(max))"
        case .tapCoordinate(let x, let y): return "tap at (\(x), \(y))"
        case .wait(let s): return "wait \(s)s"
        case .assertExists(let q, let t): return "assert exists \(q) within \(t)s"
        case .assertNotExists(let q, let t): return "assert not exists \(q) within \(t)s"
        case .assertText(let q, let eq, let contains):
            if let eq { return "assert \(q) text == \"\(eq)\"" }
            return "assert \(q) text contains \"\(contains ?? "")\""
        case .assertEnabled(let q, let e): return "assert \(q) enabled == \(e)"
        case .pressKey(let k, let m): return "press key \(m.isEmpty ? "" : m.joined(separator: "+") + "+")\(k)"
        case .rotate(let o): return "rotate to \(o)"
        case .screenshot(let n): return "screenshot \"\(n)\""
        case .dumpTree(let n): return "dump accessibility tree\(n.map { " \"\($0)\"" } ?? "")"
        case .higAudit(let n, let failOn): return "HIG audit \"\(n)\"\(failOn.map { " (fail on \($0.rawValue))" } ?? " (report only)")"
        }
    }
}

extension Step: Codable {
    private enum CodingKeys: String, CodingKey {
        case action, target, text, clearFirst, seconds, direction, maxSwipes, timeout
        case equals, contains, enabled, key, modifiers, orientation, name, x, y, failOn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let action = try c.decode(String.self, forKey: .action)

        func target() throws -> ElementQuery {
            guard let q = try c.decodeIfPresent(ElementQuery.self, forKey: .target) else {
                throw DecodingError.keyNotFound(
                    CodingKeys.target,
                    .init(codingPath: c.codingPath, debugDescription: "action '\(action)' requires a \"target\"")
                )
            }
            return q
        }

        switch action {
        case "launch": self = .launch
        case "terminate": self = .terminate
        case "activate": self = .activate
        case "tap": self = .tap(try target())
        case "doubleTap": self = .doubleTap(try target())
        case "longPress":
            self = .longPress(try target(), seconds: try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 1.0)
        case "typeText":
            self = .typeText(try target(),
                             text: try c.decode(String.self, forKey: .text),
                             clearFirst: try c.decodeIfPresent(Bool.self, forKey: .clearFirst) ?? false)
        case "swipe":
            self = .swipe(try c.decodeIfPresent(ElementQuery.self, forKey: .target),
                          direction: try c.decode(SwipeDirection.self, forKey: .direction))
        case "scrollTo":
            self = .scrollTo(try target(),
                             direction: try c.decodeIfPresent(SwipeDirection.self, forKey: .direction) ?? .up,
                             maxSwipes: try c.decodeIfPresent(Int.self, forKey: .maxSwipes) ?? 10)
        case "tapCoordinate":
            self = .tapCoordinate(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y))
        case "wait":
            self = .wait(seconds: try c.decode(Double.self, forKey: .seconds))
        case "assertExists":
            self = .assertExists(try target(), timeout: try c.decodeIfPresent(Double.self, forKey: .timeout) ?? 5)
        case "assertNotExists":
            self = .assertNotExists(try target(), timeout: try c.decodeIfPresent(Double.self, forKey: .timeout) ?? 5)
        case "assertText":
            let eq = try c.decodeIfPresent(String.self, forKey: .equals)
            let contains = try c.decodeIfPresent(String.self, forKey: .contains)
            guard eq != nil || contains != nil else {
                throw DecodingError.dataCorruptedError(forKey: .equals, in: c,
                                                       debugDescription: "assertText needs \"equals\" or \"contains\"")
            }
            self = .assertText(try target(), equals: eq, contains: contains)
        case "assertEnabled":
            self = .assertEnabled(try target(), enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true)
        case "pressKey":
            self = .pressKey(key: try c.decode(String.self, forKey: .key),
                             modifiers: try c.decodeIfPresent([String].self, forKey: .modifiers) ?? [])
        case "rotate":
            self = .rotate(orientation: try c.decode(String.self, forKey: .orientation))
        case "screenshot":
            self = .screenshot(name: try c.decodeIfPresent(String.self, forKey: .name) ?? "screenshot")
        case "dumpTree":
            self = .dumpTree(name: try c.decodeIfPresent(String.self, forKey: .name))
        case "higAudit":
            let raw = try c.decodeIfPresent(String.self, forKey: .failOn) ?? "error"
            let failOn: HIGSeverity?
            switch raw.lowercased() {
            case "none", "never", "report": failOn = nil
            default:
                guard let sev = HIGSeverity(rawValue: raw.lowercased()) else {
                    throw DecodingError.dataCorruptedError(forKey: .failOn, in: c,
                                                           debugDescription: "higAudit failOn must be error | warning | info | none")
                }
                failOn = sev
            }
            self = .higAudit(name: try c.decodeIfPresent(String.self, forKey: .name) ?? "screen", failOn: failOn)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .action, in: c,
                debugDescription: "Unknown action '\(action)'. Known actions: \(Step.knownActions.joined(separator: ", "))"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(actionName, forKey: .action)
        switch self {
        case .launch, .terminate, .activate:
            break
        case .tap(let q), .doubleTap(let q):
            try c.encode(q, forKey: .target)
        case .longPress(let q, let s):
            try c.encode(q, forKey: .target)
            try c.encode(s, forKey: .seconds)
        case .typeText(let q, let t, let clear):
            try c.encode(q, forKey: .target)
            try c.encode(t, forKey: .text)
            if clear { try c.encode(clear, forKey: .clearFirst) }
        case .swipe(let q, let d):
            try c.encodeIfPresent(q, forKey: .target)
            try c.encode(d, forKey: .direction)
        case .scrollTo(let q, let d, let max):
            try c.encode(q, forKey: .target)
            try c.encode(d, forKey: .direction)
            try c.encode(max, forKey: .maxSwipes)
        case .tapCoordinate(let x, let y):
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
        case .wait(let s):
            try c.encode(s, forKey: .seconds)
        case .assertExists(let q, let t), .assertNotExists(let q, let t):
            try c.encode(q, forKey: .target)
            try c.encode(t, forKey: .timeout)
        case .assertText(let q, let eq, let contains):
            try c.encode(q, forKey: .target)
            try c.encodeIfPresent(eq, forKey: .equals)
            try c.encodeIfPresent(contains, forKey: .contains)
        case .assertEnabled(let q, let e):
            try c.encode(q, forKey: .target)
            try c.encode(e, forKey: .enabled)
        case .pressKey(let k, let m):
            try c.encode(k, forKey: .key)
            if !m.isEmpty { try c.encode(m, forKey: .modifiers) }
        case .rotate(let o):
            try c.encode(o, forKey: .orientation)
        case .screenshot(let n):
            try c.encode(n, forKey: .name)
        case .dumpTree(let n):
            try c.encodeIfPresent(n, forKey: .name)
        case .higAudit(let n, let failOn):
            try c.encode(n, forKey: .name)
            try c.encode(failOn?.rawValue ?? "none", forKey: .failOn)
        }
    }
}

// MARK: - TestPlan

public struct TestPlan: Codable, Hashable, Sendable {
    public var name: String
    public var platform: Platform
    public var bundleIdentifier: String
    public var destination: Destination?
    public var launchArguments: [String]
    public var launchEnvironment: [String: String]
    public var stopOnFailure: Bool
    public var steps: [Step]

    public init(name: String, platform: Platform, bundleIdentifier: String,
                destination: Destination? = nil, launchArguments: [String] = [],
                launchEnvironment: [String: String] = [:], stopOnFailure: Bool = true, steps: [Step]) {
        self.name = name
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
        self.destination = destination
        self.launchArguments = launchArguments
        self.launchEnvironment = launchEnvironment
        self.stopOnFailure = stopOnFailure
        self.steps = steps
    }

    private enum CodingKeys: String, CodingKey {
        case name, platform, bundleIdentifier, destination, launchArguments, launchEnvironment, stopOnFailure, steps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled plan"
        platform = try c.decode(Platform.self, forKey: .platform)
        bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        destination = try c.decodeIfPresent(Destination.self, forKey: .destination)
        launchArguments = try c.decodeIfPresent([String].self, forKey: .launchArguments) ?? []
        launchEnvironment = try c.decodeIfPresent([String: String].self, forKey: .launchEnvironment) ?? [:]
        stopOnFailure = try c.decodeIfPresent(Bool.self, forKey: .stopOnFailure) ?? true
        steps = try c.decodeIfPresent([Step].self, forKey: .steps) ?? []
    }

    public static func decode(_ data: Data) throws -> TestPlan {
        try JSONDecoder().decode(TestPlan.self, from: data)
    }

    public static func decode(json: String) throws -> TestPlan {
        try decode(Data(json.utf8))
    }

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(self)
    }

    public func encodedString() -> String {
        (try? encoded()).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Non-fatal problems a human (or Claude) should fix before running.
    public func validate() -> [String] {
        var issues: [String] = []
        if bundleIdentifier.split(separator: ".").count < 2 {
            issues.append("bundleIdentifier \"\(bundleIdentifier)\" does not look like a reverse-DNS identifier.")
        }
        if steps.isEmpty { issues.append("Plan has no steps.") }
        for (i, step) in steps.enumerated() {
            if let q = step.target, !q.hasMatcher {
                issues.append("Step \(i + 1) (\(step.actionName)) has a target with no matcher (id/label/labelContains/text, or type+index).")
            }
            switch step {
            case .pressKey where platform != .macOS:
                issues.append("Step \(i + 1): pressKey is only supported on macOS.")
            case .rotate where platform == .macOS || platform == .watchOS:
                issues.append("Step \(i + 1): rotate is only supported on iOS/iPadOS.")
            case .typeText where platform == .watchOS:
                issues.append("Step \(i + 1): typeText on watchOS is unreliable (no hardware keyboard); prefer tapping dictation/scribble or prefilled state via launchEnvironment.")
            default: break
            }
        }
        let hasAssertion = steps.contains { $0.actionName.hasPrefix("assert") }
        let hasAudit = steps.contains { $0.actionName == "higAudit" || $0.actionName == "dumpTree" }
        if !hasAssertion && !hasAudit {
            issues.append("Plan has no assertions or HIG audits. It will only exercise the UI, not verify it.")
        }
        let auditNames = steps.compactMap { step -> String? in
            if case .higAudit(let name, _) = step { return name }
            return nil
        }
        if Set(auditNames).count != auditNames.count {
            issues.append("Several higAudit steps share the same name; give each screen a distinct name.")
        }
        return issues
    }

    /// A plan that just launches the app and dumps its accessibility tree — used to ground Claude's prompt.
    public static func snapshotPlan(platform: Platform, bundleIdentifier: String, destination: Destination?, settleSeconds: Double = 2) -> TestPlan {
        TestPlan(name: "Accessibility snapshot",
                 platform: platform,
                 bundleIdentifier: bundleIdentifier,
                 destination: destination,
                 steps: [.launch, .wait(seconds: settleSeconds), .dumpTree(name: "snapshot"), .screenshot(name: "snapshot")])
    }

    /// Launches the app and audits the first screen against the HIG rules. Also dumps the tree so Claude gets both.
    public static func higAuditPlan(platform: Platform, bundleIdentifier: String, destination: Destination?,
                                    screenName: String = "first-screen", failOn: HIGSeverity? = nil, settleSeconds: Double = 2) -> TestPlan {
        TestPlan(name: "HIG audit",
                 platform: platform,
                 bundleIdentifier: bundleIdentifier,
                 destination: destination,
                 stopOnFailure: false,
                 steps: [.launch, .wait(seconds: settleSeconds),
                         .dumpTree(name: "snapshot"),
                         .screenshot(name: screenName),
                         .higAudit(name: screenName, failOn: failOn)])
    }
}
