"""Shared statistics helpers (stdlib only, so benchmarks need no installs)."""
import math
import random


def percentile(values, p):
    if not values:
        return float("nan")
    s = sorted(values)
    rank = p / 100 * (len(s) - 1)
    lo, hi = math.floor(rank), math.ceil(rank)
    return s[lo] + (s[hi] - s[lo]) * (rank - lo)


def mean(values):
    return sum(values) / len(values) if values else float("nan")


def stdev(values):
    if len(values) < 2:
        return float("nan")
    m = mean(values)
    return math.sqrt(sum((v - m) ** 2 for v in values) / (len(values) - 1))


def wilson(successes, n, z=1.96):
    """95% Wilson score interval for a proportion."""
    if n == 0:
        return (float("nan"), float("nan"))
    p = successes / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def bootstrap_ci(groups, statistic, iterations=2000, seed=7, alpha=0.05):
    """Percentile bootstrap that resamples whole groups (for example all clips
    of one sentence or speaker) so correlated samples are not treated as
    independent evidence."""
    rng = random.Random(seed)
    keys = list(groups)
    if not keys:
        return (float("nan"), float("nan"))
    stats = []
    for _ in range(iterations):
        sample = []
        for _ in keys:
            sample.extend(groups[rng.choice(keys)])
        stats.append(statistic(sample))
    stats.sort()
    return (stats[int(alpha / 2 * iterations)], stats[int((1 - alpha / 2) * iterations) - 1])


def paired_bootstrap_diff(pairs, iterations=2000, seed=11):
    """CI for mean(b - a) over paired observations [(a, b), ...]."""
    rng = random.Random(seed)
    diffs = [b - a for a, b in pairs]
    out = []
    for _ in range(iterations):
        s = [rng.choice(diffs) for _ in diffs]
        out.append(mean(s))
    out.sort()
    return mean(diffs), (out[int(0.025 * iterations)], out[int(0.975 * iterations) - 1])


def levenshtein(a, b):
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        for j, cb in enumerate(b, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb))
        prev = cur
    return prev[-1]


def approx_substring_distance(needle, haystack):
    """Minimum edit distance between `needle` and any substring of `haystack`
    (semi-global alignment)."""
    if not needle:
        return 0
    prev = [0] * (len(haystack) + 1)
    for i, cn in enumerate(needle, 1):
        cur = [i] + [0] * len(haystack)
        for j, ch in enumerate(haystack, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (cn != ch))
        prev = cur
    return min(prev)


def auroc(scores_pos, scores_neg):
    """Probability a random positive scores higher than a random negative."""
    if not scores_pos or not scores_neg:
        return float("nan")
    wins = 0.0
    for p in scores_pos:
        for n in scores_neg:
            wins += 1 if p > n else 0.5 if p == n else 0
    return wins / (len(scores_pos) * len(scores_neg))
