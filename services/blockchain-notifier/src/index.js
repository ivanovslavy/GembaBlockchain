// GembaBlockchain blockchain-notifier — EMAIL alerts for chain/sale/uptime/risk events.
// One NETWORK switch (testnet|mainnet) drives everything; every email is labelled accordingly.
// Sources: (A) validators via Cosmos REST, (B) GMB sales via the dispenser's Dispensed event,
// (C) uptime via HTTP probes, (D) risk alarms (shares/Nakamoto/bonded-ratio/large-sale/rate).
import fs from 'node:fs';
import path from 'node:path';
import { cfg } from './config.js';
import { notify, resetKey } from './mailer.js';
import * as chain from './chain.js';

// ----------------------------- state -----------------------------
function loadState() {
  try { return JSON.parse(fs.readFileSync(cfg.stateFile, 'utf8')); } catch { return {}; }
}
function saveState(s) {
  fs.mkdirSync(path.dirname(cfg.stateFile), { recursive: true });
  fs.writeFileSync(cfg.stateFile, JSON.stringify(s, null, 2));
}
let state = loadState();
state.validators ||= {};
state.bondedHistory ||= [];
state.shareSnapshots ||= [];
state.uptime ||= {};
state.lastDispenserBlock ||= 0;

const pct = (n) => `${(n * 100).toFixed(1)}%`;

// ----------------------------- A + D: validators & concentration risk -----------------------------
async function watchValidators() {
  const vals = await chain.fetchAllValidators();
  const bonded = vals.filter((v) => !v.jailed && v.status === 'BOND_STATUS_BONDED');
  const totalBonded = bonded.reduce((a, v) => a + v.tokens, 0n);

  // (A) new / jailed / unjailed vs last seen
  for (const v of vals) {
    const prev = state.validators[v.operator];
    if (!prev) {
      await notify(`val-new-${v.operator}`,
        `New validator: ${v.moniker || v.operator}`,
        `A validator joined.\nMoniker: ${v.moniker}\nOperator: ${v.operator}\nStake: ${chain.fmtGmb(v.tokens)} GMB\nJailed: ${v.jailed}`,
        'info');
    } else if (v.jailed && !prev.jailed) {
      await notify(`val-jail-${v.operator}-${Date.now()}`,
        `Validator JAILED: ${v.moniker || v.operator}`,
        `A validator was jailed (downtime or double-sign).\nMoniker: ${v.moniker}\nOperator: ${v.operator}`,
        'warning');
    } else if (!v.jailed && prev.jailed) {
      await notify(`val-unjail-${v.operator}-${Date.now()}`,
        `Validator unjailed: ${v.moniker || v.operator}`,
        `A validator returned to the active set.\nMoniker: ${v.moniker}\nOperator: ${v.operator}`,
        'info');
    }
    state.validators[v.operator] = { moniker: v.moniker, jailed: v.jailed, tokens: v.tokens.toString() };
  }

  // (D) active count below the BFT floor
  if (bonded.length < cfg.thresholds.minValidators) {
    await notify('val-count-low',
      `Active validators below BFT floor: ${bonded.length}`,
      `Only ${bonded.length} active validators (floor ${cfg.thresholds.minValidators}). Below 4 the chain cannot tolerate a single failure (BFT N≥3f+1).`,
      'critical');
  } else { resetKey('val-count-low'); }

  if (totalBonded === 0n) return;

  // (D) single-validator voting-power share
  const shares = {};
  for (const v of bonded) {
    const share = Number((v.tokens * 1000000n) / totalBonded) / 1000000;
    shares[v.operator] = share;
    if (share >= cfg.thresholds.validatorShareCrit) {
      await notify(`val-share-crit-${v.operator}`,
        `Validator ≥1/3 of voting power: ${v.moniker || v.operator} (${pct(share)})`,
        `This validator alone can HALT the chain (>1/3). Consider the pre-written defensive proposal (vote-share cap).`,
        'critical');
    } else if (share >= cfg.thresholds.validatorShareWarn) {
      await notify(`val-share-warn-${v.operator}`,
        `Validator share high: ${v.moniker || v.operator} (${pct(share)})`,
        `Approaching the 1/3 halt line. Watch for further accumulation.`,
        'warning');
    }
  }

  // (D) Nakamoto coefficient (min validators to exceed 1/3)
  const sorted = [...bonded].sort((a, b) => (b.tokens > a.tokens ? 1 : -1));
  let acc = 0n, nakamoto = 0;
  for (const v of sorted) { acc += v.tokens; nakamoto++; if (acc * 3n > totalBonded) break; }
  if (nakamoto <= 1) {
    await notify('nakamoto-1', `Nakamoto coefficient = 1`,
      `A single validator controls ≥1/3 of voting power — the chain can be halted by one operator.`, 'critical');
  } else { resetKey('nakamoto-1'); }

  // (D) share rate-of-change: snapshot hourly, compare to ~7d ago
  const now = Date.now();
  const lastSnap = state.shareSnapshots[state.shareSnapshots.length - 1];
  if (!lastSnap || now - lastSnap.t > 3600_000) {
    state.shareSnapshots.push({ t: now, shares });
    if (state.shareSnapshots.length > 250) state.shareSnapshots.shift();
  }
  const ref = state.shareSnapshots.find((s) => now - s.t >= 7 * 86400_000);
  if (ref) {
    for (const [op, sh] of Object.entries(shares)) {
      const before = ref.shares[op];
      if (before != null && (sh - before) * 100 >= cfg.thresholds.shareRisePP7d) {
        await notify(`val-share-rise-${op}`,
          `Validator share rising fast: ${shares[op] != null ? pct(sh) : ''}`,
          `Operator ${op} rose +${((sh - before) * 100).toFixed(1)}pp in ~7d (${pct(before)} → ${pct(sh)}). Possible accumulation (delegations are not capped).`,
          'warning');
      }
    }
  }
}

