import Foundation

/// What the user wants from Claude Code.
public enum AssistMode: String, CaseIterable, Codable, Sendable {
    /// "How should I ask this tool to test X?" — Claude explains the approach and may ask questions.
    case explain
    /// Produce a runnable plan JSON (or clarifying questions if it cannot).
    case plan
    /// Given a failed run report, propose a fixed plan or diagnose the app.
    case diagnose
    /// Given a HIG audit (automatic findings + element list), judge HIG compliance and propose fixes.
    case hig

    public var title: String {
        switch self {
        case .explain: return "Ask how to test"
        case .plan: return "Generate a plan"
        case .diagnose: return "Diagnose a failed run"
        case .hig: return "Review HIG compliance"
        }
    }
}

/// Everything PromptBuilder needs to ground the prompt in reality.
public struct PromptContext: Sendable {
    public var mode: AssistMode
    public var goal: String
    public var platform: Platform
    public var bundleIdentifier: String
    public var devices: [DeviceTarget]
    public var selectedDevice: DeviceTarget?
    public var accessibilityTree: String?
    public var extraContext: String
    /// Answers to earlier clarifying questions, keyed by question id.
    public var answers: [String: String]
    public var previousPlan: TestPlan?
    public var failedReport: RunReport?
    /// Latest automatic HIG audit(s) to review — one per screen.
    public var higReports: [HIGAuditReport]

    public init(mode: AssistMode, goal: String, platform: Platform, bundleIdentifier: String,
                devices: [DeviceTarget] = [], selectedDevice: DeviceTarget? = nil,
                accessibilityTree: String? = nil, extraContext: String = "",
                answers: [String: String] = [:], previousPlan: TestPlan? = nil, failedReport: RunReport? = nil,
                higReports: [HIGAuditReport] = []) {
        self.mode = mode
        self.goal = goal
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
        self.devices = devices
        self.selectedDevice = selectedDevice
        self.accessibilityTree = accessibilityTree
        self.extraContext = extraContext
        self.answers = answers
        self.previousPlan = previousPlan
        self.failedReport = failedReport
        self.higReports = higReports
    }
}

public enum PromptBuilder {
    /// Maximum characters of accessibility tree to inline. Trees for big screens can be enormous.
    public static let treeCharacterLimit = 24_000

    public static func build(_ ctx: PromptContext) -> String {
        var sections: [String] = []

        sections.append("""
        You are helping drive **TestBridge**, a tool that checks whether an iOS, iPadOS, watchOS or macOS app violates \
        Apple's Human Interface Guidelines (HIG, \(HIGRules.baseURL)). TestBridge drives the app through XCUITest with \
        declarative JSON plans: it navigates to screens, snapshots every on-screen element (type, label, identifier, \
        frame, enabled state) and runs an automatic HIG rule set on each snapshot (`higAudit` step). You then review the \
        findings against the HIG and judge what the rules cannot measure. TestBridge cannot read the app's source code; it \
        only sees what XCUITest exposes. The developer can run `testbridge` from a terminal (same machine as this Xcode \
        install) if you need to discover things yourself.
        """)

        sections.append(PlanSchema.reference)
        sections.append(HIGRules.reference(for: ctx.platform))

        var context = """
        # Current context
        - Target platform: \(ctx.platform.displayName)
        - App bundle identifier: \(ctx.bundleIdentifier.isEmpty ? "(unknown — ask for it)" : ctx.bundleIdentifier)
        """
        if let dev = ctx.selectedDevice {
            context += "\n- Selected device: \(dev.name) (\(dev.runtime), udid: \(dev.udid.isEmpty ? "host" : dev.udid))"
        }
        let sameplatform = ctx.devices.filter { $0.platform == ctx.platform }
        if !sameplatform.isEmpty {
            let list = sameplatform.prefix(8).map { "  - \($0.name) · \($0.runtime) · \($0.state)\($0.udid.isEmpty ? "" : " · \($0.udid)")" }
            context += "\n- Available \(ctx.platform.displayName) destinations:\n" + list.joined(separator: "\n")
        }
        sections.append(context)

        if let tree = ctx.accessibilityTree, !tree.isEmpty {
            let clipped = tree.count > treeCharacterLimit
                ? String(tree.prefix(treeCharacterLimit)) + "\n…(truncated, \(tree.count - treeCharacterLimit) more characters)"
                : tree
            sections.append("""
            # Accessibility tree captured from the running app (first screen after launch)
            Use the identifiers/labels below. Do not invent identifiers that are not in this tree unless you also add a `dumpTree` step to verify.
            ```
            \(clipped)
            ```
            """)
        } else {
            sections.append("""
            # Accessibility tree
            Not captured yet. If you need it, either ask the developer to press "Capture snapshot" in TestBridge, \
            or run `testbridge snapshot --bundle-id <id> --platform \(ctx.platform.rawValue)`.
            """)
        }

        if !ctx.extraContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("# Additional notes from the developer\n\(ctx.extraContext)")
        }

