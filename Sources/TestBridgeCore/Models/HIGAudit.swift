import Foundation
import CoreGraphics

// MARK: - Severity

public enum HIGSeverity: String, Codable, CaseIterable, Hashable, Sendable, Comparable {
    case info, warning, error

    public var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }

    public static func < (lhs: HIGSeverity, rhs: HIGSeverity) -> Bool { lhs.rank < rhs.rank }
}

// MARK: - Rect (plain JSON instead of CGRect's encoding)

public struct HIGRect: Codable, Hashable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public init(_ r: CGRect) {
        self.init(x: Double(r.origin.x), y: Double(r.origin.y), width: Double(r.size.width), height: Double(r.size.height))
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public var area: Double { max(0, width) * max(0, height) }
    public var isEmpty: Bool { width <= 0 || height <= 0 }
    public var minSide: Double { min(width, height) }

    public func intersection(_ other: HIGRect) -> HIGRect {
        let r = cgRect.intersection(other.cgRect)
        return r.isNull ? HIGRect(x: 0, y: 0, width: 0, height: 0) : HIGRect(r)
    }

    public func intersects(_ other: HIGRect) -> Bool { !intersection(other).isEmpty }

    public var description: String {
        "\(Int(width.rounded()))×\(Int(height.rounded())) @ \(Int(x.rounded())),\(Int(y.rounded()))"
    }
}

// MARK: - Rule catalog

public struct HIGRule: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let titleKo: String
    /// One line: what the HIG asks for and what this rule measures.
    public let guideline: String
    /// Path under the HIG site, e.g. "layout".
    public let higPath: String
    public let platforms: Set<Platform>
    public let defaultSeverity: HIGSeverity

    public var url: URL { HIGRules.url(for: higPath) }
}

public enum HIGRules {
    /// Korean HIG site. Each rule links to the matching page.
    public static let baseURL = "https://developer.apple.com/kr/design/human-interface-guidelines/"

    public static func url(for path: String) -> URL { URL(string: baseURL + path)! }

    private static let all4: Set<Platform> = [.iOS, .iPadOS, .watchOS, .macOS]
    private static let touch: Set<Platform> = [.iOS, .iPadOS, .watchOS]

    public static let all: [HIGRule] = [
        HIGRule(id: "target-size", title: "Control is smaller than the minimum target size", titleKo: "컨트롤이 최소 터치 영역보다 작음",
                guideline: "iOS/iPadOS/watchOS controls need a hit area of at least 44×44pt; macOS pointer targets should not be smaller than about 20pt.",
                higPath: "layout", platforms: all4, defaultSeverity: .error),
        HIGRule(id: "missing-label", title: "Control has no accessibility label", titleKo: "컨트롤에 접근성 라벨이 없음",
                guideline: "Every control must have a label VoiceOver can read. Image-only buttons need an accessibilityLabel.",
                higPath: "accessibility", platforms: all4, defaultSeverity: .error),
        HIGRule(id: "text-field-label", title: "Text field has no label", titleKo: "텍스트 필드에 라벨이 없음",
                guideline: "Text fields need a visible or accessibility label; a placeholder alone disappears while typing.",
                higPath: "text-fields", platforms: all4, defaultSeverity: .warning),
        HIGRule(id: "identifier-like-label", title: "User-facing label looks like an internal identifier", titleKo: "사용자에게 보이는 라벨이 내부 식별자처럼 보임",
                guideline: "Labels are read aloud by VoiceOver and shown on screen; write them as human language, not code names.",
                higPath: "writing", platforms: all4, defaultSeverity: .warning),
        HIGRule(id: "duplicate-label", title: "Several controls share the same label", titleKo: "여러 컨트롤이 같은 라벨을 공유함",
                guideline: "VoiceOver users cannot tell identically labeled controls apart. Give each a distinct label or identifier.",
                higPath: "accessibility", platforms: all4, defaultSeverity: .info),
        HIGRule(id: "tab-bar-item-count", title: "Tab bar has more than five items", titleKo: "탭 막대 항목이 5개를 초과함",
                guideline: "On iPhone a tab bar should hold three to five tabs; more are truncated into a More tab.",
                higPath: "tab-bars", platforms: [.iOS], defaultSeverity: .warning),
        HIGRule(id: "alert-button-count", title: "Alert has too many buttons", titleKo: "알림창 버튼이 너무 많음",
                guideline: "Alerts work best with one or two buttons; use an action sheet or menu for more choices.",
                higPath: "alerts", platforms: all4, defaultSeverity: .warning),
        HIGRule(id: "small-text", title: "Text appears smaller than the minimum readable size", titleKo: "텍스트가 최소 가독 크기보다 작아 보임",
                guideline: "Keep text at 11pt or larger on iOS (10pt on macOS); the measured line height suggests a smaller font.",
                higPath: "typography", platforms: all4, defaultSeverity: .warning),
        HIGRule(id: "overlapping-targets", title: "Two controls overlap", titleKo: "두 컨트롤이 겹침",
                guideline: "Interactive elements must not overlap; overlapping hit areas cause mis-taps and confuse assistive tech.",
                higPath: "layout", platforms: all4, defaultSeverity: .warning),
        HIGRule(id: "offscreen-target", title: "Control is mostly outside the screen", titleKo: "컨트롤이 화면 밖에 대부분 걸쳐 있음",
                guideline: "Controls that are not inside a scrolling container must be fully visible within the safe area.",
                higPath: "layout", platforms: all4, defaultSeverity: .warning),
        HIGRule(id: "nested-interactive", title: "Control is nested inside another control", titleKo: "컨트롤 안에 다른 컨트롤이 중첩됨",
                guideline: "A button inside a button (or link) is ambiguous for VoiceOver and pointer focus; flatten the hierarchy.",
                higPath: "accessibility", platforms: all4, defaultSeverity: .warning),
        HIGRule(id: "list-row-height", title: "List row is shorter than 44pt", titleKo: "목록 행 높이가 44pt 미만임",
                guideline: "List rows are tap targets; keep them at least 44pt tall.",
                higPath: "lists-and-tables", platforms: [.iOS, .iPadOS], defaultSeverity: .warning),
        HIGRule(id: "window-title", title: "Window has no title", titleKo: "윈도우에 제목이 없음",
                guideline: "macOS windows should show a title so people can identify them in the Window menu and Mission Control.",
                higPath: "windows", platforms: [.macOS], defaultSeverity: .warning),
        HIGRule(id: "no-accessible-content", title: "Screen exposes nothing to accessibility", titleKo: "화면이 접근성 트리에 아무것도 노출하지 않음",
                guideline: "A screen with no accessible text or controls is unusable with VoiceOver and cannot be tested.",
                higPath: "accessibility", platforms: all4, defaultSeverity: .warning),
    ]

