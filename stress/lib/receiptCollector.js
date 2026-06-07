// Tracks in-flight txs and resolves them to receipts (block, status, gasUsed, latency)
// without blocking the submit loop. Polls new blocks; sweeps stragglers; times out.
export class ReceiptCollector {
  constructor(providers, metrics, logger, { timeoutMs = 120000, onSettle = null } = {}) {
    this.providers = providers; this.metrics = metrics; this.logger = logger; this.timeoutMs = timeoutMs; this.onSettle = onSettle;
    this.inflight = new Map(); // hash -> {submitMs, type, from}
    this.running = false;
    this.lastBlock = 0;
  }
  track(hash, meta) { this.inflight.set(hash, meta); }
  get size() { return this.inflight.size; }

  start() { this.running = true; this._blockLoop(); this._sweepLoop(); }
  stop() { this.running = false; }

  async _blockLoop() {
    while (this.running) {
      try {
        const p = this.providers.primary;
        const bn = await p.getBlockNumber();
        if (bn > this.lastBlock) {
          for (let n = this.lastBlock === 0 ? bn : this.lastBlock + 1; n <= bn; n++) await this._block(n);
          this.lastBlock = bn;
        }
      } catch {}
      await sleep(1000);
    }
  }
  async _block(n) {
    const p = this.providers.next();
    let blk;
    try { blk = await p.getBlock(n, false); } catch { return; }
    if (!blk) return;
    this.logger.write("blocks", {
      number: blk.number, ts: blk.timestamp, txCount: blk.transactions.length,
      gasUsed: blk.gasUsed?.toString(), gasLimit: blk.gasLimit?.toString(),
      baseFeeWei: blk.baseFeePerGas?.toString() ?? null,
    });
    for (const h of blk.transactions) if (this.inflight.has(h)) await this._resolve(h, blk.number);
  }
  async _resolve(hash, blockNumber) {
    const meta = this.inflight.get(hash); if (!meta) return;
    this.inflight.delete(hash);
    let rcpt = null;
    try { rcpt = await this.providers.next().getTransactionReceipt(hash); } catch {}
    const latency = Date.now() - meta.submitMs;
    const status = rcpt ? Number(rcpt.status) : 1;
    this.metrics.onMined(latency, status);
    this.logger.write("tx", {
      ...meta.row, hash, block: blockNumber, minedMs: Date.now(), latencyMs: latency,
      status, gasUsed: rcpt?.gasUsed?.toString() ?? null,
    });
    if (status === 0) this.logger.write("errors", { kind: "revert", hash, type: meta.row.type, block: blockNumber });
    this.onSettle?.(meta.row.from, true);
  }
  async _sweepLoop() {
    while (this.running) {
      const now = Date.now();
      for (const [h, m] of this.inflight) {
        if (now - m.submitMs > this.timeoutMs) {
          this.inflight.delete(h); this.metrics.onTimeout();
          this.logger.write("tx", { ...m.row, hash: h, status: "timeout", latencyMs: now - m.submitMs });
          this.logger.write("errors", { kind: "timeout", hash: h, type: m.row.type });
          this.onSettle?.(m.row.from, false);
        }
      }
      await sleep(3000);
    }
  }
  async drain(maxMs = 60000) {
    const t0 = Date.now();
    while (this.inflight.size > 0 && Date.now() - t0 < maxMs) await sleep(1000);
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
