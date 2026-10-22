#!/usr/bin/env python3 -I
"""Builds Results/Reports/dashboard.html and Results/Aggregated/summary.json
from the raw benchmark results. Every number is read from a result file;
anything without a valid measurement is shown as "Not measured".

Usage: python3 -I Benchmarks/scripts/report.py
"""
import datetime
import html
import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from stats import mean, percentile  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "Results/Raw"
AGG = ROOT / "Results/Aggregated"


def load_all(category):
    return [json.loads(p.read_text()) for p in sorted((RAW / category).glob("*.json"))] if (RAW / category).exists() else []


def esc(x):
    return html.escape(str(x))


# ---------- SVG charts (no dependencies) ----------

PALETTE = ["#2a6f97", "#c8553d", "#6a994e", "#8d6a9f", "#d4a017", "#5c677d"]


def bar_chart(categories, series, unit="", width=640, height=260, log=False, fmt="{:.1f}"):
    """series: [(name, [values])]. Grouped bars."""
    import math
    pad_l, pad_b, pad_t = 60, 46, 16
    w, h = width - pad_l - 10, height - pad_b - pad_t
    vals = [v for _, vs in series for v in vs if v is not None and v == v]
    vmax = max(vals) if vals else 1
    vmin_pos = min([v for v in vals if v > 0], default=1)
    def y(v):
        if v is None or v != v:
            return None
        if log:
            lo, hi = math.log10(vmin_pos / 2), math.log10(vmax * 1.2)
            return pad_t + h - (math.log10(max(v, vmin_pos / 2)) - lo) / (hi - lo) * h
        return pad_t + h - v / (vmax * 1.12) * h
    group_w = w / max(1, len(categories))
    bar_w = group_w * 0.8 / max(1, len(series))
    out = [f'<svg viewBox="0 0 {width} {height}" class="chart" role="img">']
    for t in range(5):
        if log:
            lo, hi = math.log10(vmin_pos / 2), math.log10(vmax * 1.2)
            v = 10 ** (lo + (hi - lo) * t / 4)
        else:
            v = vmax * 1.12 * t / 4
        yy = y(v)
        out.append(f'<line x1="{pad_l}" x2="{pad_l + w}" y1="{yy:.1f}" y2="{yy:.1f}" class="grid"/><text x="{pad_l - 6}" y="{yy + 4:.1f}" class="axis" text-anchor="end">{fmt.format(v)}</text>')
    for i, cat in enumerate(categories):
        gx = pad_l + i * group_w + group_w * 0.1
        for j, (name, vs) in enumerate(series):
            v = vs[i]
            yy = y(v)
            if yy is None:
                out.append(f'<text x="{gx + j * bar_w + bar_w / 2:.1f}" y="{pad_t + h - 4}" class="na" text-anchor="middle">n/a</text>')
                continue
            out.append(f'<rect x="{gx + j * bar_w:.1f}" y="{yy:.1f}" width="{bar_w - 2:.1f}" height="{pad_t + h - yy:.1f}" fill="{PALETTE[j % len(PALETTE)]}"><title>{esc(name)} {esc(cat)}: {fmt.format(v)}{unit}</title></rect>')
        out.append(f'<text x="{pad_l + i * group_w + group_w / 2:.1f}" y="{pad_t + h + 16}" class="axis" text-anchor="middle">{esc(cat)}</text>')
    lx = pad_l
    for j, (name, _) in enumerate(series):
        out.append(f'<rect x="{lx}" y="{height - 14}" width="10" height="10" fill="{PALETTE[j % len(PALETTE)]}"/><text x="{lx + 14}" y="{height - 5}" class="axis">{esc(name)}</text>')
        lx += 14 + 7 * len(name) + 18
    out.append(f'<text x="12" y="{pad_t + h / 2}" class="axis" transform="rotate(-90 12 {pad_t + h / 2})" text-anchor="middle">{esc(unit)}</text></svg>')
    return "".join(out)


