import "dotenv/config";
import { Interface, Contract, Wallet, getCreateAddress, getCreate2Address, toBeHex, zeroPadValue } from "ethers";
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
const profileName = (process.argv.find((a) => a.startsWith("--profile="))?.split("=")[1] || "ENDURANCE").toUpperCase();
const profile = buildProfile(profileName, env);
const dep = JSON.parse(readFileSync(join(root, "deployed.json"), "utf8"));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const providers = makeProviders(env.RPC_URLS.split(","), env.CHAIN_ID);
const records = loadWallets();
const signers = asSigners(records, providers); // FIX #1: each wallet pinned to ONE RPC (in asSigners)
const fee = feeOverrides(env);
const chainId = Number(env.CHAIN_ID);

const runId = `${profileName}-${new Date().toISOString().replace(/[:.]/g, "-")}`;
const logger = new RunLogger(runId, env.LOG_DIR || join(root, "logs"), Number(env.LOG_ROTATE_LINES || 200000));
const metrics = new Metrics();
const nonceMgr = new NonceManager();
const collector = new ReceiptCollector(providers, metrics, logger, {
  timeoutMs: Number(env.TX_TIMEOUT_MS || 120000),
  receiptConcurrency: Number(env.RECEIPT_CONCURRENCY || 6),
  onSettle: (addr, mined) => { nonceMgr.settle(addr); if (!mined) nonceMgr.resync(addr, providers.primary).catch(() => {}); },
  // CONFIRMATION-GATE: _apply (producer effect) runs ONLY on success; _onResolve runs on any
  // definitive outcome (success/revert/timeout) — used by permit to clear in-flight + resync.
  onResolve: (hash, ok) => { const e = ctx.pendingByHash.get(hash); if (!e) return; ctx.pendingByHash.delete(hash); try { e.onResolve?.(ok); if (ok) e.apply?.(); } catch {} },
});
// Node/disk probe is OPT-IN (COMETBFT_RPC set). On the Pi run we DO NOT probe the validators,
// so it stays disabled — we never touch validator hosts.
const probe = env.COMETBFT_RPC ? new NodeProbe(env.COMETBFT_RPC, env.NODE_DATA_DIR, logger, { minFreeGb: Number(env.DISK_MIN_FREE_GB || 12) }) : null;

// minimal human-readable ABIs for the LIVE infra
const wgmbAbi = [
  { name: "deposit", type: "function", stateMutability: "payable", inputs: [], outputs: [] },
  { name: "withdraw", type: "function", stateMutability: "nonpayable", inputs: [{ type: "uint256", name: "wad" }], outputs: [] },
];
const routerAbi = [
  "function swapExactTokensForTokens(uint256 amountIn,uint256 amountOutMin,address[] path,address to,uint256 deadline) returns (uint256[])",
  "function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256 amountIn,uint256 amountOutMin,address[] path,address to,uint256 deadline)",
  "function addLiquidity(address tokenA,address tokenB,uint256 amountADesired,uint256 amountBDesired,uint256 amountAMin,uint256 amountBMin,address to,uint256 deadline) returns (uint256,uint256,uint256)",
  "function removeLiquidity(address tokenA,address tokenB,uint256 liquidity,uint256 amountAMin,uint256 amountBMin,address to,uint256 deadline) returns (uint256,uint256)",
];
const nativePoolAbi = [
  "function addLiquidity(uint256 amountTokenDesired,uint256 amountTokenMin,uint256 amountNativeMin,address to,uint256 deadline) payable returns (uint256,uint256,uint256)",
  "function removeLiquidity(uint256 liquidity,uint256 amountTokenMin,uint256 amountNativeMin,address to,uint256 deadline) returns (uint256,uint256)",
  "function swapExactNativeForTokens(uint256 amountOutMin,address to,uint256 deadline) payable returns (uint256)",
  "function swapExactTokensForNative(uint256 amountIn,uint256 amountOutMin,address to,uint256 deadline) returns (uint256)",
];

