import { parseUnits } from "ethers";

export function feeOverrides(env) {
  return {
    maxFeePerGas: parseUnits(env.MAX_FEE_GWEI || "3", "gwei"),
    maxPriorityFeePerGas: parseUnits(env.PRIORITY_FEE_GWEI || "1", "gwei"),
  };
}

// Sign with a manual nonce and broadcast WITHOUT awaiting the receipt (pipelined).
// Returns the tx hash. Throws on submit error (caller logs/classifies).
export async function sendRaw(walletRec, provider, nonceMgr, req, fee, chainId) {
  const nonce = nonceMgr.take(walletRec.address);
  const tx = {
    type: 2, chainId: Number(chainId), nonce,
    to: req.to, data: req.data || "0x", value: req.value || 0n,
    gasLimit: req.gas, maxFeePerGas: fee.maxFeePerGas, maxPriorityFeePerGas: fee.maxPriorityFeePerGas,
  };
  const signed = await walletRec.wallet.signTransaction(tx);
  try {
    const resp = await provider.broadcastTransaction(signed);
    return { hash: resp.hash, nonce };
  } catch (e) {
    // nonce drift → resync so the wallet recovers on its next op
    if (String(e.message || e).toLowerCase().includes("nonce")) {
      try { await nonceMgr.resync(walletRec.address, provider); } catch {}
    }
    throw e;
  }
}