def line_chart(xs, series, unit="", width=640, height=260, ymax=None, fmt="{:.0f}", xlabels=None):
    """series: [(name, [values], [(lo, hi)] or None)]."""
    pad_l, pad_b, pad_t = 60, 46, 16
    w, h = width - pad_l - 16, height - pad_b - pad_t
    vals = [v for _, vs, ci in series for v in vs if v is not None] + [c[1] for _, _, ci in series if ci for c in ci if c]
    top = ymax if ymax is not None else (max(vals) * 1.1 if vals else 1)
    x = lambda i: pad_l + (i / max(1, len(xs) - 1)) * w
    y = lambda v: pad_t + h - (v / top) * h
    out = [f'<svg viewBox="0 0 {width} {height}" class="chart" role="img">']
    for t in range(5):
        v = top * t / 4
        out.append(f'<line x1="{pad_l}" x2="{pad_l + w}" y1="{y(v):.1f}" y2="{y(v):.1f}" class="grid"/><text x="{pad_l - 6}" y="{y(v) + 4:.1f}" class="axis" text-anchor="end">{fmt.format(v)}</text>')
    for i, label in enumerate(xlabels or xs):
        out.append(f'<text x="{x(i):.1f}" y="{pad_t + h + 16}" class="axis" text-anchor="middle">{esc(label)}</text>')
    for j, (name, vs, ci) in enumerate(series):
        color = PALETTE[j % len(PALETTE)]
        pts = [(x(i), y(v)) for i, v in enumerate(vs) if v is not None]
        out.append(f'<polyline fill="none" stroke="{color}" stroke-width="2.5" points="{" ".join(f"{a:.1f},{b:.1f}" for a, b in pts)}"/>')
        for i, v in enumerate(vs):
            if v is None:
                continue
            if ci and ci[i]:
                out.append(f'<line x1="{x(i):.1f}" x2="{x(i):.1f}" y1="{y(ci[i][0]):.1f}" y2="{y(ci[i][1]):.1f}" stroke="{color}" stroke-width="1.5" opacity="0.6"/>')
            out.append(f'<circle cx="{x(i):.1f}" cy="{y(v):.1f}" r="3.5" fill="{color}"><title>{esc(name)} {esc((xlabels or xs)[i])}: {fmt.format(v)}{unit}</title></circle>')
    lx = pad_l
    for j, (name, _, _) in enumerate(series):
        out.append(f'<rect x="{lx}" y="{height - 14}" width="10" height="10" fill="{PALETTE[j % len(PALETTE)]}"/><text x="{lx + 14}" y="{height - 5}" class="axis">{esc(name)}</text>')
        lx += 14 + 7 * len(name) + 18
    out.append(f'<text x="12" y="{pad_t + h / 2}" class="axis" transform="rotate(-90 12 {pad_t + h / 2})" text-anchor="middle">{esc(unit)}</text></svg>')
    return "".join(out)


def table(headers, rows):
    out = ['<div class="table"><table><thead><tr>'] + [f"<th>{esc(hd)}</th>" for hd in headers] + ["</tr></thead><tbody>"]
    for r in rows:
        out.append("<tr>" + "".join(f"<td>{c if isinstance(c, Markup) else esc(c)}</td>" for c in r) + "</tr>")
    out.append("</tbody></table></div>")
    return "".join(out)


class Markup(str):
    pass


def badge(text, kind):
    return Markup(f'<span class="badge {kind}">{esc(text)}</span>')


# ---------- Sections ----------

summary = {"generated": datetime.datetime.now(datetime.timezone.utc).isoformat(), "sections": {}}
sections = []


def section(title, label_html, body):
    sections.append(f'<section><h2>{esc(title)}</h2><p class="labels">{label_html}</p>{body}</section>')


MAC = badge("Measured (Mac)", "mac")
SYN = badge("Synthetic speech", "syn")
MIX = badge("Artificial mix", "syn")
MOCK = badge("Mock AI", "mock")
REAL = badge("Real local AI", "real")
NM = badge("Not measured", "nm")

