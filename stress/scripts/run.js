import "dotenv/config";
import { Interface } from "ethers";
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { makeProviders } from "../lib/provider.js";
import { loadWallets, asSigners } from "../lib/wallets.js";
import { NonceManager } from "../lib/nonceManager.js";
import { RateLimiter, Semaphore } from "../lib/rateLimiter.js";
import { RunLogger } from "../lib/txLogger.js";
import { Metrics } from "../lib/metrics.js";
import { ReceiptCollector } from "../lib/receiptCollector.js";
import { NodeProbe } from "../lib/nodeProbe.js";
import { feeOverrides, sendRaw } from "../lib/tx.js";
import { buildProfile } from "../config/profiles.js";
import { buildWorkloadSet } from "../config/workloads.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const art = (n) => JSON.parse(readFileSync(join(root, "artifacts", `${n}.json`), "utf8"));
const env = process.env;
const profileName = (process.argv.find((a) => a.startsWith("--profile="))?.split("=")[1] || "A").toUpperCase();
const profile = buildProfile(profileName, env);
const dep = JSON.parse(readFileSync(join(root, "deployed.json"), "utf8"));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const providers = makeProviders(env.RPC_URLS.split(","), env.CHAIN_ID);
const records = loadWallets();
const signers = asSigners(records, providers);
const fee = feeOverrides(env);
const chainId = Number(env.CHAIN_ID);

const runId = `${profileName}-${new Date().toISOString().replace(/[:.]/g, "-")}`;
const logger = new RunLogger(runId, env.LOG_DIR || join(root, "logs"), Number(env.LOG_ROTATE_LINES || 200000));
const metrics = new Metrics();
const collector = new ReceiptCollector(providers, metrics, logger);
const probe = new NodeProbe(env.COMETBFT_RPC, env.NODE_DATA_DIR, logger, { minFreeGb: Number(env.DISK_MIN_FREE_GB || 12) });

// workload context
const indexByAddr = new Map(records.map((r) => [r.address, r.index]));
const ctx = {
  iface: { erc20: new Interface(art("StressERC20").abi), erc721: new Interface(art("StressERC721").abi), erc1155: new Interface(art("StressERC1155").abi), storage: new Interface(art("Storage").abi), gasbomb: new Interface(art("GasBomb").abi), dex: new Interface(art("StressDex").abi) },
  addr: dep.addresses,
  addresses: records.map((r) => r.address),
  indexOf: (a) => indexByAddr.get(a),
  nft: { count: 0 }, maxNft: Number(env.MAX_NFT_SUPPLY || 200000),
  deployBytecode: art("Storage").bytecode,
};
const work = buildWorkloadSet(profile.weights, ctx);
const sem = new Semaphore(profile.concurrency);
const rate = new RateLimiter(profile.startTps || 5);

console.log(`\n▶ profile ${profileName} | wallets ${records.length} | concurrency ${profile.concurrency} | RPCs ${providers.all.length}`);
console.log(`  run ${runId}\n`);

// init nonces (chunked)
const nonceMgr = new NonceManager();
for (let i = 0; i < signers.length; i += 50) {
  await Promise.all(signers.slice(i, i + 50).map((s) => nonceMgr.init(s.address, providers.next()).catch(() => 0)));
}

let running = true;
let rr = 0;
async function fireOne() {
  const sig = signers[rr++ % signers.length];
  const it = work.pick();
  let req; try { req = it.build(ctx, sig.address); } catch { return; }
  if (!req) return;
  const submitMs = Date.now();
  try {
    const { hash, nonce } = await sendRaw(sig, sig.provider(), nonceMgr, req, fee, chainId);
    metrics.onSubmit(it.type);
    collector.track(hash, { submitMs, row: { ts: submitMs, profile: profileName, walletIdx: sig.index, from: sig.address, nonce, type: it.type, to: req.to ?? null, gas: req.gas.toString() } });
  } catch (e) {
    metrics.onSubmitFail(String(e.message || e));
    logger.write("errors", { kind: "submit", type: it.type, from: sig.address, msg: String(e.message || e).slice(0, 200) });
  }
}
async function pump() { while (running) { await rate.take(); if (!running) break; await sem.acquire(); fireOne().finally(() => sem.release()); } }

