# Learning-impact study protocol (not yet run)

No learning outcome has been measured. Any claim about retention or speaking improvement requires this study (or a stronger one) with real, consented participants.

## Questions

1. Does Languify's FSRS scheduling improve recall of words learners actually encountered, compared with a fixed schedule?
2. Do learners produce more complete, correct heritage-language sentences after four weeks of use?

## Design

- Participants: receptive bilinguals of Tamil or Malayalam, 18+, informed consent, ethics review if run through a university. Target at least 30 per arm for retention (power for a 10 percentage-point difference is limited at this size; report it as a pilot).
- Within-subject retention comparison: each participant's saved words are randomly split into FSRS and fixed-interval (1, 3, 7, 14 days) arms. Same number of reviews offered per arm.
- Recall tests: immediate, 24 h, 7 days, 30 days. Prompt: hear the English meaning, say the word. Scored by two blind raters.
- Speaking: the same 6 prompts (talking to parents, describing your day, ...) at baseline and week 4, recorded with consent, scored with the rubric below by two blind raters who do not know which recording is which week.

## Speaking rubric (0 to 3 each)

Vocabulary used, sentence completion, grammatical accuracy, pronunciation intelligibility, fluency (pauses, English fallback).

## Analysis

- Retention: mixed-effects logistic regression (recall ~ arm × interval + (1 | participant) + (1 | word)); report percentage-point differences with 95% CIs.
- Speaking: paired differences with bootstrap CIs; inter-rater agreement (weighted kappa).
- Without a comparison group for speaking, report observed change only and make no causal claim.
- Separate satisfaction surveys from measured learning.

## Data handling

Recordings stored encrypted, deleted after scoring, never used for model training.
