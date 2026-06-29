// Per-wallet nonce pipeline WITH a bounded in-flight window. The local nonce must not
// outrun the mined nonce by more than `cap` — otherwise Cosmos EVM returns a hash for
// the future-nonce tx (no submit error) but never mines it (the `app` mempool won't
// include past a gap), which floods timeouts and starves real throughput.
export class NonceManager {
  constructor() { this.next = new Map(); this.inflight = new Map(); }

  async init(address, provider) {
    const n = await provider.getTransactionCount(address, "latest");
    this.next.set(address, n); this.inflight.set(address, 0);
    return n;
  }
  canSend(address, cap) { return (this.inflight.get(address) || 0) < cap; }
  take(address) {
    const n = this.next.get(address) ?? 0;
    this.next.set(address, n + 1);
    this.inflight.set(address, (this.inflight.get(address) || 0) + 1);
    return n;
  }
  settle(address) { this.inflight.set(address, Math.max(0, (this.inflight.get(address) || 0) - 1)); }
  // After a timeout, advance the local nonce to chain truth WITHOUT rewinding past
  // nonces we've already broadcast (rewinding re-sends pending nonces → "replacement fee
  // too low"). Only move forward; recompute in-flight from the gap.
  async resync(address, provider) {
    const mined = await provider.getTransactionCount(address, "latest");
    const cur = this.next.get(address) ?? mined;
    const next = Math.max(cur, mined);
    this.next.set(address, next);
    this.inflight.set(address, Math.max(0, next - mined));
    return next;
  }
}
