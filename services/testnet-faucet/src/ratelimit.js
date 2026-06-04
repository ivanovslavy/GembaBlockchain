// Per-key cooldown rate limiter for the testnet faucet. Pure (no deps) so it is
// unit-test runnable. The faucet rate-limits per recipient ADDRESS and per IP so a
// single requester can't drain the drip account.

export class CooldownLimiter {
  /** @param {number} cooldownMs minimum time between successful acquisitions per key */
  constructor(cooldownMs) {
    this.cooldownMs = cooldownMs;
    this._last = new Map(); // key -> last-acquire timestamp (ms)
  }

  /** ms remaining before `key` may acquire again (0 = available now). */
  remaining(key, now = Date.now()) {
    const t = this._last.get(key);
    if (t === undefined) return 0;
    return Math.max(0, this.cooldownMs - (now - t));
  }

  /** Try to acquire for `key`; returns true and records the time, or false if cooling down. */
  tryAcquire(key, now = Date.now()) {
    if (this.remaining(key, now) > 0) return false;
    this._last.set(key, now);
    return true;
  }

  /** Roll back a recorded acquisition (e.g. when the on-chain send failed). */
  release(key) {
    this._last.delete(key);
  }
}
