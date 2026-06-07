// Token-bucket rate limiter. setRate(tps) is adjustable on the fly (ramp/spike).
export class RateLimiter {
  constructor(tps) { this.setRate(tps); this.tokens = 0; this.last = Date.now(); }
  setRate(tps) { this.tps = Math.max(0, tps); this.capacity = Math.max(1, tps); }
  _refill() {
    const now = Date.now();
    this.tokens = Math.min(this.capacity, this.tokens + ((now - this.last) / 1000) * this.tps);
    this.last = now;
  }
  // Resolves when a token is available.
  async take() {
    for (;;) {
      this._refill();
      if (this.tokens >= 1) { this.tokens -= 1; return; }
      const need = this.tps > 0 ? (1 - this.tokens) / this.tps * 1000 : 50;
      await new Promise((r) => setTimeout(r, Math.min(100, Math.max(2, need))));
    }
  }
}

export class Semaphore {
  constructor(max) { this.max = max; this.cur = 0; this.q = []; }
  async acquire() {
    if (this.cur < this.max) { this.cur++; return; }
    await new Promise((r) => this.q.push(r));
    this.cur++;
  }
  release() { this.cur--; const r = this.q.shift(); if (r) r(); }
}
