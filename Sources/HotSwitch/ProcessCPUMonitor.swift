import Foundation

/// A process that has stayed at or above the CPU threshold.
struct CPUHog: Equatable {
    let pid: Int32
    let name: String
    let percent: Double      // latest sample, 100% = one full core
    let duration: TimeInterval
}

/// Samples per-process CPU usage via `/bin/ps` (setuid root, so it sees every process).
/// Usage is computed from the change in cumulative CPU time between samples, so it is an
/// instantaneous value (not ps's decaying %cpu average).
actor ProcessCPUMonitor {
    private var lastTimes: [Int32: Double] = [:]
    private var lastSampleDate: Date?
    /// Streak start per pid, and how many consecutive samples it has been below the threshold.
    private var aboveSince: [Int32: (since: Date, misses: Int)] = [:]
    /// Samples a process may dip below the threshold without losing its streak
    /// (a single-threaded process at full load often measures 99.x%).
    private let allowedMisses = 1
    /// ps reports CPU time in 0.01s steps, so allow ~1 percentage point of measurement error.
    private let tolerance = 1.0

    /// Takes a sample and returns the top process (highest usage) plus the hog that has stayed
    /// above `threshold` the longest.
    func sample(threshold: Double) -> (top: CPUHog?, hog: CPUHog?) {
        let now = Date()
        guard let snapshot = Self.readProcesses() else { return (nil, nil) }
        defer {
            lastTimes = snapshot.mapValues(\.cpuSeconds)
            lastSampleDate = now
        }
        guard let last = lastSampleDate else { return (nil, nil) }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0.2 else { return (nil, nil) }

        var top: CPUHog?
        var hog: CPUHog?
        var stillAbove: [Int32: (since: Date, misses: Int)] = [:]
        for (pid, p) in snapshot {
            guard let prev = lastTimes[pid], p.cpuSeconds >= prev else { continue }
            let percent = (p.cpuSeconds - prev) / elapsed * 100
            if percent > (top?.percent ?? 0) {
                top = CPUHog(pid: pid, name: p.name, percent: percent, duration: 0)
            }
            let since: Date
            if percent >= threshold - tolerance {
                // The delta covers the previous interval, so count it when the streak starts.
                since = aboveSince[pid]?.since ?? last
                stillAbove[pid] = (since, 0)
            } else if let streak = aboveSince[pid], streak.misses < allowedMisses {
                since = streak.since
                stillAbove[pid] = (since, streak.misses + 1)
            } else {
                continue
            }
            let candidate = CPUHog(pid: pid, name: p.name, percent: percent, duration: now.timeIntervalSince(since))
            if candidate.duration > (hog?.duration ?? -1) { hog = candidate }
        }
        aboveSince = stillAbove
        return (top, hog)
    }

    private struct ProcInfo { let cpuSeconds: Double; let name: String }

    private static func readProcesses() -> [Int32: ProcInfo]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aceo", "pid=,time=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }

        var result: [Int32: ProcInfo] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 2, let pid = Int32(parts[0]), let secs = parseTime(parts[1]) else { continue }
            let name = parts.count > 2 ? String(parts[2]) : "?"
            result[pid] = ProcInfo(cpuSeconds: secs, name: name)
        }
        return result
    }

    /// Parses ps `time` format: [[dd-]hh:]mm:ss.cc
    private static func parseTime(_ s: Substring) -> Double? {
        var days = 0.0
        var rest = s
        if let dash = rest.firstIndex(of: "-") {
            guard let d = Double(rest[..<dash]) else { return nil }
            days = d
            rest = rest[rest.index(after: dash)...]
        }
        var total = 0.0
        for comp in rest.split(separator: ":") {
            guard let v = Double(comp) else { return nil }
            total = total * 60 + v
        }
        return total + days * 86400
    }
}
