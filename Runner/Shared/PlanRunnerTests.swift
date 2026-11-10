import XCTest

/// Entry point invoked by `xcodebuild test`. The plan arrives base64-encoded through the
/// `TEST_RUNNER_TESTBRIDGE_PLAN_B64` environment variable (xcodebuild strips the `TEST_RUNNER_` prefix).
final class PlanRunnerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testRunPlan() throws {
        let env = ProcessInfo.processInfo.environment
        guard let b64 = env["TESTBRIDGE_PLAN_B64"], let data = Data(base64Encoded: b64) else {
            XCTFail("TESTBRIDGE_PLAN_B64 is missing. Run through the TestBridge app or `testbridge run`.")
            return
        }

        let plan = try TestPlan.decode(data)
        let outputDirectory = env["TESTBRIDGE_OUTPUT_DIR"].map { URL(fileURLWithPath: $0) }

        let interpreter = PlanInterpreter(plan: plan, testCase: self, outputDirectory: outputDirectory)
        let report = interpreter.run()

        let reportData = try report.encoded()
        let attachment = XCTAttachment(data: reportData, uniformTypeIdentifier: "public.json")
        attachment.name = "testbridge-report.json"
        attachment.lifetime = .keepAlways
        add(attachment)

        if let outputDirectory {
            try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try? reportData.write(to: outputDirectory.appendingPathComponent("report.json"))
        }

        // Deliberately no XCTFail here: pass/fail is read from report.json by the app and the CLI.
        // A failing XCTest makes xcodebuild "collect diagnostics from simulator", which stalls for
        // 600 s on Xcode 27 and would make every HIG violation cost ten minutes.
        if !report.passed {
            print("TESTBRIDGE: plan failed — \(report.failureSummary)")
        }
    }
}
