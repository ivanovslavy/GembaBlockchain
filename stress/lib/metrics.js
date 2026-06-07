// Rolling counters + latency reservoir for periodic snapshots.
export class Metrics {
  constructor() {
    this.submitted = 0; this.mined = 0; this.failedSubmit = 0; this.reverted = 0; this.timedOut = 0;
    this.byType = {}; this.errors = {};
    this._subWindow = []; this._minWindow = []; // timestamps (ms)
    this._lat = []; // recent latencies (ms), capped reservoir
  }
  onSubmit(type) { this.submitted++; this.byType[type] = (this.byType[type] || 0) + 1; this._subWindow.push(Date.now()); }
  onSubmitFail(msg) { this.failedSubmit++; const k = classify(msg); this.errors[k] = (this.errors[k] || 0) + 1; }
  onMined(latencyMs, status) {
    this.mined++; if (status === 0) this.reverted++;
    this._minWindow.push(Date.now());
    this._lat.push(latencyMs); if (this._lat.length > 5000) this._lat.shift();
  }
  onTimeout() { this.timedOut++; }
  _tps(arr, win = 5000) { const now = Date.now(); while (arr.length && arr[0] < now - win) arr.shift(); return arr.length / (win / 1000); }
  snapshot(inflight) {
    const lat = [...this._lat].sort((a, b) => a - b);
    const pct = (p) => (lat.length ? lat[Math.min(lat.length - 1, Math.floor(p * lat.length))] : 0);
    return {
      ts: Date.now(), submitted: this.submitted, mined: this.mined, failedSubmit: this.failedSubmit,
      reverted: this.reverted, timedOut: this.timedOut, inflight,
      submitTps: +this._tps(this._subWindow).toFixed(1), minedTps: +this._tps(this._minWindow).toFixed(1),
      p50: pct(0.5), p95: pct(0.95), p99: pct(0.99),
      errors: { ...this.errors },
    };
  }
}

export function classify(msg) {
  const m = (msg || "").toLowerCase();
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