# Buffer
buffer_runs = [r for r in load_all("buffer") if len(r["perf"]) >= 24 and any(s["simulatedMinutes"] >= 60 for s in r["sustained"])]
buffer_runs = buffer_runs[-3:]
if buffer_runs:
    def agg(impl, dur, field, stat="p50"):
        vals = [p[field][stat] for r in buffer_runs for p in r["perf"] if p["implementation"] == impl and p["capacitySeconds"] == dur and p["chunkFrames"] == 1600]
        return mean(vals) if vals else None
    durs = [30, 60, 120]
    rows = []
    for d in durs:
        b_app, o_app = agg("baseline_v1_int16_ring", d, "appendNs"), agg("shipping", d, "appendNs")
        b_snap, o_snap = agg("baseline_v1_int16_ring", d, "snapshotNs"), agg("shipping", d, "snapshotNs")
        rows.append([f"{d} s", f"{b_app / 1e3:.2f} µs", f"{o_app / 1e3:.2f} µs", f"{(b_app - o_app) / b_app * 100:.1f}%", f"{b_snap / 1e6:.2f} ms", f"{o_snap / 1e6:.3f} ms", f"{(b_snap - o_snap) / b_snap * 100:.1f}%"])
    boundary = [b for r in buffer_runs for b in r["boundary"]]
    sustained = [s for s in buffer_runs[-1]["sustained"] if s["implementation"] == "shipping"]
    mem = load_all("memory")
    mem_rows, mem_series = [], []
    if mem:
        res = mem[-1]["results"]
        def m(impl, d, field):
            vs = [x[field] for x in res if x["implementation"] == impl and x["capacitySeconds"] == d]
            return mean(vs) / 1048576 if vs else None
        impls = [("baseline_v1_int16_ring", "Original ring"), ("shipping", "Optimized ring"), ("float32_ring", "Float32 ring"), ("naive_append_trim_float", "Naive append+trim")]
        mem_series = [(label, [m(i, d, "peakDuringSnapshotDeltaBytes") for d in durs]) for i, label in impls]
        for i, label in impls:
            mem_rows.append([label] + [f"{m(i, d, 'fillDeltaBytes'):.2f} / {m(i, d, 'peakDuringSnapshotDeltaBytes'):.2f}" for d in durs])
    passed = sum(b["pass"] for b in boundary)
    body = (
        "<h3>Append and extraction cost, original vs optimized (100 ms chunks, median of 3,000 appends and 100 extractions, mean of 3 runs)</h3>"
        + table(["Window", "Append (orig)", "Append (opt)", "Reduction", "Extract under lock (orig)", "Extract (opt)", "Reduction"], rows)
        + bar_chart([f"{d} s" for d in durs], [("Original", [agg("baseline_v1_int16_ring", d, "snapshotNs") / 1e6 for d in durs]), ("Optimized", [agg("shipping", d, "snapshotNs") / 1e6 for d in durs]), ("Naive append+trim", [agg("naive_append_trim_float", d, "snapshotNs") / 1e6 if agg("naive_append_trim_float", d, "snapshotNs") else None for d in durs])], unit=" ms (log)", log=True, fmt="{:.2f}")
        + "<h3>Memory: steady / peak during extraction (MB, fresh process, mean of 3)</h3>"
        + (table(["Implementation", "30 s", "60 s", "120 s"], mem_rows) + bar_chart([f"{d} s" for d in durs], mem_series, unit=" MB peak", fmt="{:.0f}") if mem_rows else "<p>Not measured</p>")
        + f"<h3>Boundary correctness</h3><p><b>{passed}/{len(boundary)}</b> sample-exact cases passed across {len(buffer_runs)} runs and 4 implementations (questions 0 to 119 s after a word, at, straddling and beyond the window edge, with 0 or 2 s of audio after the question).</p>"
        + "<h3>Sustained session (time-compressed, 60 simulated minutes)</h3>"
        + line_chart([p["simulatedMinutes"] for p in sustained[0]["points"]][::6], [(f"{int(s['capacitySeconds'])} s window", [p["footprintBytes"] / 1048576 for p in s["points"]][::6], None) for s in sustained], unit=" MB footprint", xlabels=[f"{int(p['simulatedMinutes'])}" for p in sustained[0]["points"]][::6])
        + "<p>" + "; ".join(f"{int(s['capacitySeconds'])} s: growth after first fill {s['footprintGrowthAfterFirstFillBytes'] / 1024:+.0f} KB" for s in sustained) + "</p>"
    )
    section("Live Rewind buffer", f"{MAC} release build, {esc(buffer_runs[-1]['metadata']['chip'])}", body)
    summary["sections"]["buffer"] = dict(rows=rows, boundary=f"{passed}/{len(boundary)}", runs=[r["metadata"]["runID"] for r in buffer_runs])

