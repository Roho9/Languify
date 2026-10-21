import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";
import type { PlanCatalog, Tier } from "./quota/plans.js";

export interface TransactionVerifier {
  /** Returns the active tier and expiry implied by StoreKit 2 signed transactions. */
  resolve(signedTransactions: string[], now?: Date): Promise<{ tier: Tier; expiresAt: Date | null }>;
}

/**
 * Verifies StoreKit 2 JWS transactions with Apple's official library: the
 * certificate chain must lead to an Apple root, and the bundle id and
 * environment must match. Revoked or expired transactions grant nothing.
 */
export class AppStoreTransactionVerifier implements TransactionVerifier {
  private readonly verifier: SignedDataVerifier;

  constructor(
    private readonly catalog: PlanCatalog,
    opts: { rootCertsDir?: string; environment: `${Environment}`; bundleId: string; appAppleId?: number },
  ) {
    const certs = opts.rootCertsDir
      ? readdirSync(opts.rootCertsDir)
          .filter((f) => f.endsWith(".cer"))
          .map((f) => readFileSync(join(opts.rootCertsDir!, f)))
      : [];
    if (certs.length === 0 && opts.environment !== "Xcode" && opts.environment !== "LocalTesting") {
      throw new Error("APPLE_ROOT_CERTS_DIR must contain Apple root certificates for Sandbox/Production verification");
    }
    this.verifier = new SignedDataVerifier(certs, true, opts.environment as Environment, opts.bundleId, opts.appAppleId);
  }

  async resolve(signedTransactions: string[], now = new Date()) {
    let best: { tier: Tier; expiresAt: Date | null } = { tier: "free", expiresAt: null };
    for (const jws of signedTransactions.slice(0, 20)) {
      try {
        const tx = await this.verifier.verifyAndDecodeTransaction(jws);
        if (!tx.productId || !this.catalog.premium_product_ids.includes(tx.productId)) continue;
        if (tx.revocationDate) continue;
        const expires = tx.expiresDate ? new Date(tx.expiresDate) : null;
        if (expires && expires <= now) continue;
        if (best.tier === "free" || (expires && best.expiresAt && expires > best.expiresAt)) {
          best = { tier: "premium", expiresAt: expires };
        }
      } catch {
        // Invalid signature or wrong app: ignore the transaction.
      }
    }
    return best;
  }
}
