import XCTest

/// Executes a `TestPlan` against a live `XCUIApplication`.
/// Lives inside the UI-test bundle so it can use XCUITest APIs on every Apple platform.
final class PlanInterpreter {
    struct StepError: Error, CustomStringConvertible {
        let description: String
    }

    let plan: TestPlan
    unowned let testCase: XCTestCase
    let outputDirectory: URL?
    private let app: XCUIApplication

    init(plan: TestPlan, testCase: XCTestCase, outputDirectory: URL?) {
        self.plan = plan
        self.testCase = testCase
        self.outputDirectory = outputDirectory
        app = XCUIApplication(bundleIdentifier: plan.bundleIdentifier)
        app.launchArguments = plan.launchArguments
        app.launchEnvironment = plan.launchEnvironment
    }

    // MARK: Run loop

    func run() -> RunReport {
        let startedAt = Date()
        var reports: [RunReport.StepReport] = []
        var trees: [String: String] = [:]
        var higAudits: [HIGAuditReport] = []
        var hasFailed = false

        if plan.steps.first?.actionName != "launch" {
            app.launch()
        }

        for (index, step) in plan.steps.enumerated() {
            if hasFailed && plan.stopOnFailure {
                reports.append(.init(index: index, action: step.actionName, summary: step.summary,
                                     status: .skipped, message: "Skipped after earlier failure", durationMs: 0))
                continue
            }
            // The app reads this line from the xcodebuild log to show which step is running (`RunProgress`).
            print("TESTBRIDGE-STEP \(index + 1)/\(plan.steps.count) \(step.summary)")
            fflush(stdout)
            let stepStart = Date()
            var artifacts: [String] = []
            do {
                try perform(step, index: index, trees: &trees, higAudits: &higAudits, artifacts: &artifacts)
                reports.append(.init(index: index, action: step.actionName, summary: step.summary,
                                     status: .passed, durationMs: elapsedMs(since: stepStart), artifacts: artifacts))
            } catch {
                hasFailed = true
                let failureShot = saveScreenshot(named: "failure-step-\(index + 1)")
                if let failureShot { artifacts.append(failureShot) }
                let tree = app.debugDescription
                trees["failure-step-\(index + 1)"] = tree
                reports.append(.init(index: index, action: step.actionName, summary: step.summary,
                                     status: .failed, message: String(describing: error),
                                     durationMs: elapsedMs(since: stepStart), artifacts: artifacts))
            }
        }

        return RunReport(planName: plan.name,
                         platform: plan.platform,
                         bundleIdentifier: plan.bundleIdentifier,
                         startedAt: startedAt,
                         finishedAt: Date(),
                         steps: reports,
                         trees: trees,
                         higAudits: higAudits,
                         passed: !hasFailed)
    }

    // MARK: Step dispatch