# ASR
asr_agg = sorted(AGG.glob("asr_asr-*.json"))
asr_main = None
for p in asr_agg:
    d = json.loads(p.read_text())
    notes = " ".join(d["metadata"]["notes"])
    # The primary run reads files directly (runs before the input note existed did too).
    if d["overall"]["n_clips"] >= 500 and "input: buffer" not in notes and "vad: true" not in notes:
        asr_main = d
if asr_main:
    conds = asr_main["conditions"]
    order_noise = ["clean/normal", "pink_noise/+20dB", "pink_noise/+10dB", "pink_noise/+0dB", "pink_noise/-5dB"]
    by = {c["label"]: c for c in conds}
    rows = [[c["label"], c["n_clips"], f"{c['cer_mean']:.3f} [{c['cer_ci95'][0]:.3f}, {c['cer_ci95'][1]:.3f}]", f"{c['wer_mean']:.3f}", f"{c['target_hit_rate'] * 100:.1f}% [{c['target_hit_ci95'][0] * 100:.1f}, {c['target_hit_ci95'][1] * 100:.1f}]", f"{c['latency_ms']['p50']:.0f} / {c['latency_ms']['p95']:.0f}"] for c in conds + asr_main["categories_clean_normal"]]
    noise_chart = line_chart(order_noise, [
        ("Target-word hit %", [by[k]["target_hit_rate"] * 100 for k in order_noise], [(by[k]["target_hit_ci95"][0] * 100, by[k]["target_hit_ci95"][1] * 100) for k in order_noise]),
        ("CER x100", [by[k]["cer_mean"] * 100 for k in order_noise], [(by[k]["cer_ci95"][0] * 100, by[k]["cer_ci95"][1] * 100) for k in order_noise]),
    ], unit=" %", ymax=100, xlabels=["clean", "+20 dB", "+10 dB", "0 dB", "-5 dB"])
    en = asr_main["english_in_codeswitch"]
    cal = asr_main["confidence_calibration"]
    windows = [r for r in load_all("asr") if r["dataset"] == "asr_windows_v1" and r.get("inputMode", "file") == "file"]
    wchart, wrows = "", []
    if windows:
        w = windows[-1]
        g = defaultdict(list)
        for r in w["results"]:
            g[r["condition"]].append(r["combinedLatencyMs"])
        ks = sorted(g, key=lambda k: int(k.split("_")[1][:-1]))
        wchart = line_chart(ks, [("P50", [percentile(g[k], 50) for k in ks], None), ("P95", [percentile(g[k], 95) for k in ks], None)], unit=" ms", xlabels=[k.split("_")[1] for k in ks])
        wrows = [[k.split("_")[1], len(g[k]), f"{percentile(g[k], 50):.0f}", f"{percentile(g[k], 95):.0f}"] for k in ks]
    par = sorted(AGG.glob("compare_*.json"))
    vad = [json.loads(p.read_text()) for p in par if "vad" in p.name]
    vad_rows = []
    for v in vad:
        for c in v["by_condition"]:
            if c["condition"] in ("window_60s", "window_120s", "overlapping_speaker", "ALL"):
                vad_rows.append([v["label"].replace("vad_", ""), c["condition"], c["n"], f"{c['latency_p50_ms'][0]:.0f} -> {c['latency_p50_ms'][1]:.0f}", f"{c['latency_relative_change'] * 100:+.1f}% [{c['latency_diff_ci95'][0]:+.0f}, {c['latency_diff_ci95'][1]:+.0f} ms]", f"{c['target_hit'][0] * 100:.1f} -> {c['target_hit'][1] * 100:.1f}%", f"{c['audio_kept_fraction'] * 100:.0f}%"])
    body = (
        f"<p>56 sentences × 10 conditions = {asr_main['overall']['n_clips']} clips. Apple on-device SpeechTranscriber (ta-IN + en-IN in parallel). 95% CIs resample sentences.</p>"
        + table(["Condition", "Clips", "CER [95% CI]", "WER", "Target-word hit [95% CI]", "Latency p50/p95 ms"], rows)
        + "<h3>Robustness curve: pink noise</h3>" + noise_chart
        + f"<h3>Code-switching</h3><p>English words in code-switched sentences recovered by the Tamil model: <b>{en['recall_ta_model'] * 100:.1f}%</b> ({en['n_english_words']} words); with the parallel English pass: <b>{en['recall_union'] * 100:.1f}%</b>.</p>"
        + f"<h3>Confidence calibration</h3><p>Minimum token confidence detects target-word misses with AUROC <b>{cal['auroc_min_conf_detects_target_miss']:.2f}</b>. Miss rate when min confidence &lt; 0.5: {cal['miss_rate_when_min_conf_below_0_5'] * 100:.1f}%; when ≥ 0.5: {cal['miss_rate_when_min_conf_at_least_0_5'] * 100:.1f}% (n={cal['n']}).</p>"
        + ("<h3>Recognition time vs rewind window length</h3>" + table(["Window", "n", "P50 ms", "P95 ms"], wrows) + wchart if wrows else "")
        + ("<h3>Experiment D: silence trimming before recognition (rejected)</h3>" + table(["Run", "Condition", "n", "P50 ms", "Mean change [95% CI]", "Target hit", "Audio kept"], vad_rows) if vad_rows else "")
    )
    section("Tamil speech recognition", f"{MAC} {SYN} {MIX} single synthetic speaker; Malayalam {NM}", body)
    summary["sections"]["asr"] = dict(conditions=conds, english=en, calibration=cal)
