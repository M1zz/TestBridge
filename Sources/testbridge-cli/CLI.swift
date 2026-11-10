import Foundation
#if canImport(TestBridgeCore)
import TestBridgeCore
#endif

@main
struct TestBridgeCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else { printUsage(); exit(2) }
        args.removeFirst()
        let opts = Options(args)

        do {
            switch command {
            case "devices": try await devices(opts)
            case "schema": schema(opts)
            case "snapshot": try await snapshot(opts)
            case "hig": try await hig(opts)
            case "rules": rules(opts)
            case "run": try await run(opts)
            case "prompt": try await prompt(opts)
            case "import": try importPlan(opts)
            case "claude-md": claudeMD(opts)
            case "doctor": await doctor()
            case "validate": try validate(opts)
            case "help", "--help", "-h": printUsage()
            default:
                fail("Unknown command '\(command)'.")
                printUsage()
                exit(2)
            }
        } catch {
            fail(String(describing: error))
            exit(1)
        }
    }

    // MARK: Commands

    static func devices(_ o: Options) async throws {
        let devices = try await SimctlService.listDevices()
        if o.json {
            printJSON(devices)
        } else {
            for d in devices {
                print("\(d.platform.displayName.padding(toLength: 8, withPad: " ", startingAt: 0)) \(d.name) · \(d.runtime) · \(d.state)\(d.udid.isEmpty ? "" : " · \(d.udid)")")
            }
        }
    }

    static func schema(_ o: Options) {
        print(PlanSchema.reference)
        print()
        print(HIGRules.reference())
        print("\n## Example\n```json\n\(PlanSchema.example)\n```")
    }

    static func rules(_ o: Options) {
        let platform = try? o.platform(default: .iOS)
        if o.json {
            let rows = HIGRules.all.filter { rule in platform.map { rule.platforms.contains($0) } ?? true }.map { r -> [String: Any] in
                ["id": r.id, "title": r.title, "titleKo": r.titleKo, "severity": r.defaultSeverity.rawValue,
                 "guideline": r.guideline, "hig": r.url.absoluteString,
                 "platforms": Platform.allCases.filter { r.platforms.contains($0) }.map(\.rawValue)]
            }
            if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
               let s = String(data: data, encoding: .utf8) { print(s) }
        } else {
            print(HIGRules.reference(for: o.value("--platform") == nil ? nil : platform))
        }
    }

    /// Launch the app and audit its first screen against the HIG rules.
    static func hig(_ o: Options) async throws {
        guard let bundleId = o.value("--bundle-id") else { throw usage("hig requires --bundle-id") }
        let platform = try o.platform(default: .iOS)
        let destination = o.destination(for: platform)
        let failOn: HIGSeverity? = {
            switch (o.value("--fail-on") ?? "error").lowercased() {
            case "none", "never": return nil
            case let raw: return HIGSeverity(rawValue: raw) ?? .error
            }
        }()
        let (audit, _, outcome) = try await XcodebuildService.auditFirstScreen(
            platform: platform, bundleIdentifier: bundleId, destination: destination, failOn: nil,
            runnerProject: o.runnerProject(), log: stderrLogger(o.verbose))
        let violates = failOn.map { audit.violates($0) } ?? false
        if o.json {
            var dict: [String: Any] = [
                "bundleIdentifier": bundleId, "platform": platform.rawValue,
                "outputDirectory": outcome.outputDirectory,
                "violates": violates,
                "hig": HIGRules.baseURL,
            ]
            if let data = try? audit.encoded(), let obj = try? JSONSerialization.jsonObject(with: data) { dict["audit"] = obj }
            printJSONObject(dict)
        } else {
            print(audit.summaryText(maxElements: o.verbose ? 400 : 60))
            print("\nArtifacts: \(outcome.outputDirectory)")
            print(violates ? "\nRESULT: HIG violations at or above '\(failOn!.rawValue)'." : "\nRESULT: no findings at or above the fail threshold.")
        }
        exit(violates ? 1 : 0)
    }

    static func snapshot(_ o: Options) async throws {
        guard let bundleId = o.value("--bundle-id") else { throw usage("snapshot requires --bundle-id") }
        let platform = try o.platform(default: .iOS)
        let destination = o.destination(for: platform)
        let runner = o.runnerProject()
        let (tree, outcome) = try await XcodebuildService.captureSnapshot(
            platform: platform, bundleIdentifier: bundleId, destination: destination, runnerProject: runner,
            log: stderrLogger(o.verbose))
        if o.json {
            printJSONObject(["bundleIdentifier": bundleId, "platform": platform.rawValue,
                             "outputDirectory": outcome.outputDirectory, "tree": tree])
        } else {
            print(tree)
        }
    }

    static func run(_ o: Options) async throws {
        guard let path = o.positional.first else { throw usage("run requires a plan file path") }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        var plan: TestPlan
        switch ClaudeCLI.parse(String(decoding: data, as: UTF8.self)) {
        case .plan(let p, _): plan = p
        default: throw usage("\(path) is not a TestBridge plan")
        }
        if let bid = o.value("--bundle-id") { plan.bundleIdentifier = bid }
        if let p = o.value("--platform") {
            guard let platform = Platform(rawValue: p.lowercased()) else { throw usage("Unknown platform \(p)") }
            plan.platform = platform
        }
        let issues = plan.validate()
        if !issues.isEmpty && !o.json {
            for i in issues { FileHandle.standardError.write(Data("warning: \(i)\n".utf8)) }
        }
        let destination = o.destination(for: plan.platform)
        let outcome = try await XcodebuildService.run(
            plan: plan, destination: destination, runnerProject: o.runnerProject(),
            log: stderrLogger(o.verbose))

        if o.json {
            printJSON(outcome)
        } else {
            print("Plan: \(outcome.planName)  →  \(outcome.passed ? "PASSED" : "FAILED") (xcodebuild exit \(outcome.exitCode))")
            if let report = outcome.report {
                for s in report.steps {
                    let mark = s.status == .passed ? "✓" : (s.status == .failed ? "✗" : "–")
                    print("  \(mark) \(s.index + 1). \(s.summary)\(s.message.map { "\n       \($0)" } ?? "")")
                }
                for audit in report.higAudits {
                    print("\nHIG audit \"\(audit.name)\": \(audit.countsLine)")
                    for f in audit.findings.sorted(by: { $0.severity > $1.severity }) {
                        print("  - \(f.oneLine)\n    \(f.higURL)")
                    }
                }
            } else {
                print("No report produced. xcodebuild tail:\n\(outcome.logTail)")
            }
            print("Artifacts: \(outcome.outputDirectory)")
        }
        exit(outcome.passed ? 0 : 1)
    }

    static func prompt(_ o: Options) async throws {
        let goal = o.value("--goal") ?? ""
        let platform = try o.platform(default: .iOS)
        let bundleId = o.value("--bundle-id") ?? ""
        let modeRaw = o.value("--mode") ?? "hig"
        guard let mode = AssistMode(rawValue: modeRaw) else { throw usage("--mode must be hig | explain | plan | diagnose") }
        var tree: String? = nil
        if let snapshotPath = o.value("--snapshot") {
            tree = try String(contentsOfFile: snapshotPath, encoding: .utf8)
        }
        var audits: [HIGAuditReport] = []
        if let auditPath = o.value("--hig-report") {
            let data = try Data(contentsOf: URL(fileURLWithPath: auditPath))
            if let one = try? HIGAuditReport.decode(data) {
                audits = [one]
            } else if let run = try? RunReport.decode(data) {
                audits = run.higAudits
            } else {
                throw usage("\(auditPath) is neither a hig-<screen>.json nor a report.json")
            }
        }
        let devices = (try? await SimctlService.listDevices()) ?? []
        let ctx = PromptContext(mode: mode, goal: goal, platform: platform, bundleIdentifier: bundleId,
                                devices: devices, accessibilityTree: tree, extraContext: o.value("--notes") ?? "",
                                higReports: audits)
        print(PromptBuilder.build(ctx))
    }

    static func importPlan(_ o: Options) throws {
        guard let path = o.positional.first else { throw usage("import requires a plan file path") }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard case .plan(let plan, _) = ClaudeCLI.parse(String(decoding: data, as: UTF8.self)) else {
            throw usage("\(path) is not a TestBridge plan")
        }
        let url = try PlanInbox.deposit(plan)
        print("Imported → \(url.path)\nThe TestBridge app will pick it up if it is running.")
    }

    static func claudeMD(_ o: Options) {
        print(ClaudeMDSnippet.render(bundleIdentifier: o.value("--bundle-id"),
                                     platform: o.value("--platform").flatMap { Platform(rawValue: $0.lowercased()) }))
    }

    static func validate(_ o: Options) throws {
        guard let path = o.positional.first else { throw usage("validate requires a plan file path") }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let plan = try TestPlan.decode(data)
        let issues = plan.validate()
        if o.json {
            printJSONObject(["valid": issues.isEmpty, "issues": issues])
        } else if issues.isEmpty {
            print("OK — \(plan.steps.count) steps, platform \(plan.platform.displayName), app \(plan.bundleIdentifier)")
        } else {
            issues.forEach { print("warning: \($0)") }
        }
    }

    static func doctor() async {
        func check(_ label: String, _ ok: Bool, _ detail: String) {
            print("\(ok ? "✓" : "✗") \(label): \(detail)")
        }
        let xcodebuild = (try? await ShellRunner.run("/usr/bin/xcrun", ["xcodebuild", "-version"]))
        check("xcodebuild", xcodebuild?.succeeded == true,
              xcodebuild?.stdout.split(separator: "\n").first.map(String.init) ?? "not found")
        let xcodegen = await ShellRunner.which("xcodegen")
        check("xcodegen", xcodegen != nil, xcodegen ?? "not installed (brew install xcodegen) — needed once to generate the Runner project")
        let claude = await ClaudeCLI.locate()
        check("claude CLI", claude != nil, claude ?? "not found — prompts can still be copied manually")
        let runner = Paths.defaultRunnerProject()
        check("Runner project", FileManager.default.fileExists(atPath: runner.path), runner.path)
        let devices = (try? await SimctlService.listDevices()) ?? []
        let booted = devices.filter { $0.isBooted && !$0.isHostMac }
        check("simulators", !devices.isEmpty, "\(devices.count - 1) available, \(booted.count) booted")
        print("Inbox: \(Paths.inbox.path)\nRuns:  \(Paths.runs.path)")
    }

    // MARK: Helpers

    static func printUsage() {
        print("""
        testbridge — check Apple apps against the Human Interface Guidelines from the terminal (built for Claude Code)

        USAGE
          testbridge hig --bundle-id <id> [--platform ios|ipados|watchos|macos] [--destination <udid>] [--fail-on error|warning|info|none] [--json] [-v]
                                                  # launch the app, audit the first screen, exit 1 on violations
          testbridge rules [--platform <p>] [--json]   # the HIG rule catalog with links
          testbridge devices [--json]
          testbridge schema
          testbridge snapshot --bundle-id <id> [--platform <p>] [--destination <udid>] [--json] [-v]
          testbridge run <plan.json> [--destination <udid>] [--bundle-id <id>] [--platform <p>] [--json] [-v]
                                                  # plans with higAudit steps audit deeper screens
          testbridge validate <plan.json> [--json]
          testbridge prompt --goal "<question>" [--mode hig|explain|plan|diagnose] [--bundle-id <id>] [--platform <p>] [--hig-report <hig-screen.json|report.json>] [--snapshot <tree.txt>] [--notes "<text>"]
          testbridge import <plan.json>          # hand a plan to the GUI
          testbridge claude-md [--bundle-id <id>] [--platform <p>]   # snippet for your CLAUDE.md
          testbridge doctor

        ENV
          TESTBRIDGE_RUNNER_PROJECT   path to Runner/TestBridgeRunner.xcodeproj (also settable in the app)
        """)
    }

    static func stderrLogger(_ enabled: Bool) -> (@Sendable (String) -> Void)? {
        guard enabled else { return nil }
        return { FileHandle.standardError.write(Data($0.utf8)) }
    }

    static func fail(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }

    static func usage(_ message: String) -> ShellError { ShellError(description: message) }

    static func printJSON<T: Encodable>(_ value: T) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(value), let s = String(data: data, encoding: .utf8) { print(s) }
    }

    static func printJSONObject(_ dict: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) { print(s) }
    }
}

