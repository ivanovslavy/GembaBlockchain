import { parseUnits, keccak256 } from "ethers";

// The fee object is MUTABLE and shared: run.js refreshes maxFeePerGas from the chain's
// live base fee (see the fee poller), so under real load the bid tracks the rising base
// fee instead of getting rejected. priority + floor stay fixed from env.
export function feeOverrides(env) {
  const prio = parseUnits(env.PRIORITY_FEE_GWEI || "2", "gwei");
  const floor = parseUnits(env.MAX_FEE_GWEI || "5", "gwei"); // initial / minimum bid
  return { maxFeePerGas: floor, maxPriorityFeePerGas: prio, floorWei: floor, priorityWei: prio };
}

// Mempool errors that mean "a tx for this nonce is already in the pool / dup" — the tx is
// (or will be) included; they are NOT chain stress and must not trip the load knee.
const BENIGN = ["already known", "already in", "replacement", "underpriced", "coalesce"];
const isBenign = (m) => BENIGN.some((s) => m.includes(s));

// Sign with a manual nonce and broadcast WITHOUT awaiting the receipt (pipelined).
// Returns {hash, nonce, status}: "ok" (accepted) | "soft" (benign dup, still in pool —
// track it) | "dropped" (our nonce already used → won't mine; resynced). Throws only on
// genuine failures (insufficient funds, mempool full, intrinsic gas, connection…), which
// the caller counts toward the knee. The hash is computed locally from the signed tx, so
// it is valid even when the RPC response is unparseable ("could not coalesce").
export async function sendRaw(walletRec, provider, nonceMgr, req, fee, chainId) {
  const nonce = nonceMgr.take(walletRec.address);
  const tx = {
    type: 2, chainId: Number(chainId), nonce,
    to: req.to, data: req.data || "0x", value: req.value || 0n,
    gasLimit: req.gas, maxFeePerGas: fee.maxFeePerGas, maxPriorityFeePerGas: fee.maxPriorityFeePerGas,
  };
  const signed = await walletRec.wallet.signTransaction(tx);
  const hash = keccak256(signed);
  try {
    await provider.broadcastTransaction(signed);
    return { hash, nonce, status: "ok" };
  } catch (e) {
    const m = String(e.message || e).toLowerCase();
    if (isBenign(m)) return { hash, nonce, status: "soft", msg: m };
    if (m.includes("nonce")) {
      try { await nonceMgr.resync(walletRec.address, provider); } catch {}
      return { hash, nonce, status: "dropped", msg: m };
    }
    throw e; // genuine failure → caller classifies + counts toward the knee
  }
}
