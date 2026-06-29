// Rolling counters + latency reservoir for periodic snapshots.
export class Metrics {
  constructor() {
    this.submitted = 0; this.mined = 0; this.failedSubmit = 0; this.reverted = 0; this.timedOut = 0;
    this.softSubmit = 0; // benign mempool churn (already-known / replacement / nonce-resync) — NOT a hard failure
    this.byType = {}; this.errors = {}; this.softErrors = {};
    this._subWindow = []; this._minWindow = []; // timestamps (ms)
    this._lat = []; // recent latencies (ms), capped reservoir
  }
  onSubmit(type) { this.submitted++; this.byType[type] = (this.byType[type] || 0) + 1; this._subWindow.push(Date.now()); }
  onSubmitFail(msg) { this.failedSubmit++; const k = classify(msg); this.errors[k] = (this.errors[k] || 0) + 1; }
  // benign mempool churn — counted + visible, but excluded from the error-rate knee
  onSoft(msg) { this.softSubmit++; const k = classify(msg); this.softErrors[k] = (this.softErrors[k] || 0) + 1; }
  // mined = tx appeared in a block (cheap, no per-tx RPC). Throughput metric.
  onMined(latencyMs) {
    this.mined++;
    this._minWindow.push(Date.now());
    this._lat.push(latencyMs); if (this._lat.length > 5000) this._lat.shift();
  }
  onRevert() { this.reverted++; } // best-effort, from async receipt fetch
  onTimeout() { this.timedOut++; }
  _tps(arr, win = 5000) { const now = Date.now(); while (arr.length && arr[0] < now - win) arr.shift(); return arr.length / (win / 1000); }
  snapshot(inflight) {
    const lat = [...this._lat].sort((a, b) => a - b);
    const pct = (p) => (lat.length ? lat[Math.min(lat.length - 1, Math.floor(p * lat.length))] : 0);
    return {
      ts: Date.now(), submitted: this.submitted, mined: this.mined, failedSubmit: this.failedSubmit,
      softSubmit: this.softSubmit, reverted: this.reverted, timedOut: this.timedOut, inflight,
      submitTps: +this._tps(this._subWindow).toFixed(1), minedTps: +this._tps(this._minWindow).toFixed(1),
      p50: pct(0.5), p95: pct(0.95), p99: pct(0.99),
      errors: { ...this.errors }, softErrors: { ...this.softErrors },
    };
  }
}

export function classify(msg) {
  const m = (msg || "").toLowerCase();
  if (m.includes("replacement") || m.includes("underpriced")) return "replacement"; // nonce dup, NOT a fee floor issue
  if (m.includes("coalesce")) return "coalesce";                                     // unparseable RPC resp (likely submitted)
  if (m.includes("nonce")) return "nonce";
  if (m.includes("mempool is full") || m.includes("txpool") || m.includes("mempool")) return "mempool_full";
  if (m.includes("tx too large") || m.includes("too large")) return "tx_too_large";
  if (m.includes("insufficient funds")) return "insufficient_funds";
  if (m.includes("intrinsic gas")) return "intrinsic_gas";
  if (m.includes("fee") && m.includes("low")) return "fee_too_low";
  if (m.includes("already known") || m.includes("already in")) return "already_known";
  if (m.includes("timeout") || m.includes("timed out")) return "rpc_timeout";
  if (m.includes("429") || m.includes("rate")) return "rate_limited";
  if (m.includes("connection") || m.includes("econn") || m.includes("socket")) return "connection";
  return "other";
}
