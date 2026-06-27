// Chain data access: Cosmos REST (validators/slashing/pool/bank) + EVM (dispenser events, uptime).
import { JsonRpcProvider, Contract, formatEther } from 'ethers';
import { cfg } from './config.js';

// ---------------- Cosmos REST (validator / staking / slashing / bank) ----------------

async function rest(path) {
  const r = await fetch(cfg.cosmosRest + path, { signal: AbortSignal.timeout(10_000) });
  if (!r.ok) throw new Error(`cosmos REST ${path} -> ${r.status}`);
  return r.json();
}

/** All bonded validators (paginated), normalized to {operator, moniker, tokens}. */
export async function fetchBondedValidators() {
  const out = [];
  let key = '';
  do {
    const q = `/cosmos/staking/v1beta1/validators?status=BOND_STATUS_BONDED&pagination.limit=200` +
      (key ? `&pagination.key=${encodeURIComponent(key)}` : '');
    const d = await rest(q);
    for (const v of d.validators || []) {
      out.push({
        operator: v.operator_address,
        moniker: v.description?.moniker || '',
        tokens: BigInt(v.tokens || '0'),
        jailed: !!v.jailed,
      });
    }
    key = d.pagination?.next_key || '';
  } while (key);
  return out;
}

/** All validators (any status) with jailed flag — used to detect new/jailed/unjailed. */
export async function fetchAllValidators() {
  const out = [];
  let key = '';
  do {
    const q = `/cosmos/staking/v1beta1/validators?pagination.limit=200` +
      (key ? `&pagination.key=${encodeURIComponent(key)}` : '');
    const d = await rest(q);
    for (const v of d.validators || []) {
      out.push({
        operator: v.operator_address,
        moniker: v.description?.moniker || '',
        tokens: BigInt(v.tokens || '0'),
        jailed: !!v.jailed,
        status: v.status,
      });
    }
    key = d.pagination?.next_key || '';
  } while (key);
  return out;
}

export async function fetchBondedTokens() {
  const d = await rest('/cosmos/staking/v1beta1/pool');
  return BigInt(d.pool?.bonded_tokens || '0');
}

export async function fetchTotalSupply() {
  const d = await rest(`/cosmos/bank/v1beta1/supply/by_denom?denom=${cfg.denom}`);
  return BigInt(d.amount?.amount || '0');
}

export async function fetchBalance(addr) {
  const d = await rest(`/cosmos/bank/v1beta1/balances/${addr}/by_denom?denom=${cfg.denom}`);
  return BigInt(d.balance?.amount || '0');
}

/** Bonded / circulating (circulating = supply − non-voting reserves) — the security KPI (ADR-008). */
export async function fetchBondedRatio() {
  const [bonded, supply] = await Promise.all([fetchBondedTokens(), fetchTotalSupply()]);
  let reserves = 0n;
  for (const a of cfg.reserves) {
    try { reserves += await fetchBalance(a); } catch { /* skip unreachable reserve */ }
  }
  const circ = supply > reserves ? supply - reserves : 0n;
  return circ === 0n ? 0 : Number((bonded * 1000000n) / circ) / 1000000;
}

// ---------------- EVM (GembaPay dispenser events + uptime) ----------------

let provider = null;
export function evm() {
  if (!provider) provider = new JsonRpcProvider(cfg.evmRpc, cfg.chainId, { staticNetwork: true });
  return provider;
}

const DISPENSER_ABI = ['event Dispensed(address indexed to, uint256 amount, bytes32 indexed ref)'];

/** Dispensed (GMB-sold) events from the GembaPay dispenser between two blocks. */
export async function fetchDispensedLogs(fromBlock, toBlock) {
  const c = new Contract(cfg.dispenser, DISPENSER_ABI, evm());
  const evs = await c.queryFilter(c.filters.Dispensed(), fromBlock, toBlock);
  return evs.map((e) => ({
    to: e.args.to,
    amount: e.args.amount,            // bigint (wei)
    amountGmb: Number(formatEther(e.args.amount)),
    ref: e.args.ref,
    txHash: e.transactionHash,
    block: e.blockNumber,
  }));
}

export async function evmBlockNumber() {
  return evm().getBlockNumber();
}

/** Liveness probe: POST eth_chainId; returns {ok, chainId, block} or {ok:false, error}. */
export async function probeRpc(url) {
  try {
    const body = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_blockNumber', params: [] });
    const r = await fetch(url, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body,
      signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) return { ok: false, error: `HTTP ${r.status}` };
    const j = await r.json();
    return { ok: true, block: parseInt(j.result, 16) || 0 };
  } catch (e) {
    return { ok: false, error: String(e?.message || e) };
  }
}

/** Liveness probe for a plain HTTPS endpoint (explorer): GET, expect 2xx/3xx. */
export async function probeHttp(url) {
  try {
    const r = await fetch(url, { method: 'GET', signal: AbortSignal.timeout(8000) });
    return { ok: r.status < 500, status: r.status };
  } catch (e) {
    return { ok: false, error: String(e?.message || e) };
  }
}

export const fmtGmb = (wei) => Number(formatEther(wei)).toLocaleString('en-US');
