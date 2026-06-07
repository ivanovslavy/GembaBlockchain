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
  // After a timeout (gap suspected) resync the local nonce to chain truth and clear in-flight.
  async resync(address, provider) {
    const n = await provider.getTransactionCount(address, "latest");
    this.next.set(address, n); this.inflight.set(address, 0);
    return n;
  }
}
