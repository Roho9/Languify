import { createLanguageAI } from "./ai/factory.js";
import { ConcurrencyLimiter } from "./ai/limiter.js";
import { buildApp } from "./app.js";
import { AppleIdentityVerifier, TokenService } from "./auth/tokens.js";
import { loadConfig } from "./config.js";
import { AppStoreTransactionVerifier } from "./entitlements.js";
import { loadCatalog } from "./quota/plans.js";
import { InMemoryUsageStore } from "./quota/store.js";

const config = loadConfig();
const catalog = loadCatalog(process.env.LANGUIFY_PLAN_CATALOG_JSON);

const ai = createLanguageAI(config);

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
  aiLimiter: config.AI_MAX_CONCURRENCY > 0 ? new ConcurrencyLimiter(config.AI_MAX_CONCURRENCY, config.AI_MAX_QUEUE, config.AI_MAX_QUEUE_WAIT_MS) : undefined,
});

await app.listen({ port: config.PORT, host: config.HOST });
app.log.info(`AI provider: ${config.AI_PROVIDER} (${config.AI_PROVIDER === "ollama" ? config.OLLAMA_MODEL : config.ANTHROPIC_MODEL})`);