    public static func rule(_ id: String) -> HIGRule? { all.first { $0.id == id } }

    /// Markdown table embedded in prompts so Claude cites the same rule ids and URLs.
    public static func reference(for platform: Platform? = nil) -> String {
        let rules = all.filter { rule in platform.map { rule.platforms.contains($0) } ?? true }
        var lines = [
            "# HIG rules TestBridge checks automatically (`higAudit` step)",
            "Guidelines: \(baseURL)",
            "",
            "| rule id | default severity | platforms | what it checks | HIG page |",
            "|---|---|---|---|---|",
        ]
        for r in rules {
            let plats = Platform.allCases.filter { r.platforms.contains($0) }.map(\.displayName).joined(separator: ", ")
            lines.append("| \(r.id) | \(r.defaultSeverity.rawValue) | \(plats) | \(r.guideline) | \(r.url.absoluteString) |")
        }
        lines.append("")
        lines.append("Anything the tree cannot show (color contrast, Dynamic Type, Dark Mode, motion, wording tone, layout rhythm) is for you to judge from the screenshot, the element list and the HIG.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Captured element

public struct HIGElement: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var parent: Int?
    public var depth: Int
    public var type: ElementKind
    public var identifier: String
    public var label: String
    public var value: String?
    public var placeholder: String?
    public var frame: HIGRect
    public var isEnabled: Bool

    public init(id: Int, parent: Int?, depth: Int, type: ElementKind, identifier: String, label: String,
                value: String? = nil, placeholder: String? = nil, frame: HIGRect, isEnabled: Bool = true) {
        self.id = id
        self.parent = parent
        self.depth = depth
        self.type = type
        self.identifier = identifier
        self.label = label
        self.value = value
        self.placeholder = placeholder
        self.frame = frame
        self.isEnabled = isEnabled
    }

    /// Identity used to drop subtrees XCUITest reports twice (e.g. keyboard/toolbar accessories).
    public var signature: String { "\(type.rawValue)|\(identifier)|\(label)|\(frame)" }

    /// Removes subtrees that XCUITest reports twice (same node *and* same descendants, e.g. a toolbar accessory),
    /// then re-indexes `id`/`parent`. A lone node that merely looks like an earlier one (nested full-screen
    /// containers) is kept because its subtree differs.
    public static func deduplicated(_ elements: [HIGElement]) -> [HIGElement] {
        guard elements.count > 1 else { return elements }
        var position: [Int: Int] = [:]
        for (i, e) in elements.enumerated() { position[e.id] = i }
        var children: [Int: [Int]] = [:]
        for e in elements { if let p = e.parent { children[p, default: []].append(e.id) } }

        var subtreeHash: [Int: Int] = [:]
        var hasContent: [Int: Bool] = [:]
        func compute(_ id: Int) -> (Int, Bool) {
            guard let i = position[id] else { return (0, false) }
            let e = elements[i]
            var hasher = Hasher()
            hasher.combine(e.signature)
            var content = !e.label.isEmpty || !e.identifier.isEmpty || HIGAuditor.interactiveKinds.contains(e.type)
            for c in children[id] ?? [] {
                let (h, hc) = compute(c)
                hasher.combine(h)
                content = content || hc
            }
            let h = hasher.finalize()
            subtreeHash[id] = h
            hasContent[id] = content
            return (h, content)
        }
        for e in elements where e.parent == nil { _ = compute(e.id) }
        for e in elements where subtreeHash[e.id] == nil { _ = compute(e.id) }   // orphans, defensively

        var seen = Set<Int>()
        var dropped = Set<Int>()
        var kept: [HIGElement] = []
        for e in elements {
            if let p = e.parent, dropped.contains(p) { dropped.insert(e.id); continue }
            if e.parent != nil, !e.frame.isEmpty, hasContent[e.id] == true,
               let h = subtreeHash[e.id], !seen.insert(h).inserted {
                dropped.insert(e.id)
                continue
            }
            kept.append(e)
        }
        guard !dropped.isEmpty else { return elements }
        var remap: [Int: Int] = [:]
        for (newIndex, e) in kept.enumerated() { remap[e.id] = newIndex }
        return kept.enumerated().map { newIndex, e in
            var copy = e
            copy.id = newIndex
            copy.parent = e.parent.flatMap { remap[$0] }
            return copy
        }
    }

    /// Short human/LLM-readable description: `button "Sign In" id=login.submit (120×32 @ 20,400)`.
    public var summary: String {
        var s = type.rawValue
        if !label.isEmpty { s += " \"\(label)\"" }
        if !identifier.isEmpty { s += " id=\(identifier)" }
        if let value, !value.isEmpty, value != label { s += " value=\"\(value)\"" }
        if let placeholder, !placeholder.isEmpty { s += " placeholder=\"\(placeholder)\"" }
        s += " (\(frame))"
        if !isEnabled { s += " disabled" }
        return s
    }
}

// MARK: - Finding

public struct HIGFinding: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var rule: String
    public var severity: HIGSeverity
    public var title: String
    public var message: String
    public var element: Int?
    public var elementSummary: String?
    public var frame: HIGRect?
    public var higURL: String

    public init(id: String = "", rule: String, severity: HIGSeverity, title: String, message: String,
                element: Int? = nil, elementSummary: String? = nil, frame: HIGRect? = nil, higURL: String) {
        self.id = id
        self.rule = rule
        self.severity = severity
        self.title = title
        self.message = message
        self.element = element
        self.elementSummary = elementSummary
        self.frame = frame
        self.higURL = higURL
    }

    public var oneLine: String {
        "[\(severity.rawValue)] \(rule): \(message)\(elementSummary.map { " — \($0)" } ?? "")"
    }
}

// MARK: - Report

public struct HIGAuditReport: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var platform: Platform
    public var bundleIdentifier: String
    public var capturedAt: Date
    public var screenFrame: HIGRect
    public var elements: [HIGElement]
    public var findings: [HIGFinding]

