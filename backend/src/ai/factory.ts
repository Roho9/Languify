import Anthropic from "@anthropic-ai/sdk";
import type { Config } from "../config.js";
import { ClaudeLanguageAI } from "./claude.js";
import { OllamaLanguageAI } from "./ollama.js";
import type { LanguageAI } from "./provider.js";

/** Builds the provider selected by `AI_PROVIDER`. */
export function createLanguageAI(config: Config): LanguageAI {
  switch (config.AI_PROVIDER) {
    case "ollama":
      return new OllamaLanguageAI({
        baseUrl: config.OLLAMA_URL,
        model: config.OLLAMA_MODEL,
        timeoutMs: config.OLLAMA_TIMEOUT_MS,
        keepAlive: config.OLLAMA_KEEP_ALIVE,
      });
    case "claude":
      // Resolves ANTHROPIC_API_KEY (or an `ant auth login` profile) from the environment.
      return new ClaudeLanguageAI(new Anthropic(), {
        model: config.ANTHROPIC_MODEL,
        rewindEffort: config.REWIND_EFFORT,
        tutorEffort: config.TUTOR_EFFORT,
        lessonEffort: config.LESSON_EFFORT,
        timeoutMs: config.AI_TIMEOUT_MS,
      });
  }
}
