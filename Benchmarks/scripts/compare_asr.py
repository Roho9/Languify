#!/usr/bin/env python3 -I
"""Paired comparison of two ASR runs over the same manifest (for example
without vs with silence trimming). Reports latency, CER and target-word hit
for each, with paired bootstrap intervals on the differences.

Usage: python3 -I Benchmarks/scripts/compare_asr.py <baseline.json> <candidate.json> [label]
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from stats import levenshtein, mean, paired_bootstrap_diff, percentile, wilson  # noqa: E402
from tamil_romanize import skeleton  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def target_cer(target, hyp):
    tokens = hyp.split()
    spans = ["".join(tokens[i:i + k]) for k in (1, 2, 3) for i in range(len(tokens) - k + 1)]
    candidates = spans + [sp[-len(target):] for sp in spans if len(sp) > len(target)] + [sp[:len(target)] for sp in spans if len(sp) > len(target)]
    return min((levenshtein(target, sp) / max(1, len(target)) for sp in candidates), default=1.0)


def rows_for(run_path):
    run = json.loads(Path(run_path).read_text())
    manifest = json.loads((ROOT / f"BenchmarkData/Manifests/{run['dataset']}.json").read_text())
    clips = {c["clip_id"]: c for c in manifest["clips"]}
    sentences = {s["id"]: s for s in json.loads((ROOT / "BenchmarkData/Annotations/tamil_pilot_v1.json").read_text())["sentences"]}
    rows = {}
    for r in run["results"]:
        clip = clips[r["clipID"]]
        ids = clip.get("sentences") or [clip["sentence_id"]]
        reference = skeleton(" ".join(sentences[i]["text"] for i in ids)).replace(" ", "")
        ta = next((h for h in r["hypotheses"] if h["locale"].startswith("ta")), None)
        hyp = skeleton(ta["text"]) if ta else ""
        target = skeleton(sentences[clip["sentence_id"]]["target"]["native"]).replace(" ", "")
        rows[r["clipID"]] = dict(
            latency=r["combinedLatencyMs"],
            cer=levenshtein(reference, hyp.replace(" ", "")) / max(1, len(reference)),
            hit=target_cer(target, hyp) <= 0.2,
            audio=r["audioSeconds"],
            kept=r.get("keptSeconds", r["audioSeconds"]),
            condition=r["condition"],
        )
    return run, rows


def compare(base_path, cand_path, label=""):
    base_run, base = rows_for(base_path)
    cand_run, cand = rows_for(cand_path)
    keys = [k for k in base if k in cand][1:]  # drop the first clip: cold start
    groups = sorted({base[k]["condition"] for k in keys})
    out = dict(label=label, baseline=base_run["metadata"]["runID"], candidate=cand_run["metadata"]["runID"], dataset=base_run["dataset"], by_condition=[])
    for g in groups + ["ALL"]:
        ks = [k for k in keys if g == "ALL" or base[k]["condition"] == g]
        lat_diff, lat_ci = paired_bootstrap_diff([(base[k]["latency"], cand[k]["latency"]) for k in ks])
        cer_diff, cer_ci = paired_bootstrap_diff([(base[k]["cer"], cand[k]["cer"]) for k in ks])
        bh, ch = sum(base[k]["hit"] for k in ks), sum(cand[k]["hit"] for k in ks)
        lost = sum(base[k]["hit"] and not cand[k]["hit"] for k in ks)
        gained = sum(cand[k]["hit"] and not base[k]["hit"] for k in ks)
        bl = [base[k]["latency"] for k in ks]
        cl = [cand[k]["latency"] for k in ks]
        out["by_condition"].append(dict(
            condition=g, n=len(ks),
            latency_p50_ms=[percentile(bl, 50), percentile(cl, 50)], latency_p95_ms=[percentile(bl, 95), percentile(cl, 95)],
            latency_mean_diff_ms=lat_diff, latency_diff_ci95=lat_ci, latency_relative_change=lat_diff / mean(bl),
            cer=[mean([base[k]["cer"] for k in ks]), mean([cand[k]["cer"] for k in ks])], cer_diff=cer_diff, cer_diff_ci95=cer_ci,
            target_hit=[bh / len(ks), ch / len(ks)], target_hit_ci95=[wilson(bh, len(ks)), wilson(ch, len(ks))],
            discordant=dict(lost=lost, gained=gained),
            audio_kept_fraction=mean([cand[k]["kept"] / base[k]["audio"] for k in ks if base[k]["audio"]]),
        ))
    return out


def main():
    a, b = sys.argv[1], sys.argv[2]
    label = sys.argv[3] if len(sys.argv) > 3 else "comparison"
    out = compare(ROOT / a if not a.startswith("/") else a, ROOT / b if not b.startswith("/") else b, label)
    print(f"{label}: {out['baseline']} -> {out['candidate']} ({out['dataset']})")
    print(f"{'condition':22} {'n':>3} {'p50 ms':>15} {'p95 ms':>15} {'mean diff ms [95% CI]':>28} {'rel':>7} {'CER':>13} {'target hit':>15} {'lost/gained':>11} {'kept':>5}")
    for c in out["by_condition"]:
        print(f"{c['condition']:22} {c['n']:3} {c['latency_p50_ms'][0]:6.0f} -> {c['latency_p50_ms'][1]:5.0f} {c['latency_p95_ms'][0]:6.0f} -> {c['latency_p95_ms'][1]:5.0f} "
              f"{c['latency_mean_diff_ms']:8.0f} [{c['latency_diff_ci95'][0]:6.0f},{c['latency_diff_ci95'][1]:6.0f}] {c['latency_relative_change']*100:6.1f}% "
              f"{c['cer'][0]:.3f}->{c['cer'][1]:.3f} {c['target_hit'][0]*100:5.1f}->{c['target_hit'][1]*100:5.1f}% {c['discordant']['lost']:5}/{c['discordant']['gained']:<5} {c['audio_kept_fraction']*100:4.0f}%")
    dest = ROOT / "Results/Aggregated" / f"compare_{label}_{out['candidate']}.json"
    dest.write_text(json.dumps(out, indent=1))
    print(f"Wrote {dest.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
