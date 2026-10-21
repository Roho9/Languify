import { z } from "zod";

const Env = z.object({
  PORT: z.coerce.number().int().default(8787),
  HOST: z.string().default("0.0.0.0"),
  // Secret used to sign Languify's own session tokens. 32+ random bytes.
  LANGUIFY_TOKEN_SECRET: z.string().min(32, "LANGUIFY_TOKEN_SECRET must be at least 32 characters"),
  ANTHROPIC_MODEL: z.string().default("claude-opus-5-5"),
  REWIND_EFFORT: z.enum(["low", "medium", "high", "xhigh", "max"]).default("low"),
  TUTOR_EFFORT: z.enum(["low", "medium", "high", "xhigh", "max"]).default("low"),
  LESSON_EFFORT: z.enum(["low", "medium", "high", "xhigh", "max"]).default("medium"),
  AI_TIMEOUT_MS: z.coerce.number().int().default(20_000),
  APPLE_BUNDLE_ID: z.string().default("app.languify.Languify"),
  APPLE_APP_ID: z.coerce.number().int().optional(),
  APP_STORE_ENVIRONMENT: z.enum(["Sandbox", "Production", "Xcode", "LocalTesting"]).default("Sandbox"),
  // Directory of Apple root certificates (.cer) for StoreKit JWS verification.
  APPLE_ROOT_CERTS_DIR: z.string().optional(),
  LOG_LEVEL: z.string().default("info"),
});

export type Config = z.infer<typeof Env>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = Env.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
    throw new Error(`Invalid configuration: ${issues}`);
  }
  return parsed.data;
}
