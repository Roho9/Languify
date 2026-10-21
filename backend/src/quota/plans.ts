// Plan catalogue served to the app at GET /v1/config and used for server-side
// enforcement. Values are configuration, so pricing and quota experiments do
// not need an app release. Prices live in App Store Connect, never here.

export type Tier = "free" | "premium";
export type MeteredAction = "rewind_question" | "tutor_turn" | "lesson_generation" | "pronunciation_feedback";
export type Feature =
  | "live_rewind"
  | "detailed_explanations"
  | "vocabulary_journal"
  | "flashcards"
  | "quizzes"
  | "advanced_quizzes"
  | "conversation_practice"
  | "pronunciation_coaching"
  | "personalized_lessons"
  | "learning_analytics"
  | "proactive_suggestions";

export interface PlanDefinition {
  tier: Tier;
  features: Feature[];
  daily_limits: Partial<Record<MeteredAction, number>>;
}

export interface PlanCatalog {
  version: number;
  plans: Record<Tier, PlanDefinition>;
  premium_product_ids: string[];
}

const ALL_FEATURES: Feature[] = [
  "live_rewind",
  "detailed_explanations",
  "vocabulary_journal",
  "flashcards",
  "quizzes",
  "advanced_quizzes",
  "conversation_practice",
  "pronunciation_coaching",
  "personalized_lessons",
  "learning_analytics",
  "proactive_suggestions",
];

export const DEFAULT_CATALOG: PlanCatalog = {
  version: 1,
  plans: {
    free: {
      tier: "free",
      features: ["live_rewind", "vocabulary_journal", "flashcards", "quizzes", "pronunciation_coaching"],
      daily_limits: { rewind_question: 10, pronunciation_feedback: 10, tutor_turn: 0, lesson_generation: 0 },
    },
    premium: {
      tier: "premium",
      features: ALL_FEATURES,
      // Generous but finite: protects against runaway cost and abuse.
      daily_limits: { rewind_question: 200, tutor_turn: 150, lesson_generation: 20, pronunciation_feedback: 200 },
    },
  },
  premium_product_ids: ["app.languify.premium.monthly", "app.languify.premium.annual"],
};

export function loadCatalog(json?: string): PlanCatalog {
  if (!json) return DEFAULT_CATALOG;
  return JSON.parse(json) as PlanCatalog;
}
