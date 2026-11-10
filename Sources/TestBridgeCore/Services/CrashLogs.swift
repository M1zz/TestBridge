import Foundation

/// Copies the crash reports macOS wrote for the target app during a run into the run's folder, so a crash found
/// by a plan comes with its stack trace. Simulator and Mac apps both report to `~/Library/Logs/DiagnosticReports`.
public enum CrashLogs {
    @discardableResult
    public static func collect(bundleIdentifier: String, since: Date, into directory: URL,
                               reports: URL = FileManager.default.homeDirectoryForCurrentUser
                                   .appendingPathComponent("Library/Logs/DiagnosticReports")) -> [URL] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "ips" }.compactMap { file -> URL? in
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            // The report is written a moment after the crash; a few seconds of slack covers clock rounding.
            guard let modified, modified >= since.addingTimeInterval(-5),
                  let handle = try? FileHandle(forReadingFrom: file) else { return nil }
            defer { try? handle.close() }
            // The first line of an .ips file is a JSON header naming the crashed app's bundle identifier.
            let header = String(decoding: handle.readData(ofLength: 2000), as: UTF8.self)
            guard header.contains("\"\(bundleIdentifier)\"") else { return nil }
            let copy = directory.appendingPathComponent("crash-\(file.lastPathComponent)")
            try? fm.removeItem(at: copy)
            return (try? fm.copyItem(at: file, to: copy)) != nil ? copy : nil
        }
    }
}
