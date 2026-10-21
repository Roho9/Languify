import { z } from "zod";

// Wire contracts shared with the iOS app (LanguifyKit). Keys are snake_case
// because the app encodes with `.convertToSnakeCase`.

export const Language = z.enum(["ta", "ml"]);
export type Language = z.infer<typeof Language>;

export const LANGUAGE_NAMES: Record<Language, string> = { ta: "Tamil", ml: "Malayalam" };

export const QuestionKind = z.enum(["auto", "word", "sentence", "expression", "gist", "respond", "grammar", "pronunciation"]);

const Segment = z.object({
  text: z.string().max(2_000),
  start: z.number(),
  end: z.number(),
  confidence: z.number().min(0).max(1).nullish(),
  alternatives: z.array(z.string().max(2_000)).max(10).default([]),
});

export const Transcript = z.object({
  language_code: z.string().max(8),
  primary: z.array(Segment).max(200),
  english: z.array(Segment).max(200),
  // Two minutes is the longest rewind window the app offers.
  window_seconds: z.number().min(0).max(130),
});
export type Transcript = z.infer<typeof Transcript>;

export const Learner = z.object({
  comprehension: z.number().int().min(1).max(5),
  speaking: z.number().int().min(1).max(5),
  reading: z.number().int().min(1).max(5),
  recent_words: z.array(z.string().max(80)).max(20).default([]),
});
export type Learner = z.infer<typeof Learner>;

export const ExplainRequest = z.object({
  language: Language,
  question: z.string().min(1).max(500),
  kind: QuestionKind,
  sounds_like: z.string().max(120).nullish(),
  user_context: z.string().max(300).nullish(),
  transcript: Transcript,
  learner: Learner,
  clarification: z.object({ question: z.string().max(300), chosen_option: z.string().max(200) }).nullish(),
  detail_level: z.enum(["concise", "detailed"]).default("concise"),
});
export type ExplainRequest = z.infer<typeof ExplainRequest>;

// ---- Model output (structured outputs). Optional fields are nullable rather
// than omitted so every key is present for the constrained decoder.

const Phrase = z.object({
  native_script: z.string(),
  transliteration: z.string(),
  english: z.string(),
});

const VocabularyItem = z.object({
  native_script: z.string(),
  transliteration: z.string(),
  english_meaning: z.string(),
  contextual_meaning: z.string(),
  pronunciation_hint: z.string(),
  part_of_speech: z.string().nullable(),
  register: z.enum(["formal", "informal", "neutral", "unknown"]),
  usage_note: z.string().nullable(),
  cultural_note: z.string().nullable(),
  regional_note: z.string().nullable(),
  example: Phrase.nullable(),
  related: z.array(z.string()),
});

export const Explanation = z.object({
  status: z.enum(["answered", "needs_clarification", "no_relevant_speech", "uncertain"]),
  kind: QuestionKind,
  spoken_summary: z.string(),
  heard: z
    .object({
      native_script: z.string(),
      transliteration: z.string(),
      english_natural: z.string(),
      literal_gloss: z.string().nullable(),
    })
    .nullable(),
  items: z.array(VocabularyItem),
  suggested_replies: z.array(Phrase),
  grammar_note: z.string().nullable(),
  clarification: z.object({ question: z.string(), options: z.array(z.string()) }).nullable(),
  alternatives: z.array(z.object({ transliteration: z.string(), english_meaning: z.string() })),
  uncertainty_note: z.string().nullable(),
});
export type Explanation = z.infer<typeof Explanation>;

/** Server-side checks beyond the schema, mirroring LanguifyKit's validator. */
export function checkExplanation(e: Explanation): string | null {
  if (!e.spoken_summary.trim()) return "empty spoken_summary";
  if (e.status === "needs_clarification" && (!e.clarification || e.clarification.options.filter((o) => o.trim()).length < 2)) {
    return "clarification without two options";
  }
  if (e.status === "answered" && e.items.length === 0 && !e.heard && e.suggested_replies.length === 0 && !e.grammar_note) {
    return "answered without content";
  }
  return null;
}

// ---- Tutor

export const TutorRequest = z.object({
  language: Language,
  scenario: z.string().min(1).max(200),
  history: z
    .array(
      z.object({
        id: z.string().optional(),
        role: z.enum(["tutor", "learner"]),
        transliteration: z.string().max(1_000),
        native_script: z.string().max(1_000).default(""),
        english: z.string().max(1_000).default(""),
      }),
    )
    .max(40),
  learner_utterance: z.string().max(1_000),
  learner_utterance_confidence: z.number().min(0).max(1).nullish(),
  learner: Learner,
});
export type TutorRequest = z.infer<typeof TutorRequest>;

export const TutorResponse = z.object({
  reply: Phrase,
  correction: z.object({ natural: Phrase, explanation: z.string() }).nullable(),
  encouragement: z.string(),
  assessment: z.object({
    fluency: z.number(),
    grammar: z.number(),
    complete_sentence: z.boolean(),
    used_english: z.boolean(),
  }),
});
export type TutorResponse = z.infer<typeof TutorResponse>;

// ---- Proactive suggestions

export const SuggestionsRequest = z.object({
  language: Language,
  transcript: Transcript.extend({ window_seconds: z.number().min(0).max(4 * 60 * 60) }),
  learner: Learner,
  known_words: z.array(z.string().max(80)).max(200).default([]),
});
export type SuggestionsRequest = z.infer<typeof SuggestionsRequest>;

export const SuggestionsResponse = z.object({ items: z.array(VocabularyItem) });

// ---- Lessons

export const LessonRequest = z.object({
  language: Language,
  focus: z.enum(["listening", "speaking", "vocabulary", "pronunciation", "sentenceConstruction", "grammar"]),
  words: z
    .array(z.object({ transliteration: z.string().max(80), english: z.string().max(200), context: z.string().max(400).nullish() }))
    .max(15),
  learner: Learner,
});
export type LessonRequest = z.infer<typeof LessonRequest>;

export const Lesson = z.object({
  title: z.string(),
  goal: z.string(),
  steps: z.array(
    z.object({
      kind: z.enum(["explain", "listen_and_repeat", "build_sentence", "speak_prompt"]),
      prompt: z.string(),
      model: Phrase.nullable(),
      tip: z.string().nullable(),
    }),
  ),
});
export type Lesson = z.infer<typeof Lesson>;
