# Backend

TypeScript, Node 22, Fastify 5, Zod 4, `@anthropic-ai/sdk`, `jose`, `@apple/app-store-server-library`. Source in `backend/src`.

## AI providers

Set `AI_PROVIDER`:

| Value | Model | Cost | Data leaves your machine? |
|---|---|---|---|
| `ollama` (default) | Any Ollama model, default `gemma3:27b` | Free | No, runs on the host running Ollama |
| `claude` | `claude-opus-5-5` (configurable) | Paid per token | Text goes to Anthropic's API |

Both implement `LanguageAI` (`src/ai/provider.ts`), share the same prompts and Zod schemas, and go through the same validation, so the app cannot tell them apart except by answer quality and speed.

Ollama setup:

```bash
brew install ollama
brew services start ollama
ollama pull gemma3:27b      # about 17 GB; needs ~20 GB free memory. On 16 GB Macs use gemma3:12b
```

Ollama only needs to be reachable from the backend (default `http://127.0.0.1:11434`). The first request after a while loads the model into memory and is slower; `OLLAMA_KEEP_ALIVE` (default 30 minutes) keeps it loaded.

## Endpoints

| Method and path | Auth | Purpose |
|---|---|---|
| `GET /healthz` | none | Liveness |
| `GET /v1/config` | none | Plan catalogue (features, daily limits, product ids) |
| `POST /v1/auth/install` | none, 10/hour/IP | Guest token for an install id |
| `POST /v1/auth/apple` | bearer | Verify a Sign in with Apple identity token, merge guest usage, issue a user token |
| `GET /v1/usage` | bearer | Today's usage and limits |
| `POST /v1/rewind/explain` | bearer, metered | Live Rewind explanation |
| `POST /v1/tutor/turn` | bearer, metered, Premium | Conversation practice turn |
| `POST /v1/lessons` | bearer, metered, Premium | Personalised lesson |
| `POST /v1/suggestions` | bearer, metered, Premium | Post-session word suggestions |
| `POST /v1/entitlements/verify` | bearer | Verify StoreKit 2 signed transactions and record the tier |
| `DELETE /v1/account` | bearer | Delete all server-side data for the subject |

Errors: `400 invalid_request`, `401 unauthorized`, `402 quota_exceeded` (with `resets_at`), `403 feature_locked`, `429 rate_limited` (with `Retry-After`), `502` invalid AI output, `503` provider unavailable, `504` provider timeout. Quota is only consumed after a successful AI response.

## Security

- No provider credentials ever reach the app. The Anthropic key lives in the server environment.
- Session tokens are HS256 JWTs signed with `LANGUIFY_TOKEN_SECRET`, 30-day expiry.
- Global rate limit 60 requests per minute per token (or IP), stricter on install registration.
- Request bodies are size-limited (256 KB) and schema-validated; transcripts are capped at 200 segments and 130 s.
- Logs redact authorization headers and never include bodies.
- Prompts treat transcripts and user context as data, inside tags, to reduce prompt injection from overheard speech.

**Before production:** require an App Attest assertion on `/v1/auth/install` (DeviceCheck `DCAppAttestService`) so tokens can only be minted by genuine app installs; replace `InMemoryUsageStore` with Redis or DynamoDB (the interface is `UsageStore`); call Apple's token revocation endpoint when a signed-in user deletes their account; request zero data retention from Anthropic.

## Running locally

```bash
cd backend
npm install
cp .env.example .env    # set LANGUIFY_TOKEN_SECRET; ANTHROPIC_API_KEY only for AI_PROVIDER=claude
npm run dev             # http://0.0.0.0:8787
npm test                # 20 tests, no network or model needed
npm run smoke           # live call to the configured provider on a real on-device Tamil transcript
```

## Deploying

Any Node 22 host works (Fly.io, Render, AWS App Runner, Cloud Run):

```bash
npm ci && npm run build && npm start
```

Set the variables from `.env.example` as secrets. For `AI_PROVIDER=ollama` in production, run Ollama on a GPU host next to the backend and point `OLLAMA_URL` at it over a private network (Ollama has no authentication, so never expose it publicly). Put TLS in front (the platform's default is fine). Use `APP_STORE_ENVIRONMENT=Sandbox` for TestFlight and `Production` with `APPLE_APP_ID` and `APPLE_ROOT_CERTS_DIR` (Apple Root CA G3 from apple.com/certificateauthority) for release. Run more than one instance only after moving to a shared `UsageStore`.

Plan limits can be changed without a deploy by setting `LANGUIFY_PLAN_CATALOG_JSON`.
