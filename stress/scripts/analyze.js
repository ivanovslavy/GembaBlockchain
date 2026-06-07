import { readdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { gunzipSync } from "node:zlib";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { classify } from "../lib/metrics.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const runId = process.argv.find((a) => a.startsWith("--run="))?.split("=")[1];
if (!runId) { console.error("usage: node scripts/analyze.js --run=<runId>"); process.exit(1); }
const dir = join(process.env.LOG_DIR || join(root, "logs"), runId);

function* readStream(name) {
  for (const f of readdirSync(dir).filter((x) => x.startsWith(name + ".") && (x.endsWith(".jsonl") || x.endsWith(".jsonl.gz"))).sort()) {
    const raw = f.endsWith(".gz") ? gunzipSync(readFileSync(join(dir, f))).toString("utf8") : readFileSync(join(dir, f), "utf8");
    for (const line of raw.split("\n")) if (line.trim()) { try { yield JSON.parse(line); } catch {} }
  }
}
const pct = (arr, p) => (arr.length ? arr.sort((a, b) => a - b)[Math.min(arr.length - 1, Math.floor(p * arr.length))] : 0);
const num = (x) => (x == null ? 0 : Number(x));

// ---- tx ----
let txTotal = 0, ok = 0, reverted = 0, timeout = 0;
const byType = {}, byTypeRevert = {}, lat = [];
for (const t of readStream("tx")) {
  txTotal++; byType[t.type] = (byType[t.type] || 0) + 1;
  if (t.status === "timeout") timeout++;
  else if (Number(t.status) === 0) { reverted++; byTypeRevert[t.type] = (byTypeRevert[t.type] || 0) + 1; }
  else ok++;
  if (typeof t.latencyMs === "number" && t.status !== "timeout") { if (lat.length < 300000) lat.push(t.latencyMs); }
}
// ---- errors ----
const errCounts = {};
for (const e of readStream("errors")) { const k = e.kind === "submit" ? classify(e.msg) : e.kind; errCounts[k] = (errCounts[k] || 0) + 1; }
// ---- blocks ----
let blkN = 0, gasUsedSum = 0n, gasLimit = 0n, maxTx = 0, maxGas = 0n, baseMin = null, baseMax = null;
const blkTs = [];
for (const b of readStream("blocks")) {
  blkN++; gasUsedSum += BigInt(b.gasUsed || 0); gasLimit = BigInt(b.gasLimit || gasLimit);
  maxTx = Math.max(maxTx, b.txCount || 0); if (BigInt(b.gasUsed || 0) > maxGas) maxGas = BigInt(b.gasUsed || 0);
  if (b.baseFeeWei != null) { const v = BigInt(b.baseFeeWei); baseMin = baseMin == null || v < baseMin ? v : baseMin; baseMax = baseMax == null || v > baseMax ? v : baseMax; }
  if (b.ts) blkTs.push(b.ts);
}
const blkGaps = []; for (let i = 1; i < blkTs.length; i++) blkGaps.push((blkTs[i] - blkTs[i - 1]) * 1000);
// ---- node ----
let diskStart = null, diskEnd = null, memPeak = 0, btMax = 0, btSum = 0, btN = 0, caughtUp = false;
for (const n of readStream("node")) {
  if (n.diskFreeGb != null) { if (diskStart == null) diskStart = n.diskFreeGb; diskEnd = n.diskFreeGb; }
  if (n.mempool != null) memPeak = Math.max(memPeak, n.mempool);
  if (n.blockTimeMs) { btMax = Math.max(btMax, n.blockTimeMs); btSum += n.blockTimeMs; btN++; }
  if (n.catchingUp) caughtUp = true;
}
// ---- metrics peaks ----
let peakSubmit = 0, peakMined = 0;
for (const m of readStream("metrics")) { peakSubmit = Math.max(peakSubmit, m.submitTps || 0); peakMined = Math.max(peakMined, m.minedTps || 0); }
const summary = existsSync(join(dir, "summary.json")) ? JSON.parse(readFileSync(join(dir, "summary.json"), "utf8")) : {};

const gwei = (w) => (w == null ? "?" : (Number(w) / 1e9).toFixed(2));
const fillPct = gasLimit > 0n ? Number(gasUsedSum / BigInt(Math.max(1, blkN)) * 100n / gasLimit) : 0;

// ---- suspected problems ----
const problems = [];
const unintendedReverts = reverted - (byTypeRevert.revertOp || 0) - (byTypeRevert.dexRemoveLiq || 0) - (byTypeRevert.dexSwap || 0);
if (txTotal && unintendedReverts / txTotal > 0.05) problems.push(`High *unexpected* revert rate: ${unintendedReverts}/${txTotal} (excl. intentional). Investigate by type: ${JSON.stringify(byTypeRevert)}`);
for (const k of ["mempool_full", "nonce", "rpc_timeout", "rate_limited", "tx_too_large", "fee_too_low", "connection"]) if (errCounts[k]) problems.push(`Submit errors '${k}': ${errCounts[k]}`);
if (timeout) problems.push(`${timeout} txs never mined within timeout (mempool eviction / drop?).`);
const avgBt = btN ? btSum / btN : 0;
if (avgBt > 6500) problems.push(`Block time drift: avg ${Math.round(avgBt)}ms (target ~5200ms) under load.`);
if (fillPct > 90) problems.push(`Blocks ~${fillPct.toFixed(0)}% full → block-gas-limited; raise limit or this is the TPS ceiling.`);
if (caughtUp) problems.push(`A node reported catching_up during the run (consensus fell behind).`);
if (diskStart != null && diskEnd != null && diskStart - diskEnd > 5) problems.push(`Disk grew ${(diskStart - diskEnd).toFixed(1)}GB during the run — watch state growth/pruning.`);
if (summary.pendingAtEnd) problems.push(`${summary.pendingAtEnd} txs still in-flight at end.`);
if (!problems.length) problems.push("No obvious red flags from heuristics — review the numbers above manually.");

const md = `# Stress report — ${runId}

**Profile ${summary.profile || "?"}** · ${summary.finishedAt || ""} · wallets ${summary.wallets || "?"}

## Throughput
- Submitted: **${summary.submitted ?? txTotal}** · Mined OK: **${ok}** · Reverted: **${reverted}** · Failed submit: **${summary.failedSubmit ?? "?"}** · Timed out: **${timeout}**
- Peak submit TPS: **${peakSubmit}** · Peak mined TPS: **${peakMined}**
${summary.knee ? `- Knee (profile A): target **${summary.knee.target}** tps, reason *${summary.knee.reason}*, sustained mined ≈ **${summary.knee.minedTps}** tps` : ""}

## Latency (submit → mined)
- p50 **${pct(lat, 0.5)}ms** · p95 **${pct(lat, 0.95)}ms** · p99 **${pct(lat, 0.99)}ms**  (block ≈ 5200ms)

## Blocks
- Blocks observed: ${blkN} · avg gas/block: ${blkN ? (gasUsedSum / BigInt(blkN)).toString() : 0} · block gas limit: ${gasLimit} · avg fill: **${fillPct.toFixed(1)}%**
- Max txs in a block: **${maxTx}** · max gas in a block: ${maxGas}
- Base fee: ${gwei(baseMin)} → ${gwei(baseMax)} gwei · block-time avg/max: ${Math.round(avgBt)}ms / ${btMax}ms

## By workload type
${Object.entries(byType).sort((a, b) => b[1] - a[1]).map(([k, v]) => `- ${k}: ${v}${byTypeRevert[k] ? ` (reverted ${byTypeRevert[k]})` : ""}`).join("\n")}

## Errors (submit + chain)
${Object.keys(errCounts).length ? Object.entries(errCounts).sort((a, b) => b[1] - a[1]).map(([k, v]) => `- ${k}: ${v}`).join("\n") : "- none"}

## Node
- Disk free: ${diskStart ?? "?"}GB → ${diskEnd ?? "?"}GB · mempool peak: ${memPeak} · node caught_up event: ${caughtUp ? "YES ⚠" : "no"}

## ⚑ Suspected problems
${problems.map((p) => `- ${p}`).join("\n")}
`;

writeFileSync(join(dir, "report.md"), md);
console.log(md);
console.log(`\n✓ report → ${join(dir, "report.md")}`);
