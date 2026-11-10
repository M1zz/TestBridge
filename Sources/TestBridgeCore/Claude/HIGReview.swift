import Foundation

/// Claude's judgement on a HIG audit: the automatic findings plus everything only a reader of the HIG can see.
public struct HIGReviewFinding: Codable, Hashable, Identifiable, Sendable {
    public var rule: String
    public var severity: HIGSeverity
    public var element: String?
    public var issue: String
    public var hig: String?
    public var fix: String?

    public var id: String { "\(rule)|\(element ?? "")|\(issue.prefix(40))" }

    public init(rule: String, severity: HIGSeverity, element: String? = nil, issue: String, hig: String? = nil, fix: String? = nil) {
        self.rule = rule
        self.severity = severity
        self.element = element
        self.issue = issue
        self.hig = hig
        self.fix = fix
    }

    private enum CodingKeys: String, CodingKey { case rule, severity, element, issue, hig, fix }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rule = try c.decodeIfPresent(String.self, forKey: .rule) ?? "custom"
        let sev = try c.decodeIfPresent(String.self, forKey: .severity) ?? "warning"
        severity = HIGSeverity(rawValue: sev.lowercased()) ?? .warning
        element = try c.decodeIfPresent(String.self, forKey: .element)
        issue = try c.decodeIfPresent(String.self, forKey: .issue) ?? ""
        hig = try c.decodeIfPresent(String.self, forKey: .hig)
        fix = try c.decodeIfPresent(String.self, forKey: .fix)
    }
}

public struct HIGReview: Codable, Hashable, Sendable {
    public enum Verdict: String, Codable, Sendable {
        case pass, needsWork = "needs-work", fail
    }

    public var verdict: Verdict
    public var summary: String
    public var findings: [HIGReviewFinding]
    /// A plan that visits screens not yet audited and runs `higAudit` on each.
    public var nextPlan: TestPlan?

    public init(verdict: Verdict, summary: String, findings: [HIGReviewFinding], nextPlan: TestPlan? = nil) {
        self.verdict = verdict
        self.summary = summary
        self.findings = findings
        self.nextPlan = nextPlan
    }
}
