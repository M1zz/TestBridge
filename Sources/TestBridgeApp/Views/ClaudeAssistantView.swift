import SwiftUI
import AppKit

/// The reason this app exists: a two-way bridge to Claude Code.
/// Left: what you want + context. Right: the generated prompt and Claude's typed reply (plan / questions / explanation).
struct ClaudeAssistantView: View {
    @Environment(AppState.self) private var state
    @State private var showPrompt = false
    @State private var showGuide = false

    var body: some View {
        HSplitView {
            requestPane
                .frame(minWidth: 380, idealWidth: 440)
            responsePane
                .frame(minWidth: 420)
        }
        .navigationTitle("Claude Code")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await state.captureSnapshot() }
                } label: {
                    Label("Capture snapshot", systemImage: "camera.viewfinder")
                }
                .help("Launch the app and dump its accessibility tree so Claude sees real identifiers")
                .disabled(state.isCapturingSnapshot || state.bundleIdentifier.isEmpty)

                Button {
                    state.resetClaudeSession()
                } label: {
                    Label("New session", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .task {
            state.claude.claudePath = await ClaudeCLI.locate()
        }
        .sheet(isPresented: $showGuide) {
            PlanRequestGuideView()
        }
    }

    // MARK: Request

    private var requestPane: some View {
        @Bindable var claude = state.claude
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // A segmented control with four long titles has a fixed intrinsic width (~670pt) that forces
                // the whole HSplitView wider than the detail column and makes the window content overflow.
                // A menu picker keeps the full titles without dictating the column width.
                Picker("Mode", selection: $claude.mode) {
                    ForEach(AssistMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Button {
                    showGuide = true
                } label: {
                    Label("Ask Claude Code yourself and paste the plan", systemImage: "questionmark.circle")
                }
                .buttonStyle(.link)

                Text(modeHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                GroupBox("What do you want to test?") {
                    TextEditor(text: $claude.goal)
                        .font(.body)
                        .frame(minHeight: 90)
                }

                GroupBox("Extra context (credentials for test accounts, which screen, known identifiers…)") {
                    TextEditor(text: $claude.extraContext)
                        .font(.body)
                        .frame(minHeight: 70)
                }

                GroupBox {
                    HStack {
                        Toggle("Include accessibility snapshot", isOn: $claude.includeSnapshot)
                        Spacer()
                        if state.isCapturingSnapshot {
                            ProgressView().controlSize(.small)
                        } else if let tree = state.accessibilityTree {
                            Text("\(tree.count.formatted()) chars captured")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("none yet").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    Text("Grounding")
                }

                if !claude.pendingQuestions.isEmpty {
                    questionsForm
                }

                HStack {
                    Button("Build prompt") { state.buildPrompt(previousPlan: claude.proposedPlan); showPrompt = true }
                    Button {
                        state.buildPrompt(previousPlan: claude.proposedPlan)
                        copy(claude.prompt)
                    } label: {
                        Label("Copy prompt", systemImage: "doc.on.doc")
                    }
                    .help("Paste into Claude Code in your project's terminal, then paste its reply on the right")
                    Spacer()
                    Button {
                        Task {
                            if claude.pendingQuestions.isEmpty {
                                state.buildPrompt(previousPlan: claude.proposedPlan)
                                await state.sendPromptToClaude()
                            } else {
                                await state.submitAnswers()
                            }
                        }
                    } label: {
                        if claude.isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(claude.pendingQuestions.isEmpty ? "Send to Claude Code" : "Send answers", systemImage: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(claude.isBusy || claude.claudePath == nil)
                    .help(claude.claudePath == nil ? "`claude` CLI not found — use Copy prompt instead" : "Runs `claude -p` headlessly\(claude.sessionId == nil ? "" : " (resuming session)")")
                }

                if claude.claudePath == nil {
                    Label("`claude` CLI not found in PATH. You can still copy the prompt and paste the reply manually.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }

                DisclosureGroup("Prompt preview", isExpanded: $showPrompt) {
                    TextEditor(text: $claude.prompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 200)
                }
            }
            .padding()
        }
    }

    private var modeHint: String {
        switch state.claude.mode {
        case .explain:
            return "Ask Claude Code how this app should be tested with TestBridge. It answers with an approach, the identifiers your app should expose, and a prompt you can send back in \"Generate a plan\" mode."
        case .plan:
            return "Claude returns a runnable plan JSON — or asks you questions first if it is missing information (test accounts, which screen, etc.)."
        case .diagnose:
            return "Pick a failed run in Runs → \"Ask Claude to diagnose\". Claude gets the step results and the accessibility tree at the failure point."
        case .hig:
            return "Run a HIG audit in the HIG tab, then \"Ask Claude to review\". Claude gets the automatic findings and every element's frame, judges them against the Human Interface Guidelines, and can propose a plan for the remaining screens."
        }
    }

    private var questionsForm: some View {
        @Bindable var claude = state.claude
        return GroupBox("Claude needs some input from you") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(claude.pendingQuestions) { q in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(q.question).font(.body.weight(.medium))
                        if let why = q.why { Text(why).font(.caption).foregroundStyle(.secondary) }
                        TextField(q.example ?? "Your answer", text: Binding(
                            get: { claude.answers[q.id] ?? "" },
                            set: { claude.answers[q.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: Response

    private var responsePane: some View {
        @Bindable var claude = state.claude
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Claude's reply").font(.headline)
                if let reply = claude.reply {
                    Text(reply.kindLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(badgeColor(reply).opacity(0.2), in: Capsule())
                }
                Spacer()
                if let sid = claude.sessionId {
                    Text("session \(sid.prefix(8))…").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let reply = claude.reply {
                        replyBody(reply)
                    } else {
                        ContentUnavailableView("No reply yet",
                                               systemImage: "sparkles",
                                               description: Text("Send a prompt, or paste a reply from Claude Code below."))
                    }

                    GroupBox("Paste a reply from Claude Code (JSON or a plan)") {
                        VStack(alignment: .trailing) {
                            TextEditor(text: $claude.pastedReply)
                                .font(.system(.caption, design: .monospaced))
                                .frame(minHeight: 100)
                            Button("Parse reply") { state.applyPastedReply() }
                                .disabled(claude.pastedReply.isEmpty)
                        }
                    }

                    if !claude.log.isEmpty {
                        DisclosureGroup("claude CLI log") {
                            Text(claude.log)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func replyBody(_ reply: AssistantReply) -> some View {
        switch reply {
        case .plan(let plan, let notes):
            if let notes { Text(notes).font(.callout) }
            let issues = plan.validate()
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(issues, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption) }
                }
                .foregroundStyle(.orange)
            }
            GroupBox("\(plan.name) · \(plan.platform.displayName) · \(plan.steps.count) steps") {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { i, step in
                        Text("\(i + 1). \(step.summary)").font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Save as plan") { Task { await state.importProposedPlan(andRun: false) } }
                Button("Save and run") { Task { await state.importProposedPlan(andRun: true) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isRunning)
                Button("Copy JSON") { copy(plan.encodedString()) }
            }

        case .questions(let qs):
            Text("Claude asked \(qs.count) question\(qs.count == 1 ? "" : "s"). Answer them on the left and press \"Send answers\".")
                .font(.callout)

        case .explanation(let approach, let suggested, let qs):
            Text(approach).textSelection(.enabled)
            if let suggested {
                GroupBox("Suggested prompt for \"Generate a plan\"") {
                    Text(suggested).font(.callout).textSelection(.enabled)
                    HStack {
                        Button("Use as goal") { state.claude.goal = suggested; state.claude.mode = .plan }
                        Button("Copy") { copy(suggested) }
                    }
                }
            }
            if !qs.isEmpty {
                Text("Claude also has \(qs.count) question\(qs.count == 1 ? "" : "s") — see the left pane.").font(.callout)
            }

        case .higReview(let review):
            HIGReviewBody(review: review)

        case .unsupported(let reason, let alternative):
            Label(reason, systemImage: "xmark.octagon").foregroundStyle(.red)
            if let alternative { Text(alternative).font(.callout) }

        case .prose(let text):
            Text("Claude did not follow the JSON protocol; raw reply:").font(.caption).foregroundStyle(.secondary)
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
    }

    private func badgeColor(_ reply: AssistantReply) -> Color {
        switch reply {
        case .plan: return .green
        case .questions: return .blue
        case .explanation: return .purple
        case .higReview: return .teal
        case .unsupported: return .red
        case .prose: return .gray
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