struct Options {
    var flags: [String: String] = [:]
    var switches: Set<String> = []
    var positional: [String] = []

    static let booleanSwitches: Set<String> = ["--json", "-v", "--verbose", "-h", "--help"]

    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let a = args[i]
            if Options.booleanSwitches.contains(a) {
                switches.insert(a)
                i += 1
            } else if a.hasPrefix("--"), i + 1 < args.count, !args[i + 1].hasPrefix("-") {
                flags[a] = args[i + 1]
                i += 2
            } else if a.hasPrefix("-") {
                switches.insert(a)
                i += 1
            } else {
                positional.append(a)
                i += 1
            }
        }
    }

    var json: Bool { switches.contains("--json") }
    var verbose: Bool { switches.contains("-v") || switches.contains("--verbose") }
    func value(_ key: String) -> String? { flags[key] }

    func platform(default d: Platform) throws -> Platform {
        guard let raw = value("--platform") else { return d }
        guard let p = Platform(rawValue: raw.lowercased()) else {
            throw ShellError(description: "Unknown platform '\(raw)'. Use ios | ipados | watchos | macos")
        }
        return p
    }

    func destination(for platform: Platform) -> Destination? {
        if platform == .macOS { return .thisMac }
        guard let udid = value("--destination") else { return nil }
        return Destination(udid: udid)
    }

    func runnerProject() -> URL {
        if let p = value("--runner") { return URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
        return Paths.defaultRunnerProject()
    }
}
