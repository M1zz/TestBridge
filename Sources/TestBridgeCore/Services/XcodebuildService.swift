import Foundation

/// Where TestBridge keeps its state on disk.
public enum Paths {
    public static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("TestBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    public static var plans: URL { subdir("Plans") }
    public static var runs: URL { subdir("Runs") }
    public static var inbox: URL { subdir("Inbox") }
    public static var derivedData: URL { subdir("DerivedData") }
    public static var snapshots: URL { subdir("Snapshots") }
    /// The developer's own apps (`AppPreset`). Optional; the target picker hides its menu when the file is missing.
    public static var apps: URL { appSupport.appendingPathComponent("Apps.json") }

    private static func subdir(_ name: String) -> URL {
        let dir = appSupport.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Default Runner project location: `<repo>/Runner/TestBridgeRunner.xcodeproj`, overridable via settings/env.
    public static func defaultRunnerProject() -> URL {
        if let env = ProcessInfo.processInfo.environment["TESTBRIDGE_RUNNER_PROJECT"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        if let stored = UserDefaults.standard.string(forKey: "runnerProjectPath"), !stored.isEmpty {
            return URL(fileURLWithPath: (stored as NSString).expandingTildeInPath)
        }
        return appSupport.appendingPathComponent("Runner/TestBridgeRunner.xcodeproj")
    }
}

public struct RunOutcome: Codable, Sendable {
    public var planName: String
    public var exitCode: Int32
    public var report: RunReport?
    public var outputDirectory: String
    public var xcresultPath: String
    public var logTail: String

    public var passed: Bool { report?.passed ?? (exitCode == 0) }
}

public enum XcodebuildService {
    /// Runs a plan through the Runner project. `log` receives raw xcodebuild output as it streams.
    public static func run(plan: TestPlan,
                           destination: Destination?,
                           runnerProject: URL = Paths.defaultRunnerProject(),
                           outputDirectory: URL? = nil,
                           log: (@Sendable (String) -> Void)? = nil) async throws -> RunOutcome {
        guard FileManager.default.fileExists(atPath: runnerProject.path) else {
            throw ShellError(description: """
            Runner project not found at \(runnerProject.path).
            Run `xcodegen generate` inside the Runner folder, then point TestBridge at the generated .xcodeproj (Settings → Runner project).
            """)
        }

        let dest = destination ?? plan.destination ?? (plan.platform == .macOS ? .thisMac : Destination())
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safeName = plan.name.replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
        let outDir = outputDirectory ?? Paths.runs.appendingPathComponent("\(stamp)_\(safeName)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let xcresult = outDir.appendingPathComponent("result.xcresult")

        if dest.udid != nil, plan.platform.needsSimulator, let udid = dest.udid {
            try? await SimctlService.boot(udid: udid)
        }

        try plan.encoded().write(to: outDir.appendingPathComponent("plan.json"))
        let planB64 = try plan.encoded().base64EncodedString()

        var args: [String] = [
            "xcodebuild", "test",
            "-project", runnerProject.path,
            "-scheme", plan.platform.runnerScheme,
            "-destination", dest.xcodebuildArgument(for: plan.platform),
            "-resultBundlePath", xcresult.path,
            "-derivedDataPath", Paths.derivedData.path,
            "-only-testing:\(plan.platform.runnerScheme)/PlanRunnerTests",
            "-parallel-testing-enabled", "NO",
        ]
        if plan.platform.needsSimulator {
            args += ["CODE_SIGNING_ALLOWED=NO"]
        } else {
            args += ["CODE_SIGN_IDENTITY=-"]
        }

        let env = [
            "TEST_RUNNER_TESTBRIDGE_PLAN_B64": planB64,
            "TEST_RUNNER_TESTBRIDGE_OUTPUT_DIR": outDir.path,
        ]

        log?("$ " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ") + "\n")
        let result = try await ShellRunner.run("/usr/bin/xcrun", args, environment: env, onOutput: log)
        try? result.combinedOutput.write(to: outDir.appendingPathComponent("xcodebuild.log"), atomically: true, encoding: .utf8)

        var report = try? RunReport.decode(Data(contentsOf: outDir.appendingPathComponent("report.json")))
        if report == nil {
            report = await XCResultParser.extractReport(from: xcresult, into: outDir)
        }

        let tail = result.combinedOutput.split(separator: "\n").suffix(40).joined(separator: "\n")
        return RunOutcome(planName: plan.name, exitCode: result.exitCode, report: report,
                          outputDirectory: outDir.path, xcresultPath: xcresult.path, logTail: tail)
    }

    /// Launches the app, waits, dumps the accessibility tree. Returns the tree text.
    public static func captureSnapshot(platform: Platform,
                                       bundleIdentifier: String,
                                       destination: Destination?,
                                       runnerProject: URL = Paths.defaultRunnerProject(),
                                       log: (@Sendable (String) -> Void)? = nil) async throws -> (tree: String, outcome: RunOutcome) {
        let plan = TestPlan.snapshotPlan(platform: platform, bundleIdentifier: bundleIdentifier, destination: destination)
        let outcome = try await run(plan: plan, destination: destination, runnerProject: runnerProject, log: log)
        if let tree = outcome.report?.trees["snapshot"] {
            let file = Paths.snapshots.appendingPathComponent("\(bundleIdentifier)-\(platform.rawValue).txt")
            try? tree.write(to: file, atomically: true, encoding: .utf8)
            return (tree, outcome)
        }
        throw ShellError(description: "Snapshot run finished (exit \(outcome.exitCode)) but produced no tree.\n\(outcome.logTail)")
    }

    /// Launches the app and audits its first screen against the HIG rules. Also stores the accessibility tree snapshot.
    public static func auditFirstScreen(platform: Platform,
                                        bundleIdentifier: String,
                                        destination: Destination?,
                                        failOn: HIGSeverity? = nil,
                                        runnerProject: URL = Paths.defaultRunnerProject(),
                                        log: (@Sendable (String) -> Void)? = nil) async throws -> (audit: HIGAuditReport, tree: String?, outcome: RunOutcome) {
        let plan = TestPlan.higAuditPlan(platform: platform, bundleIdentifier: bundleIdentifier, destination: destination, failOn: failOn)
        let outcome = try await run(plan: plan, destination: destination, runnerProject: runnerProject, log: log)
        let tree = outcome.report?.trees["snapshot"]
        if let tree {
            let file = Paths.snapshots.appendingPathComponent("\(bundleIdentifier)-\(platform.rawValue).txt")
            try? tree.write(to: file, atomically: true, encoding: .utf8)
        }
        guard let audit = outcome.report?.higAudits.first else {
            throw ShellError(description: "HIG audit run finished (exit \(outcome.exitCode)) but produced no audit report.\n\(outcome.logTail)")
        }
        return (audit, tree, outcome)
    }
}

/// Fallback for when the Runner could not write to the host filesystem (e.g. physical devices):
/// pull the report attachment out of the .xcresult bundle.
public enum XCResultParser {
    public static func extractReport(from xcresult: URL, into outDir: URL) async -> RunReport? {
        let attachmentsDir = outDir.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        guard let result = try? await ShellRunner.run("/usr/bin/xcrun", [
            "xcresulttool", "export", "attachments",
            "--path", xcresult.path,
            "--output-path", attachmentsDir.path,
        ]), result.succeeded else { return nil }

        guard let files = try? FileManager.default.contentsOfDirectory(at: attachmentsDir, includingPropertiesForKeys: nil) else {
            return nil
        }
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let report = try? RunReport.decode(data) {
                return report
            }
        }
        return nil
    }
}