else:
    section("Tamil speech recognition", NM, "<p>Not measured</p>")

# Context and prompt
ctx = [r for r in load_all("context") if r["summary"]["n_cases"] >= 50]
if ctx:
    c = ctx[-1]
    s = c["summary"]
    def fmt_rate(x):
        return f"{x['rate'] * 100:.1f}% ({x['k']}/{x['n']}) [{x['ci95'][0] * 100:.1f}, {x['ci95'][1] * 100:.1f}]" if x["n"] else "n/a"
    rows = [[k.replace("_", " "), fmt_rate(s[k])] for k in ["target_identification", "sentence_localisation", "clarification_when_ambiguous", "abstention_when_unanswerable", "confident_wrong_when_unanswerable", "unnecessary_clarification_on_clear_lookups", "respond_has_replies", "schema_and_semantic_valid", "native_script_valid"]]
    lrows = [[k.replace("_", " "), v["n"], f"{v['p50'] / 1000:.1f}", f"{v['p90'] / 1000:.1f}", f"{v['p95'] / 1000:.1f}"] for k, v in s["latency_ms"].items()]
    body = table(["Metric", "Rate (k/n) [95% Wilson CI]"], rows) + "<h3>Latency by question type (s)</h3>" + table(["Type", "n", "P50", "P90", "P95"], lrows)
    body += f"<p>Model: {esc(c['metadata']['model'])}. Explanation quality is not auto-scored; review sheet exported for bilingual reviewers ({NM} human quality).</p>"
    section("Contextual retrieval and explanation", f"{MAC} {REAL} real recogniser transcripts of {SYN}", body)
    summary["sections"]["context"] = s
else:
    section("Contextual retrieval and explanation", NM, "<p>Not measured</p>")

