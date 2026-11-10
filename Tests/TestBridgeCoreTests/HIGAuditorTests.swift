import XCTest
#if canImport(TestBridgeCore)
@testable import TestBridgeCore
#endif

final class HIGAuditorTests: XCTestCase {
    private let screen = HIGRect(x: 0, y: 0, width: 393, height: 852)

    private func el(_ id: Int, _ type: ElementKind, label: String = "", identifier: String = "", parent: Int? = 0,
                    frame: HIGRect, enabled: Bool = true, placeholder: String? = nil) -> HIGElement {
        HIGElement(id: id, parent: parent, depth: parent == nil ? 0 : 1, type: type, identifier: identifier,
                   label: label, placeholder: placeholder, frame: frame, isEnabled: enabled)
    }

    private var window: HIGElement { el(0, .window, label: "Main", parent: nil, frame: screen) }

    private func rules(_ findings: [HIGFinding]) -> Set<String> { Set(findings.map(\.rule)) }

    func testSmallButtonIsAnErrorOnIOSButNotOnMac() {
        let small = el(1, .button, label: "Close", frame: HIGRect(x: 10, y: 10, width: 24, height: 24))
        let ios = HIGAuditor.audit(elements: [window, small], screen: screen, platform: .iOS)
        XCTAssertTrue(ios.contains { $0.rule == "target-size" && $0.severity == .error && $0.element == 1 })

        let mac = HIGAuditor.audit(elements: [window, small], screen: screen, platform: .macOS)
        XCTAssertFalse(mac.contains { $0.rule == "target-size" }, "24pt is above the 20pt macOS pointer threshold")
    }

    func testCompliantButtonProducesNoTargetOrLabelFinding() {
        let ok = el(1, .button, label: "Continue", identifier: "onboarding.continue", frame: HIGRect(x: 20, y: 700, width: 353, height: 50))
        let findings = HIGAuditor.audit(elements: [window, ok], screen: screen, platform: .iOS)
        XCTAssertFalse(rules(findings).contains("target-size"))
        XCTAssertFalse(rules(findings).contains("missing-label"))
    }

    func testMissingLabelAndTextFieldRules() {
        let unlabeled = el(1, .button, identifier: "home.gear", frame: HIGRect(x: 0, y: 0, width: 44, height: 44))
        let field = el(2, .textField, frame: HIGRect(x: 0, y: 100, width: 300, height: 44), placeholder: "Email")
        let bare = el(3, .textField, frame: HIGRect(x: 0, y: 200, width: 300, height: 44))
        let findings = HIGAuditor.audit(elements: [window, unlabeled, field, bare], screen: screen, platform: .iOS)
        XCTAssertTrue(findings.contains { $0.rule == "missing-label" && $0.element == 1 && $0.severity == .error })
        XCTAssertTrue(findings.contains { $0.rule == "text-field-label" && $0.element == 2 && $0.severity == .info })
        XCTAssertTrue(findings.contains { $0.rule == "text-field-label" && $0.element == 3 && $0.severity == .warning })
    }

    func testTabBarItemCountOnlyOnIPhone() {
        var elements = [window, el(1, .tabBar, frame: HIGRect(x: 0, y: 770, width: 393, height: 82))]
        for i in 0..<6 {
            elements.append(el(2 + i, .button, label: "Tab \(i)", parent: 1, frame: HIGRect(x: Double(i) * 65, y: 770, width: 65, height: 49)))
        }
        XCTAssertTrue(rules(HIGAuditor.audit(elements: elements, screen: screen, platform: .iOS)).contains("tab-bar-item-count"))
        XCTAssertFalse(rules(HIGAuditor.audit(elements: elements, screen: screen, platform: .iPadOS)).contains("tab-bar-item-count"))
    }

    func testOverlappingAndNestedControls() {
        let a = el(1, .button, label: "Save", frame: HIGRect(x: 0, y: 0, width: 100, height: 44))
        let b = el(2, .button, label: "Cancel", frame: HIGRect(x: 50, y: 0, width: 100, height: 44))
        let outer = el(3, .button, label: "Card", frame: HIGRect(x: 0, y: 200, width: 393, height: 120))
        let inner = el(4, .button, label: "More", parent: 3, frame: HIGRect(x: 300, y: 240, width: 60, height: 44))
        let findings = HIGAuditor.audit(elements: [window, a, b, outer, inner], screen: screen, platform: .iOS)
        XCTAssertTrue(findings.contains { $0.rule == "overlapping-targets" && $0.element == 1 })
        XCTAssertTrue(findings.contains { $0.rule == "nested-interactive" && $0.element == 4 })
        XCTAssertFalse(findings.contains { $0.rule == "overlapping-targets" && $0.element == 3 }, "parent/child overlap is not a collision")
    }

