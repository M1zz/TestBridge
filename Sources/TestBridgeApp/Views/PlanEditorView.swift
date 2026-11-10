import SwiftUI
import AppKit

struct PlanEditorView: View {
    @Environment(AppState.self) private var state
    @State private var showGuide = false

    var body: some View {
        @Bindable var state = state
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $state.selectedPlanID) {
                    ForEach(state.planGroups, id: \.title) { group in
                        Section(group.title.isEmpty ? String(localized: "Other") : group.title) {
                            ForEach(group.files) { file in
                                VStack(alignment: .leading, spacing: 2) {
                                    // Flows are named "<app> · <flow>"; under the app's own heading the prefix is noise.
                                    Text(file.displayName.replacingOccurrences(of: "\(group.title) · ", with: ""))
                                    HStack(spacing: 6) {
                                        if let plan = file.plan {
                                            Text(plan.platform.displayName)
                                            Text("·")
                                            Text("\(plan.steps.count) steps")
                                        } else {
                                            Label("invalid", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                                        }
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                                .tag(file.id)
                            }
                        }
                    }
                }
                .onChange(of: state.selectedPlanID) { _, _ in state.loadEditor() }
                Divider()
                HStack {
                    Button { state.createPlan() } label: { Image(systemName: "plus") }
                    Button { state.deleteSelectedPlan() } label: { Image(systemName: "minus") }
                        .disabled(state.selectedPlan == nil)
                    Spacer()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([Paths.plans])
                    } label: { Image(systemName: "folder") }
                    .help("Reveal plans folder")
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 220, idealWidth: 260)

            VStack(spacing: 0) {
                if state.selectedPlan == nil {
                    ContentUnavailableView {
                        Label("No plan selected", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Create one, import from Claude, or drop a JSON into the Inbox folder.")
                    } actions: {
                        Button {
                            showGuide = true
                        } label: {
                            Label("Ask Claude Code yourself and paste the plan", systemImage: "questionmark.circle")
                        }
                    }
                } else {
                    TextEditor(text: $state.editorText)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: state.editorText) { _, _ in state.validateEditor() }
                    Divider()
                    issuesBar
                }
            }
            .frame(minWidth: 500)
        }
        .navigationTitle("Plans")
        .sheet(isPresented: $showGuide) {
            PlanRequestGuideView(switchToClaudeTab: true)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { state.saveEditor() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .disabled(state.selectedPlan == nil)
                Button {
                    state.saveEditor()
                    Task { await state.runEditorPlan() }
                } label: {
                    if state.isRunning { ProgressView().controlSize(.small) } else { Label("Run", systemImage: "play.fill") }
                }
                .disabled(state.isRunning || state.selectedPlan == nil || state.editorIssues.contains { $0.hasPrefix("JSON error") })
                .keyboardShortcut("r", modifiers: [.command])
                Button {
                    state.claude.mode = .plan
                    if let plan = try? TestPlan.decode(json: state.editorText) {
                        state.claude.goal = "Improve this plan: \(plan.name)"
                        state.buildPrompt(previousPlan: plan)
                    }
                } label: { Label("Ask Claude", systemImage: "sparkles") }
                .help("Builds a prompt with this plan attached (see Claude Code tab)")
            }
        }
    }

    private var issuesBar: some View {
        HStack(alignment: .top) {
            if state.editorIssues.isEmpty {
                Label("Valid plan", systemImage: "checkmark.circle").foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(state.editorIssues, id: \.self) { issue in
                        Label(issue, systemImage: issue.hasPrefix("JSON error") ? "xmark.octagon" : "exclamationmark.triangle")
                            .foregroundStyle(issue.hasPrefix("JSON error") ? .red : .orange)
                    }
                }
            }
            Spacer()
            Text("Destination: \(state.selectedDevice?.name ?? "plan default")")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(8)
    }
}
