// Testnet drip faucet: sends a fixed amount of VALUELESS test GMB from the funded
// faucet account to a requester. Uses ethers against the testnet's EVM JSON-RPC.
// The faucet key (ACCESS via env) controls the gemba-testnet-1 drip account
// (chain/testnet: tnfaucet) — a testnet-only key, never a mainnet key (CLAUDE.md §3).

import { ethers } from 'ethers';
import { isEvmAddress } from './validation.js';

// `faucetContract` (optional): the GembaDripFaucet address. When set (MAINNET mode), the
// drip is relayed through the on-chain contract's `dripTo`, so the per-address cooldown is
// enforced ON-CHAIN and a service restart cannot bypass it (audit AU-2). When unset (testnet),
// the faucet raw-sends from its own balance and the cooldown is the off-chain limiter only —
// which is fine for valueless test tokens (CLAUDE.md: secure IP+on-chain faucet is mainnet-only).
export function createFaucet({ rpcUrl, faucetKey, dripAmountGmb, faucetContract }) {
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(faucetKey, provider);
  const value = ethers.parseEther(String(dripAmountGmb));
  const drip = faucetContract
    ? new ethers.Contract(faucetContract, ['function dripTo(address recipient)'], wallet)
    : null;

  // Serialize sends so concurrent drips can't read the same nonce and collide/replace each
  // other (audit finding #8). The faucet is low-QPS, so a simple in-process queue suffices.
  let queue = Promise.resolve();
  function serialize(fn) {
    const run = queue.then(fn, fn); // run after the prior send settles (success OR failure)
    queue = run.then(() => {}, () => {}); // keep the chain alive regardless of outcome
    return run;
  }

  return {
    address: wallet.address,

    async balance() {
      return provider.getBalance(wallet.address);
    },

    /** True in mainnet mode: drips go through the on-chain cooldown contract. */
    onChainCooldown: Boolean(drip),

    /** Send the drip to `to`. Returns the tx hash. Throws on failure (fail loud). Serialized.
     *  MAINNET mode routes through GembaDripFaucet.dripTo (on-chain per-address cooldown);
     *  testnet mode raw-sends. The contract reverts CooldownActive if the address claimed
     *  recently — a durable guard the off-chain limiter cannot provide across restarts. */
    async drip(to) {
      if (!isEvmAddress(to)) throw new Error('invalid recipient address');
      return serialize(async () => {
        const tx = drip ? await drip.dripTo(to) : await wallet.sendTransaction({ to, value });
        const receipt = await tx.wait();
        if (!receipt || receipt.status !== 1) throw new Error('drip transaction failed');
        return receipt.hash;
      });
    },
  };
}
