import SwiftUI
import AppKit

/// In-app guide for the paste workflow: the developer asks Claude Code in their own terminal, pastes the reply
/// into TestBridge, and the plan runs. Opened from the Claude Code tab and from the empty state of the Plans tab.
struct PlanRequestGuideView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    /// When true, "Use this example" also switches the window to the Claude Code tab (used from the Plans tab).
    var switchToClaudeTab = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Ask Claude Code yourself, paste the plan here", systemImage: "questionmark.circle")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    flowSection
                    goalSection
                    exampleSection
                    templateSection
                    avoidSection
                    afterSection
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 720)
    }

    // MARK: Sections

    private var flowSection: some View {
        section("How it works", systemImage: "arrow.triangle.turn.up.right.diamond") {
            numbered(1, title: "Write the request and copy it.",
                     body: "Type what to test in \"What do you want to test?\" and press \"Copy prompt\". The copied text already contains the plan format, your target (platform, bundle ID, device), the accessibility snapshot if you captured one, and the exact reply format. You do not need the claude CLI or the \"Send to Claude Code\" button.")
            numbered(2, title: "Paste it into Claude Code.",
                     body: "Any Claude Code session works: your project's terminal is best because Claude can read the app code and add missing identifiers. Claude replies with one JSON object.")
            numbered(3, title: "Paste the reply back here and run.",
                     body: "Copy Claude's reply, paste it into \"Paste a reply from Claude Code\" on the right, press \"Parse reply\", then \"Save and run\". A bare plan JSON without the wrapper is recognized too. The run appears in the Runs tab with step results and screenshots.")
        }
    }

    private var goalSection: some View {
        section("What a good request contains", systemImage: "checklist") {
            bullet("Which screen or flow, in order.", detail: "For example: launch → General → About. One flow per plan.")
            bullet("The starting state.", detail: "Logged in or not, which test account, which data must exist. Mention the -uiTesting launch argument if your app seeds state with it.")
            bullet("What must be verified.", detail: "Which screens to audit against the HIG, which texts or elements must be visible, and the failOn level (error, warning, info or none).")
            bullet("Known identifiers.", detail: "Press \"Capture snapshot\" first and keep \"Include accessibility snapshot\" on so Claude sees real identifiers. State your naming scheme (for example screen.element).")
            bullet("Platform and device.", detail: "Taken from the Target box in the sidebar. Say so if the plan must also run on iPad or Mac.")
        }
    }

    private var exampleSection: some View {
        section("Example request", systemImage: "text.quote") {
            codeBlock(exampleGoal, monospaced: false)
            Text("Extra context:")
                .font(.body.weight(.medium))
            codeBlock(exampleContext, monospaced: false)
            HStack {
                Button {
                    state.claude.mode = .plan
                    state.claude.goal = exampleGoal
                    state.claude.extraContext = exampleContext
                    state.buildPrompt(previousPlan: nil)
                    copy(state.claude.prompt)
                    if switchToClaudeTab { state.pendingSection = .claude }
                    dismiss()
                } label: { Label("Use this example and copy the prompt", systemImage: "doc.on.doc") }
                .buttonStyle(.borderedProminent)
                Button {
                    copy(exampleGoal + "\n\n" + exampleContext)
                } label: { Label("Copy text only", systemImage: "doc.on.doc") }
            }
            Text("The prompt lands on your clipboard. Paste it into Claude Code, then paste the reply on the right.")
                .font(.body).foregroundStyle(.secondary)
        }
    }

    private var templateSection: some View {
        section("Writing the request without this app", systemImage: "terminal") {
            Text("If you prefer to type your own request in Claude Code, it must still know the plan format and the reply shape. \"Copy template with plan format\" copies this text followed by the plan reference and the reply format, so the result can be pasted here unchanged.")
                .font(.body).foregroundStyle(.secondary)
            codeBlock(terminalTemplate, monospaced: true)
            Button {
                copy(terminalTemplate + "\n\n" + PlanSchema.reference + "\n\n" + PromptBuilder.responseProtocol(for: .plan))
            } label: { Label("Copy template with plan format", systemImage: "doc.on.doc") }
        }
    }

    private var avoidSection: some View {
        section("Avoid", systemImage: "hand.raised") {
            bullet("\"Test everything\" with no screen named.", detail: "Claude will either ask questions or guess. Name the screens.")
            bullet("Asking for coordinates.", detail: "tapCoordinate breaks on every device size. Ask which identifier to add to the app instead.")
            bullet("Several flows in one plan.", detail: "Keep a plan under about 15 steps. Long flows are hard to diagnose when they fail.")
            bullet("Assuming Claude knows your test accounts.", detail: "Put credentials, seeded data and feature flags in Extra context.")
            bullet("Pasting prose around the JSON.", detail: "The parser skips code fences and chatter, but if Claude explained a lot, paste only the JSON object.")
        }
    }

    private var afterSection: some View {
        section("After the reply", systemImage: "arrow.right.circle") {
            numbered(1, title: "Questions instead of a plan?", body: "Answer Claude directly in the terminal and paste its next reply here. Or answer in the form that appears on the left and press \"Copy prompt\" again.")
            numbered(2, title: "Check the validation.", body: "Orange warnings under the plan mean missing waits or verifications. You can still save and edit the JSON in the Plans tab.")
            numbered(3, title: "Save and run.", body: "If the run fails, open it in the Runs tab and press \"Ask Claude to diagnose\": the prompt with step results and the accessibility tree at the failure point is built for you. \"Copy prompt\", paste it into Claude Code, paste the corrected plan back.")
        }
    }

    // MARK: Texts

    private var exampleGoal: String {
        String(localized: "Launch the app, go from the first screen to General and then About, and audit every screen against the HIG along the way. Add a higAudit and a screenshot per screen. On About, verify that the text \"Software Version\" is visible. Use failOn \"error\".",
               comment: "Example goal text for asking Claude for a plan.")
    }

    private var exampleContext: String {
        String(localized: "Identifier scheme: screen.element (for example settings.general). No login required. Device: the simulator selected in the sidebar.",
               comment: "Example extra-context text for asking Claude for a plan.")
    }

    private var terminalTemplate: String {
        let bid = state.bundleIdentifier.isEmpty ? "<bundle-id>" : state.bundleIdentifier
        let platform = state.platform.rawValue
        return String(localized: """
        Write ONE TestBridge plan JSON for \(bid) on \(platform), following the plan format below.
        Goal: <which flow, which screens to audit, what must be visible>
        Starting state: <logged in or not, test account, seeded data>
        Use only identifiers that exist in the app (check the source or the snapshot). If an element has no identifier, add one in the app code and use it instead of tapCoordinate.
        Reply with only {"kind":"plan","plan":{...},"notes":"..."} so I can paste it into TestBridge.
        """, comment: "Template the developer pastes into Claude Code in a terminal. Keep the JSON shape unchanged.")
    }

    // MARK: Building blocks

    private func codeBlock(_ text: String, monospaced: Bool) -> some View {
        Text(text)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey, systemImage: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }

    private func numbered(_ n: Int, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.body.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(body).font(.body).foregroundStyle(.secondary)
            }
        }
    }

    private func bullet(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.body).foregroundStyle(.secondary)
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