const indexByAddr = new Map(records.map((r) => [r.address, r.index]));
const walletByAddr = new Map(signers.map((s) => [s.address, s.wallet]));
const A = dep.addresses;
// per-run random bases so re-runs never collide (CREATE2 salts / chosen ERC721 ids must be fresh)
const base = BigInt(Date.now());
const voucherSigner = new Wallet(env.FUNDER_PK); // = founder = the VoucherMinter authorized signer
const ctx = {
  iface: {
    erc20: new Interface(art("EndERC20").abi), erc721: new Interface(art("EndERC721").abi), erc1155: new Interface(art("EndERC1155").abi),
    counter: new Interface(art("CounterFacet").abi), registry: new Interface(art("RegistryFacet").abi),
    ecoBank: new Interface(art("EcoBank").abi), market: new Interface(art("EnduranceMarket").abi), staking: new Interface(art("EnduranceStaking").abi),
    batch: new Interface(art("BatchExecutor").abi), workbench: new Interface(art("Workbench").abi),
    factory: new Interface(art("MiniFactory").abi), child: new Interface(art("ChildCounter").abi),
    cloneFactory: new Interface(art("CloneFactory").abi), cloneTarget: new Interface(art("CloneTarget").abi),
    vault: new Interface(art("MiniVault").abi), rewardStaking: new Interface(art("RewardStaking").abi),
    auctionHouse: new Interface(art("AuctionHouse").abi), batchNft: new Interface(art("BatchMintNFT").abi),
    nftStaking: new Interface(art("NftStaking").abi), royaltyNft: new Interface(art("RoyaltyNFT").abi), royaltyMarket: new Interface(art("RoyaltyMarket").abi),
    miniGov: new Interface(art("MiniGov").abi), hopA: new Interface(art("HopA").abi),
    disperse: new Interface(art("Disperse").abi), eventsHeavy: new Interface(art("EventsHeavy").abi),
    permit: new Interface(art("PermitToken").abi), voucher: new Interface(art("VoucherMinter").abi), rebase: new Interface(art("RebasingToken").abi),
    wgmb: new Interface(wgmbAbi), router: new Interface(routerAbi), nativePool: new Interface(nativePoolAbi),
  },
  addr: A,
  addresses: records.map((r) => r.address),
  indexOf: (a) => indexByAddr.get(a),
  pairs: [
    { a: A.tka, b: A.tkb, lp: A.pairAB },
    { a: A.tkb, b: A.tkc, lp: A.pairBC },
    { a: A.tka, b: A.tkc, lp: A.pairAC },
  ],
  settleMs: Number(env.SETTLE_MS || 20000),
  settled: (ts) => Date.now() - ts > ctx.settleMs,
  // deterministic-address helpers
  childBytecode: art("ChildCounter").bytecode,
  createAddr: (from, nonce) => getCreateAddress({ from, nonce }),
  create2Addr: (salt) => getCreate2Address(A.miniFactory, zeroPadValue(toBeHex(salt), 32), dep.childInitCodeHash),
  salt32: (salt) => zeroPadValue(toBeHex(salt), 32),
  cloneAddr: (saltHex) => getCreate2Address(A.cloneFactory, saltHex, dep.cloneInitCodeHash),
  // EIP-712 signing (synchronous via SigningKey)
  signingKeyOf: (addr) => walletByAddr.get(addr).signingKey,
  voucherSigningKey: voucherSigner.signingKey,
  permitDomain: { name: "Permit Token", version: "1", chainId, verifyingContract: A.permitToken },
  permitTypes: { Permit: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }, { name: "value", type: "uint256" }, { name: "nonce", type: "uint256" }, { name: "deadline", type: "uint256" }] },
  voucherDomain: { name: "Voucher Token", version: "1", chainId, verifyingContract: A.voucherMinter },
  voucherTypes: { Voucher: [{ name: "to", type: "address" }, { name: "id", type: "uint256" }, { name: "amount", type: "uint256" }, { name: "deadline", type: "uint256" }] },
  // per-run unique sequences (bigint)
  nftSeq: base * 1000n, mktSeq: base * 1000n + 100000000n, roySeq: base * 1000n + 200000000n,
  aucSeq: base * 1000n + 300000000n, batchSeq: base * 1000n + 400000000n,
  salt: base * 1000000n + BigInt((Math.random() * 1e6) | 0), cloneSalt: base * 1000000n + 500000000n + BigInt((Math.random() * 1e6) | 0),
  govPid: base * 1000n + 600000000n, voucherId: base * 1000n + 700000000n,
  // confirmation-gated workload state
  pendingByHash: new Map(),
  nftOwned: {}, mktOwned: {}, has1155: {}, wgmb: {}, eco: {}, stake: {}, lp: {}, nlp: {},
  eoaChildren: {}, factoryChildren: {}, clones: {},
  mktListed: [], mktCursor: 0, royOwned: {}, royListed: [], royCursor: 0,
  batchIds: {}, nftStaked: {}, vault: {}, rwd: {},
  aucOwned: {}, auctions: [], props: [],
  permitNonce: {}, permitsBySpender: {}, permitInFlight: {},
};

