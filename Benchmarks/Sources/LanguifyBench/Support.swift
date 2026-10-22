import Darwin
import Foundation

/// Metadata captured with every run so results are reproducible and never
/// mixed across environments.
struct RunMetadata: Codable {
    let benchmark: String
    let runID: String
    let timestamp: String
    let gitCommit: String
    let gitDirty: Bool
    let machine: String
    let chip: String
    let memoryGB: Int
    let osVersion: String
    let buildConfiguration: String
    let environment: String
    let notes: [String]

    static func capture(benchmark: String, environment: String, notes: [String] = []) -> RunMetadata {
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now)
        let compact = stamp.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        #if DEBUG
        let config = "debug"
        #else
        let config = "release"
        #endif
        return RunMetadata(
            benchmark: benchmark,
            runID: "\(benchmark)-\(compact)",
            timestamp: stamp,
            gitCommit: shell("git rev-parse --short HEAD"),
            gitDirty: !shell("git status --porcelain -- ../Packages ../Benchmarks ../backend/src").isEmpty,
            machine: sysctlString("hw.model"),
            chip: sysctlString("machdep.cpu.brand_string"),
            memoryGB: Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            buildConfiguration: config,
            environment: environment,
            notes: notes
        )
    }
}

func sysctlString(_ name: String) -> String {
    var size = 0
    sysctlbyname(name, nil, &size, nil, 0)
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &buffer, &size, nil, 0)
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

@discardableResult
func shell(_ command: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Physical memory footprint of this process in bytes (what Xcode's memory
/// gauge and jetsam use on iOS).
func physFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

/// Heap blocks and bytes currently in use in the default malloc zone.
func mallocStats() -> (blocks: Int, bytes: Int) {
    var stats = malloc_statistics_t()
    malloc_zone_statistics(nil, &stats)
    return (Int(stats.blocks_in_use), Int(stats.size_in_use))
}

/// Process CPU time (user + system) in seconds.
func cpuTime() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
}

@inline(never)
func blackHole<T>(_ value: T) {
    withExtendedLifetime(value) {}
}

/// Times `body` once and returns nanoseconds.
@inline(__always)
func timeNs(_ body: () -> Void) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    return Double(DispatchTime.now().uptimeNanoseconds - start)
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let sorted = values.sorted()
    let rank = p / 100 * Double(sorted.count - 1)
    let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - Double(lo))
}

struct Summary: Codable {
    let n: Int
    let mean: Double
    let p50: Double
    let p90: Double
    let p95: Double
    let p99: Double
    let min: Double
    let max: Double
    let stddev: Double

    init(_ values: [Double]) {
        n = values.count
        mean = values.reduce(0, +) / Double(Swift.max(values.count, 1))
        p50 = percentile(values, 50)
        p90 = percentile(values, 90)
        p95 = percentile(values, 95)
        p99 = percentile(values, 99)
        min = values.min() ?? .nan
        max = values.max() ?? .nan
        let m = mean
        stddev = (values.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(Swift.max(values.count - 1, 1))).squareRoot()
    }
}

/// Writes a result document to Results/Raw/<category>/<runID>.json, never
/// overwriting earlier runs.
func writeResult<T: Encodable>(_ value: T, category: String, runID: String) throws -> URL {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent()
    let dir = root.appending(path: "Results/Raw/\(category)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appending(path: "\(runID).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
    try encoder.encode(value).write(to: url)
    return url
}
