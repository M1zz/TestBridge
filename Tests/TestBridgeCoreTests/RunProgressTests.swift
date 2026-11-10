import XCTest
#if canImport(TestBridgeCore)
@testable import TestBridgeCore
#endif

final class RunProgressTests: XCTestCase {
    func testLatestStepLineWins() {
        let log = "t = 1.0s Tap\nTESTBRIDGE-STEP 1/18 wait 3.0s\nnoise\nTESTBRIDGE-STEP 7/18 tap button \"사용 기록\"\nt = 9.0s Find\n"
        XCTAssertEqual(RunProgress.latest(in: log), RunProgress(step: 7, total: 18, summary: "tap button \"사용 기록\""))
        XCTAssertEqual(RunProgress.latest(in: log)?.fraction ?? 0, 6.0 / 18.0, accuracy: 0.0001)
    }

    func testNoStepLineYet() {
        XCTAssertNil(RunProgress.latest(in: "Build succeeded\nTESTBRIDGE-STEP x/y broken\n"))
    }
}
