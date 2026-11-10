import Foundation

public struct ShellResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == 0 }
    public var combinedOutput: String { stderr.isEmpty ? stdout : stdout + "\n" + stderr }
}

public struct ShellError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(description: String) { self.description = description }
}

/// Runs subprocesses with streaming output. Everything TestBridge does on the host
/// (xcrun, xcodebuild, claude, xcodegen) goes through here.
public enum ShellRunner {
    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var out = ""
        private var err = ""

        func appendOut(_ s: String) { lock.lock(); out += s; lock.unlock() }
        func appendErr(_ s: String) { lock.lock(); err += s; lock.unlock() }
        var snapshot: (String, String) { lock.lock(); defer { lock.unlock() }; return (out, err) }
    }

    public static func run(_ executable: String,
                           _ arguments: [String] = [],
                           environment: [String: String]? = nil,
                           currentDirectory: URL? = nil,
                           stdin: Data? = nil,
                           onOutput: (@Sendable (String) -> Void)? = nil) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            var env = ProcessInfo.processInfo.environment
            environment?.forEach { env[$0.key] = $0.value }
            process.environment = env
            if let currentDirectory { process.currentDirectoryURL = currentDirectory }

            let outPipe = Pipe()
            let errPipe = Pipe()
            let inPipe: Pipe? = stdin == nil ? nil : Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            if let inPipe { process.standardInput = inPipe }

            let collector = OutputCollector()
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self)
                collector.appendOut(text)
                onOutput?(text)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self)
                collector.appendErr(text)
                onOutput?(text)
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let restOut = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let restErr = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if !restOut.isEmpty { collector.appendOut(restOut); onOutput?(restOut) }
                if !restErr.isEmpty { collector.appendErr(restErr); onOutput?(restErr) }
                let (out, err) = collector.snapshot
                continuation.resume(returning: ShellResult(exitCode: proc.terminationStatus, stdout: out, stderr: err))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ShellError(description: "Failed to launch \(executable): \(error.localizedDescription)"))
                return
            }

            if let inPipe, let stdin {
                inPipe.fileHandleForWriting.write(stdin)
                try? inPipe.fileHandleForWriting.close()
            }
        }
    }

    /// Runs a command line through the user's login shell so PATH additions (Homebrew, nvm, …) are honored.
    public static func runInLoginShell(_ commandLine: String,
                                       stdin: Data? = nil,
                                       currentDirectory: URL? = nil,
                                       onOutput: (@Sendable (String) -> Void)? = nil) async throws -> ShellResult {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return try await run(shell, ["-lc", commandLine], currentDirectory: currentDirectory, stdin: stdin, onOutput: onOutput)
    }

    /// Resolves an executable name to a path using the login shell. `nil` if not installed.
    public static func which(_ name: String) async -> String? {
        guard let result = try? await runInLoginShell("command -v \(name)") else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.succeeded && !path.isEmpty ? path : nil
    }

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
