/**
 * Bounded concurrency for AI provider calls (backpressure).
 *
 * A local model serves only a few requests at once. Without a limit, excess
 * requests wait inside the provider until they time out, which wastes model
 * time on answers the phone has already given up on. With the limiter, at
 * most `maxConcurrent` calls run, up to `maxQueue` wait, and anything that
 * cannot start within `maxWaitMs` is rejected immediately with a retryable
 * error. See docs/benchmarks/ExperimentLog.md, experiment F.
 */
export class Overloaded extends Error {
  constructor(readonly retryAfterSeconds: number) {
    super("AI provider is at capacity");
  }
}

export interface LimiterStats {
  running: number;
  queued: number;
  rejected: number;
  completed: number;
}

export class ConcurrencyLimiter {
  private running = 0;
  private readonly queue: { start: () => void; timer: NodeJS.Timeout }[] = [];
  private rejected = 0;
  private completed = 0;

  constructor(
    readonly maxConcurrent: number,
    readonly maxQueue: number,
    readonly maxWaitMs: number,
  ) {
    if (maxConcurrent < 1) throw new Error("maxConcurrent must be at least 1");
  }

  get stats(): LimiterStats {
    return { running: this.running, queued: this.queue.length, rejected: this.rejected, completed: this.completed };
  }

  async run<T>(task: () => Promise<T>): Promise<T> {
    await this.acquire();
    try {
      return await task();
    } finally {
      this.completed++;
      this.release();
    }
  }

  private acquire(): Promise<void> {
    if (this.running < this.maxConcurrent) {
      this.running++;
      return Promise.resolve();
    }
    if (this.queue.length >= this.maxQueue) {
      this.rejected++;
      return Promise.reject(new Overloaded(Math.ceil(this.maxWaitMs / 1000)));
    }
    return new Promise((resolve, reject) => {
      const entry = {
        start: () => {
          clearTimeout(entry.timer);
          this.running++;
          resolve();
        },
        timer: setTimeout(() => {
          const i = this.queue.indexOf(entry);
          if (i >= 0) this.queue.splice(i, 1);
          this.rejected++;
          reject(new Overloaded(Math.ceil(this.maxWaitMs / 1000)));
        }, this.maxWaitMs),
      };
      this.queue.push(entry);
    });
  }

  private release() {
    this.running--;
    const next = this.queue.shift();
    if (next) next.start();
  }
}