collector.start();
let prev = { submitted: 0, failedSubmit: 0 };
const mon = setInterval(async () => {
  const s = metrics.snapshot(collector.size);
  logger.write("metrics", s);
  const np = await probe.sample();
  const dSub = s.submitted - prev.submitted, dErr = s.failedSubmit - prev.failedSubmit; prev = s;
  const errRate = dSub > 0 ? dErr / dSub : 0;
  s._errRate = errRate;
  process.stdout.write(`\r  tps s/m ${s.submitTps}/${s.minedTps} | inflight ${s.inflight} | p95 ${s.p95}ms | err ${(errRate * 100).toFixed(1)}% | blk ${np.height ?? "?"} ${np.blockTimeMs ?? "?"}ms | mem ${np.mempool ?? "?"} | disk ${np.diskFreeGb ?? "?"}GB    `);
  if (probe.aborted) { console.log(`\n⚠ ABORT: ${probe.abortReason}`); running = false; }
  global._last = s;
}, 2000);

// ---- schedules ----
async function runPhases() {
  for (const ph of profile.phases) {
    if (!running) break;
    console.log(`\n  ▸ phase ${ph.name} (${ph.durationSec}s) → ${ph.tps ?? `${ph.fromTps}->${ph.toTps}`} tps`);
    const t0 = Date.now(), dur = ph.durationSec * 1000;
    while (running && Date.now() - t0 < dur) {
      const f = (Date.now() - t0) / dur;
      const tps = ph.tps != null ? ph.tps : Math.round(ph.fromTps + (ph.toTps - ph.fromTps) * f);
      rate.setRate(tps);
      await sleep(1000);
    }
  }
}
async function runRamp() {
  const k = profile.knee; let target = profile.startTps;
  rate.setRate(target);
  console.log(`  ▸ warmup ${profile.warmupSec}s @ ${target} tps`);
  await sleep(profile.warmupSec * 1000);
  const t0 = Date.now();
  let knee = null;
  while (running && Date.now() - t0 < profile.maxDurationSec * 1000) {
    target += profile.stepTps; rate.setRate(target);
    await sleep(profile.stepSec * 1000);
    const s = global._last || metrics.snapshot(collector.size);
    const plateau = s.submitTps >= target * 0.8 && s.minedTps < s.submitTps * k.plateauRatio;
    if (s.p95 > k.p95Ms || (s._errRate || 0) > k.errRate || plateau) {
      knee = { target, reason: s.p95 > k.p95Ms ? "p95" : plateau ? "plateau" : "errors", minedTps: s.minedTps };
      console.log(`\n  ● knee at target ${target} tps (${knee.reason}); sustained mined ≈ ${s.minedTps} tps`);
      break;
    }
  }
  profile._knee = knee || { target, reason: "maxDuration", minedTps: (global._last || {}).minedTps };
}

const onSig = () => { console.log("\n  …draining"); running = false; };
process.on("SIGINT", onSig); process.on("SIGTERM", onSig);

pump();
if (profile.mode === "ramp") await runRamp(); else await runPhases();
running = false;
clearInterval(mon);
console.log("\n  draining in-flight…");
await collector.drain(90000);
collector.stop();

const final = metrics.snapshot(collector.size);
const summary = { runId, profile: profileName, finishedAt: new Date().toISOString(), wallets: records.length, ...final, knee: profile._knee, pendingAtEnd: collector.size };
logger.write("summary", summary);
writeFileSync(join(logger.dir, "summary.json"), JSON.stringify(summary, null, 2));
await logger.close();
console.log(`\n✓ done. submitted ${final.submitted} | mined ${final.mined} | reverted ${final.reverted} | failedSubmit ${final.failedSubmit} | timeout ${final.timedOut}`);
if (profile._knee) console.log(`  → suggested TARGET_TPS=${profile._knee.minedTps || profile._knee.target} for profiles B/C`);
console.log(`  logs: ${logger.dir}  → run: node scripts/analyze.js --run=${runId}`);
process.exit(0);
