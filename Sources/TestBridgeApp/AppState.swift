import Foundation
import SwiftUI
import Observation

struct RunRecord: Identifiable, Hashable {
    let id = UUID()
    let startedAt: Date
    let outcome: RunOutcome

    static func == (lhs: RunRecord, rhs: RunRecord) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One `higAudit` result, tied to the run that produced it.
struct HIGAuditEntry: Identifiable, Hashable {
    let runID: UUID
    let startedAt: Date
    let outputDirectory: String
    let report: HIGAuditReport

    var id: String { "\(runID)-\(report.name)" }

    static func == (lhs: HIGAuditEntry, rhs: HIGAuditEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct PlanFile: Identifiable, Hashable {
    var url: URL
    var plan: TestPlan?
    var parseError: String?

    var id: URL { url }
    var displayName: String { plan?.name ?? url.deletingPathExtension().lastPathComponent }
}

/// Everything Claude-related the assistant view binds to.
@Observable
final class ClaudeSession {
    var mode: AssistMode = .hig
    var goal: String = ""
    var extraContext: String = ""
    var includeSnapshot = true

    var prompt: String = ""
    var isBusy = false
    var lastResponseText: String = ""
    var reply: AssistantReply? = nil
    var sessionId: String? = nil
    var pendingQuestions: [ClarifyingQuestion] = []
    var answers: [String: String] = [:]
    var proposedPlan: TestPlan? = nil
    var proposedNotes: String? = nil
    var pastedReply: String = ""
    var claudePath: String? = nil
    var log: String = ""
}

@MainActor
@Observable
final class AppState {
    // Devices
    var devices: [DeviceTarget] = []
    var selectedDeviceID: DeviceTarget.ID? = nil
    var isLoadingDevices = false
    var installedApps: [String] = []

    // Target app
    var platform: Platform = .iOS {
        didSet { if platform == .macOS { selectedDeviceID = DeviceTarget.thisMac.id } }
    }
    var bundleIdentifier: String = UserDefaults.standard.string(forKey: "bundleIdentifier") ?? "" {
        didSet { UserDefaults.standard.set(bundleIdentifier, forKey: "bundleIdentifier") }
    }
    /// The developer's own apps from `Apps.json`; picking one fills the platform and bundle identifier.
    var appPresets: [AppPreset] = AppPreset.load()

    func select(_ preset: AppPreset) {
        platform = preset.platform
        bundleIdentifier = preset.bundleIdentifier
    }

    var runnerProjectPath: String = Paths.defaultRunnerProject().path {
        didSet { UserDefaults.standard.set(runnerProjectPath, forKey: "runnerProjectPath") }
    }

    // Plans
    var plans: [PlanFile] = []
    var selectedPlanID: URL? = nil
    var editorText: String = ""
    var editorIssues: [String] = []

    // Runs
    var runs: [RunRecord] = []
    var isRunning = false
    var liveLog: String = ""
    /// What the progress bar at the bottom of the window says is running (plan name, snapshot, audit).
    var runTitle: String = ""
    var runProgress: RunProgress? = nil
    var selectedRunID: UUID? = nil

    // Snapshot
    var accessibilityTree: String? = nil
    var isCapturingSnapshot = false

    // HIG
    var isAuditing = false
    var selectedAuditID: String? = nil
    var lastReviewedAudits: [HIGAuditReport] = []

    // Claude
    let claude = ClaudeSession()
    private let inbox = PlanInbox()
    var inboxNotice: String? = nil

    // Navigation request from a detail view (e.g. "Review in HIG tab")
    var pendingSection: SidebarSection? = nil

    // Errors
    var errorMessage: String? = nil

    var selectedDevice: DeviceTarget? { devices.first { $0.id == selectedDeviceID } }
    var selectedPlan: PlanFile? { plans.first { $0.id == selectedPlanID } }
    var runnerProjectURL: URL { URL(fileURLWithPath: (runnerProjectPath as NSString).expandingTildeInPath) }
    var devicesForPlatform: [DeviceTarget] { devices.filter { $0.platform == platform } }

    /// Every HIG audit from every run, newest first.
    var higAudits: [HIGAuditEntry] {
        runs.flatMap { run in
            (run.outcome.report?.higAudits ?? []).map {
                HIGAuditEntry(runID: run.id, startedAt: run.startedAt, outputDirectory: run.outcome.outputDirectory, report: $0)
            }
        }
    }
    var selectedAudit: HIGAuditEntry? { higAudits.first { $0.id == selectedAuditID } }

    init() {
        startInbox()
        Task { await refreshDevices() }
        reloadPlans()
        runs = RunOutcome.loadPast().map { RunRecord(startedAt: $0.report?.startedAt ?? Date(), outcome: $0) }
    }

    // MARK: Devices

    func refreshDevices() async {
        isLoadingDevices = true
        defer { isLoadingDevices = false }
        do {
            devices = try await SimctlService.listDevices()
            if selectedDeviceID == nil || !devices.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = devicesForPlatform.first(where: { $0.isBooted })?.id ?? devicesForPlatform.first?.id
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func bootSelectedDevice() async {
        guard let dev = selectedDevice, !dev.isHostMac else { return }
        do {
            try await SimctlService.boot(udid: dev.udid)
            await SimctlService.openSimulatorApp()
            await refreshDevices()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func loadInstalledApps() async {
        guard let dev = selectedDevice, !dev.isHostMac else { installedApps = []; return }
        installedApps = await SimctlService.installedApps(udid: dev.udid)
    }

    // MARK: Plans

    func reloadPlans() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Paths.plans, includingPropertiesForKeys: nil)) ?? []
        plans = urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            do {
                let plan = try TestPlan.decode(Data(contentsOf: url))
                return PlanFile(url: url, plan: plan, parseError: nil)
            } catch {
                return PlanFile(url: url, plan: nil, parseError: String(describing: error))
            }
        }
        if selectedPlanID == nil { selectedPlanID = plans.first?.id }
        loadEditor()
    }

    func loadEditor() {
        guard let file = selectedPlan else { editorText = ""; editorIssues = []; return }
        editorText = (try? String(contentsOf: file.url, encoding: .utf8)) ?? ""
        validateEditor()
    }

    func validateEditor() {
        do {
            let plan = try TestPlan.decode(json: editorText)
            editorIssues = plan.validate()
        } catch {
            editorIssues = ["JSON error: \(error.localizedDescription) — \(String(describing: error))"]
        }
    }

    func saveEditor() {
        guard let file = selectedPlan else { return }
        do {
            try editorText.write(to: file.url, atomically: true, encoding: .utf8)
            reloadPlans()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func createPlan(_ plan: TestPlan? = nil, select: Bool = true) {
        let newPlan = plan ?? TestPlan(name: "New plan", platform: platform,
                                       bundleIdentifier: bundleIdentifier.isEmpty ? "com.example.MyApp" : bundleIdentifier,
                                       steps: [.assertExists(ElementQuery(label: "Change me"), timeout: 5)])
        let safe = newPlan.name.replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
        var url = Paths.plans.appendingPathComponent("\(safe).json")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = Paths.plans.appendingPathComponent("\(safe)-\(n).json")
            n += 1
        }
        do {
            try newPlan.encoded().write(to: url)
            reloadPlans()
            if select { selectedPlanID = url; loadEditor() }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func deleteSelectedPlan() {
        guard let file = selectedPlan else { return }
        try? FileManager.default.removeItem(at: file.url)
        selectedPlanID = nil
        reloadPlans()
    }

    // MARK: Running

    func runEditorPlan() async {
        do {
            let plan = try TestPlan.decode(json: editorText)
            await run(plan: plan)
        } catch {
            errorMessage = "Plan JSON is invalid: \(error)"
        }
    }

    private func beginLog(title: String) {
        liveLog = ""
        runTitle = title
        runProgress = nil
    }

    private func appendLog(_ chunk: String) {
        liveLog.append(chunk)
        // Only the tail can hold a newer step line; scanning the whole log on every chunk would be quadratic.
        if let latest = RunProgress.latest(in: liveLog.suffix(4000)) { runProgress = latest }
    }

    func run(plan: TestPlan) async {
        guard !isRunning else { return }
        isRunning = true
        beginLog(title: plan.name)
        defer { isRunning = false }
        let destination = plan.destination ?? selectedDevice?.destination
        let runner = runnerProjectURL
        do {
            let outcome = try await XcodebuildService.run(plan: plan, destination: destination, runnerProject: runner) { [weak self] chunk in
                Task { @MainActor in self?.appendLog(chunk) }
            }
            let record = RunRecord(startedAt: Date(), outcome: outcome)
            runs.insert(record, at: 0)
            selectedRunID = record.id
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func captureSnapshot() async {
        guard !bundleIdentifier.isEmpty else { errorMessage = "Enter the target app's bundle identifier first."; return }
        isCapturingSnapshot = true
        beginLog(title: String(localized: "Accessibility snapshot"))
        defer { isCapturingSnapshot = false }
        do {
            let (tree, outcome) = try await XcodebuildService.captureSnapshot(
                platform: platform, bundleIdentifier: bundleIdentifier,
                destination: selectedDevice?.destination, runnerProject: runnerProjectURL) { [weak self] chunk in
                    Task { @MainActor in self?.appendLog(chunk) }
                }
            accessibilityTree = tree
            runs.insert(RunRecord(startedAt: Date(), outcome: outcome), at: 0)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: HIG

    /// Launch the target app and audit its first screen. Deeper screens come from plans with `higAudit` steps.
    func auditFirstScreen() async {
        guard !bundleIdentifier.isEmpty else { errorMessage = "Enter the target app's bundle identifier first."; return }
        guard !isRunning, !isAuditing else { return }
        isAuditing = true
        isRunning = true
        beginLog(title: String(localized: "First screen HIG audit"))
        defer { isAuditing = false; isRunning = false }
        do {
            let (audit, tree, outcome) = try await XcodebuildService.auditFirstScreen(
                platform: platform, bundleIdentifier: bundleIdentifier,
                destination: selectedDevice?.destination, runnerProject: runnerProjectURL) { [weak self] chunk in
                    Task { @MainActor in self?.appendLog(chunk) }
                }
            if let tree { accessibilityTree = tree }
            let record = RunRecord(startedAt: Date(), outcome: outcome)
            runs.insert(record, at: 0)
            selectedRunID = record.id
            selectedAuditID = HIGAuditEntry(runID: record.id, startedAt: record.startedAt, outputDirectory: outcome.outputDirectory, report: audit).id
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Hand one or more audits to Claude in "Review HIG compliance" mode.
    func askClaudeToReviewHIG(_ reports: [HIGAuditReport]) {
        claude.mode = .hig
        lastReviewedAudits = reports
        if claude.goal.isEmpty {
            claude.goal = "Does this app violate Apple's Human Interface Guidelines? Review the automatic findings, drop false positives, add what the rules cannot see, and propose a plan to audit the remaining screens."
        }
        buildPrompt(higReports: reports)
    }

    // MARK: Claude

    func buildPrompt(previousPlan: TestPlan? = nil, failedReport: RunReport? = nil, higReports: [HIGAuditReport]? = nil) {
        let audits = higReports ?? (claude.mode == .hig ? lastReviewedAudits : [])
        let ctx = PromptContext(mode: claude.mode,
                                goal: claude.goal,
                                platform: platform,
                                bundleIdentifier: bundleIdentifier,
                                devices: devices,
                                selectedDevice: selectedDevice,
                                accessibilityTree: claude.includeSnapshot ? accessibilityTree : nil,
                                extraContext: claude.extraContext,
                                answers: claude.answers,
                                previousPlan: previousPlan,
                                failedReport: failedReport,
                                higReports: audits)
        claude.prompt = PromptBuilder.build(ctx)
    }

    func sendPromptToClaude() async {
        if claude.prompt.isEmpty { buildPrompt() }
        claude.isBusy = true
        claude.log = ""
        defer { claude.isBusy = false }
        do {
            let response = try await ClaudeCLI.send(prompt: claude.prompt, resumeSession: claude.sessionId) { [weak self] chunk in
                Task { @MainActor in self?.claude.log.append(chunk) }
            }
            claude.sessionId = response.sessionId
            claude.lastResponseText = response.text
            apply(reply: response.reply)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// For when the developer ran Claude Code themselves and pasted the answer.
    func applyPastedReply() {
        let reply = ClaudeCLI.parse(claude.pastedReply)
        claude.lastResponseText = claude.pastedReply
        apply(reply: reply)
    }

    private func apply(reply: AssistantReply) {
        claude.reply = reply
        claude.pendingQuestions = []
        claude.proposedPlan = nil
        claude.proposedNotes = nil
        switch reply {
        case .plan(let plan, let notes):
            claude.proposedPlan = plan
            claude.proposedNotes = notes
        case .questions(let qs):
            claude.pendingQuestions = qs
        case .explanation(_, let suggested, let qs):
            claude.pendingQuestions = qs
            if let suggested, claude.goal.isEmpty { claude.goal = suggested }
        case .higReview(let review):
            claude.proposedPlan = review.nextPlan
            claude.proposedNotes = review.summary
        case .unsupported, .prose:
            break
        }
    }

    /// Developer answered Claude's questions → fold answers into the prompt and continue the session.
    func submitAnswers() async {
        for q in claude.pendingQuestions {
            if let a = claude.answers[q.id], !a.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            claude.answers[q.id] = claude.answers[q.id] ?? ""
        }
        if claude.mode == .explain { claude.mode = .plan }
        buildPrompt(previousPlan: claude.proposedPlan)
        await sendPromptToClaude()
    }

    func askClaudeToDiagnose(_ outcome: RunOutcome) {
        guard let report = outcome.report else { return }
        let planURL = URL(fileURLWithPath: outcome.outputDirectory).appendingPathComponent("plan.json")
        let plan = try? TestPlan.decode(Data(contentsOf: planURL))
        claude.mode = .diagnose
        if claude.goal.isEmpty { claude.goal = "The plan below failed. Decide whether the plan or the app is wrong and return a corrected plan." }
        buildPrompt(previousPlan: plan, failedReport: report)
    }

    func importProposedPlan(andRun: Bool) async {
        guard let plan = claude.proposedPlan else { return }
        createPlan(plan, select: true)
        if andRun { await run(plan: plan) }
    }

    func resetClaudeSession() {
        lastReviewedAudits = []
        claude.sessionId = nil
        claude.reply = nil
        claude.pendingQuestions = []
        claude.answers = [:]
        claude.proposedPlan = nil
        claude.proposedNotes = nil
        claude.lastResponseText = ""
        claude.prompt = ""
    }

    // MARK: Inbox

    private func startInbox() {
        inbox.start(onPlan: { [weak self] plan, url in
            Task { @MainActor in
                guard let self else { return }
                self.createPlan(plan, select: true)
                self.inboxNotice = "Imported \"\(plan.name)\" from \(url.lastPathComponent)"
                try? FileManager.default.removeItem(at: url)
            }
        }, onError: { [weak self] url, error in
            Task { @MainActor in self?.inboxNotice = "Ignored \(url.lastPathComponent): \(error)" }
        })
    }
}
