import { z } from "zod";
import {
  Explanation,
  Lesson,
  SuggestionsResponse,
  TutorResponse,
  checkExplanation,
  type ExplainRequest,
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

export interface OllamaOptions {
  /** Ollama server, e.g. http://127.0.0.1:11434 */
  baseUrl: string;
  /** Any pulled model, e.g. gemma3:27b */
  model: string;
  timeoutMs: number;
  /** How long Ollama keeps the model in memory between requests. */
  keepAlive: string;
}

/**
 * Free, local provider using an open-weight model served by Ollama. Nothing
 * leaves the machine running Ollama. Uses Ollama's structured outputs
 * (`format` = JSON schema), then validates with the same Zod schemas and
 * semantic checks as the Claude provider, so a weaker model can return a
 * worse answer but never a malformed one.
 */
export class OllamaLanguageAI implements LanguageAI {
  constructor(
    private readonly options: OllamaOptions,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  async explain(req: ExplainRequest): Promise<Explanation> {
    const result = await this.call(EXPLAIN_SYSTEM, explainUserTurn(req), Explanation);
    const problem = checkExplanation(result);
    if (problem) throw new AIProviderError(`explanation failed validation: ${problem}`, "invalid_output");
    return result;
  }

  tutorTurn(req: TutorRequest): Promise<TutorResponse> {
    return this.call(TUTOR_SYSTEM, tutorUserTurn(req), TutorResponse);
  }

  suggestions(req: SuggestionsRequest): Promise<z.infer<typeof SuggestionsResponse>> {
    return this.call(SUGGESTIONS_SYSTEM, suggestionsUserTurn(req), SuggestionsResponse);
  }

  lesson(req: LessonRequest): Promise<Lesson> {
    return this.call(LESSON_SYSTEM, lessonUserTurn(req), Lesson);
  }

  private async call<T extends z.ZodType>(system: string, user: string, schema: T): Promise<z.infer<T>> {
    let response: Response;
    try {
      response = await this.fetchImpl(new URL("/api/chat", this.options.baseUrl), {
        method: "POST",
        headers: { "content-type": "application/json" },
        signal: AbortSignal.timeout(this.options.timeoutMs),
        body: JSON.stringify({
          model: this.options.model,
          stream: false,
          keep_alive: this.options.keepAlive,
          format: z.toJSONSchema(schema),
          // Low temperature: explanations should be stable, not creative.
          options: { temperature: 0.2 },
          messages: [
            { role: "system", content: system },
            { role: "user", content: user },
          ],
        }),
      });
    } catch (error) {
      if (error instanceof DOMException && (error.name === "TimeoutError" || error.name === "AbortError")) {
        throw new AIProviderError("ollama timeout", "timeout");
      }
      throw new AIProviderError("ollama unreachable; is `ollama serve` running?", "unavailable");
    }

    if (response.status === 404) {
      throw new AIProviderError(`model ${this.options.model} not found; run \`ollama pull ${this.options.model}\``, "unavailable");
    }
    if (!response.ok) {
      throw new AIProviderError(`ollama status ${response.status}`, "unavailable");
    }

    let content: unknown;
    try {
      const body = (await response.json()) as { message?: { content?: string } };
      content = JSON.parse(body.message?.content ?? "");
    } catch {
      throw new AIProviderError("ollama returned invalid JSON", "invalid_output");
    }
    const parsed = schema.safeParse(content);
    if (!parsed.success) throw new AIProviderError("ollama output did not match schema", "invalid_output");
    return parsed.data;
  }
}
