import { parseUnits, keccak256 } from "ethers";

// The fee object is MUTABLE and shared: run.js refreshes maxFeePerGas from the chain's
// live base fee (see the fee poller), so under real load the bid tracks the rising base
// fee instead of getting rejected. priority + floor stay fixed from env.
export function feeOverrides(env) {
  const prio = parseUnits(env.PRIORITY_FEE_GWEI || "2", "gwei");
  const floor = parseUnits(env.MAX_FEE_GWEI || "15", "gwei"); // initial / minimum bid
  return { maxFeePerGas: floor, maxPriorityFeePerGas: prio, floorWei: floor, priorityWei: prio };
}

// Mempool errors that mean "a tx for this nonce is already in the pool / dup" — the tx is
// (or will be) included; they are NOT chain stress and must not trip any knee.
const BENIGN = ["already known", "already in", "replacement", "underpriced", "coalesce"];
const isBenign = (m) => BENIGN.some((s) => m.includes(s));

// RELIABILITY FIX #2 — transient submit errors over the public WAN RPCs (TLS resets, socket
// hangups, nginx 429/5xx, momentary txpool-full) are retried with backoff before being
// counted as a hard failure. Re-broadcasting the SAME signed tx is idempotent ("already
// known" is benign), so a retry can never double-spend a nonce.
const TRANSIENT = /timeout|econn|socket|reset|fetch|429|500|502|503|504|server error|server response 5|txpool|mempool is full/;
const isTransient = (m) => TRANSIENT.test(m);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Sign with a manual nonce and broadcast WITHOUT awaiting the receipt (pipelined).
// Returns {hash, nonce, signed, status}: "ok" (accepted) | "soft" (benign dup, still in pool
// — track it) | "dropped" (our nonce already used → won't mine; resynced). Throws only on
// genuine, non-transient failures. The hash is computed locally from the signed tx, so it is
// valid even when the RPC response is unparseable ("could not coalesce"). `signed` is returned
// so the receipt collector can RE-BROADCAST a tx that gets dropped from the mempool (fix #3).
export async function sendRaw(walletRec, provider, nonceMgr, req, fee, chainId) {
  const nonce = nonceMgr.take(walletRec.address);
  const tx = {
    type: 2, chainId: Number(chainId), nonce,
    to: req.to, data: req.data || "0x", value: req.value || 0n,
    gasLimit: req.gas, maxFeePerGas: fee.maxFeePerGas, maxPriorityFeePerGas: fee.maxPriorityFeePerGas,
  };
  const signed = await walletRec.wallet.signTransaction(tx);
  const hash = keccak256(signed);

  for (let attempt = 0; ; attempt++) {
    try {
      await provider.broadcastTransaction(signed);
      return { hash, nonce, signed, status: "ok" };
    } catch (e) {
      const m = String(e.message || e).toLowerCase();
      if (isBenign(m)) return { hash, nonce, signed, status: "soft", msg: m };
      if (m.includes("nonce")) {
        try { await nonceMgr.resync(walletRec.address, provider); } catch {}
        return { hash, nonce, signed, status: "dropped", msg: m };
      }
      if (isTransient(m) && attempt < 3) { await sleep(80 * (attempt + 1)); continue; } // bounded retry
      throw e; // genuine failure → caller classifies + counts it
    }
  }
}
