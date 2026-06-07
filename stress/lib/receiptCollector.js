// Resolves in-flight txs to "mined" by scanning each new block's tx-hash list — ONE
// getBlock per block, no per-tx RPC. This keeps throughput measurement accurate even
// over a WAN (RPi → remote nodes). Receipts (status/gasUsed for revert stats) are
// fetched best-effort in a bounded background pool that may lag without affecting the
// mined count or wallet nonce settling.
export class ReceiptCollector {
  constructor(providers, metrics, logger, { timeoutMs = 120000, onSettle = null, receiptConcurrency = 16 } = {}) {
    this.providers = providers; this.metrics = metrics; this.logger = logger; this.timeoutMs = timeoutMs;
    this.onSettle = onSettle; this.receiptConcurrency = receiptConcurrency;
    this.inflight = new Map();   // hash -> {submitMs, row}
    this.receiptQ = [];          // {hash, type, block} for best-effort status fetch
    this.running = false; this.lastBlock = 0;
  }
  track(hash, meta) { this.inflight.set(hash, meta); }
  get size() { return this.inflight.size; }

  start() { this.running = true; this._blockLoop(); this._sweepLoop(); for (let i = 0; i < this.receiptConcurrency; i++) this._receiptWorker(); }
  stop() { this.running = false; }

  async _blockLoop() {
    while (this.running) {
      try {
        const bn = await this.providers.primary.getBlockNumber();
        if (bn > this.lastBlock) {
          for (let n = this.lastBlock === 0 ? bn : this.lastBlock + 1; n <= bn; n++) await this._block(n);
          this.lastBlock = bn;
        }
      } catch {}
      await sleep(1000);
    }
  }
  async _block(n) {
    let blk; try { blk = await this.providers.next().getBlock(n, false); } catch { return; }
    if (!blk) return;
    this.logger.write("blocks", { number: blk.number, ts: blk.timestamp, txCount: blk.transactions.length, gasUsed: blk.gasUsed?.toString(), gasLimit: blk.gasLimit?.toString(), baseFeeWei: blk.baseFeePerGas?.toString() ?? null });
    const now = Date.now();
    for (const h of blk.transactions) {
      const m = this.inflight.get(h);
      if (!m) continue;
      this.inflight.delete(h);
      const latency = now - m.submitMs;
      this.metrics.onMined(latency);
      this.logger.write("tx", { ...m.row, hash: h, block: blk.number, minedMs: now, latencyMs: latency });
      this.onSettle?.(m.row.from, true);
      if (this.receiptQ.length < 100000) this.receiptQ.push({ hash: h, type: m.row.type, block: blk.number });
    }
  }
  async _receiptWorker() {
    while (this.running) {
      const job = this.receiptQ.shift();
      if (!job) { await sleep(50); continue; }
      try {
        const r = await this.providers.next().getTransactionReceipt(job.hash);
        if (r && Number(r.status) === 0) { this.metrics.onRevert(); this.logger.write("errors", { kind: "revert", hash: job.hash, type: job.type, block: job.block }); }
      } catch {}
    }
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
  async drain(maxMs = 60000) { const t0 = Date.now(); while (this.inflight.size > 0 && Date.now() - t0 < maxMs) await sleep(1000); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
