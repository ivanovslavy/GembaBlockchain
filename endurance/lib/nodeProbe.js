import { statfs } from "node:fs";
import { promisify } from "node:util";
const statfsAsync = promisify(statfs);

// Best-effort node health: CometBFT status + mempool size + data-dir free space.
// Runs ON .83, so it can read local disk directly.
export class NodeProbe {
  constructor(cometRpc, dataDir, logger, { minFreeGb = 12 } = {}) {
    this.cometRpc = cometRpc; this.dataDir = dataDir; this.logger = logger; this.minFreeGb = minFreeGb;
    this.aborted = false; this.lastHeight = 0; this.lastTs = 0;
  }
  async sample() {
    const row = { ts: Date.now() };
    try {
      const s = await fetchJson(`${this.cometRpc}/status`);
      const si = s?.result?.sync_info;
      row.height = Number(si?.latest_block_height);
      row.catchingUp = !!si?.catching_up;
      const t = si?.latest_block_time ? Date.parse(si.latest_block_time) : 0;
      if (this.lastHeight && row.height > this.lastHeight && this.lastTs)
        row.blockTimeMs = Math.round((t - this.lastTs) / (row.height - this.lastHeight));
      this.lastHeight = row.height; this.lastTs = t;
      if (row.catchingUp) this._abort("node catching_up");
    } catch (e) { row.statusErr = String(e.message || e); }
    try {
      const u = await fetchJson(`${this.cometRpc}/num_unconfirmed_txs`);
      row.mempool = Number(u?.result?.total);
    } catch {}
    try {
      const st = await statfsAsync(this.dataDir);
      const freeGb = (st.bavail * st.bsize) / 1e9;
      row.diskFreeGb = +freeGb.toFixed(2);
      if (freeGb < this.minFreeGb) this._abort(`disk free ${freeGb.toFixed(1)}GB < ${this.minFreeGb}GB`);
    } catch (e) { row.diskErr = String(e.message || e); }
    this.logger.write("node", row);
    return row;
  }
  _abort(reason) { if (!this.aborted) { this.aborted = true; this.abortReason = reason; } }
}
async function fetchJson(url) {
  const c = new AbortController(); const t = setTimeout(() => c.abort(), 5000);
  try { const r = await fetch(url, { signal: c.signal }); return await r.json(); } finally { clearTimeout(t); }
}
