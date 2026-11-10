import Foundation

/// Pure rule engine: takes the flattened accessibility snapshot the Runner captured and returns HIG findings.
/// Lives in Models so the XCUITest Runner, the app and the CLI all share the exact same checks.
public enum HIGAuditor {
    public static let interactiveKinds: Set<ElementKind> = [
        .button, .link, .switch, .slider, .stepper, .segmentedControl,
        .textField, .secureTextField, .searchField, .checkBox, .radioButton, .popUpButton,
    ]
    static let textInputKinds: Set<ElementKind> = [.textField, .secureTextField, .searchField]
    static let labelRequiredKinds: Set<ElementKind> = [.button, .link, .switch, .checkBox, .radioButton, .slider, .stepper]
    static let scrollContainerKinds: Set<ElementKind> = [.scrollView, .table, .collectionView, .webView, .map, .pickerWheel]

    static let appleCamelCaseWords: Set<String> = [
        "iphone", "ipad", "ipod", "icloud", "imessage", "itunes", "imac", "ios", "ipados", "macos", "watchos", "tvos", "visionos", "ebay", "macbook", "airpods",
    ]

    public static func audit(elements rawElements: [HIGElement], screen: HIGRect, platform: Platform) -> [HIGFinding] {
        let elements = HIGElement.deduplicated(rawElements)
        let ctx = Context(elements: elements, screen: screen, platform: platform)
        var findings: [HIGFinding] = []
        findings += targetSize(ctx)
        findings += missingLabel(ctx)
        findings += textFieldLabel(ctx)
        findings += identifierLikeLabel(ctx)
        findings += duplicateLabel(ctx)
        findings += tabBarItemCount(ctx)
        findings += alertButtonCount(ctx)
        findings += smallText(ctx)
        findings += overlappingTargets(ctx)
        findings += offscreenTarget(ctx)
        findings += nestedInteractive(ctx)
        findings += listRowHeight(ctx)
        findings += windowTitle(ctx)
        findings += noAccessibleContent(ctx)

        findings.sort { ($0.severity, $0.element ?? -1) > ($1.severity, $1.element ?? -1) }
        for i in findings.indices { findings[i].id = "\(i)-\(findings[i].rule)" }
        return findings
    }

    // MARK: Context

    struct Context {
        let elements: [HIGElement]
        let screen: HIGRect
        let platform: Platform

        func visible(_ e: HIGElement) -> Bool {
            !e.frame.isEmpty && e.frame.intersects(screen)
        }

        func ancestors(of e: HIGElement) -> [HIGElement] {
            var result: [HIGElement] = []
            var cursor = e.parent
            var guardCount = 0
            while let p = cursor, p >= 0, p < elements.count, guardCount < 500 {
                result.append(elements[p])
                cursor = elements[p].parent
                guardCount += 1
            }
            return result
        }

        func isDescendant(_ e: HIGElement, of ancestor: HIGElement) -> Bool {
            ancestors(of: e).contains { $0.id == ancestor.id }
        }

        func isInsideScrollContainer(_ e: HIGElement) -> Bool {
            ancestors(of: e).contains { HIGAuditor.scrollContainerKinds.contains($0.type) }
        }

        var interactive: [HIGElement] {
            elements.filter { HIGAuditor.interactiveKinds.contains($0.type) }
        }
    }

    static func finding(_ ruleID: String, _ ctx: Context, element: HIGElement?, message: String, severity: HIGSeverity? = nil) -> HIGFinding? {
        guard let rule = HIGRules.rule(ruleID), rule.platforms.contains(ctx.platform) else { return nil }
        return HIGFinding(rule: rule.id,
                          severity: severity ?? rule.defaultSeverity,
                          title: rule.title,
                          message: message,
                          element: element?.id,
                          elementSummary: element?.summary,
                          frame: element?.frame,
                          higURL: rule.url.absoluteString)
    }

    static func fmt(_ v: Double) -> String { String(Int(v.rounded())) }

    // MARK: Rules

    static func targetSize(_ ctx: Context) -> [HIGFinding] {
        let minimum: Double = ctx.platform == .macOS ? 20 : 44
        return ctx.interactive.compactMap { e in
            guard e.isEnabled, ctx.visible(e), e.type != .segmentedControl, e.type != .slider else { return nil }
            let side = e.frame.minSide
            guard side < minimum - 0.5 else { return nil }
            let severity: HIGSeverity = (ctx.platform == .macOS || textInputKinds.contains(e.type)) ? .warning : .error
            return finding("target-size", ctx, element: e,
                           message: "Hit area is \(fmt(e.frame.width))×\(fmt(e.frame.height))pt; the HIG minimum on \(ctx.platform.displayName) is \(fmt(minimum))×\(fmt(minimum))pt.",
                           severity: severity)
        }
    }

