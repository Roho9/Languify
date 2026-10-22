# Reproducing the benchmarks

All commands run from the repository root unless noted. Results are written to `Results/Raw/<category>/<runID>.json` with metadata and never overwrite earlier runs.

## Requirements

- macOS 26 or later on Apple silicon, Xcode 26 (Swift 6.2), Python 3 (standard library only), Node 22.
- Apple speech models for `ta-IN` and `en-IN` (downloaded automatically on first use).
- Ollama with `gemma3:27b` for AI benchmarks (`brew install ollama && brew services start ollama && ollama pull gemma3:27b`).
- Close other heavy apps; do not run AI and speech benchmarks at the same time (they compete for the GPU and Neural Engine).

## 1. Fast local tests (deterministic, used by CI)

```bash
(cd Packages/LanguifyKit && swift test)
(cd Benchmarks && swift test)
(cd backend && npm ci && npm run typecheck && npm run typecheck:bench && npm test)
```

## 2. Live Rewind buffer

```bash
cd Benchmarks
swift run -c release LanguifyBench buffer          # full: 4 implementations, 3 windows, 2 chunk sizes, 60 min sustained
swift run -c release LanguifyBench buffer --quick  # about 1 minute
swift run -c release LanguifyBench memprobe        # memory, one fresh process per measurement
```

Run `buffer` three times to see run-to-run variation.

## 3. Tamil speech recognition

```bash
python3 -I Benchmarks/scripts/make_asr_dataset.py        # 560 synthetic clips (about 1.5 min)
python3 -I Benchmarks/scripts/make_window_dataset.py     # 40 rewind windows
cd Benchmarks
swift run -c release LanguifyBench asr                   # all 560 clips, ta-IN + en-IN in parallel (about 5 min)
swift run -c release LanguifyBench asr --manifest BenchmarkData/Manifests/asr_windows_v1.json --locales ta-IN
swift run -c release LanguifyBench asr-profile           # stage breakdown of one request
swift run -c release LanguifyBench asr-variants          # transcriber configuration comparison
cd ..
python3 -I Benchmarks/scripts/score_asr.py               # newest full run -> Results/Aggregated
```

Experiments D and E:

```bash
cd Benchmarks
swift run -c release LanguifyBench asr --manifest BenchmarkData/Manifests/asr_windows_v1.json --buffer   # baseline arm
swift run -c release LanguifyBench asr --manifest BenchmarkData/Manifests/asr_windows_v1.json --vad      # trimming arm
swift run -c release LanguifyBench asr --manifest BenchmarkData/Manifests/asr_tamil_synthetic_v1_clean_normal.json --sequential
cd ..
python3 -I Benchmarks/scripts/compare_asr.py Results/Raw/asr/<baseline>.json Results/Raw/asr/<candidate>.json <label>
```

To benchmark real recordings (for example consented Malayalam), add sentences to a new annotation file, point a manifest at the audio, and run the same commands.

## 4. AI evaluation (local Gemma 3 27B, free)

```bash
cd backend
npx tsx bench/context-eval.ts                  # 98 labelled cases, about 30 min
npx tsx bench/prompt-experiment.ts --cases 20  # experiment C, about 15 min
npx tsx bench/context-eval.ts --provider claude   # needs ANTHROPIC_API_KEY
```

Review sheets for human scoring are written to `Results/Reviews/`.

## 5. Backend load

```bash
cd backend
npx tsx bench/load-test.ts --ai mock --mock-latency 300 --stages 1,10,25,50,100,200 --seconds 10
npx tsx bench/load-test.ts --ai real --stages 1,2,4,8 --requests-per-worker 2                       # no limiter
npx tsx bench/load-test.ts --ai real --stages 1,2,4,8 --requests-per-worker 2 --limit 1 --queue 2 --wait 20000
```

Never point the load test at a paid provider without a cost limit.

## 6. Privacy, regression and reports

```bash
python3 -I Benchmarks/scripts/privacy_checks.py         # needs a simulator build in .build/DerivedData
python3 -I Benchmarks/scripts/check_regressions.py
python3 -I Benchmarks/scripts/report.py                 # Results/Reports/dashboard.html
```