prompt = load_all("prompt")
if prompt:
    p = prompt[-1]["result"]
    rows = [[v, p[v]["n"], f"{p[v]['wall_ms']['p50'] / 1000:.1f} / {p[v]['wall_ms']['p95'] / 1000:.1f}", f"{p[v]['output_tokens']['mean']:.0f}", f"{p[v]['prompt_tokens_mean']:.0f}", f"{p[v]['decode_tokens_per_s']:.1f}", p[v]["correct"], f"{p[v]['valid_rate'] * 100:.0f}%"] for v in ("v1", "v2")]
    body = table(["Prompt", "Calls", "Latency p50/p95 s", "Output tokens", "Prompt tokens", "Decode tok/s", "Correct", "Valid"], rows)
    body += f"<p>Paired mean change v1 → v2: <b>{p['paired_wall_diff_ms']['mean'] / 1000:+.1f} s</b> [{p['paired_wall_diff_ms']['ci95'][0] / 1000:+.1f}, {p['paired_wall_diff_ms']['ci95'][1] / 1000:+.1f}] ({p['relative_change'] * 100:+.1f}%). Cold start (model unloaded): mean {p['cold_start']['wall_ms_mean'] / 1000:.1f} s including {p['cold_start']['load_ms_mean'] / 1000:.1f} s load.</p>"
    section("Experiment C: explanation prompt length", f"{MAC} {REAL}", body)
    summary["sections"]["prompt"] = p

# Load
loads = load_all("load")
mock = [l for l in loads if l["metadata"]["ai"].startswith("MOCK")]
real = [l for l in loads if l["metadata"]["ai"].startswith("REAL")]
if mock:
    m = mock[-1]
    s = m["summary"]
    rows = [[x["concurrency"], x["requests"], f"{x['throughput_rps']:.0f}", f"{x['success_rate'] * 100:.1f}%", f"{x['latency_ok_ms']['p50']:.0f}", f"{x['latency_ok_ms']['p95']:.0f}", f"{x['latency_ok_ms']['p99']:.0f}" if x["latency_ok_ms"]["p99"] else "n/a", f"{x['server_cpu_percent_mean']:.0f}%", f"{x['server_rss_mb_max']:.0f}"] for x in s]
    body = f"<p>{esc(m['metadata']['ai'])}. {esc(m['metadata']['environment'])}.</p>" + table(["Concurrency", "Requests", "Req/s", "Success", "P50 ms", "P95 ms", "P99 ms", "Server CPU", "RSS MB"], rows)
    body += line_chart([x["concurrency"] for x in s], [("Requests/s", [x["throughput_rps"] for x in s], None)], unit=" req/s", xlabels=[str(x["concurrency"]) for x in s])
    section("Backend capacity (mock AI)", f"{MAC} {MOCK}", body)
if real:
    rows = []
    for l in real:
        lim = l["metadata"]["limiter"]
        for x in l["summary"]:
            rows.append(["limiter " + (f"{lim['maxConcurrent']}/{lim['maxQueue']}/{lim['maxWaitMs'] // 1000}s" if lim else "off"), x["concurrency"], x["requests"], f"{x['goodput_rps'] * 60:.2f}", f"{x['success_rate'] * 100:.0f}%", f"{x['latency_ok_ms']['p50'] / 1000:.1f}" if x["latency_ok_ms"]["p50"] == x["latency_ok_ms"]["p50"] else "n/a", f"{x['latency_ok_ms']['p95'] / 1000:.1f}" if x["latency_ok_ms"]["p95"] == x["latency_ok_ms"]["p95"] else "n/a", f"{x['failed_request_ms_p50'] / 1000:.1f}" if x["failed_request_ms_p50"] == x["failed_request_ms_p50"] else "n/a", json.dumps(x["statuses"])])
    section("Experiment F: backend under real local-model load", f"{MAC} {REAL}", table(["Config", "Concurrency", "Requests", "Successful/min", "Success", "P50 s", "P95 s", "Failure latency p50 s", "Statuses"], rows))

