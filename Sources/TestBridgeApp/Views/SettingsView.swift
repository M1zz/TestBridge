import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var doctorOutput: String = ""
    @State private var isWorking = false

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Runner project") {
                HStack {
                    TextField("Path to TestBridgeRunner.xcodeproj", text: $state.runnerProjectPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseRunner() }
                }
                Text("Generated from Runner/project.yml with XcodeGen. The Runner hosts the XCUITest interpreter for every platform.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Generate with xcodegen") { Task { await generateRunner() } }
                        .disabled(isWorking)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([state.runnerProjectURL])
                    }
                }
            }

            Section("Claude Code") {
                HStack {
                    Text("claude CLI")
                    Spacer()
                    Text(state.claude.claudePath ?? "not found").foregroundStyle(.secondary)
                }
                Button("Copy CLAUDE.md snippet") {
                    let text = ClaudeMDSnippet.render(bundleIdentifier: state.bundleIdentifier, platform: state.platform)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Text("Paste into your app project's CLAUDE.md so Claude Code knows the `testbridge` CLI workflow and conventions.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Folders") {
                LabeledContent("Plans") { pathLink(Paths.plans) }
                LabeledContent("Inbox (drop plans here)") { pathLink(Paths.inbox) }
                LabeledContent("Runs") { pathLink(Paths.runs) }
                LabeledContent("Derived data") { pathLink(Paths.derivedData) }
            }

            Section("Doctor") {
                Button("Run checks") { Task { await runDoctor() } }.disabled(isWorking)
                if !doctorOutput.isEmpty {
                    Text(doctorOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 560)
        .task { state.claude.claudePath = await ClaudeCLI.locate() }
    }

    private func pathLink(_ url: URL) -> some View {
        Button(url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            .buttonStyle(.link)
            .font(.caption)
    }

    private func chooseRunner() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Select TestBridgeRunner.xcodeproj"
        if panel.runModal() == .OK, let url = panel.url {
            state.runnerProjectPath = url.path
        }
    }

    private func generateRunner() async {
        isWorking = true
        defer { isWorking = false }
        let runnerDir = state.runnerProjectURL.deletingLastPathComponent()
        guard await ShellRunner.which("xcodegen") != nil else {
            doctorOutput = "xcodegen not installed. brew install xcodegen"
            return
        }
        do {
            let r = try await ShellRunner.runInLoginShell("xcodegen generate", currentDirectory: runnerDir)
            doctorOutput = r.combinedOutput
        } catch {
            doctorOutput = String(describing: error)
        }
    }

    private func runDoctor() async {
        isWorking = true
        defer { isWorking = false }
        var lines: [String] = []
        let xb = try? await ShellRunner.run("/usr/bin/xcrun", ["xcodebuild", "-version"])
        lines.append((xb?.succeeded == true ? "✓" : "✗") + " xcodebuild: " + (xb?.stdout.split(separator: "\n").first.map(String.init) ?? "missing"))
        let xg = await ShellRunner.which("xcodegen")
        lines.append((xg != nil ? "✓" : "✗") + " xcodegen: " + (xg ?? "not installed"))
        let cl = await ClaudeCLI.locate()
        lines.append((cl != nil ? "✓" : "✗") + " claude: " + (cl ?? "not installed"))
        let runnerOK = FileManager.default.fileExists(atPath: state.runnerProjectURL.path)
        lines.append((runnerOK ? "✓" : "✗") + " runner: " + state.runnerProjectURL.path)
        lines.append("✓ simulators: \(state.devices.count - 1) available")
        doctorOutput = lines.joined(separator: "\n")
    }
}
