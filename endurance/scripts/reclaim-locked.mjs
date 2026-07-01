import "dotenv/config";
import { Wallet, JsonRpcProvider, Network, Contract, parseEther, parseUnits, formatEther } from "ethers";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadWallets } from "../lib/wallets.js";

// ─────────────────────────────────────────────────────────────────────────────
// reclaim-locked — return native GMB that is still LOCKED IN THE TEST'S OWN
// CONTRACTS (the GembaNativePool LP + WGMB wrapper) back to the founder.
//
// After the endurance run, native GMB remains in two places the plain
// drain-to-founder sweep can't reach (it only moves EOA balances):
//   • nativePool (GembaNativePool)  — native backing every LP position (the
//     founder's seed liquidity + each worker's nativeAddLiq). Recovered by
//     removeLiquidity() for each LP holder's full LP balance.
//   • wgmb (WGMB)                   — native wrapped by workers' wrapGMB ops.
//     Recovered by each holder calling withdraw(balanceOf) (WETH9-style; only
//     the holder can unwrap their own — so each acting wallet needs a little gas).
//
// This mirrors drain-to-founder.mjs's style (ethers v6, loadWallets(), providers
// from RPC_URLS, EIP-1559 fee = base*3 + PRIORITY_FEE_GWEI). It is idempotent and
// safe: zero balances are skipped, every tx is wrapped in try/catch, and it NEVER
// touches the public testnet faucet. Re-running with nothing locked is a no-op.
//
// Note on residual dust: GembaNativePool locks MINIMUM_LIQUIDITY (1000 wei of LP)
// at 0xdead on first mint (Uniswap-V2 style), so a tiny, proportional slice of the
// pool's native (a few tens of wei) can never be removed. That is expected and is
// reported as residual dust — we do NOT force-drain the contract to chase it.
// ─────────────────────────────────────────────────────────────────────────────

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dep = JSON.parse(readFileSync(join(root, "deployed.json"), "utf8"));
const A = dep.addresses;

const FOUNDER = "0x5578c75F22dE0bf1caA4BdD46BA28406C696a5dC";
const NATIVE_POOL = A.nativePool;
const WGMB = A.wgmb;
// HARD GUARDRAIL: the public testnet faucet reserve — never sweep/drain/interact.
const FAUCET = A.faucet;

// Sanity: our targets must not be the faucet (defense-in-depth; they never are).
for (const [name, a] of [["nativePool", NATIVE_POOL], ["wgmb", WGMB], ["founder", FOUNDER]]) {
  if (a.toLowerCase() === FAUCET.toLowerCase()) throw new Error(`refusing to run: ${name} == faucet`);
}

const net = Network.from(Number(process.env.CHAIN_ID));
const urls = process.env.RPC_URLS.split(",").map((u) => u.trim());
const providers = urls.map((u) => new JsonRpcProvider(u, net, { staticNetwork: net }));
const provFor = (i) => providers[i % providers.length];
const provider = providers[0];
const funder = new Wallet(process.env.FUNDER_PK, provider);

const wallets = loadWallets();
const base = (await provider.getBlock("latest")).baseFeePerGas || parseUnits("5", "gwei");
const tip = parseUnits(process.env.PRIORITY_FEE_GWEI || "2", "gwei");
const maxFee = base * 3n + tip;
const feeG = (gas) => ({ maxFeePerGas: maxFee, maxPriorityFeePerGas: tip, gasLimit: gas });
const gasResv = 21000n * maxFee;                       // reserve to leave for the final sweep tx
const TOPUP = parseEther(process.env.RECLAIM_TOPUP || "0.05");    // gas grant to acting workers
const TOPUP_MIN = parseEther(process.env.RECLAIM_TOPUP_MIN || "0.02"); // top up only if below this
const DEADLINE = 19999999999n;
const REMOVE_GAS = 320000n, WITHDRAW_GAS = 90000n;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const chunks = (a, n) => { const o = []; for (let i = 0; i < a.length; i += n) o.push(a.slice(i, i + n)); return o; };