    func testDuplicateSubtreesAreDroppedAndReindexed() {
        let toolbar1 = el(1, .toolbar, label: "Toolbar", frame: HIGRect(x: 0, y: 800, width: 393, height: 52))
        let mic1 = el(2, .button, label: "Dictate", identifier: "Dictate", parent: 1, frame: HIGRect(x: 342, y: 811, width: 17, height: 22))
        let toolbar2 = el(3, .toolbar, label: "Toolbar", frame: HIGRect(x: 0, y: 800, width: 393, height: 52))
        let mic2 = el(4, .button, label: "Dictate", identifier: "Dictate", parent: 3, frame: HIGRect(x: 342, y: 811, width: 17, height: 22))
        let deduped = HIGElement.deduplicated([window, toolbar1, mic1, toolbar2, mic2])
        XCTAssertEqual(deduped.map(\.id), [0, 1, 2])
        XCTAssertEqual(deduped[2].parent, 1)

        let findings = HIGAuditor.audit(elements: [window, toolbar1, mic1, toolbar2, mic2], screen: screen, platform: .iOS)
        XCTAssertEqual(findings.filter { $0.rule == "target-size" }.count, 1, "the duplicate must not be counted twice")
        XCTAssertFalse(rules(findings).contains("duplicate-label"))
        XCTAssertFalse(rules(findings).contains("overlapping-targets"))
    }

    func testNestedIdenticalContainersAreNotDropped() {
        // Application → Window → Other → Other → Other (all full-screen, unlabeled) → real content.
        let w1 = HIGElement(id: 1, parent: 0, depth: 1, type: .other, identifier: "", label: "", frame: screen)
        let w2 = HIGElement(id: 2, parent: 1, depth: 2, type: .other, identifier: "", label: "", frame: screen)
        let w3 = HIGElement(id: 3, parent: 2, depth: 3, type: .other, identifier: "", label: "", frame: screen)
        let button = el(4, .button, label: "Go", parent: 3, frame: HIGRect(x: 0, y: 0, width: 100, height: 44))
        let text = el(5, .staticText, label: "Hello", parent: 3, frame: HIGRect(x: 0, y: 100, width: 100, height: 20))
        let deduped = HIGElement.deduplicated([window, w1, w2, w3, button, text])
        XCTAssertEqual(deduped.count, 6)
        XCTAssertEqual(deduped.map(\.id), [0, 1, 2, 3, 4, 5])
    }

    func testOverlapIgnoresOtherLayersAndAccessories() {
        let list = el(1, .collectionView, frame: screen)
        let row = el(2, .button, label: "Screen Time", parent: 1, frame: HIGRect(x: 16, y: 799, width: 370, height: 52))
        let search = el(3, .searchField, label: "Search", frame: HIGRect(x: 28, y: 808, width: 346, height: 28))
        let mic = el(4, .button, label: "Dictate", frame: HIGRect(x: 342, y: 811, width: 17, height: 22))
        let findings = HIGAuditor.audit(elements: [window, list, row, search, mic], screen: screen, platform: .iOS)
        XCTAssertFalse(rules(findings).contains("overlapping-targets"))
    }

    func testOffscreenRespectsScrollContainers() {
        let scroll = el(1, .scrollView, frame: screen)
        let inScroll = el(2, .button, label: "Later", parent: 1, frame: HIGRect(x: 0, y: 2000, width: 100, height: 44))
        let loose = el(3, .button, label: "Lost", frame: HIGRect(x: 0, y: 2000, width: 100, height: 44))
        let findings = HIGAuditor.audit(elements: [window, scroll, inScroll, loose], screen: screen, platform: .iOS)
        let offscreen = findings.filter { $0.rule == "offscreen-target" }.compactMap(\.element)
        XCTAssertEqual(offscreen, [3])
    }

