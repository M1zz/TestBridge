import Foundation

/// Which step of a plan is running right now, read from the Runner's `TESTBRIDGE-STEP 7/18 tap …` log lines.
public struct RunProgress: Equatable, Sendable {
    public let step: Int
    public let total: Int
    public let summary: String

    public var fraction: Double { total > 0 ? Double(step - 1) / Double(total) : 0 }

    /// The most recent complete step line in `log`, or nil if the plan has not started stepping yet.
    public static func latest(in log: some StringProtocol) -> RunProgress? {
        for line in log.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard let marker = line.range(of: "TESTBRIDGE-STEP ") else { continue }
            let parts = line[marker.upperBound...].split(separator: " ", maxSplits: 1)
            let counts = parts.first?.split(separator: "/") ?? []
            guard counts.count == 2, let step = Int(counts[0]), let total = Int(counts[1]) else { continue }
            return RunProgress(step: step, total: total, summary: parts.count > 1 ? String(parts[1]) : "")
        }
        return nil
    }
}
