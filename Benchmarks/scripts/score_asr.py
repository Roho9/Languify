#!/usr/bin/env python3 -I
"""Scores an ASR run (Results/Raw/asr/*.json) against the Tamil pilot
annotations and writes Results/Aggregated/asr_<runID>.json.

Usage: python3 -I Benchmarks/scripts/score_asr.py [Results/Raw/asr/<run>.json]
Defaults to the newest full (560-clip) run.
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from stats import auroc, bootstrap_ci, levenshtein, mean, percentile, wilson  # noqa: E402
from tamil_romanize import latin_words, skeleton  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def newest_full_run():
    runs = sorted((ROOT / "Results/Raw/asr").glob("*.json"))
    full = [r for r in runs if len(json.loads(r.read_text())["results"]) >= 500]
    return full[-1] if full else runs[-1]


def score(run_path: Path):
    run = json.loads(run_path.read_text())
    ann = json.loads((ROOT / "BenchmarkData/Annotations/tamil_pilot_v1.json").read_text())
    sentences = {s["id"]: s for s in ann["sentences"]}

    rows = []
    for r in run["results"]:
        s = sentences[r["sentence_id"]] if "sentence_id" in r else sentences[r["sentenceID"]]
        ta = next((h for h in r["hypotheses"] if h["locale"].startswith("ta")), None)
        en = next((h for h in r["hypotheses"] if h["locale"].startswith("en")), None)
        ref = skeleton(s["text"])
        hyp = skeleton(ta["text"]) if ta else ""
        ref_c, hyp_c = ref.replace(" ", ""), hyp.replace(" ", "")
        target = skeleton(s["target"]["native"]).replace(" ", "")
        # The target must match 1 to 3 consecutive recognised words (joined)
        # within 20% character error. Matching across arbitrary character
        # spans was too lenient: it found short words inside garbled output.
        tokens = hyp.split()
        spans = ["".join(tokens[i:i + k]) for k in (1, 2, 3) for i in range(len(tokens) - k + 1)]
        # Also accept the target at the start or end of a span, since Tamil
        # particles attach to words ("boring-aa irundhuchu" -> "aagirundhuchu").
        candidates = spans + [sp[-len(target):] for sp in spans if len(sp) > len(target)] + [sp[:len(target)] for sp in spans if len(sp) > len(target)]
        target_cer = min((levenshtein(target, sp) / max(1, len(target)) for sp in candidates), default=1.0)
        english = latin_words(s["text"])
        ta_words = set(skeleton(ta["text"]).split()) if ta else set()
        en_words = set(skeleton(en["text"]).split()) if en else set()
        rows.append(dict(
            clip=r["clipID"], sentence=s["id"], category=s["category"], condition=r["condition"], rate=r["rate"], snr=r.get("snrDb"),
            cer=levenshtein(ref_c, hyp_c) / max(1, len(ref_c)),
            wer=levenshtein(ref.split(), hyp.split()) / max(1, len(ref.split())),
            exact=ref_c == hyp_c,
            target_hit=target_cer <= 0.2,
            target_cer=target_cer,
            english_total=len(english),
            english_ta=sum(skeleton(w) in ta_words for w in english),
            english_en=sum(skeleton(w) in en_words for w in english),
            conf_mean=ta.get("meanConfidence") if ta else None,
            conf_min=ta.get("minConfidence") if ta else None,
            latency_ta=ta["latencyMs"] if ta else None,
            latency_en=en["latencyMs"] if en else None,
            latency_combined=r["combinedLatencyMs"],
            audio_s=r["audioSeconds"],
            error=r.get("error"),
            hyp=ta["text"] if ta else "",
        ))

    def summarize(subset, label):
        groups = defaultdict(list)
        for x in subset:
            groups[x["sentence"]].append(x)
        hits = sum(x["target_hit"] for x in subset)
        exact = sum(x["exact"] for x in subset)
        cer = [x["cer"] for x in subset]
        lat = [x["latency_combined"] for x in subset if x["latency_combined"]]
        rtf = [x["latency_ta"] / 1000 / x["audio_s"] for x in subset if x["latency_ta"] and x["audio_s"]]
        return dict(
            label=label, n_clips=len(subset), n_sentences=len(groups),
            cer_mean=mean(cer), cer_ci95=bootstrap_ci(groups, lambda xs: mean([x["cer"] for x in xs])),
            wer_mean=mean([x["wer"] for x in subset]), wer_ci95=bootstrap_ci(groups, lambda xs: mean([x["wer"] for x in xs])),
            target_hit_rate=hits / len(subset), target_hit_ci95=wilson(hits, len(subset)),
            exact_rate=exact / len(subset),
            latency_ms=dict(p50=percentile(lat, 50), p90=percentile(lat, 90), p95=percentile(lat, 95), max=max(lat) if lat else None),
            ta_real_time_factor_p50=percentile(rtf, 50),
            errors=sum(1 for x in subset if x["error"]),
        )

    def cond_key(x):
        if x["condition"] == "clean":
            return f"clean/{x['rate']}"
        if x["condition"] in ("pink_noise", "english_babble"):
            return f"{x['condition']}/{x['snr']:+.0f}dB"
        return x["condition"]

    by_condition = defaultdict(list)
    for x in rows:
        by_condition[cond_key(x)].append(x)
    order = ["clean/slow", "clean/normal", "clean/fast", "pink_noise/+20dB", "pink_noise/+10dB", "pink_noise/+0dB", "pink_noise/-5dB", "english_babble/+10dB", "english_babble/+0dB", "overlapping_speaker"]
    conditions = [summarize(by_condition[k], k) for k in order if k in by_condition]

    clean = by_condition.get("clean/normal", [])
    categories = []
    for cat in ["everyday", "uncommon", "idiom", "codeswitch"]:
        sub = [x for x in clean if x["category"] == cat]
        if sub:
            categories.append(summarize(sub, f"clean/normal/{cat}"))

    cs = [x for x in clean if x["category"] == "codeswitch"]
    en_total = sum(x["english_total"] for x in cs)
    english = dict(
        n_english_words=en_total,
        recall_ta_model=sum(x["english_ta"] for x in cs) / max(1, en_total),
        recall_ta_ci95=wilson(sum(x["english_ta"] for x in cs), en_total),
        recall_en_model=sum(x["english_en"] for x in cs) / max(1, en_total),
        recall_union=sum(min(x["english_total"], max(x["english_ta"], x["english_en"])) for x in cs) / max(1, en_total),
    )

    # Does recogniser confidence flag target-word misses? (all conditions)
    with_conf = [x for x in rows if x["conf_min"] is not None]
    calibration = dict(
        n=len(with_conf),
        auroc_min_conf_detects_target_miss=auroc([1 - x["conf_min"] for x in with_conf if not x["target_hit"]], [1 - x["conf_min"] for x in with_conf if x["target_hit"]]),
        mean_conf_when_hit=mean([x["conf_mean"] for x in with_conf if x["target_hit"]]),
        mean_conf_when_miss=mean([x["conf_mean"] for x in with_conf if not x["target_hit"]]),
        miss_rate_when_min_conf_below_0_5=(lambda s: sum(not x["target_hit"] for x in s) / len(s) if s else None)([x for x in with_conf if x["conf_min"] < 0.5]),
        miss_rate_when_min_conf_at_least_0_5=(lambda s: sum(not x["target_hit"] for x in s) / len(s) if s else None)([x for x in with_conf if x["conf_min"] >= 0.5]),
    )

    out = dict(
        source_run=str(run_path.relative_to(ROOT)), metadata=run["metadata"], source_label=run["sourceLabel"], mode=run["mode"],
        overall=summarize(rows, "all"), conditions=conditions, categories_clean_normal=categories,
        english_in_codeswitch=english, confidence_calibration=calibration,
        worst_clean_examples=sorted(([dict(clip=x["clip"], cer=x["cer"], hyp=x["hyp"]) for x in clean]), key=lambda d: -d["cer"])[:8],
        cold_start_first_clip_ms=rows[0]["latency_combined"] if rows else None,
    )
    dest = ROOT / "Results/Aggregated" / f"asr_{run['metadata']['runID']}.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    return out, dest


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else newest_full_run()
    if not path.is_absolute():
        path = ROOT / path
    out, dest = score(path)
    print(f"Run {out['metadata']['runID']}  ({out['source_label']})  mode={out['mode']}")
    print(f"{'condition':24} {'clips':>5} {'CER':>6} {'95% CI':>15} {'WER':>6} {'target hit':>10} {'95% CI':>15} {'lat p50':>8} {'p95':>6}")
    for c in out["conditions"] + out["categories_clean_normal"]:
        print(f"{c['label']:24} {c['n_clips']:5} {c['cer_mean']:6.3f} [{c['cer_ci95'][0]:.3f},{c['cer_ci95'][1]:.3f}] {c['wer_mean']:6.3f} {c['target_hit_rate']*100:9.1f}% [{c['target_hit_ci95'][0]*100:5.1f},{c['target_hit_ci95'][1]*100:5.1f}] {c['latency_ms']['p50']:8.0f} {c['latency_ms']['p95']:6.0f}")
    print("English words in code-switched speech:", json.dumps(out["english_in_codeswitch"]))
    print("Confidence calibration:", json.dumps(out["confidence_calibration"]))
    print("Cold start first clip ms:", out["cold_start_first_clip_ms"])
    print("Worst clean/normal:")
    for w in out["worst_clean_examples"][:5]:
        print("  ", w)
    print(f"Wrote {dest.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