const work = buildWorkloadSet(profile.weights, ctx);
const sem = new Semaphore(profile.concurrency);
const rate = new RateLimiter(profile.phases?.[0]?.fromTps || 1);
const CAP = Number(env.MAX_INFLIGHT_PER_WALLET || 3);

console.log(`\n▶ profile ${profileName} | wallets ${records.length} | concurrency ${profile.concurrency} | RPCs ${providers.all.length} | settle ${ctx.settleMs}ms`);
console.log(`  run ${runId}\n`);

// init nonces (chunked) from chain truth on the pinned/primary provider
for (let i = 0; i < signers.length; i += 50) {
  await Promise.all(signers.slice(i, i + 50).map((s) => nonceMgr.init(s.address, providers.primary).catch(() => 0)));
}
// init EIP-2612 permit nonces from chain: nonces[owner] is PERSISTENT on-chain state (prior runs
// advance it), so a fresh run must NOT assume 0 or every permit signs a stale nonce → bad sig.
// Read across ALL providers with retry — a single-provider read that transiently fails and
// defaults to 0 would make that owner's first permit revert (then self-heal); robust read avoids it.
{
  const permitCs = providers.all.map((p) => new Contract(A.permitToken, art("PermitToken").abi, p));
  const readNonce = async (addr) => { for (let t = 0; t < 2; t++) for (const c of permitCs) { try { return await c.nonces(addr); } catch {} } return null; };
  // self-heal: re-read an owner's on-chain permit nonce on any permit failure.
  ctx.resyncPermitNonce = async (addr) => { const n = await readNonce(addr); if (n !== null) { ctx.permitNonce[addr] = n; ctx.permitInFlight[addr] = false; } };
  for (let i = 0; i < signers.length; i += 25) {
    await Promise.all(signers.slice(i, i + 25).map(async (s) => {
      const n = await readNonce(s.address);
      if (n !== null) ctx.permitNonce[s.address] = n;
      else { ctx.permitInFlight[s.address] = true; ctx.resyncPermitNonce(s.address); } // unknown → block permits until resynced
    }));
  }
}

let running = true;
let rr = 0;
function nextSigner() { for (let k = 0; k < signers.length; k++) { const s = signers[rr++ % signers.length]; if (nonceMgr.canSend(s.address, CAP)) return s; } return null; }

async function fireOne(sig) {
  let it = null, req = null;
  for (let attempt = 0; attempt < 8; attempt++) { // re-pick if a guarded op isn't ready yet (keeps realized tps near target)
    it = work.pick();
    try { req = it.build(ctx, sig.address); } catch { req = null; }
    if (req) break;
  }
  if (!req) return;
  const submitMs = Date.now();
  try {
    const res = await sendRaw(sig, sig.provider(), nonceMgr, req, fee, chainId);
    if (res.status === "dropped") { metrics.onSoft(res.msg); nonceMgr.settle(sig.address); if (it.type === "permit") { ctx.permitInFlight[sig.address] = false; ctx.resyncPermitNonce?.(sig.address); } return; }
    metrics.onSubmit(it.type);
    if (res.status === "soft") metrics.onSoft(res.msg);
    collector.track(res.hash, { submitMs, signed: res.signed, row: { ts: submitMs, profile: profileName, walletIdx: sig.index, from: sig.address, nonce: res.nonce, type: it.type, to: req.to ?? null, gas: req.gas.toString() } });
    // CONFIRMATION-GATE: _apply (success-only) + _onResolve (any outcome) deferred to collector.onResolve.
    if (req._apply || req._onResolve) { const r = res; ctx.pendingByHash.set(res.hash, { apply: req._apply ? () => req._apply(r) : null, onResolve: req._onResolve || null }); }
  } catch (e) {
    nonceMgr.settle(sig.address);
    if (it.type === "permit") { ctx.permitInFlight[sig.address] = false; ctx.resyncPermitNonce?.(sig.address); }
    metrics.onSubmitFail(String(e.message || e));
    logger.write("errors", { kind: "submit", type: it.type, from: sig.address, msg: String(e.message || e).slice(0, 200) });
  }
}
async function pump() {
  while (running) {
    await rate.take(); if (!running) break;
    const sig = nextSigner();
    if (!sig) { await sleep(20); continue; }
    await sem.acquire(); fireOne(sig).finally(() => sem.release());
  }
}

