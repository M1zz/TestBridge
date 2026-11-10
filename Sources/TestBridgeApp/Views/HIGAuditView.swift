import SwiftUI
import AppKit

/// The app's main job: does the target app violate the Human Interface Guidelines?
/// Left: every audit (one per screen per run). Right: findings with links into the HIG, and a hand-off to Claude.
struct HIGAuditView: View {
    @Environment(AppState.self) private var state
    @State private var severityFilter: HIGSeverity? = nil

    var body: some View {
        @Bindable var state = state
        HSplitView {
            auditList
                .frame(minWidth: 240, idealWidth: 280)
            Group {
                if let entry = state.selectedAudit {
                    auditDetail(entry)
                } else if state.isAuditing {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Launching the app and auditing its first screen…")
                        Text("The first run compiles the Runner once; later audits take seconds.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                }
            }
            .frame(minWidth: 560)
        }
        .navigationTitle("HIG")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await state.auditFirstScreen() }
                } label: {
                    if state.isAuditing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Audit first screen", systemImage: "checkmark.seal")
                    }
                }
                .help("Launch the target app and check its first screen against the HIG rules (⇧⌘H)")
                .disabled(state.isRunning || state.bundleIdentifier.isEmpty)

                Button {
                    NSWorkspace.shared.open(HIGRules.url(for: ""))
                } label: {
                    Label("Open HIG", systemImage: "book")
                }
                .help("Apple Human Interface Guidelines")
            }
        }
    }

    // MARK: List

    private var auditList: some View {
        @Bindable var state = state
        return List(state.higAudits, selection: $state.selectedAuditID) { entry in
            HStack(alignment: .top, spacing: 8) {
                severityIcon(entry.report.worstSeverity)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.report.name).font(.body.weight(.medium))
                    Text("\(entry.report.platform.displayName) · \(entry.startedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.body).foregroundStyle(.secondary)
                    Text(countsText(entry.report))
                        .font(.body).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .tag(entry.id)
        }
        .overlay {
            if state.higAudits.isEmpty && !state.isAuditing {
                Text("No audits yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private func auditDetail(_ entry: HIGAuditEntry) -> some View {
        let report = entry.report
        let shown = report.findings.filter { finding in severityFilter.map { $0 == finding.severity } ?? true }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            verdictBadge(report)
                            Text(report.name).font(.title2.weight(.semibold))
                        }
                        Text("\(report.bundleIdentifier) · \(report.platform.displayName) · \(report.elements.count) elements · \(Int(report.screenFrame.width))×\(Int(report.screenFrame.height))pt")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        state.askClaudeToReviewHIG([report])
                    } label: {
                        Label("Ask Claude to review", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Send the findings and the element list to Claude Code in “Review HIG compliance” mode")
                }

                HStack(spacing: 10) {
                    Button("Copy findings JSON") {
                        if let data = try? report.encoded(), let s = String(data: data, encoding: .utf8) { copy(s) }
                    }
                    Button("Reveal artifacts") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.outputDirectory)])
                    }
                    Spacer()
                    Picker("Filter", selection: $severityFilter) {
                        Text("All (\(report.findings.count))").tag(HIGSeverity?.none)
                        ForEach(HIGSeverity.allCases.reversed(), id: \.self) { sev in
                            Text("\(severityName(sev)) (\(report.count(sev)))").tag(Optional(sev))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 420)
                }

                screenshot(for: entry)

                if report.findings.isEmpty {
                    GroupBox {
                        Label("No automatic findings on this screen. Ask Claude to review what the rules cannot measure: wording, hierarchy, control choice, platform conventions.", systemImage: "checkmark.circle")
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if shown.isEmpty {
                    Text("No findings at this severity.").font(.body).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(shown) { finding in
                            findingRow(finding, in: report)
                        }
                    }
                }

                DisclosureGroup("Rules checked on \(report.platform.displayName)") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(HIGRules.all.filter { $0.platforms.contains(report.platform) }) { rule in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(rule.id).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                                Text(ruleTitle(rule)).font(.body)
                                Spacer()
                                Link(destination: rule.url) { Label("HIG", systemImage: "arrow.up.right.square") }
                                    .font(.body)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.body)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func screenshot(for entry: HIGAuditEntry) -> some View {
        let url = URL(fileURLWithPath: entry.outputDirectory).appendingPathComponent("hig-\(entry.report.name).png")
        if let image = NSImage(contentsOf: url) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                    .onTapGesture { NSWorkspace.shared.open(url) }
                Text("Tap the screenshot to open it. Frames in the findings are in points relative to the \(entry.report.platform == .macOS ? String(localized: "window") : String(localized: "screen")).")
                    .font(.body).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func findingRow(_ finding: HIGFinding, in report: HIGAuditReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    severityIcon(finding.severity)
                    Text(HIGRules.rule(finding.rule).map(ruleTitle) ?? finding.title).font(.body.weight(.semibold))
                    Spacer()
                    Text(finding.rule).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    if let url = URL(string: finding.higURL) {
                        Link(destination: url) { Label("HIG", systemImage: "arrow.up.right.square") }.font(.body)
                    }
                }
                Text(finding.message).font(.body).textSelection(.enabled)
                if let summary = finding.elementSummary {
                    Text(summary)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Does your app violate the HIG?").font(.title2.weight(.semibold))
            Text("Pick the platform, bundle identifier and device in the sidebar, then press “Audit first screen”. TestBridge launches the app, measures every control against Apple's Human Interface Guidelines, and lets Claude Code review the rest.")
                .font(.body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .foregroundStyle(.secondary)
            Button {
                Task { await state.auditFirstScreen() }
            } label: {
                Label("Audit first screen", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isRunning || state.bundleIdentifier.isEmpty)
            if state.bundleIdentifier.isEmpty {
                Text("Enter the target app's bundle identifier in the sidebar first.").font(.body).foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func countsText(_ report: HIGAuditReport) -> String {
        String(localized: "\(report.errorCount) errors · \(report.warningCount) warnings · \(report.infoCount) info")
    }

    private func severityName(_ s: HIGSeverity) -> String {
        switch s {
        case .error: return String(localized: "Errors")
        case .warning: return String(localized: "Warnings")
        case .info: return String(localized: "Info")
        }
    }

    private func ruleTitle(_ rule: HIGRule) -> String {
        Locale.current.language.languageCode?.identifier == "ko" ? rule.titleKo : rule.title
    }

    @ViewBuilder
    private func severityIcon(_ s: HIGSeverity?) -> some View {
        switch s {
        case .error: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .info: Image(systemName: "info.circle.fill").foregroundStyle(.blue)
        case nil: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    private func verdictBadge(_ report: HIGAuditReport) -> some View {
        let (text, color): (LocalizedStringKey, Color) = {
            switch report.worstSeverity {
            case .error: return ("VIOLATIONS", .red)
            case .warning: return ("NEEDS WORK", .orange)
            case .info, nil: return ("NO VIOLATIONS", .green)
            }
        }()
        return Text(text)
            .font(.body.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Claude's HIG review, rendered inside the Claude Code tab.
struct HIGReviewBody: View {
    @Environment(AppState.self) private var state
    let review: HIGReview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(verdictText)
                    .font(.body.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(verdictColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(verdictColor)
                Text("\(review.findings.count) findings").font(.body).foregroundStyle(.secondary)
            }
            if !review.summary.isEmpty {
                Text(review.summary).font(.body).textSelection(.enabled)
            }
            ForEach(review.findings) { f in
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(f.severity.rawValue.uppercased())
                                .font(.body.weight(.bold))
                                .foregroundStyle(color(f.severity))
                            Text(f.rule).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                            Spacer()
                            if let hig = f.hig, let url = URL(string: hig) {
                                Link(destination: url) { Label("HIG", systemImage: "arrow.up.right.square") }.font(.body)
                            }
                        }
                        if let element = f.element, !element.isEmpty {
                            Text(element).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Text(f.issue).font(.body).textSelection(.enabled)
                        if let fix = f.fix, !fix.isEmpty {
                            Label(fix, systemImage: "wrench.and.screwdriver").font(.body).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let plan = review.nextPlan {
                GroupBox("Next audit plan: \(plan.name) · \(plan.steps.count) steps") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(plan.steps.enumerated()), id: \.offset) { i, step in
                            Text("\(i + 1). \(step.summary)").font(.system(.body, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Save as plan") { Task { await state.importProposedPlan(andRun: false) } }
                    Button("Save and run") { Task { await state.importProposedPlan(andRun: true) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.isRunning)
                }
            }
        }
    }

    private var verdictText: LocalizedStringKey {
        switch review.verdict {
        case .pass: return "PASS"
        case .needsWork: return "NEEDS WORK"
        case .fail: return "FAIL"
        }
    }

    private var verdictColor: Color {
        switch review.verdict {
        case .pass: return .green
        case .needsWork: return .orange
        case .fail: return .red
        }
    }

    private func color(_ s: HIGSeverity) -> Color {
        switch s {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