    static func missingLabel(_ ctx: Context) -> [HIGFinding] {
        ctx.elements.compactMap { e in
            guard ctx.visible(e) else { return nil }
            let label = e.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if labelRequiredKinds.contains(e.type), label.isEmpty {
                return finding("missing-label", ctx, element: e,
                               message: "This \(e.type.rawValue) has no accessibility label\(e.identifier.isEmpty ? "" : " (identifier \"\(e.identifier)\" is not read aloud)"). VoiceOver announces only \"\(e.type.rawValue)\".")
            }
            if e.type == .popUpButton, label.isEmpty, (e.value ?? "").isEmpty {
                return finding("missing-label", ctx, element: e, message: "Pop-up button has neither a label nor a selected value for VoiceOver to read.")
            }
            return nil
        }
    }

    static func textFieldLabel(_ ctx: Context) -> [HIGFinding] {
        ctx.elements.compactMap { e in
            guard textInputKinds.contains(e.type), ctx.visible(e) else { return nil }
            let label = e.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard label.isEmpty else { return nil }
            let placeholder = (e.placeholder ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if placeholder.isEmpty {
                return finding("text-field-label", ctx, element: e, message: "Text field has no label and no placeholder; VoiceOver users cannot tell what to type.")
            }
            return finding("text-field-label", ctx, element: e,
                           message: "Text field relies on the placeholder \"\(placeholder)\" alone; add a label so the purpose stays visible after typing.",
                           severity: .info)
        }
    }

    static let dottedIdentifier = try! NSRegularExpression(pattern: #"^[A-Za-z0-9]+(?:[._][A-Za-z0-9]+)+$"#)
    static let camelCase = try! NSRegularExpression(pattern: #"^[a-z]+(?:[A-Z][a-z0-9]*){1,}$"#)

    static func looksLikeIdentifier(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.rangeOfCharacter(from: .letters) != nil,
              trimmed.rangeOfCharacter(from: .whitespaces) == nil else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if dottedIdentifier.firstMatch(in: trimmed, range: range) != nil {
            // "3.5" has no letters (excluded above); "v1.2" has one letter segment — treat as version, not identifier.
            let segments = trimmed.split(whereSeparator: { $0 == "." || $0 == "_" })
            return segments.filter { $0.rangeOfCharacter(from: .letters) != nil && $0.count >= 2 }.count >= 2
        }
        if camelCase.firstMatch(in: trimmed, range: range) != nil {
            return !appleCamelCaseWords.contains(trimmed.lowercased())
        }
        return false
    }

    static func identifierLikeLabel(_ ctx: Context) -> [HIGFinding] {
        ctx.elements.compactMap { e in
            guard interactiveKinds.contains(e.type) || e.type == .staticText, ctx.visible(e), looksLikeIdentifier(e.label) else { return nil }
            return finding("identifier-like-label", ctx, element: e,
                           message: "Label \"\(e.label)\" reads like a code identifier. Users and VoiceOver see this text; use natural language and move the technical name to accessibilityIdentifier.")
        }
    }

    static func duplicateLabel(_ ctx: Context) -> [HIGFinding] {
        var groups: [String: [HIGElement]] = [:]
        for e in ctx.interactive where ctx.visible(e) {
            let label = e.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            groups["\(e.type.rawValue)|\(label)", default: []].append(e)
        }
        return groups.values.compactMap { group in
            guard group.count > 1 else { return nil }
            let ids = Set(group.map(\.identifier).filter { !$0.isEmpty })
            guard ids.count < group.count else { return nil }   // all distinguishable by identifier
            let first = group.sorted { $0.id < $1.id }[0]
            return finding("duplicate-label", ctx, element: first,
                           message: "\(group.count) \(first.type.rawValue)s share the label \"\(first.label)\" without distinct identifiers.")
        }
        .sorted { ($0.element ?? 0) < ($1.element ?? 0) }
    }

    static func tabBarItemCount(_ ctx: Context) -> [HIGFinding] {
        ctx.elements.compactMap { bar in
            guard bar.type == .tabBar else { return nil }
            let items = ctx.elements.filter { $0.type == .button && ctx.isDescendant($0, of: bar) }
            guard items.count > 5 else { return nil }
            return finding("tab-bar-item-count", ctx, element: bar,
                           message: "Tab bar exposes \(items.count) tabs; the HIG recommends three to five on iPhone.")
        }
    }

    static func alertButtonCount(_ ctx: Context) -> [HIGFinding] {
        ctx.elements.compactMap { alert in
            guard alert.type == .alert else { return nil }
            let buttons = ctx.elements.filter { $0.type == .button && ctx.isDescendant($0, of: alert) }
            guard buttons.count > 3 else { return nil }
            return finding("alert-button-count", ctx, element: alert,
                           message: "Alert \"\(alert.label)\" shows \(buttons.count) buttons; prefer two, and move longer choice lists to an action sheet or menu.")
        }
    }

    static func smallText(_ ctx: Context) -> [HIGFinding] {
        let threshold: Double = ctx.platform == .macOS ? 12 : 13
        return ctx.elements.compactMap { e in
            guard e.type == .staticText, ctx.visible(e), !e.label.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            guard e.frame.height < threshold, e.frame.width > 0 else { return nil }
            return finding("small-text", ctx, element: e,
                           message: "Text \"\(e.label.prefix(40))\" is only \(fmt(e.frame.height))pt tall, which implies a font below the \(ctx.platform == .macOS ? 10 : 11)pt minimum.")
        }
    }

    static func overlappingTargets(_ ctx: Context) -> [HIGFinding] {
        let targets = ctx.interactive.filter { $0.isEnabled && ctx.visible($0) }
        var result: [HIGFinding] = []
        guard targets.count > 1 else { return result }
        for i in 0..<(targets.count - 1) {
            for j in (i + 1)..<targets.count {
                let a = targets[i], b = targets[j]
                if ctx.isDescendant(a, of: b) || ctx.isDescendant(b, of: a) { continue }
                // Different layers: scrolling content legitimately passes under floating bars.
                if ctx.isInsideScrollContainer(a) != ctx.isInsideScrollContainer(b) { continue }
                let inter = a.frame.intersection(b.frame).area
                guard inter > 0 else { continue }
                let smaller = min(a.frame.area, b.frame.area)
                guard smaller > 0, inter / smaller > 0.25 else { continue }
                // Full containment is an accessory pattern (clear/mic button inside a field), not a collision.
                if inter >= smaller - 0.5 { continue }
                if let f = finding("overlapping-targets", ctx, element: a,
                                   message: "\(a.summary) overlaps \(b.summary) by \(Int((inter / smaller * 100).rounded()))% of the smaller control.") {
                    result.append(f)
                }
                if result.count >= 10 { return result }
            }
        }
        return result
    }

    static func offscreenTarget(_ ctx: Context) -> [HIGFinding] {
        ctx.interactive.compactMap { e in
            guard e.isEnabled, !e.frame.isEmpty, !ctx.isInsideScrollContainer(e) else { return nil }
            let visibleFraction = e.frame.intersection(ctx.screen).area / e.frame.area
            guard visibleFraction < 0.5 else { return nil }
            return finding("offscreen-target", ctx, element: e,
                           message: "Only \(Int((visibleFraction * 100).rounded()))% of this control is inside the \(ctx.platform == .macOS ? "window" : "screen") and it is not in a scrolling container.")
        }
    }

    static func nestedInteractive(_ ctx: Context) -> [HIGFinding] {
        ctx.interactive.compactMap { e in
            guard ctx.visible(e) else { return nil }
            guard let container = ctx.ancestors(of: e).first(where: { $0.type == .button || $0.type == .link }) else { return nil }
            return finding("nested-interactive", ctx, element: e,
                           message: "\(e.type.rawValue) \"\(e.label)\" is nested inside \(container.type.rawValue) \"\(container.label)\"; assistive technologies cannot tell which one activates.")
        }
    }

    static func listRowHeight(_ ctx: Context) -> [HIGFinding] {
        ctx.elements.compactMap { e in
            guard e.type == .cell, ctx.visible(e), e.frame.width >= ctx.screen.width * 0.6, e.frame.height < 43.5 else { return nil }
            return finding("list-row-height", ctx, element: e,
                           message: "Row \"\(e.label.prefix(40))\" is \(fmt(e.frame.height))pt tall; list rows should be at least 44pt.")
        }
    }

    static func windowTitle(_ ctx: Context) -> [HIGFinding] {
        ctx.elements.compactMap { e in
            guard e.type == .window, !e.frame.isEmpty, e.label.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return finding("window-title", ctx, element: e, message: "Window \(e.frame) has an empty title.")
        }
    }

    static func noAccessibleContent(_ ctx: Context) -> [HIGFinding] {
        let meaningful = ctx.elements.filter {
            (interactiveKinds.contains($0.type) || $0.type == .staticText || $0.type == .cell || $0.type == .image) && !$0.label.isEmpty
        }
        guard meaningful.isEmpty else { return [] }
        return [finding("no-accessible-content", ctx, element: nil,
                        message: "The screen exposes \(ctx.elements.count) elements but none has a readable label; VoiceOver and UI tests see an empty screen.")].compactMap { $0 }
    }
}
