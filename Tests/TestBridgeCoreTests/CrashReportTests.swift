import XCTest
#if canImport(TestBridgeCore)
@testable import TestBridgeCore
#endif

final class CrashReportTests: XCTestCase {
    private let plan = try! TestPlan.decode(json: """
    {"name":"p","platform":"ios","bundleIdentifier":"com.x.y","steps":[
      {"action":"wait","seconds":1},{"action":"tap","target":{"label":"Go"}},{"action":"screenshot","name":"a"}]}
    """)

    private func partial(steps: Int) -> RunReport {
        RunReport(planName: "p", platform: .iOS, bundleIdentifier: "com.x.y", startedAt: Date(), finishedAt: Date(),
                  steps: (0..<steps).map { .init(index: $0, action: "wait", summary: "", status: .passed, durationMs: 1) },
                  trees: [:], passed: false)
    }

    func testAbortedRunMarksTheStepItDiedOnAsACrash() {
        let closed = partial(steps: 1).closingAbortedRun(plan: plan, lostApp: true)
        XCTAssertEqual(closed.steps.map(\.status), [.passed, .failed, .skipped])
        XCTAssertEqual(closed.crashedAtStep, 1)
        XCTAssertFalse(closed.passed)
        XCTAssertTrue(closed.failureSummary.hasPrefix("CRASH"))
    }

    func testAbortWithoutLosingTheAppIsNotCalledACrash() {
        let closed = partial(steps: 0).closingAbortedRun(plan: plan, lostApp: false)
        XCTAssertEqual(closed.steps.map(\.status), [.failed, .skipped, .skipped])
        XCTAssertNil(closed.crashedAtStep)
    }

    func testOldReportsWithoutCrashFieldStillDecode() throws {
        var data = try partial(steps: 1).encoded()
        data = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "crashedAtStep", with: "x").data(using: .utf8)!
        XCTAssertNil(try RunReport.decode(data).crashedAtStep)
    }
}