collector.start();

// Dynamic fee: every 3s bid 2x live base fee (+ tip), clamped to [floor, 200x floor].
const FEE_CAP = fee.floorWei * 200n;
const feePoll = setInterval(async () => {
  try {
    const blk = await providers.primary.getBlock("latest");
    const b = blk?.baseFeePerGas;
    if (b) { let bid = b * 2n + fee.priorityWei; if (bid < fee.floorWei) bid = fee.floorWei; if (bid > FEE_CAP) bid = FEE_CAP; fee.maxFeePerGas = bid; }
  } catch {}
}, 3000);

let prev = { submitted: 0, failedSubmit: 0 };
const mon = setInterval(async () => {
  const s = metrics.snapshot(collector.size);
  logger.write("metrics", { ...s, rebroadcasts: collector.rebroadcasts });
  const np = probe ? await probe.sample() : {};
  const dSub = s.submitted - prev.submitted, dErr = s.failedSubmit - prev.failedSubmit; prev = s;
  const errRate = dSub > 0 ? dErr / dSub : 0; s._errRate = errRate;
  process.stdout.write(`\r  tps s/m ${s.submitTps}/${s.minedTps} | inflight ${s.inflight} | p95 ${s.p95}ms | sub ${s.submitted} mined ${s.mined} rev ${s.reverted} fail ${s.failedSubmit} to ${s.timedOut} rb ${collector.rebroadcasts} | fee ${(Number(fee.maxFeePerGas) / 1e9).toFixed(2)}gw | blk ${collector.lastBlock}    `);
  if (probe?.aborted) { console.log(`\n⚠ ABORT: ${probe.abortReason}`); running = false; }
  global._last = s;
}, 5000);

async function runPhases() {
  for (const ph of profile.phases) {
    if (!running) break;
    console.log(`\n  ▸ phase ${ph.name} (${ph.durationSec}s) → ${ph.tps ?? `${ph.fromTps}->${ph.toTps}`} tps`);
    const t0 = Date.now(), dur = ph.durationSec * 1000;
    while (running && Date.now() - t0 < dur) {
      const f = (Date.now() - t0) / dur;
      const tps = ph.tps != null ? ph.tps : (ph.fromTps + (ph.toTps - ph.fromTps) * f);
      rate.setRate(tps);
      await sleep(1000);
    }
  }
}

const onSig = () => { console.log("\n  …draining (Ctrl-C again to force)"); running = false; };
process.on("SIGINT", onSig); process.on("SIGTERM", onSig);

pump();
await runPhases();
running = false;
clearInterval(mon); clearInterval(feePoll);
console.log("\n  draining in-flight…");
await collector.drain(Number(env.DRAIN_MS || 180000));
collector.stop();

const final = metrics.snapshot(collector.size);
const minedPct = final.submitted > 0 ? (100 * final.mined / final.submitted) : 0;
const summary = { runId, profile: profileName, finishedAt: new Date().toISOString(), wallets: records.length, settleMs: ctx.settleMs, ...final, minedPct: +minedPct.toFixed(3), rebroadcasts: collector.rebroadcasts, pendingAtEnd: collector.size };
logger.write("summary", summary);
writeFileSync(join(logger.dir, "summary.json"), JSON.stringify(summary, null, 2));
await logger.close();
console.log(`\n✓ done. submitted ${final.submitted} | mined ${final.mined} (${minedPct.toFixed(3)}%) | reverted ${final.reverted} | failedSubmit ${final.failedSubmit} | timedOut ${final.timedOut} | rebroadcasts ${collector.rebroadcasts}`);
console.log(`  byType:`, JSON.stringify(metrics.byType));
if (Object.keys(final.errors).length) console.log(`  submit errors:`, JSON.stringify(final.errors));
console.log(`  logs: ${logger.dir}`);
process.exit(0);
