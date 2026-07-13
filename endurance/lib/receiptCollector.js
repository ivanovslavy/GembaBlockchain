// Resolves in-flight txs to "mined" by scanning each new block's tx-hash list — ONE
// getBlock per block, no per-tx RPC. This keeps throughput measurement accurate even
// over a WAN (Pi → remote public RPCs). Receipts (status/gasUsed for revert stats) are
// fetched best-effort in a bounded background pool that may lag without affecting the
// mined count or wallet nonce settling.
export class ReceiptCollector {
  constructor(providers, metrics, logger, { timeoutMs = 120000, onSettle = null, onResolve = null, receiptConcurrency = 6 } = {}) {
    this.providers = providers; this.metrics = metrics; this.logger = logger; this.timeoutMs = timeoutMs;
    this.onSettle = onSettle; this.onResolve = onResolve; this.receiptConcurrency = receiptConcurrency;
    this.inflight = new Map();   // hash -> {submitMs, signed, deadline, rebroadcast, row}
    this.receiptQ = [];          // {hash, type, block} for best-effort status fetch
    this.running = false; this.lastBlock = 0;
    this.rebroadcasts = 0;       // observability: how many timed-out txs we re-pushed
  }
  // RELIABILITY FIX #3 — `meta.signed` is stored so a tx that gets dropped from the mempool
  // (no submit error, but never mined) can be RE-BROADCAST once on its first timeout.
  track(hash, meta) {
    meta.deadline = (meta.submitMs || Date.now()) + this.timeoutMs;
    meta.rebroadcast = false;
    this.inflight.set(hash, meta);
  }
  get size() { return this.inflight.size; }

  start() { this.running = true; this._blockLoop(); this._sweepLoop(); for (let i = 0; i < this.receiptConcurrency; i++) this._receiptWorker(); }
  stop() { this.running = false; }

  async _blockLoop() {
    while (this.running) {
      try {
        const bn = await this.providers.primary.getBlockNumber();
        if (this.lastBlock === 0) this.lastBlock = bn - 1; // start from the tip, don't backfill history
        // advance ONE block at a time; only past blocks we actually scanned. A failed getBlock
        // over the WAN must NOT skip the block (that would false-time-out every tracked tx in it).
        while (this.running && this.lastBlock < bn) {
          const ok = await this._block(this.lastBlock + 1);
          if (!ok) break; // fetch failed on all providers — retry this same block next iteration
          this.lastBlock += 1;
        }
      } catch {}
      await sleep(1000);
    }
  }
  // returns true if the block was fetched + scanned, false if all providers failed (so the
  // caller does not advance past it).
  async _block(n) {
    let blk = null;
    for (const p of this.providers.all) { try { blk = await p.getBlock(n, false); if (blk) break; } catch {} }
    if (!blk) return false;
    this.logger.write("blocks", { number: blk.number, ts: blk.timestamp, txCount: blk.transactions.length, gasUsed: blk.gasUsed?.toString(), gasLimit: blk.gasLimit?.toString(), baseFeeWei: blk.baseFeePerGas?.toString() ?? null });
    const now = Date.now();
    for (const h of blk.transactions) {
      const m = this.inflight.get(h);
      if (!m) continue;
      this.inflight.delete(h);
      const latency = now - m.submitMs;
      this.metrics.onMined(latency); // throughput metric — counts the mine regardless of status
      this.logger.write("tx", { ...m.row, hash: h, block: blk.number, minedMs: now, latencyMs: latency, rebroadcast: m.rebroadcast || undefined });
      this.onSettle?.(m.row.from, true); // account nonce advanced even on a revert
      // Producer effects are NOT applied here — a reverted tx is also "mined". They are applied
      // from the receipt worker, gated on STATUS == success, so a revert can't corrupt state.
      this.receiptQ.push({ hash: h, type: m.row.type, block: blk.number, tries: 0 });
    }
    return true;
  }
  async _receiptWorker() {
    while (this.running) {
      const job = this.receiptQ.shift();
      if (!job) { await sleep(50); continue; }
      let r = null;
      for (const p of this.providers.all) { try { r = await p.getTransactionReceipt(job.hash); if (r) break; } catch {} }
      try {
        if (!r) { // transient: the tx IS mined (block scan saw it) — retry a few times before giving up
          if (job.tries < 4) { job.tries++; this.receiptQ.push(job); await sleep(200); }
          else this.onResolve?.(job.hash, false); // give up → discard the producer effect (conservative)
          continue;
        }
        const ok = Number(r.status) === 1;
        if (!ok) {
          this.metrics.onRevert();
          const reason = await this._revertReason(job.hash, job.block); // best-effort; null if it can't be recovered
          this.logger.write("errors", { kind: "revert", hash: job.hash, type: job.type, block: job.block, reason: reason || "unknown", gasUsed: r.gasUsed?.toString() });
        }
        this.onResolve?.(job.hash, ok); // CONFIRMATION-GATE: apply producer effect ONLY on success
      } catch {}
    }
  }
  // Best-effort revert-reason recovery: replay the mined tx via eth_call against the
  // state before its block and decode the revert. A tx that does NOT revert on replay
  // was a state/timing race (e.g. removeLiquidity on an already-drained pool) — reported
  // as "state-race" rather than a deterministic contract failure. Never throws.
  async _revertReason(hash, block) {
    try {
      let tx = null;
      for (const p of this.providers.all) { try { tx = await p.getTransaction(hash); if (tx) break; } catch {} }
      if (!tx) return null;
      const req = { to: tx.to, from: tx.from, data: tx.data, value: tx.value, gasLimit: tx.gasLimit };
      const at = typeof block === "number" && block > 0 ? block - 1 : "latest"; // state the tx executed against
      for (const p of this.providers.all) {
        try {
          await p.call({ ...req, blockTag: at });
          return "state-race"; // replayed clean → not a deterministic revert
        } catch (e) {
          const msg = e?.reason || e?.revert?.name || e?.shortMessage || e?.info?.error?.message || e?.code || "unknown";
          return String(msg).replace(/\s+/g, " ").trim().slice(0, 140);
        }
      }
    } catch {}
    return null;
  }
  async _sweepLoop() {
    while (this.running) {
      const now = Date.now();
      for (const [h, m] of this.inflight) {
        if (now <= m.deadline) continue;
        if (!m.rebroadcast && m.signed) {
          // First miss: re-broadcast the SAME signed tx once (idempotent) and give it one more
          // full window. Recovers txs silently dropped from the mempool over the WAN.
          m.rebroadcast = true; m.deadline = now + this.timeoutMs; this.rebroadcasts++;
          this.providers.next().broadcastTransaction(m.signed).catch(() => {}); // "already known" is benign
          this.logger.write("errors", { kind: "rebroadcast", hash: h, type: m.row.type });
          continue;
        }
        // Second miss (or no signed blob): give up and count the timeout.
        this.inflight.delete(h); this.metrics.onTimeout();
        this.logger.write("tx", { ...m.row, hash: h, status: "timeout", latencyMs: now - m.submitMs });
        this.logger.write("errors", { kind: "timeout", hash: h, type: m.row.type });
        this.onSettle?.(m.row.from, false);
        this.onResolve?.(h, false); // never mined → discard the producer's (deferred) effect
      }
      await sleep(3000);
    }
  }
  async drain(maxMs = 60000) { const t0 = Date.now(); while (this.inflight.size > 0 && Date.now() - t0 < maxMs) await sleep(1000); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
