# Explanation quality review rubric

For bilingual reviewers scoring the CSV sheets in `Results/Reviews/`. Each row is one AI explanation. Score independently; do not discuss rows with other reviewers until both have finished.

| Column | Scale | Guidance |
|---|---|---|
| semantic_accuracy | 0 to 2 | 0 wrong meaning, 1 roughly right but misleading, 2 correct |
| contextual_correctness | 0 to 2 | Does it explain what the speaker meant *in this conversation*? |
| fluency | 0 to 2 | Native script and romanisation correct and natural; replies sound like real spoken Tamil/Malayalam |
| cultural_appropriateness | 0 to 2 | Register (formal/informal), respect forms, cultural notes accurate |
| unsupported_claims | y / n | Did it state something the transcript does not support (invented words, speakers, details)? |
| usefulness | 0 to 2 | Would this help a receptive bilingual understand and reply? |

## Procedure

1. At least two reviewers per language, ideally from different regions.
2. Each reviewer scores the same rows.
3. Report per-criterion means with bootstrap 95% CIs, and inter-rater agreement as quadratic-weighted Cohen's kappa (two reviewers) or Krippendorff's alpha (more). Report disagreement rather than averaging it away.
4. For the context-vs-isolated comparison, show reviewers both explanations for the same case in random order without labels.

No review has been performed yet.