// ----------------------------- D: bonded ratio (the security KPI) -----------------------------
async function watchBondedRatio() {
  const ratio = await chain.fetchBondedRatio();
  if (ratio <= 0) return;
  if (ratio < cfg.thresholds.bondedRatioCrit) {
    await notify('bonded-crit', `Bonded ratio RED LINE: ${pct(ratio)}`,
      `Bonded/circulating below 1/3 — halting is cheap. Levers: tail-reward rate + gas floor (ADR-008).`, 'critical');
  } else if (ratio < cfg.thresholds.bondedRatioWarn) {
    await notify('bonded-warn', `Bonded ratio below floor: ${pct(ratio)}`, `Below the 50% floor (target 66%).`, 'warning');
  } else { resetKey('bonded-crit'); resetKey('bonded-warn'); }

  const now = Date.now();
  const last = state.bondedHistory[state.bondedHistory.length - 1];
  if (!last || now - last.t > 3600_000) {
    state.bondedHistory.push({ t: now, ratio });
    if (state.bondedHistory.length > 250) state.bondedHistory.shift();
  }
  const ref = state.bondedHistory.find((h) => now - h.t >= 7 * 86400_000);
  if (ref && (ref.ratio - ratio) * 100 >= cfg.thresholds.bondedDropPP7d) {
    await notify('bonded-drop', `Bonded ratio dropping fast`,
      `Fell ${((ref.ratio - ratio) * 100).toFixed(1)}pp in ~7d (${pct(ref.ratio)} → ${pct(ratio)}).`, 'warning');
  }
}

// ----------------------------- B + D: GMB sales (dispenser Dispensed event) -----------------------------
async function watchGmbSales() {
  const latest = await chain.evmBlockNumber();
  const from = state.lastDispenserBlock ? state.lastDispenserBlock + 1 : Math.max(0, latest - 500);
  if (from > latest) return;
  const logs = await chain.fetchDispensedLogs(from, latest);
  let bonded = null;
  for (const ev of logs) {
    await notify(`sale-${ev.txHash}`,
      `GMB sold via GembaPay: ${ev.amountGmb.toLocaleString('en-US')} GMB`,
      `Buyer: ${ev.to}\nAmount: ${ev.amountGmb.toLocaleString('en-US')} GMB\nRef: ${ev.ref}\nTx: ${cfg.explorer}/tx/${ev.txHash}`,
      'info');
    // (D) large single sale relative to the LIVE bonded stake (S>B/2 is the danger zone)
    try { bonded ??= await chain.fetchBondedTokens(); } catch { bonded = 0n; }
    if (bonded > 0n) {
      const frac = Number((ev.amount * 1000000n) / bonded) / 1000000;
      if (frac >= cfg.thresholds.largeSaleFracBondedCrit) {
        await notify(`sale-crit-${ev.txHash}`, `LARGE GMB sale: ${pct(frac)} of bonded stake`,
          `${ev.amountGmb.toLocaleString('en-US')} GMB to ${ev.to} = ${pct(frac)} of current bonded. If staked it could approach the 1/3 halt line.`, 'critical');
      } else if (frac >= cfg.thresholds.largeSaleFracBondedWarn) {
        await notify(`sale-warn-${ev.txHash}`, `Sizeable GMB sale: ${pct(frac)} of bonded stake`,
          `${ev.amountGmb.toLocaleString('en-US')} GMB to ${ev.to} = ${pct(frac)} of current bonded.`, 'warning');
      }
    }
  }
  state.lastDispenserBlock = latest;
}

// ----------------------------- C: uptime -----------------------------
async function watchUptime() {
  for (const url of cfg.uptimeUrls) {
    const isRpc = url.includes('rpc');
    const res = isRpc ? await chain.probeRpc(url) : await chain.probeHttp(url);
    const wasOk = state.uptime[url]?.ok !== false; // default assume up
    if (!res.ok && wasOk) {
      await notify(`down-${url}`, `Service DOWN: ${url}`, `Health check failed: ${res.error || res.status}`, 'critical');
    } else if (res.ok && !wasOk) {
      resetKey(`down-${url}`);
      await notify(`up-${url}`, `Service recovered: ${url}`, `Health check passing again.`, 'info');
    }
    state.uptime[url] = { ok: res.ok };
  }
}

// ----------------------------- loop -----------------------------
async function runChainCycle() {
  for (const [name, fn] of [['validators', watchValidators], ['bondedRatio', watchBondedRatio], ['gmbSales', watchGmbSales]]) {
    try { await fn(); } catch (e) { console.error(`[${name}]`, e?.message || e); }
  }
  saveState(state);
}
async function runUptimeCycle() {
  try { await watchUptime(); } catch (e) { console.error('[uptime]', e?.message || e); }
  saveState(state);
}

console.log(`blockchain-notifier starting — NETWORK=${cfg.LABEL} chainId=${cfg.chainId} dryRun=${cfg.dryRun}`);
console.log(`  cosmosRest=${cfg.cosmosRest} evmRpc=${cfg.evmRpc} dispenser=${cfg.dispenser}`);
console.log(`  email: ${cfg.smtp.from} -> ${cfg.smtp.to}  (${cfg.dryRun ? 'DRY-RUN: SMTP not configured' : 'live'})`);

if (process.argv.includes('--once')) {
  // one-shot (for testing): run each cycle once, then exit
  await runChainCycle();
  await runUptimeCycle();
  process.exit(0);
} else {
  await runChainCycle();
  await runUptimeCycle();
  setInterval(runChainCycle, cfg.pollMs);
  setInterval(runUptimeCycle, cfg.uptimePollMs);
}
