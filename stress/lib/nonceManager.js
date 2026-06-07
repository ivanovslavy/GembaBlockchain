// Per-wallet local nonce pipeline — lets each wallet fire many txs without awaiting
// receipts (the key to high submit throughput). Resync on "nonce too low".
export class NonceManager {
  constructor() { this.next = new Map(); }

  async init(address, provider) {
    const n = await provider.getTransactionCount(address, "latest");
    this.next.set(address, n);
    return n;
  }
  take(address) {
    const n = this.next.get(address) ?? 0;
    this.next.set(address, n + 1);
    return n;
  }
  async resync(address, provider) {
    const n = await provider.getTransactionCount(address, "latest");
    this.next.set(address, n);
    return n;
  }
}