const npAbi = [
  "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function reserveNative() view returns (uint256)",
  "function removeLiquidity(uint256 liquidity,uint256 amountTokenMin,uint256 amountNativeMin,address to,uint256 deadline) returns (uint256,uint256)",
];
const wgmbAbi = [
  "function balanceOf(address) view returns (uint256)",
  "function withdraw(uint256 wad)",
];
const np = new Contract(NATIVE_POOL, npAbi, provider);
const wg = new Contract(WGMB, wgmbAbi, provider);
const balOf = (addr) => provider.getBalance(addr);

async function report(tag) {
  const [poolN, wgmbN, fnd] = await Promise.all([balOf(NATIVE_POOL), balOf(WGMB), balOf(FOUNDER)]);
  console.log(`  [${tag}] nativePool=${formatEther(poolN)} GMB | wgmb=${formatEther(wgmbN)} GMB | founder=${formatEther(fnd)} GMB`);
  return { poolN, wgmbN, fnd };
}

console.log("reclaim-locked → recovering native GMB from nativePool + wgmb to founder", FOUNDER);
console.log("  nativePool", NATIVE_POOL, "| wgmb", WGMB, "| faucet(untouched)", FAUCET);
const before = await report("before");

// ── Snapshot every holder: LP + WGMB + native balance (founder first, then workers) ──
// The founder holds the seed LP; workers hold LP (nativeAddLiq) and WGMB (wrapGMB).
const holders = [{ index: -1, address: FOUNDER, wallet: funder, prov: provider }];
for (const w of wallets) holders.push({ index: w.index, address: w.address, wallet: new Wallet(w.privateKey, provFor(w.index)), prov: provFor(w.index) });

for (const ch of chunks(holders, 20)) {
  await Promise.all(ch.map(async (h) => {
    const [lp, wgmb, nat] = await Promise.all([np.balanceOf(h.address), wg.balanceOf(h.address), h.prov.getBalance(h.address)]);
    h.lp = lp; h.wgmb = wgmb; h.native = nat;
  }));
}
const lpHolders = holders.filter((h) => h.lp > 0n);
const wgmbHolders = holders.filter((h) => h.wgmb > 0n);
console.log(`  holders: ${lpHolders.length} with LP, ${wgmbHolders.length} with WGMB`);

// ── Pass A: gas top-up any ACTING worker that is too empty to send its unwind tx(s) ──
// The founder pays its own gas (huge balance) and is skipped here.
{
  const need = holders.filter((h) => h.index >= 0 && (h.lp > 0n || h.wgmb > 0n) && h.native < TOPUP_MIN && h.address.toLowerCase() !== FAUCET.toLowerCase());
  console.log(`  pass A: topping up ${need.length} acting wallets with ${formatEther(TOPUP)} GMB each`);
  // Assign EXPLICIT sequential nonces: many top-ups fire concurrently from the SAME founder
  // wallet, so auto-nonce would hand them all the same nonce → "replacement fee too low".
  let nonce = await provider.getTransactionCount(funder.address, "latest");
  const ops = need.map((h) => ({ to: h.address, index: h.index, n: nonce++ }));
  let last;
  for (const ch of chunks(ops, 20)) {
    const rs = await Promise.all(ch.map(async (o) => {
      try { return await funder.sendTransaction({ to: o.to, value: TOPUP, nonce: o.n, ...feeG(21000n) }); }
      catch (e) { console.log("    skip topup", o.index, String(e.message).slice(0, 60)); return null; }
    }));
    last = rs.filter(Boolean).pop() || last;
    await sleep(300);
  }
  if (last) await last.wait();
}