# Privacy
priv = [r for r in load_all("privacy") if any(c["kind"] == "runtime" for c in r["checks"])] or load_all("privacy")
if priv:
    p = priv[-1]
    rows = [[c["id"], c["requirement"], badge("pass", "pass") if c["passed"] else badge("fail", "fail"), c["kind"]] for c in p["checks"]]
    section("Privacy validation", f"{MAC} {p['passed']}/{p['total']} checks passed", table(["ID", "Requirement", "Result", "Type"], rows))
    summary["sections"]["privacy"] = dict(passed=p["passed"], total=p["total"])

# Not measured
nm_rows = [
    ["iPhone memory, CPU, energy, thermal", "Needs a physical iPhone", "docs/benchmarks/DeviceTestProtocol.md"],
    ["Siri and AirPods end-to-end latency", "Needs a physical iPhone and AirPods", "docs/TESTING_CHECKLIST.md section B/C"],
    ["Malayalam recognition accuracy", "No Malayalam voice or consented recordings", "Run make_asr_dataset with recordings"],
    ["Real speakers, accents, distance, AirPods mic", "Needs consented human recordings", "Same pipeline, new manifest"],
    ["Explanation quality (human)", "Needs bilingual reviewers", "docs/benchmarks/TranslationReviewRubric.md"],
    ["Claude latency and quality", "No Anthropic API key available", "AI_PROVIDER=claude, rerun context-eval"],
    ["Learning retention and speaking gains", "Needs consented participants", "docs/benchmarks/LearningStudyProtocol.md"],
    ["Production scaling (multi-instance, network)", "Single-machine loopback only", "Deploy and rerun load-test against it"],
]
section("Not measured", NM, table(["Metric", "Why", "How to measure"], nm_rows))

commit = __import__("subprocess").run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Languify Benchmarks</title><style>
:root{{--bg:#fbfbfa;--fg:#1b1f24;--muted:#5b6470;--card:#fff;--line:#e3e5e8;--grid:#eceef1}}
@media (prefers-color-scheme: dark){{:root{{--bg:#111418;--fg:#e8eaed;--muted:#9aa3ad;--card:#1a1e24;--line:#2b3038;--grid:#252a31}}}}
body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;padding:24px 16px}}
main{{max-width:980px;margin:0 auto}} h1{{margin:0 0 4px}} h2{{margin-top:0}} h3{{font-size:15px;margin:20px 0 8px}}
section{{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:20px;margin:16px 0}}
.meta,.labels{{color:var(--muted);font-size:13px}} .table{{overflow-x:auto}} table{{border-collapse:collapse;width:100%;font-size:13px}}
th,td{{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}} th{{color:var(--muted);font-weight:600}}
.chart{{width:100%;max-width:680px;height:auto;margin:8px 0}} .grid{{stroke:var(--grid)}} .axis{{fill:var(--muted);font-size:11px}} .na{{fill:var(--muted);font-size:10px}}
.badge{{display:inline-block;padding:1px 8px;border-radius:99px;font-size:12px;font-weight:600;margin-right:4px}}
.mac{{background:#dbeafe;color:#1e3a8a}} .syn{{background:#fef3c7;color:#78350f}} .mock{{background:#ede9fe;color:#4c1d95}} .real{{background:#dcfce7;color:#14532d}} .nm{{background:#f3f4f6;color:#374151}}
.pass{{background:#dcfce7;color:#14532d}} .fail{{background:#fee2e2;color:#7f1d1d}}
</style></head><body><main>
<h1>Languify benchmarks</h1>
<p class="meta">Generated {esc(summary['generated'][:19])} UTC from commit {esc(commit)}. Every value is read from Results/Raw; methods in docs/benchmarks/BenchmarkMethodology.md.</p>
{''.join(sections)}
</main></body></html>"""
(ROOT / "Results/Reports").mkdir(parents=True, exist_ok=True)
(ROOT / "Results/Reports/dashboard.html").write_text(page)
AGG.mkdir(parents=True, exist_ok=True)
(AGG / "summary.json").write_text(json.dumps(summary, indent=1, default=str))
print("Wrote Results/Reports/dashboard.html and Results/Aggregated/summary.json")