    func testIdentifierLikeLabels() {
        XCTAssertTrue(HIGAuditor.looksLikeIdentifier("login.submit"))
        XCTAssertTrue(HIGAuditor.looksLikeIdentifier("btn_save_now"))
        XCTAssertTrue(HIGAuditor.looksLikeIdentifier("signInButton"))
        XCTAssertFalse(HIGAuditor.looksLikeIdentifier("Sign In"))
        XCTAssertFalse(HIGAuditor.looksLikeIdentifier("iPhone"))
        XCTAssertFalse(HIGAuditor.looksLikeIdentifier("macOS"))
        XCTAssertFalse(HIGAuditor.looksLikeIdentifier("v1.2"))
        XCTAssertFalse(HIGAuditor.looksLikeIdentifier("3.5"))
    }

    func testWindowTitleOnMacOnly() {
        let untitled = HIGElement(id: 0, parent: nil, depth: 0, type: .window, identifier: "", label: "", frame: HIGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertTrue(rules(HIGAuditor.audit(elements: [untitled], screen: untitled.frame, platform: .macOS)).contains("window-title"))
        XCTAssertFalse(rules(HIGAuditor.audit(elements: [untitled], screen: untitled.frame, platform: .iOS)).contains("window-title"))
    }

    func testFindingsAreSortedBySeverityAndHaveUniqueIDs() {
        let small = el(1, .button, label: "x", frame: HIGRect(x: 0, y: 0, width: 20, height: 20))
        let tiny = el(2, .staticText, label: "legal", frame: HIGRect(x: 0, y: 100, width: 200, height: 10))
        let findings = HIGAuditor.audit(elements: [window, small, tiny], screen: screen, platform: .iOS)
        XCTAssertEqual(findings.first?.severity, .error)
        XCTAssertEqual(Set(findings.map(\.id)).count, findings.count)
    }
}

final class HIGPlanCodingTests: XCTestCase {
    func testHigAuditStepRoundTrip() throws {
        let json = """
        {"platform":"ios","bundleIdentifier":"com.example.App","steps":[
          {"action":"higAudit","name":"home"},
          {"action":"higAudit","name":"settings","failOn":"none"},
          {"action":"higAudit","name":"paywall","failOn":"warning"}
        ]}
        """
        let plan = try TestPlan.decode(json: json)
        XCTAssertEqual(plan.steps.count, 3)
        guard case .higAudit(let n1, let f1) = plan.steps[0], case .higAudit(_, let f2) = plan.steps[1], case .higAudit(_, let f3) = plan.steps[2] else {
            return XCTFail("steps did not decode as higAudit")
        }
        XCTAssertEqual(n1, "home")
        XCTAssertEqual(f1, .error)
        XCTAssertNil(f2)
        XCTAssertEqual(f3, .warning)

        let reencoded = try TestPlan.decode(try plan.encoded())
        XCTAssertEqual(reencoded.steps, plan.steps)
        XCTAssertTrue(plan.validate().isEmpty, "\(plan.validate())")
    }

    func testDuplicateAuditNamesAreFlagged() throws {
        let plan = TestPlan(name: "dup", platform: .iOS, bundleIdentifier: "com.example.App",
                            steps: [.higAudit(name: "a", failOn: .error), .higAudit(name: "a", failOn: nil)])
        XCTAssertTrue(plan.validate().contains { $0.contains("distinct name") })
    }

    func testRunReportWithoutHigAuditsStillDecodes() throws {
        let json = """
        {"planName":"p","platform":"ios","bundleIdentifier":"b","startedAt":"2026-01-01T00:00:00Z","finishedAt":"2026-01-01T00:00:01Z","steps":[],"trees":{},"passed":true}
        """
        let report = try RunReport.decode(Data(json.utf8))
        XCTAssertTrue(report.higAudits.isEmpty)
    }

    func testHigReviewReplyParses() {
        let text = """
        Here you go:
        ```json
        {"kind":"higReview","verdict":"needs-work","summary":"Mostly fine.","findings":[{"rule":"target-size","severity":"error","element":"button Close","issue":"24pt","hig":"https://developer.apple.com/kr/design/human-interface-guidelines/layout","fix":"Make it 44pt"}]}
        ```
        """
        guard case .higReview(let review) = ClaudeCLI.parse(text) else { return XCTFail("expected higReview") }
        XCTAssertEqual(review.verdict, .needsWork)
        XCTAssertEqual(review.findings.first?.rule, "target-size")
        XCTAssertEqual(review.findings.first?.severity, .error)
    }
}
