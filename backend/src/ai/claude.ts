import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import type { z } from "zod";
import {
  Explanation,
  Lesson,
  SuggestionsResponse,
  TutorResponse,
  checkExplanation,
  type ExplainInput,
  type LessonRequest,
  type SuggestionsRequest,
  type TutorRequest,
} from "../schemas.js";
import { AIProviderError, type LanguageAI } from "./provider.js";
import {
  EXPLAIN_SYSTEM,
  LESSON_SYSTEM,
  SUGGESTIONS_SYSTEM,
  TUTOR_SYSTEM,
  explainUserTurn,
  lessonUserTurn,
  suggestionsUserTurn,
  tutorUserTurn,
} from "./prompts.js";

type Effort = "low" | "medium" | "high" | "xhigh" | "max";

export interface ClaudeOptions {
  model: string;
  /** Live Rewind is latency sensitive; it runs at lower effort than lessons. */
  rewindEffort: Effort;
  tutorEffort: Effort;
  lessonEffort: Effort;
  timeoutMs: number;
}

/**
 * Claude-backed implementation. Uses structured outputs so every response is
 * schema-valid JSON, and server-side refusal fallbacks so a classifier false
 * positive on ordinary family conversation does not surface as an error.
 */
export class ClaudeLanguageAI implements LanguageAI {
  constructor(
    private readonly client: Anthropic,
    private readonly options: ClaudeOptions,
  ) {}

  async explain(req: ExplainInput): Promise<Explanation> {
    const result = await this.call(EXPLAIN_SYSTEM, explainUserTurn(req), Explanation, this.options.rewindEffort, req.detail_level === "detailed" ? 4_000 : 2_500);
    const problem = checkExplanation(result);
    if (problem) throw new AIProviderError(`explanation failed validation: ${problem}`, "invalid_output");
    return result;
  }

  tutorTurn(req: TutorRequest): Promise<TutorResponse> {
    return this.call(TUTOR_SYSTEM, tutorUserTurn(req), TutorResponse, this.options.tutorEffort, 2_000);
  }

  suggestions(req: SuggestionsRequest): Promise<z.infer<typeof SuggestionsResponse>> {
    return this.call(SUGGESTIONS_SYSTEM, suggestionsUserTurn(req), SuggestionsResponse, this.options.lessonEffort, 4_000);
  }

  lesson(req: LessonRequest): Promise<Lesson> {
    return this.call(LESSON_SYSTEM, lessonUserTurn(req), Lesson, this.options.lessonEffort, 6_000);
  }

  private async call<T extends z.ZodType>(system: string, user: string, schema: T, effort: Effort, maxTokens: number): Promise<z.infer<T>> {
    try {
      const response = await this.client.beta.messages.parse(
        {
          model: this.options.model,
          max_tokens: maxTokens,
          betas: ["server-side-fallback-2026-07-01"],
          fallbacks: "default",
          // The system prompt is static per task, so mark it for caching.
          system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
          messages: [{ role: "user", content: user }],
          output_config: { effort, format: betaZodOutputFormat(schema) },
        },
        { timeout: this.options.timeoutMs, maxRetries: 1 },
      );

      if (response.stop_reason === "refusal") {
        throw new AIProviderError("model declined the request", "refused");
      }
      if (response.stop_reason === "max_tokens") {
        throw new AIProviderError("response truncated", "invalid_output");
      }
      if (response.parsed_output == null) {
        throw new AIProviderError("no parsed output", "invalid_output");
      }
      return response.parsed_output as z.infer<T>;
    } catch (error) {
      if (error instanceof AIProviderError) throw error;
      if (error instanceof Anthropic.RateLimitError) throw new AIProviderError("provider rate limited", "rate_limited");
      if (error instanceof Anthropic.APIConnectionTimeoutError) throw new AIProviderError("provider timeout", "timeout");
      if (error instanceof Anthropic.APIConnectionError) throw new AIProviderError("provider unreachable", "unavailable");
      if (error instanceof Anthropic.InternalServerError) throw new AIProviderError("provider error", "unavailable");
      if (error instanceof Anthropic.APIError) throw new AIProviderError(`provider status ${error.status}`, "unavailable");
      throw new AIProviderError("unexpected provider failure", "invalid_output");
    }
  }
}