    private func perform(_ step: Step, index: Int, trees: inout [String: String],
                         higAudits: inout [HIGAuditReport], artifacts: inout [String]) throws {
        switch step {
        case .launch:
            app.launch()
        case .terminate:
            app.terminate()
        case .activate:
            app.activate()

        case .tap(let q):
            let el = try element(q)
            #if os(macOS)
            el.click()
            #else
            el.tap()
            #endif

        case .doubleTap(let q):
            let el = try element(q)
            #if os(macOS)
            el.doubleClick()
            #else
            el.doubleTap()
            #endif

        case .longPress(let q, let seconds):
            let el = try element(q)
            #if os(macOS)
            el.click(forDuration: seconds, thenDragTo: el)
            #else
            el.press(forDuration: seconds)
            #endif

        case .typeText(let q, let text, let clearFirst):
            let el = try element(q)
            #if os(macOS)
            el.click()
            #else
            el.tap()
            #endif
            if clearFirst {
                #if os(macOS)
                el.typeKey("a", modifierFlags: .command)
                el.typeKey(.delete, modifierFlags: [])
                #else
                let existing = (el.value as? String) ?? ""
                if !existing.isEmpty {
                    el.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
                }
                #endif
            }
            el.typeText(text)

        case .swipe(let q, let direction):
            let el = try q.map { try element($0) } ?? app
            try swipe(el, direction)

        case .scrollTo(let q, let direction, let maxSwipes):
            let target = query(q)
            var attempts = 0
            while !(target.exists && target.isHittable) && attempts < maxSwipes {
                try swipe(app, direction)
                attempts += 1
            }
            guard target.exists else {
                throw StepError(description: "scrollTo: \(q) not found after \(maxSwipes) swipes")
            }

        case .tapCoordinate(let x, let y):
            let coord = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
            #if os(macOS)
            coord.click()
            #else
            coord.tap()
            #endif

        case .wait(let seconds):
            Thread.sleep(forTimeInterval: seconds)

        case .assertExists(let q, let timeout):
            guard query(q).waitForExistence(timeout: timeout) else {
                throw StepError(description: "Expected element to exist within \(timeout)s: \(q)")
            }

        case .assertNotExists(let q, let timeout):
            let el = query(q)
            let deadline = Date().addingTimeInterval(timeout)
            while el.exists && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
            }
            if el.exists {
                throw StepError(description: "Expected element to disappear within \(timeout)s: \(q)")
            }

        case .assertText(let q, let equals, let contains):
            let el = try element(q)
            let actual = (el.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? el.label
            if let equals, actual != equals {
                throw StepError(description: "Text mismatch for \(q). Expected \"\(equals)\", got \"\(actual)\"")
            }
            if let contains, !actual.localizedCaseInsensitiveContains(contains) {
                throw StepError(description: "Text for \(q) does not contain \"\(contains)\". Actual: \"\(actual)\"")
            }

        case .assertEnabled(let q, let enabled):
            let el = try element(q)
            if el.isEnabled != enabled {
                throw StepError(description: "Expected \(q) enabled == \(enabled), got \(el.isEnabled)")
            }

        case .pressKey(let key, let modifiers):
            #if os(macOS)
            app.typeKey(keyboardKey(key), modifierFlags: modifierFlags(modifiers))
            #else
            throw StepError(description: "pressKey is only supported on macOS")
            #endif

        case .rotate(let orientation):
            #if os(iOS)
            switch orientation.lowercased() {
            case "portrait": XCUIDevice.shared.orientation = .portrait
            case "portraitupsidedown": XCUIDevice.shared.orientation = .portraitUpsideDown
            case "landscapeleft": XCUIDevice.shared.orientation = .landscapeLeft
            case "landscaperight": XCUIDevice.shared.orientation = .landscapeRight
            default: throw StepError(description: "Unknown orientation '\(orientation)'")
            }
            Thread.sleep(forTimeInterval: 0.5)
            #else
            throw StepError(description: "rotate is only supported on iOS/iPadOS")
            #endif

        case .screenshot(let name):
            if let file = saveScreenshot(named: name) { artifacts.append(file) }

        case .dumpTree(let name):
            let key = name ?? "tree-step-\(index + 1)"
            let tree = app.debugDescription
            trees[key] = tree
            attach(text: tree, name: "\(key).txt")
            if let file = write(Data(tree.utf8), named: "\(key).txt") { artifacts.append(file) }

        case .higAudit(let name, let failOn):
            let report = try auditHIG(named: name)
            higAudits.append(report)
            if let data = try? report.encoded() {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "hig-\(name).json"
                attachment.lifetime = .keepAlways
                testCase.add(attachment)
                if let file = write(data, named: "hig-\(name).json") { artifacts.append(file) }
            }
            if let shot = saveScreenshot(named: "hig-\(name)") { artifacts.append(shot) }
            if let failOn, report.violates(failOn) {
                let worst = report.findings.filter { $0.severity >= failOn }.prefix(5).map(\.oneLine).joined(separator: "\n")
                throw StepError(description: "HIG audit \"\(name)\" found \(report.countsLine).\n\(worst)")
            }
        }
    }