        if !ctx.answers.isEmpty {
            let lines = ctx.answers.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }
            sections.append("# Answers to your earlier questions\n" + lines.joined(separator: "\n"))
        }

        if let prev = ctx.previousPlan {
            sections.append("# Previous plan\n```json\n\(prev.encodedString())\n```")
        }

        if !ctx.higReports.isEmpty {
            var block = "# Automatic HIG audit results (\(ctx.higReports.count) screen\(ctx.higReports.count == 1 ? "" : "s"))"
            var budget = treeCharacterLimit
            for report in ctx.higReports {
                let text = report.summaryText(maxElements: 120)
                let clipped = text.count > budget ? String(text.prefix(max(budget, 400))) + "\n…(truncated)" : text
                budget = max(0, budget - clipped.count)
                block += "\n\n" + clipped
            }
            sections.append(block)
        }

        if let report = ctx.failedReport {
            let stepLines = report.steps.map { "\($0.index + 1). [\($0.status.rawValue)] \($0.summary)\($0.message.map { " — \($0)" } ?? "")" }
            var block = "# Last run report (\(report.passed ? "passed" : "FAILED"))\n" + stepLines.joined(separator: "\n")
            if let failureTree = report.trees.first(where: { $0.key.hasPrefix("failure") })?.value {
                let clipped = String(failureTree.prefix(treeCharacterLimit / 2))
                block += "\n\nAccessibility tree at the moment of failure:\n```\n\(clipped)\n```"
            }
            sections.append(block)
        }

        sections.append("# The developer's goal\n\(ctx.goal.isEmpty ? "(not stated — ask)" : ctx.goal)")

        sections.append(responseProtocol(for: ctx.mode))
        return sections.joined(separator: "\n\n")
    }

    /// Tells Claude exactly how to reply so the app can parse it.
    static func responseProtocol(for mode: AssistMode) -> String {
        let envelope = """
        # How to respond
        Reply with exactly ONE JSON object and nothing else (no prose before or after, no markdown fences). Choose one shape:

        1. When you have enough information to write a plan:
        {"kind":"plan","plan":{ ...TestBridge plan... },"notes":"1–3 sentences: what this verifies and any caveats"}

        2. When you need information only the developer has (credentials, which screen, identifiers, test data):
        {"kind":"questions","questions":[{"id":"short_key","question":"...","why":"one line","example":"optional sample answer"}]}
        Ask at most 4 questions, only ones that change the plan. Never ask for things you can discover with a dumpTree step.

        3. When the request cannot be met by TestBridge at all:
        {"kind":"unsupported","reason":"...","alternative":"what the developer should do instead"}
        """

        switch mode {
        case .plan, .diagnose:
            return envelope + """


            When the developer's goal is about HIG compliance, the plan should navigate to each screen and run \
            `{"action":"higAudit","name":"<screen>","failOn":"error"}` on it (one distinct name per screen), with a `screenshot` next to it.
            """
        case .hig:
            return """
            # How to respond
            Judge whether this app violates the Human Interface Guidelines. Use the automatic findings as evidence, then add what \
            only a reader of the HIG can see in the element list and screenshot: navigation structure, control choice, wording, \
            hierarchy, platform conventions. Cite the HIG page for every finding (Korean site: \(HIGRules.baseURL)<page>). \
            Reply with exactly ONE JSON object and nothing else:
            {"kind":"higReview","verdict":"pass" | "needs-work" | "fail","summary":"2–4 sentences on overall HIG compliance","findings":[{"rule":"<rule id from the table, or 'custom'>","severity":"error" | "warning" | "info","element":"how to find it: identifier, label or type","issue":"what violates which guidance","hig":"<HIG URL>","fix":"the concrete change to make"}],"nextPlan":{ ...optional TestBridge plan that navigates to screens not yet audited and runs higAudit on each... }}
            Drop automatic findings you consider false positives and say why in `summary`. Order findings by severity. \
            If you still need information only the developer has, reply instead with:
            {"kind":"questions","questions":[{"id":"short_key","question":"...","why":"one line","example":"optional sample answer"}]}
            """
        case .explain:
            return """
            # How to respond
            The developer is asking *how* to check this app against the HIG with TestBridge, not for a finished plan yet. Reply with exactly ONE JSON object:
            {"kind":"explanation","approach":"3–8 short paragraphs or bullets: which screens to audit and in what order, which HIG areas matter most for this kind of app, which identifiers the app should expose so screens can be reached, what cannot be checked this way","suggestedPrompt":"a single paragraph the developer can paste back into TestBridge in 'Generate a plan' mode to get the first audit plan","questions":[{"id":"...","question":"...","why":"...","example":"..."}]}
            `questions` may be empty. No prose outside the JSON.
            """
        }
    }
}
