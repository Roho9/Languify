#!/usr/bin/env python3 -I
"""Checks the newest benchmark results against Benchmarks/regression-thresholds.json.

Exit code 1 on any correctness or threshold failure. Categories without a
result are reported as skipped, never as passed.

Usage: python3 -I Benchmarks/scripts/check_regressions.py [--require buffer,asr,...]
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
T = json.loads((ROOT / "Benchmarks/regression-thresholds.json").read_text())
failures, skipped, passed = [], [], []


def newest(category, predicate=lambda d: True):
    for p in sorted((ROOT / "Results/Raw" / category).glob("*.json"), reverse=True) if (ROOT / "Results/Raw" / category).exists() else []:
        d = json.loads(p.read_text())
        if predicate(d):
            return d
    return None


def expect(name, ok, detail):
    (passed if ok else failures).append(f"{name}: {detail}")


buf = newest("buffer")
if buf:
    t = T["buffer"]
    b = buf["boundary"]
    expect("buffer.boundary (correctness)", sum(x["pass"] for x in b) == len(b), f"{sum(x['pass'] for x in b)}/{len(b)} sample-exact cases")
    ship = [p for p in buf["perf"] if p["implementation"] == "shipping"]
    worst_append = max(p["appendNs"]["p50"] for p in ship)
    expect("buffer.append_p50", worst_append <= t["append_p50_ns_max"], f"worst {worst_append:.0f} ns (limit {t['append_p50_ns_max']})")
    snap = max(p["snapshotNs"]["p50"] for p in ship if p["capacitySeconds"] == 120) / 1e6
    expect("buffer.snapshot_120s_p50", snap <= t["snapshot_120s_p50_ms_max"], f"{snap:.3f} ms (limit {t['snapshot_120s_p50_ms_max']})")
    growth = max(abs(s["footprintGrowthAfterFirstFillBytes"]) for s in buf["sustained"] if s["implementation"] == "shipping") / 1024
    expect("buffer.sustained_growth", growth <= t["sustained_growth_kb_max"], f"{growth:.0f} KB (limit {t['sustained_growth_kb_max']})")
else:
    skipped.append("buffer")

mem = newest("memory")
if mem:
    res = [r for r in mem["results"] if r["implementation"] == "shipping" and r["capacitySeconds"] == 120]
    steady = max(r["fillDeltaBytes"] for r in res) / 1048576
    peak = max(r["peakDuringSnapshotDeltaBytes"] for r in res) / 1048576
    expect("memory.steady_120s", steady <= T["buffer"]["steady_memory_120s_mb_max"], f"{steady:.2f} MB")
    expect("memory.peak_120s", peak <= T["buffer"]["peak_memory_120s_mb_max"], f"{peak:.2f} MB")
else:
    skipped.append("memory")

agg = sorted((ROOT / "Results/Aggregated").glob("asr_asr-*.json"))
asr = None
for p in agg:
    d = json.loads(p.read_text())
    if d["overall"]["n_clips"] >= 500:
        asr = d
if asr:
    clean = next(c for c in asr["conditions"] if c["label"] == "clean/normal")
    expect("asr.clean_target_hit", clean["target_hit_rate"] >= T["asr"]["clean_normal_target_hit_min"], f"{clean['target_hit_rate'] * 100:.1f}% (min {T['asr']['clean_normal_target_hit_min'] * 100:.1f}%)")
    expect("asr.clean_cer", clean["cer_mean"] <= T["asr"]["clean_normal_cer_max"], f"{clean['cer_mean']:.3f} (max {T['asr']['clean_normal_cer_max']})")
else:
    skipped.append("asr")

ctx = newest("context", lambda d: d["summary"]["n_cases"] >= 50)
if ctx:
    v = ctx["summary"]["schema_and_semantic_valid"]
    expect("context.valid_output", v["rate"] >= T["context"]["schema_valid_min"], f"{v['k']}/{v['n']}")
else:
    skipped.append("context")

priv = newest("privacy")
if priv:
    expect("privacy.checks", priv["passed"] == priv["total"], f"{priv['passed']}/{priv['total']}")
else:
    skipped.append("privacy")

required = next((a.split("=", 1)[1] if "=" in a else sys.argv[sys.argv.index(a) + 1] for a in sys.argv if a.startswith("--require")), "")
for r in filter(None, required.split(",")):
    if r in skipped:
        failures.append(f"{r}: required but no result found")

for line in passed:
    print("PASS", line)
for line in failures:
    print("FAIL", line)
for s in skipped:
    print("SKIP", s, "(no result)")
sys.exit(1 if failures else 0)
