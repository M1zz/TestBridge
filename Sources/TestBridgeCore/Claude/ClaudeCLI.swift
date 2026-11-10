import Foundation

public struct ClarifyingQuestion: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var question: String
    public var why: String?
    public var example: String?

    public init(id: String, question: String, why: String? = nil, example: String? = nil) {
        self.id = id
        self.question = question
        self.why = why
        self.example = example
    }
}

/// Parsed reply from Claude, independent of transport (CLI, clipboard paste, inbox file).
public enum AssistantReply: Sendable, Hashable {
    case plan(TestPlan, notes: String?)
    case questions([ClarifyingQuestion])
    case explanation(approach: String, suggestedPrompt: String?, questions: [ClarifyingQuestion])
    case higReview(HIGReview)
    case unsupported(reason: String, alternative: String?)
    case prose(String)

    public var kindLabel: String {
        switch self {
        case .plan: return "plan"
        case .questions: return "questions"
        case .explanation: return "explanation"
        case .higReview: return "HIG review"
        case .unsupported: return "unsupported"
        case .prose: return "prose"
        }
    }
}

public struct ClaudeResponse: Sendable {
    public var text: String
    public var sessionId: String?
    public var raw: String
    public var reply: AssistantReply
}

/// Drives the `claude` CLI headlessly (`claude -p --output-format json`) and parses replies.
public enum ClaudeCLI {
    private struct Envelope: Decodable {
        let kind: String?
        let plan: TestPlan?
        let notes: String?
        let questions: [ClarifyingQuestion]?
        let approach: String?
        let suggestedPrompt: String?
        let reason: String?
        let alternative: String?
        let verdict: String?
        let summary: String?
        let findings: [HIGReviewFinding]?
        let nextPlan: TestPlan?
    }

    private struct CLIOutput: Decodable {
        let result: String?
        let session_id: String?
        let is_error: Bool?
    }

    public static func locate() async -> String? {
        await ShellRunner.which("claude")
    }

    /// Sends a prompt. Pass `resumeSession` to continue a previous headless conversation.
    public static func send(prompt: String,
                            resumeSession: String? = nil,
                            model: String? = nil,
                            workingDirectory: URL? = nil,
                            log: (@Sendable (String) -> Void)? = nil) async throws -> ClaudeResponse {
        guard await locate() != nil else {
            throw ShellError(description: "`claude` CLI not found in your login shell PATH. Install Claude Code or copy the prompt manually.")
        }
        var cmd = "claude -p --output-format json"
        if let resumeSession, !resumeSession.isEmpty { cmd += " --resume \(ShellRunner.shellQuote(resumeSession))" }
        if let model, !model.isEmpty { cmd += " --model \(ShellRunner.shellQuote(model))" }

        log?("$ \(cmd)  (prompt via stdin, \(prompt.count) chars)\n")
        let result = try await ShellRunner.runInLoginShell(cmd, stdin: Data(prompt.utf8), currentDirectory: workingDirectory, onOutput: log)
        guard result.succeeded else {
            throw ShellError(description: "claude exited with \(result.exitCode): \(result.stderr.isEmpty ? result.stdout : result.stderr)")
        }

        let raw = result.stdout
        var text = raw
        var sessionId: String? = nil
        if let data = raw.data(using: .utf8), let out = try? JSONDecoder().decode(CLIOutput.self, from: data) {
            text = out.result ?? raw
            sessionId = out.session_id
            if out.is_error == true {
                throw ShellError(description: "claude reported an error: \(text)")
            }
        }
        return ClaudeResponse(text: text, sessionId: sessionId, raw: raw, reply: parse(text))
    }

    /// Parses Claude's reply (or anything the user pasted) into a typed `AssistantReply`.
    public static func parse(_ text: String) -> AssistantReply {
        guard let json = extractJSONObject(from: text), let data = json.data(using: .utf8) else {
            return .prose(text)
        }
        let decoder = JSONDecoder()
        if let env = try? decoder.decode(Envelope.self, from: data) {
            switch env.kind {
            case "plan":
                if let plan = env.plan { return .plan(plan, notes: env.notes) }
            case "questions":
                if let qs = env.questions { return .questions(qs) }
            case "explanation":
                if let approach = env.approach {
                    return .explanation(approach: approach, suggestedPrompt: env.suggestedPrompt, questions: env.questions ?? [])
                }
            case "higReview", "hig", "review":
                let verdict = env.verdict.flatMap { HIGReview.Verdict(rawValue: $0.lowercased()) }
                    ?? ((env.findings ?? []).contains { $0.severity == .error } ? .fail
                        : (env.findings ?? []).isEmpty ? .pass : .needsWork)
                return .higReview(HIGReview(verdict: verdict,
                                            summary: env.summary ?? "",
                                            findings: env.findings ?? [],
                                            nextPlan: env.nextPlan))
            case "unsupported":
                if let reason = env.reason { return .unsupported(reason: reason, alternative: env.alternative) }
            default:
                break
            }
        }
        // Claude (or a human) may paste a bare plan.
        if let plan = try? decoder.decode(TestPlan.self, from: data) {
            return .plan(plan, notes: nil)
        }
        return .prose(text)
    }

    /// Pulls the first balanced `{ … }` out of text that may contain fences or prose.
    static func extractJSONObject(from text: String) -> String? {
        var s = text
        if let fenceStart = s.range(of: "```") {
            let afterFence = s[fenceStart.upperBound...]
            if let newline = afterFence.firstIndex(of: "\n") {
                let body = afterFence[afterFence.index(after: newline)...]
                if let fenceEnd = body.range(of: "```") {
                    s = String(body[..<fenceEnd.lowerBound])
                }
            }
        }
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var idx = start
        while idx < s.endIndex {
            let ch = s[idx]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return String(s[start...idx]) }
                default: break
                }
            }
            idx = s.index(after: idx)
        }
        return nil
    }
}
