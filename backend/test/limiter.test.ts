import { describe, expect, it } from "vitest";
import { ConcurrencyLimiter, Overloaded } from "../src/ai/limiter.js";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

describe("ConcurrencyLimiter", () => {
  it("never runs more than maxConcurrent tasks", async () => {
    const limiter = new ConcurrencyLimiter(2, 10, 5_000);
    let running = 0, peak = 0;
    const task = async () => { running++; peak = Math.max(peak, running); await sleep(20); running--; };
    await Promise.all(Array.from({ length: 8 }, () => limiter.run(task)));
    expect(peak).toBe(2);
    expect(limiter.stats.completed).toBe(8);
  });

  it("rejects immediately when the queue is full", async () => {
    const limiter = new ConcurrencyLimiter(1, 1, 5_000);
    const slow = limiter.run(() => sleep(50));
    const queued = limiter.run(() => sleep(1));
    const started = Date.now();
    await expect(limiter.run(() => sleep(1))).rejects.toBeInstanceOf(Overloaded);
    expect(Date.now() - started).toBeLessThan(20);
    await Promise.all([slow, queued]);
    expect(limiter.stats.rejected).toBe(1);
  });

  it("rejects queued work that waits too long", async () => {
    const limiter = new ConcurrencyLimiter(1, 5, 30);
    const slow = limiter.run(() => sleep(100));
    await expect(limiter.run(() => sleep(1))).rejects.toBeInstanceOf(Overloaded);
    await slow;
    expect(limiter.stats.queued).toBe(0);
  });

  it("releases capacity when a task throws", async () => {
    const limiter = new ConcurrencyLimiter(1, 1, 1_000);
    await expect(limiter.run(async () => { throw new Error("boom"); })).rejects.toThrow("boom");
    await expect(limiter.run(async () => 42)).resolves.toBe(42);
    expect(limiter.stats.running).toBe(0);
  });
});
