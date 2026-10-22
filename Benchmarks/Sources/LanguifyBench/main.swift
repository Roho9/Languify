import Foundation

// Usage: swift run -c release LanguifyBench <command> [--quick] [--impl name,...]
let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "help"
let quick = args.contains("--quick")
let impls = args.firstIndex(of: "--impl").flatMap { args.index(after: $0) < args.endIndex ? args[args.index(after: $0)] : nil }?
    .split(separator: ",").map(String.init) ?? []

do {
    switch command {
    case "buffer":
        try BufferBench.run(implementations: impls, quick: quick)
    case "memprobe":
        try MemoryProbe.runAll()
    case "memprobe-one":
        let rest = Array(args.dropFirst())
        MemoryProbe.run(implementation: rest[0], seconds: Double(rest[1]) ?? 60)
    case "asr":
        let rest = Array(args.dropFirst())
        func value(_ flag: String) -> String? { rest.firstIndex(of: flag).flatMap { rest.indices.contains($0 + 1) ? rest[$0 + 1] : nil } }
        let manifest = value("--manifest") ?? "BenchmarkData/Manifests/asr_tamil_synthetic_v1.json"
        let locales = (value("--locales") ?? "ta-IN,en-IN").split(separator: ",").map(String.init)
        try await ASRBench.run(manifestPath: manifest, locales: locales, parallel: !rest.contains("--sequential"), limit: value("--limit").flatMap(Int.init), inputMode: rest.contains("--vad") || rest.contains("--buffer") ? "buffer" : "file", vad: rest.contains("--vad"))
    case "asr-profile":
        let rest = Array(args.dropFirst())
        try await ASRProfile.run(path: rest.first ?? "BenchmarkData/Audio/asr_tamil_synthetic_v1/ta-001_normal.wav", iterations: 21)
    case "asr-variants":
        let rest = Array(args.dropFirst())
        try await ASRVariants.run(path: rest.first ?? "BenchmarkData/Audio/asr_tamil_synthetic_v1/ta-001_normal.wav", iterations: 11)
    default:
        print("Commands: buffer, memprobe, asr, asr-profile, asr-variants")
    }
} catch {
    print("Benchmark failed: \(error)")
    exit(1)
}