// ── Pass B: removeLiquidity for every LP holder (native routed straight to FOUNDER) ──
// removeLiquidity() burns the caller's own LP, so each holder signs its own tx; `to`
// may be any address, so we send the recovered native (and worthless test token)
// directly to the founder — no separate sweep needed for the pool side.
{
  console.log(`  pass B: removeLiquidity for ${lpHolders.length} LP holders → founder`);
  const hashes = [];
  for (const ch of chunks(lpHolders, 15)) {
    await Promise.all(ch.map(async (h) => {
      try {
        const c = new Contract(NATIVE_POOL, npAbi, h.wallet);
        const tx = await c.removeLiquidity(h.lp, 0n, 0n, FOUNDER, DEADLINE, feeG(REMOVE_GAS));
        hashes.push(tx.hash);
      } catch (e) { console.log("    skip removeLiq", h.index, String(e.message).slice(0, 70)); }
    }));
    await sleep(400);
  }
  if (hashes.length) { console.log(`    submitted ${hashes.length} removeLiquidity txs; waiting last…`); await provider.waitForTransaction(hashes[hashes.length - 1], 1); }
}

// ── Pass C: withdraw for every WGMB holder (WETH9 sends native to msg.sender = self) ──
{
  console.log(`  pass C: withdraw for ${wgmbHolders.length} WGMB holders (native → self, swept next)`);
  const hashes = [];
  for (const ch of chunks(wgmbHolders, 15)) {
    await Promise.all(ch.map(async (h) => {
      try {
        const c = new Contract(WGMB, wgmbAbi, h.wallet);
        const tx = await c.withdraw(h.wgmb, feeG(WITHDRAW_GAS));
        hashes.push(tx.hash);
      } catch (e) { console.log("    skip withdraw", h.index, String(e.message).slice(0, 70)); }
    }));
    await sleep(400);
  }
  if (hashes.length) { console.log(`    submitted ${hashes.length} withdraw txs; waiting last…`); await provider.waitForTransaction(hashes[hashes.length - 1], 1); }
}

// ── Pass D: sweep worker native (unwrapped WGMB + leftover top-up gas) back to founder ──
// Same logic as drain-to-founder.mjs; the founder is the destination so it is never swept,
// and the faucet is never in `wallets`, so it is never touched.
{
  console.log("  pass D: sweeping worker native → founder");
  let last; const sent = [];
  for (const ch of chunks(wallets, 10)) {
    await Promise.all(ch.map(async (rec) => {
      if (rec.address.toLowerCase() === FAUCET.toLowerCase()) return; // defensive; never happens
      const p = provFor(rec.index);
      const sw = new Wallet(rec.privateKey, p);
      try {
        const bal = await p.getBalance(rec.address);
        if (bal > gasResv) {
          const tx = await sw.sendTransaction({ to: FOUNDER, value: bal - gasResv, ...feeG(21000n) });
          sent.push(tx.hash); last = tx;
        }
      } catch (e) { console.log("    skip sweep", rec.index, String(e.message).slice(0, 60)); }
    }));
    await sleep(300);
  }
  console.log(`    submitted ${sent.length} sweep txs`);
  if (last) await last.wait();
}

// ── Report before/after + how much native was pulled out of the locked contracts ──
const after = await report("after");
const recoveredFromContracts = (before.poolN - after.poolN) + (before.wgmbN - after.wgmbN);
const founderDelta = after.fnd - before.fnd;
console.log("──────────────────────────────────────────────────────────────");
console.log(`  RECOVERED from locked contracts: ${formatEther(recoveredFromContracts)} GMB`);
console.log(`    nativePool ${formatEther(before.poolN)} → ${formatEther(after.poolN)} (residual dust ${after.poolN} wei)`);
console.log(`    wgmb       ${formatEther(before.wgmbN)} → ${formatEther(after.wgmbN)} (residual dust ${after.wgmbN} wei)`);
console.log(`  founder native ${formatEther(before.fnd)} → ${formatEther(after.fnd)} (net Δ ${formatEther(founderDelta)} GMB, incl. gas paid)`);
process.exit(0);
