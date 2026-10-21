import type { Subject } from "../auth/tokens.js";
import type { MeteredAction, Tier } from "./plans.js";

export interface EntitlementRecord {
  tier: Tier;
  expiresAt: Date | null;
}

/**
 * Persistence for per-subject usage counters and entitlements. Languify's
 * backend stores nothing else about users: no transcripts, no vocabulary.
 * Production should use a shared store (Redis, DynamoDB); the in-memory one
 * is for development and single-instance deployments.
 */
export interface UsageStore {
  increment(subject: Subject, day: string, action: MeteredAction): Promise<number>;
  get(subject: Subject, day: string): Promise<Partial<Record<MeteredAction, number>>>;
  getEntitlement(subject: Subject): Promise<EntitlementRecord | null>;
  setEntitlement(subject: Subject, record: EntitlementRecord): Promise<void>;
  /** Moves a guest's usage and entitlement to a signed-in account. */
  merge(from: Subject, into: Subject, day: string): Promise<void>;
  deleteSubject(subject: Subject): Promise<void>;
}

export class InMemoryUsageStore implements UsageStore {
  private usage = new Map<string, Partial<Record<MeteredAction, number>>>();
  private entitlements = new Map<Subject, EntitlementRecord>();

  private key(subject: Subject, day: string) {
    return `${subject}|${day}`;
  }

  async increment(subject: Subject, day: string, action: MeteredAction) {
    const k = this.key(subject, day);
    const counts = this.usage.get(k) ?? {};
    counts[action] = (counts[action] ?? 0) + 1;
    this.usage.set(k, counts);
    return counts[action]!;
  }

  async get(subject: Subject, day: string) {
    return { ...(this.usage.get(this.key(subject, day)) ?? {}) };
  }

  async getEntitlement(subject: Subject) {
    return this.entitlements.get(subject) ?? null;
  }

  async setEntitlement(subject: Subject, record: EntitlementRecord) {
    this.entitlements.set(subject, record);
  }

  async merge(from: Subject, into: Subject, day: string) {
    const fromCounts = this.usage.get(this.key(from, day)) ?? {};
    const intoCounts = this.usage.get(this.key(into, day)) ?? {};
    for (const [action, n] of Object.entries(fromCounts) as [MeteredAction, number][]) {
      intoCounts[action] = (intoCounts[action] ?? 0) + n;
    }
    this.usage.set(this.key(into, day), intoCounts);
    const fromEnt = this.entitlements.get(from);
    const intoEnt = this.entitlements.get(into);
    if (fromEnt && (!intoEnt || intoEnt.tier === "free")) this.entitlements.set(into, fromEnt);
    await this.deleteSubject(from);
  }

  async deleteSubject(subject: Subject) {
    for (const k of [...this.usage.keys()]) if (k.startsWith(`${subject}|`)) this.usage.delete(k);
    this.entitlements.delete(subject);
  }
}

export function utcDay(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

export function nextUtcMidnight(now = new Date()): Date {
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1));
  return d;
}
