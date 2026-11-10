import SwiftUI
import AppKit

struct RunConsoleView: View {
    @Environment(AppState.self) private var state

    private var selectedRun: RunRecord? { state.runs.first { $0.id == state.selectedRunID } }

    var body: some View {
        @Bindable var state = state
        HSplitView {
            List(state.runs, selection: $state.selectedRunID) { run in
                HStack {
                    Image(systemName: run.outcome.report?.crashed == true ? "bolt.circle.fill"
                          : run.outcome.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(run.outcome.passed ? .green : .red)
                    VStack(alignment: .leading) {
                        Text(run.outcome.planName)
                        Text(run.startedAt.formatted(date: .omitted, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(run.id)
            }
            .frame(minWidth: 220, idealWidth: 260)

            VSplitView {
                if let run = selectedRun {
                    runDetail(run)
                        .frame(minHeight: 200)
                } else if state.isRunning || state.isCapturingSnapshot {
                    VStack {
                        ProgressView("xcodebuild is working…")
                        Text("First run compiles the Runner; later runs are much faster.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No runs yet", systemImage: "play.rectangle",
                                           description: Text("Run a plan from Plans, or capture a snapshot."))
                }

                LogView(text: state.liveLog)
                    .frame(minHeight: 120)
            }
            .frame(minWidth: 520)
        }
        .navigationTitle("Runs")
    }

    @ViewBuilder
    private func runDetail(_ run: RunRecord) -> some View {
        let outcome = run.outcome
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(outcome.report?.crashed == true ? "CRASHED" : outcome.passed ? "PASSED" : "FAILED")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(outcome.passed ? .green : .red)
                    Text("xcodebuild exit \(outcome.exitCode)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Reveal artifacts") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outcome.outputDirectory)])
                    }
                    Button("Open .xcresult") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: outcome.xcresultPath))
                    }
                    if !outcome.passed, outcome.report != nil {
                        Button {
                            state.askClaudeToDiagnose(outcome)
                        } label: { Label("Ask Claude to diagnose", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let report = outcome.report {
                    Table(report.steps) {
                        TableColumn("#") { Text("\($0.index + 1)") }.width(28)
                        TableColumn("Status") { step in
                            Text(step.status.rawValue)
                                .foregroundStyle(color(step.status))
                        }.width(60)
                        TableColumn("Step") { Text($0.summary) }
                        TableColumn("ms") { Text("\($0.durationMs)") }.width(60)
                        TableColumn("Message") { Text($0.message ?? "").foregroundStyle(.secondary) }
                    }
                    .frame(height: CGFloat(min(report.steps.count, 12)) * 28 + 32)

                    if !report.higAudits.isEmpty {
                        GroupBox("HIG audits") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(report.higAudits) { audit in
                                    HStack {
                                        Image(systemName: audit.errorCount > 0 ? "xmark.octagon.fill" : (audit.warningCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                                            .foregroundStyle(audit.errorCount > 0 ? .red : (audit.warningCount > 0 ? .orange : .green))
                                        Text(audit.name).font(.body.weight(.medium))
                                        Text(audit.countsLine).font(.body).foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Review in HIG tab") {
                                            state.selectedAuditID = HIGAuditEntry(runID: run.id, startedAt: run.startedAt,
                                                                                  outputDirectory: outcome.outputDirectory, report: audit).id
                                            state.pendingSection = .hig
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    artifacts(for: report, in: outcome.outputDirectory)

                    if !report.trees.isEmpty {
                        DisclosureGroup("Accessibility trees (\(report.trees.count))") {
                            ForEach(report.trees.keys.sorted(), id: \.self) { key in
                                DisclosureGroup(key) {
                                    Text(report.trees[key] ?? "")
                                        .font(.system(.caption2, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                } else {
                    GroupBox("No report produced") {
                        Text("The Runner did not emit a report — usually a build or destination problem. xcodebuild tail:")
                            .font(.caption)
                        Text(outcome.logTail)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func artifacts(for report: RunReport, in dir: String) -> some View {
        let pngs = report.steps.flatMap(\.artifacts).filter { $0.hasSuffix(".png") }
        if !pngs.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(pngs, id: \.self) { name in
                        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                        if let image = NSImage(contentsOf: url) {
                            VStack {
                                Image(nsImage: image)
                                    .resizable().scaledToFit()
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .onTapGesture { NSWorkspace.shared.open(url) }
                                Text(name).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func color(_ status: RunReport.Status) -> Color {
        switch status {
        case .passed: return .green
        case .failed: return .red
        case .skipped: return .secondary
        }
    }
}

/// Auto-scrolling monospaced log.
struct LogView: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "xcodebuild output will appear here." : text)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                Color.clear.frame(height: 1).id("bottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: text) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}
