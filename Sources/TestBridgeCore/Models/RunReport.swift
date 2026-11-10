import Foundation

/// Produced by the Runner (inside XCUITest) and consumed by the app / CLI.
public struct RunReport: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case passed, failed, skipped
    }

    public struct StepReport: Codable, Hashable, Sendable, Identifiable {
        public var index: Int
        public var action: String
        public var summary: String
        public var status: Status
        public var message: String?
        public var durationMs: Int
        /// File names (relative to the run's output directory) this step produced.
        public var artifacts: [String]

        public var id: Int { index }

        public init(index: Int, action: String, summary: String, status: Status,
                    message: String? = nil, durationMs: Int, artifacts: [String] = []) {
            self.index = index
            self.action = action
            self.summary = summary
            self.status = status
            self.message = message
            self.durationMs = durationMs
            self.artifacts = artifacts
        }
    }

    public var planName: String
    public var platform: Platform
    public var bundleIdentifier: String
    public var startedAt: Date
    public var finishedAt: Date
    public var steps: [StepReport]
    /// Accessibility tree dumps keyed by the `dumpTree` name.
    public var trees: [String: String]
    /// One entry per `higAudit` step, in plan order.
    public var higAudits: [HIGAuditReport]
    public var passed: Bool
    /// Index of the step during which the app stopped running without the plan asking it to (a crash or a kill).
    public var crashedAtStep: Int?

    public var crashed: Bool { crashedAtStep != nil }

    public init(planName: String, platform: Platform, bundleIdentifier: String,
                startedAt: Date, finishedAt: Date, steps: [StepReport],
                trees: [String: String], higAudits: [HIGAuditReport] = [], passed: Bool,
                crashedAtStep: Int? = nil) {
        self.planName = planName
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.steps = steps
        self.trees = trees
        self.higAudits = higAudits
        self.passed = passed
        self.crashedAtStep = crashedAtStep
    }

    private enum CodingKeys: String, CodingKey {
        case planName, platform, bundleIdentifier, startedAt, finishedAt, steps, trees, higAudits, passed, crashedAtStep
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        planName = try c.decode(String.self, forKey: .planName)
        platform = try c.decode(Platform.self, forKey: .platform)
        bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        finishedAt = try c.decode(Date.self, forKey: .finishedAt)
        steps = try c.decode([StepReport].self, forKey: .steps)
        trees = try c.decodeIfPresent([String: String].self, forKey: .trees) ?? [:]
        higAudits = try c.decodeIfPresent([HIGAuditReport].self, forKey: .higAudits) ?? []
        passed = try c.decode(Bool.self, forKey: .passed)
        crashedAtStep = try c.decodeIfPresent(Int.self, forKey: .crashedAtStep)
    }

    public var allHIGFindings: [HIGFinding] { higAudits.flatMap(\.findings) }

    public var failureSummary: String {
        let failures = steps.filter { $0.status == .failed }
        var lines = failures.map { "Step \($0.index + 1) (\($0.action)): \($0.message ?? "failed")" }
        if let crashedAtStep { lines.insert("CRASH: the app stopped running during step \(crashedAtStep + 1).", at: 0) }
        for audit in higAudits where !audit.findings.isEmpty {
            lines.append("HIG audit \"\(audit.name)\": \(audit.countsLine)")
        }
        if lines.isEmpty { return "All \(steps.count) steps passed." }
        return lines.joined(separator: "\n")
    }

    /// The Runner died before finishing (XCUITest aborts the test when the app disappears mid-query). This report
    /// holds the steps that completed; the next one is where it died, and nothing after it ran.
    public func closingAbortedRun(plan: TestPlan, lostApp: Bool) -> RunReport {
        var closed = self
        let died = steps.count
        for (index, step) in plan.steps.enumerated().dropFirst(died) {
            let isDeathStep = index == died
            let message = !isDeathStep ? "Skipped after earlier failure"
                : lostApp ? "The app stopped running during this step (crash or kill)."
                : "The test runner stopped during this step."
            closed.steps.append(.init(index: index, action: step.actionName, summary: step.summary,
                                      status: isDeathStep ? .failed : .skipped, message: message, durationMs: 0))
        }
        closed.passed = false
        if lostApp, closed.crashedAtStep == nil, died < plan.steps.count { closed.crashedAtStep = died }
        return closed
    }

    public static func decode(_ data: Data) throws -> RunReport {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(RunReport.self, from: data)
    }

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(self)
    }
}
