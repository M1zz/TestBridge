import SwiftUI
import AppKit

struct PlanEditorView: View {
    @Environment(AppState.self) private var state
    @State private var showGuide = false
    /// Off by default: with dozens of apps the full list buries the one being worked on.
    @State private var showsAllApps = false

    var body: some View {
        @Bindable var state = state
        HSplitView {
            VStack(spacing: 0) {
                let groups = state.planGroups
                let ownGroup = groups.first { $0.bundle == state.bundleIdentifier }
                let showsAll = showsAllApps || ownGroup == nil
                if groups.count > 1 {
                    Picker("App", selection: Binding(
                        get: { showsAll ? "" : state.bundleIdentifier },
                        set: { bundle in
                            showsAllApps = bundle.isEmpty
                            if !bundle.isEmpty { state.showPlans(forBundle: bundle) }
                        })) {
                        ForEach(groups, id: \.bundle) { group in
                            Text(verbatim: "\(group.title.isEmpty ? String(localized: "Other") : group.title) (\(group.files.count))")
                                .tag(group.bundle)
                        }
                        Divider()
                        Text("All apps").tag("")
                    }
                    .labelsHidden()
                    .padding(8)
                    Divider()
                }
                List(selection: $state.selectedPlanID) {
                    ForEach(showsAll ? groups : groups.filter { $0.bundle == state.bundleIdentifier }, id: \.bundle) { group in
                        if showsAll {
                            Section(group.title.isEmpty ? String(localized: "Other") : group.title) { planRows(group.title, group.files) }
                        } else {
                            planRows(group.title, group.files)
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

    private func planRows(_ appTitle: String, _ files: [PlanFile]) -> some View {
        ForEach(files) { file in
            VStack(alignment: .leading, spacing: 2) {
                // Flows are named "<app> · <flow>"; under the app's own heading the prefix is noise.
                Text(file.displayName.replacingOccurrences(of: "\(appTitle) · ", with: ""))
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
