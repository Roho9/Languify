#!/usr/bin/env python3 -I
"""Privacy and security validation: each documented guarantee becomes a
check with a pass/fail result and evidence. Static checks inspect source and
the built app binary; runtime checks run the relevant automated tests.

Usage: python3 -I Benchmarks/scripts/privacy_checks.py [--skip-tests]
Requires a simulator build in .build/DerivedData for the binary checks.
"""
import datetime
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "App/Sources"
results = []


def check(cid, requirement, passed, evidence, kind="static"):
    results.append(dict(id=cid, requirement=requirement, passed=bool(passed), evidence=evidence, kind=kind))
    print(f"{'PASS' if passed else 'FAIL'} {cid} [{kind}] {requirement}\n      {evidence}")


def grep(pattern, root=APP, glob="*.swift"):
    hits = []
    for f in root.rglob(glob):
        for n, line in enumerate(f.read_text(errors="ignore").splitlines(), 1):
            if re.search(pattern, line):
                hits.append(f"{f.relative_to(ROOT)}:{n}: {line.strip()[:120]}")
    return hits


def run(cmd, cwd):
    p = subprocess.run(cmd, cwd=cwd, shell=True, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


# --- Secrets never in the app
app_bin = next(iter(sorted((ROOT / ".build/DerivedData/Build/Products").glob("*-iphonesimulator/Languify.app/Languify"))), None)
if app_bin:
    strings = subprocess.run(["strings", "-a", str(app_bin)], capture_output=True, text=True).stdout
    debug_dylib = app_bin.parent / "Languify.debug.dylib"
    if debug_dylib.exists():
        strings += subprocess.run(["strings", "-a", str(debug_dylib)], capture_output=True, text=True).stdout
    leaked = [p for p in ["sk-ant-", "ANTHROPIC_API_KEY", "LANGUIFY_TOKEN_SECRET", "x-api-key"] if p in strings]
    check("P01", "No AI provider credentials or server secrets in the app binary", not leaked, f"scanned {app_bin.relative_to(ROOT)} (+debug dylib); matches: {leaked or 'none'}")
    bundle_files = [p.name for p in app_bin.parent.rglob("*") if p.name in (".env", ".env.example")]
    check("P02", "No .env files bundled in the app", not bundle_files, f"bundle files matching .env: {bundle_files or 'none'}")
else:
    check("P01", "No AI provider credentials in the app binary", False, "no simulator build found; run xcodebuild build first")

# --- Audio is never persisted
audio_writers = grep(r"AVAudioFile\(forWriting|AVAudioRecorder|AVAssetWriter")
check("P03", "App never writes audio files (no AVAudioFile writing, AVAudioRecorder or AVAssetWriter)", not audio_writers, f"matches: {audio_writers or 'none'}")
disk_writes = grep(r"\.write\(to:|createFile\(atPath|FileHandle\(forWriting")
allowed = [h for h in disk_writes if "AppServices.swift" in h and "export" in h.lower()]
check("P04", "Only disk write in the app is the user-initiated JSON data export", len(disk_writes) == len(allowed) == 1, f"writes: {disk_writes}")
models = (APP / "Persistence/Models.swift").read_text()
data_fields = re.findall(r"var \w+: (?:Data|\[Float\]|\[Int16\])\??", models)
check("P05", "Persisted (and iCloud-synced) models contain no audio-capable fields", not data_fields and "audio" not in models.lower().replace("audio is never stored", "").replace("raw audio is never stored", ""), f"Data/sample-array fields: {data_fields or 'none'}")

# --- Buffer lifecycle
session = (APP / "Audio/ListeningSessionManager.swift").read_text()
stop_body = session[session.index("func stop() async"):session.index("func pause()")]
check("P06", "Stopping a session clears the audio buffer and ends the Live Activity", "buffer.clear()" in stop_body and "liveActivity.end()" in stop_body and "capture.stop()" in stop_body, "ListeningSessionManager.stop() calls capture.stop(), buffer.clear(), liveActivity.end()")
fail_body = session[session.index("} catch {", session.index("private func beginCapture")):session.index("private func handle(")]
check("P07", "A failed capture start clears the buffer and stops the microphone", "buffer.clear()" in fail_body and "capture.stop()" in fail_body, "beginCapture catch path calls capture.stop() and buffer.clear()")
recorder = (APP / "Learning/UtteranceRecorder.swift").read_text()
check("P08", "Practice recordings are discarded after on-device transcription", "buffer.clear()" in recorder[recorder.index("func stopAndTranscribe"):], "UtteranceRecorder.stopAndTranscribe clears its buffer in defer")
check("P09", "Microphone capture only starts from an explicit session or practice action", len(grep(r"capture\.start\(into:")) == 2, f"capture.start call sites: {grep(r'capture\.start\(into:')}")

# --- Telemetry excludes conversation content
sensitive = re.compile(r"\\\((?:[^)]*\b(text|transcript|question|summary|spokenSummary|explanation|segments|heard|word|transliteration|englishMeaning)\b)")
log_lines = [h for h in grep(r"Log\.\w+\.(info|debug|error|notice|fault|warning)\(") if sensitive.search(h)]
check("P10", "App logs never interpolate transcript, question or answer text", not log_lines, f"suspicious log lines: {log_lines or 'none'}")
server_logs = grep(r"log\.(info|warn|error|debug)\(", ROOT / "backend/src", "*.ts")
# Allowed metadata: the language code and the answer status. Anything else
# from the request body or the answer is flagged.
leaky = [h for h in server_logs if re.search(r"\bbody\b(?!\.language)|transcript|question|\bexplanation\b(?!\.status)", h)]
check("P11", "Server log calls never include request bodies or answers", not leaky, f"{len(server_logs)} log calls reviewed; suspicious: {leaky or 'none'}")

# --- Identity and transport
keychain = (APP / "Account/KeychainStore.swift").read_text()
check("P12", "Tokens are stored in the Keychain as device-only items", "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in keychain, "KeychainStore uses AfterFirstUnlockThisDeviceOnly")
info = plistlib.loads(app_bin.parent.joinpath("Info.plist").read_bytes()) if app_bin else {}
ats = info.get("NSAppTransportSecurity", {})
check("P13", "App Transport Security not disabled (no arbitrary loads)", not ats.get("NSAllowsArbitraryLoads", False), f"NSAppTransportSecurity: {ats}")
check("P14", "Microphone purpose string explains buffering and no saving", "never saved or uploaded" in info.get("NSMicrophoneUsageDescription", ""), info.get("NSMicrophoneUsageDescription", "missing"))
manifest = plistlib.loads((ROOT / "App/Resources/PrivacyInfo.xcprivacy").read_bytes())
check("P15", "Privacy manifest declares no tracking and no tracking domains", manifest.get("NSPrivacyTracking") is False and not manifest.get("NSPrivacyTrackingDomains"), "PrivacyInfo.xcprivacy")
rewind = (APP / "Rewind/LiveRewindService.swift").read_text()
consent_pos, request_pos = rewind.find("cloudProcessingConsent else"), rewind.find("api.explain(")
check("P16", "Cloud consent is checked before any explanation request", 0 < consent_pos < request_pos, "LiveRewindService: consent guard precedes api.explain")

# --- Runtime tests
if "--skip-tests" not in sys.argv:
    code, out = run("swift test --filter 'clearDiscardsEverything|repeatedSessionsDoNotLeakAudio|snapshotExcludesAudioAfterRequestTime' 2>&1 | tail -3", ROOT / "Packages/LanguifyKit")
    check("R01", "Buffer is zeroed on clear, never leaks across sessions, and excludes audio after the question", code == 0 and "passed" in out, out.strip().splitlines()[-1] if out.strip() else "no output", "runtime")
    code, out = run("npx vitest run test/privacy.test.ts 2>&1 | grep -E 'Tests'", ROOT / "backend")
    check("R02", "Server logs contain no transcript or answer text, at trace level, on success and failure", code == 0 and "passed" in out and "failed" not in out, out.strip(), "runtime")
    code, out = run("npx vitest run -t 'enforces the free daily quota|locks premium features|rejects missing and forged' 2>&1 | grep -E 'Tests'", ROOT / "backend")
    check("R03", "Usage limits and Premium features are enforced server-side, not by client state", code == 0 and "passed" in out and "failed" not in out, out.strip(), "runtime")
    code, out = run("npx vitest run -t 'deletes all server-side data' 2>&1 | grep -E 'Tests'", ROOT / "backend")
    check("R04", "Account deletion removes all server-side records", code == 0 and "passed" in out and "failed" not in out, out.strip(), "runtime")
    code, out = run(
        "xcodebuild test -project Languify.xcodeproj -scheme Languify -destination 'platform=iOS Simulator,name=iPhone 17 Pro' "
        "-derivedDataPath .build/DerivedData -only-testing:LanguifyTests/LiveRewindServiceTests 2>&1 | grep -E 'Test run|TEST (SUCCEEDED|FAILED)' | tail -2",
        ROOT,
    )
    check("R05", "Without consent no request is sent; silence never reaches the cloud; only text (no samples) is sent", "SUCCEEDED" in out, out.strip().replace("\n", " | "), "runtime")

passed = sum(r["passed"] for r in results)
print(f"\n{passed}/{len(results)} privacy checks passed")
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
dest = ROOT / f"Results/Raw/privacy/privacy-{stamp}.json"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(json.dumps(dict(metadata=dict(benchmark="privacy", runID=f"privacy-{stamp}", gitCommit=commit), passed=passed, total=len(results), checks=results), indent=1))
print(f"Wrote {dest.relative_to(ROOT)}")
sys.exit(0 if passed == len(results) else 1)
