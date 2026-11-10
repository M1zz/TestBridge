import Foundation

/// Watches `~/Library/Application Support/TestBridge/Inbox` for plan files dropped by Claude Code
/// (via `testbridge import` or a plain file write) and hands them to the app.
public final class PlanInbox: @unchecked Sendable {
    public let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var seen: Set<String> = []
    private let queue = DispatchQueue(label: "testbridge.inbox")

    public init(directory: URL = Paths.inbox) {
        self.directory = directory
    }

    deinit { stop() }

    public func start(onPlan: @escaping @Sendable (TestPlan, URL) -> Void,
                      onError: @escaping @Sendable (URL, Error) -> Void) {
        stop()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        seen = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])

        fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: queue)
        src.setEventHandler { [weak self] in
            // Let the writer finish before reading.
            self?.queue.asyncAfter(deadline: .now() + 0.3) { self?.scan(onPlan: onPlan, onError: onError) }
        }
        src.setCancelHandler { [fd] in close(fd) }
        source = src
        src.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        fd = -1
    }

    private func scan(onPlan: @Sendable (TestPlan, URL) -> Void, onError: @Sendable (URL, Error) -> Void) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where !seen.contains(name) && name.hasSuffix(".json") {
            seen.insert(name)
            let url = directory.appendingPathComponent(name)
            do {
                let data = try Data(contentsOf: url)
                switch ClaudeCLI.parse(String(decoding: data, as: UTF8.self)) {
                case .plan(let plan, _):
                    onPlan(plan, url)
                default:
                    throw ShellError(description: "File is not a TestBridge plan (or plan envelope).")
                }
            } catch {
                onError(url, error)
            }
        }
    }

    /// Used by the CLI: copies a plan into the inbox so the running GUI picks it up.
    public static func deposit(_ plan: TestPlan, directory: URL = Paths.inbox) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = plan.name.replacingOccurrences(of: "[^\\p{L}\\p{N}_-]+", with: "-", options: .regularExpression)
        let url = directory.appendingPathComponent("\(Int(Date().timeIntervalSince1970))_\(safe).json")
        try plan.encoded().write(to: url)
        return url
    }
}