    // MARK: HIG audit

    /// Takes one hierarchical snapshot (a single round trip) and flattens it for `HIGAuditor`.
    private func auditHIG(named name: String) throws -> HIGAuditReport {
        let root = try app.snapshot()
        var elements: [HIGElement] = []

        func walk(_ node: XCUIElementSnapshot, parent: Int?, depth: Int) {
            let index = elements.count
            let label = node.label.isEmpty ? node.title : node.label
            let value: String?
            if let s = node.value as? String { value = s } else if let v = node.value { value = String(describing: v) } else { value = nil }
            elements.append(HIGElement(id: index,
                                       parent: parent,
                                       depth: depth,
                                       type: elementKind(node.elementType),
                                       identifier: node.identifier,
                                       label: label,
                                       value: value,
                                       placeholder: node.placeholderValue,
                                       frame: HIGRect(node.frame),
                                       isEnabled: node.isEnabled))
            for child in node.children { walk(child, parent: index, depth: depth + 1) }
        }
        walk(root, parent: nil, depth: 0)
        elements = HIGElement.deduplicated(elements)

        var screen = HIGRect(root.frame)
        #if os(macOS)
        let window = app.windows.firstMatch
        if window.exists { screen = HIGRect(window.frame) }
        #endif
        if screen.isEmpty, let firstWindow = elements.first(where: { $0.type == .window && !$0.frame.isEmpty }) {
            screen = firstWindow.frame
        }

        let findings = HIGAuditor.audit(elements: elements, screen: screen, platform: plan.platform)
        return HIGAuditReport(name: name,
                              platform: plan.platform,
                              bundleIdentifier: plan.bundleIdentifier,
                              screenFrame: screen,
                              elements: elements,
                              findings: findings)
    }

    private func elementKind(_ type: XCUIElement.ElementType) -> ElementKind {
        switch type {
        case .any: return .any
        case .button: return .button
        case .textField: return .textField
        case .secureTextField: return .secureTextField
        case .staticText: return .staticText
        case .textView: return .textView
        case .searchField: return .searchField
        case .cell: return .cell
        case .table: return .table
        case .collectionView: return .collectionView
        case .scrollView: return .scrollView
        case .switch: return .switch
        case .slider: return .slider
        case .stepper: return .stepper
        case .segmentedControl: return .segmentedControl
        case .picker: return .picker
        case .pickerWheel: return .pickerWheel
        case .datePicker: return .datePicker
        case .image: return .image
        case .link: return .link
        case .webView: return .webView
        case .map: return .map
        case .navigationBar: return .navigationBar
        case .tabBar: return .tabBar
        case .toolbar: return .toolbar
        case .menuItem: return .menuItem
        case .menuBarItem: return .menuBarItem
        case .popUpButton: return .popUpButton
        case .checkBox: return .checkBox
        case .radioButton: return .radioButton
        case .window: return .window
        case .sheet: return .sheet
        case .alert: return .alert
        case .dialog: return .dialog
        case .popover: return .popover
        default: return .other
        }
    }

    // MARK: Element resolution

    private func element(_ q: ElementQuery, timeout: TimeInterval = 5) throws -> XCUIElement {
        let el = query(q)
        guard el.waitForExistence(timeout: timeout) else {
            throw StepError(description: "Element not found within \(timeout)s: \(q)")
        }
        return el
    }