    public var id: String { "\(name)@\(Int(capturedAt.timeIntervalSince1970))" }

    public init(name: String, platform: Platform, bundleIdentifier: String, capturedAt: Date = Date(),
                screenFrame: HIGRect, elements: [HIGElement], findings: [HIGFinding]) {
        self.name = name
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
        self.capturedAt = capturedAt
        self.screenFrame = screenFrame
        self.elements = elements
        self.findings = findings
    }

    public func count(_ severity: HIGSeverity) -> Int { findings.filter { $0.severity == severity }.count }
    public var errorCount: Int { count(.error) }
    public var warningCount: Int { count(.warning) }
    public var infoCount: Int { count(.info) }
    public var worstSeverity: HIGSeverity? { findings.map(\.severity).max() }

    /// True when at least one finding is at or above `threshold`.
    public func violates(_ threshold: HIGSeverity) -> Bool { findings.contains { $0.severity >= threshold } }

    public var countsLine: String {
        "\(errorCount) error\(errorCount == 1 ? "" : "s"), \(warningCount) warning\(warningCount == 1 ? "" : "s"), \(infoCount) info"
    }

    /// Compact text for prompts and the CLI.
    public func summaryText(maxElements: Int = 160) -> String {
        var lines: [String] = []
        lines.append("Screen \"\(name)\" · \(platform.displayName) · \(bundleIdentifier) · window \(screenFrame) · \(elements.count) elements · \(countsLine)")
        if findings.isEmpty {
            lines.append("No automatic findings.")
        } else {
            lines.append("Findings:")
            for f in findings.sorted(by: { $0.severity > $1.severity }) {
                lines.append("- \(f.oneLine) → \(f.higURL)")
            }
        }
        let interesting = elements.filter { $0.type != .other && $0.type != .window && !($0.label.isEmpty && $0.identifier.isEmpty && $0.value == nil) }
        if !interesting.isEmpty {
            lines.append("Elements (type, label, identifier, frame):")
            let baseDepth = interesting.map(\.depth).min() ?? 0
            for e in interesting.prefix(maxElements) {
                lines.append(String(repeating: "  ", count: min(max(0, e.depth - baseDepth), 6)) + "- " + e.summary)
            }
            if interesting.count > maxElements {
                lines.append("  …(\(interesting.count - maxElements) more elements omitted)")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func decode(_ data: Data) throws -> HIGAuditReport {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(HIGAuditReport.self, from: data)
    }

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(self)
    }
}
