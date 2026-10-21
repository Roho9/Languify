import type { Explanation, ExplainRequest, Lesson, LessonRequest, SuggestionsRequest, TutorRequest, TutorResponse } from "../schemas.js";
import type { z } from "zod";
import type { SuggestionsResponse } from "../schemas.js";

/**
 * Language intelligence behind the API. The Claude implementation is the
 * production provider; tests inject a fake. Swapping providers means writing
 * another class against this interface, nothing else changes.
 */
export interface LanguageAI {
  explain(req: ExplainRequest): Promise<Explanation>;
  tutorTurn(req: TutorRequest): Promise<TutorResponse>;
  suggestions(req: SuggestionsRequest): Promise<z.infer<typeof SuggestionsResponse>>;
  lesson(req: LessonRequest): Promise<Lesson>;
}

/** Thrown when the provider is unreachable or returns unusable output. */
export class AIProviderError extends Error {
  constructor(
    message: string,
    readonly kind: "unavailable" | "rate_limited" | "invalid_output" | "refused" | "timeout",
  ) {
    super(message);
  }
}