    private func query(_ q: ElementQuery) -> XCUIElement {
        var elements = app.descendants(matching: elementType(q.type ?? .any))
        var predicates: [NSPredicate] = []
        if let id = q.id { predicates.append(NSPredicate(format: "identifier == %@", id)) }
        if let label = q.label { predicates.append(NSPredicate(format: "label == %@", label)) }
        if let part = q.labelContains { predicates.append(NSPredicate(format: "label CONTAINS[c] %@", part)) }
        if let text = q.text {
            predicates.append(NSPredicate(format: "label == %@ OR value == %@ OR title == %@ OR placeholderValue == %@",
                                          text, text, text, text))
        }
        if !predicates.isEmpty {
            elements = elements.matching(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
        }
        if let index = q.index {
            return elements.element(boundBy: index)
        }
        return elements.firstMatch
    }

    private func elementType(_ kind: ElementKind) -> XCUIElement.ElementType {
        switch kind {
        case .any: return .any
        case .button: return .button
        case .textField: return .textField
        case .secureTextField: return .secureTextField
        case .staticText: return .staticText
        case .textView: return .textView
        case .searchField: return .searchField
        case .cell: return .cell
        case .table: return .table
        case .collectionView: return .collectionView
        case .scrollView: return .scrollView
        case .switch: return .switch
        case .slider: return .slider
        case .stepper: return .stepper
        case .segmentedControl: return .segmentedControl
        case .picker: return .picker
        case .pickerWheel: return .pickerWheel
        case .datePicker: return .datePicker
        case .image: return .image
        case .link: return .link
        case .webView: return .webView
        case .map: return .map
        case .navigationBar: return .navigationBar
        case .tabBar: return .tabBar
        case .toolbar: return .toolbar
        case .menuItem: return .menuItem
        case .menuBarItem: return .menuBarItem
        case .popUpButton: return .popUpButton
        case .checkBox: return .checkBox
        case .radioButton: return .radioButton
        case .window: return .window
        case .sheet: return .sheet
        case .alert: return .alert
        case .dialog: return .dialog
        case .popover: return .popover
        case .other: return .other
        }
    }

    // MARK: Gestures

    private func swipe(_ el: XCUIElement, _ direction: SwipeDirection) throws {
        #if os(macOS)
        let delta: CGFloat = 200
        switch direction {
        case .up: el.scroll(byDeltaX: 0, deltaY: -delta)
        case .down: el.scroll(byDeltaX: 0, deltaY: delta)
        case .left: el.scroll(byDeltaX: -delta, deltaY: 0)
        case .right: el.scroll(byDeltaX: delta, deltaY: 0)
        }
        #else
        switch direction {
        case .up: el.swipeUp()
        case .down: el.swipeDown()
        case .left: el.swipeLeft()
        case .right: el.swipeRight()
        }
        #endif
    }

    #if os(macOS)
    private func keyboardKey(_ name: String) -> String {
        switch name.lowercased() {
        case "return", "enter": return XCUIKeyboardKey.return.rawValue
        case "escape", "esc": return XCUIKeyboardKey.escape.rawValue
        case "tab": return XCUIKeyboardKey.tab.rawValue
        case "space": return XCUIKeyboardKey.space.rawValue
        case "delete", "backspace": return XCUIKeyboardKey.delete.rawValue
        case "up": return XCUIKeyboardKey.upArrow.rawValue
        case "down": return XCUIKeyboardKey.downArrow.rawValue
        case "left": return XCUIKeyboardKey.leftArrow.rawValue
        case "right": return XCUIKeyboardKey.rightArrow.rawValue
        default: return name
        }
    }

    private func modifierFlags(_ names: [String]) -> XCUIElement.KeyModifierFlags {
        var flags: XCUIElement.KeyModifierFlags = []
        for n in names {
            switch n.lowercased() {
            case "cmd", "command": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "opt", "option", "alt": flags.insert(.option)
            case "ctrl", "control": flags.insert(.control)
            case "fn", "function": flags.insert(.function)
            default: break
            }
        }
        return flags
    }
    #endif

    // MARK: Artifacts

    @discardableResult
    private func saveScreenshot(named name: String) -> String? {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
        return write(shot.pngRepresentation, named: "\(name).png")
    }

    private func attach(text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    /// Best-effort write into the host-visible output directory (works on simulators and macOS; not on physical devices).
    private func write(_ data: Data, named name: String) -> String? {
        guard let outputDirectory else { return nil }
        let url = outputDirectory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try data.write(to: url)
            return name
        } catch {
            return nil
        }
    }

    private func elapsedMs(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
}
