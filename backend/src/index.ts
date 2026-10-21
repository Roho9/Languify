import Anthropic from "@anthropic-ai/sdk";
import { ClaudeLanguageAI } from "./ai/claude.js";
import { buildApp } from "./app.js";
import { AppleIdentityVerifier, TokenService } from "./auth/tokens.js";
import { loadConfig } from "./config.js";
import { AppStoreTransactionVerifier } from "./entitlements.js";
import { loadCatalog } from "./quota/plans.js";
import { InMemoryUsageStore } from "./quota/store.js";

const config = loadConfig();
const catalog = loadCatalog(process.env.LANGUIFY_PLAN_CATALOG_JSON);

// The Anthropic client resolves credentials from the environment
// (ANTHROPIC_API_KEY or an `ant auth login` profile). Never ship them to the app.
const ai = new ClaudeLanguageAI(new Anthropic(), {
  model: config.ANTHROPIC_MODEL,
  rewindEffort: config.REWIND_EFFORT,
  tutorEffort: config.TUTOR_EFFORT,
  lessonEffort: config.LESSON_EFFORT,
  timeoutMs: config.AI_TIMEOUT_MS,
});

const app = await buildApp({
  ai,
  tokens: new TokenService(config.LANGUIFY_TOKEN_SECRET),
  apple: new AppleIdentityVerifier(config.APPLE_BUNDLE_ID),
  store: new InMemoryUsageStore(),
  catalog,
  transactions: new AppStoreTransactionVerifier(catalog, {
    rootCertsDir: config.APPLE_ROOT_CERTS_DIR,
    environment: config.APP_STORE_ENVIRONMENT,
    bundleId: config.APPLE_BUNDLE_ID,
    appAppleId: config.APPLE_APP_ID,
  }),
  logLevel: config.LOG_LEVEL,
});

await app.listen({ port: config.PORT, host: config.HOST });
