import SwiftUI

@main
struct TestBridgeApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(state)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Plan") { state.createPlan() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Run Current Plan") { Task { await state.runEditorPlan() } }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(state.isRunning)
                Button("Capture Accessibility Snapshot") { Task { await state.captureSnapshot() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Audit First Screen Against HIG") { Task { await state.auditFirstScreen() } }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .disabled(state.isRunning)
            }
        }

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case hig = "HIG"
    case claude = "Claude Code"
    case plans = "Plans"
    case runs = "Runs"
    case devices = "Devices"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .hig: return "HIG"
        case .claude: return "Claude Code"
        case .plans: return "Plans"
        case .runs: return "Runs"
        case .devices: return "Devices"
        }
    }

    var icon: String {
        switch self {
        case .hig: return "checkmark.seal"
        case .claude: return "sparkles"
        case .plans: return "list.bullet.rectangle"
        case .runs: return "play.rectangle"
        case .devices: return "iphone.gen3"
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var section: SidebarSection? = .hig

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $section) { s in
                Label(s.title, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
            .safeAreaInset(edge: .bottom) { TargetSummary() }
        } detail: {
            // The section views use HSplitView (an NSSplitView). Inside a NavigationSplitView detail column that
            // AppKit view ignores the sidebar safe-area inset and its minimum width gets double-counted, which
            // makes the whole window content wider than the window. Sizing it explicitly from the real column
            // size avoids that.
            GeometryReader { geo in
                Group {
                    switch section ?? .hig {
                    case .hig: HIGAuditView()
                    case .claude: ClaudeAssistantView()
                    case .plans: PlanEditorView()
                    case .runs: RunConsoleView()
                    case .devices: DevicesView()
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if state.isRunning || state.isCapturingSnapshot { RunProgressBar() }
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let notice = state.inboxNotice {
                Text(notice)
                    .font(.callout)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        state.inboxNotice = nil
                    }
            }
        }
        .animation(.default, value: state.inboxNotice)
        .onChange(of: state.pendingSection) { _, new in
            if let new { section = new; state.pendingSection = nil }
        }
    }
}

/// Always-visible target picker: platform, bundle id, device. Every section reads from it.
struct TargetSummary: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Target").font(.body.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Platform", selection: $state.platform) {
                ForEach(Platform.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                TextField("Bundle identifier", text: $state.bundleIdentifier)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .frame(maxWidth: .infinity)
                if !state.appPresets.isEmpty {
                    Menu {
                        ForEach(state.appPresets) { preset in
                            Button { state.select(preset) } label: {
                                Text(verbatim: "\(preset.name) · \(preset.platform.displayName)")
                            }
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("My apps")
                    .accessibilityLabel("My apps")
                }
            }
            Picker("Device", selection: $state.selectedDeviceID) {
                ForEach(state.devicesForPlatform) { d in
                    Text("\(shortName(d.name))\(d.isBooted ? " ●" : "")").tag(Optional(d.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .disabled(state.platform == .macOS)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    /// Long simulator names ("iPhone 17 Pro Max (18.2)") would otherwise widen the whole sidebar.
    private func shortName(_ name: String) -> String {
        name.count > 22 ? String(name.prefix(21)) + "…" : name
    }
}

/// Shown under every section while xcodebuild is working, so it is always clear what is running and how far it is.
struct RunProgressBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(state.runTitle).fontWeight(.semibold).lineLimit(1)
                if let p = state.runProgress {
                    Text(verbatim: "\(p.step)/\(p.total)").monospacedDigit().foregroundStyle(.secondary)
                    Text(verbatim: p.summary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                } else {
                    Text("Building the runner and launching the app…").foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let p = state.runProgress {
                ProgressView(value: p.fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }
}
