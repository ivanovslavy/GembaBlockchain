// Testnet drip faucet: sends a fixed amount of VALUELESS test GMB from the funded
// faucet account to a requester. Uses ethers against the testnet's EVM JSON-RPC.
// The faucet key (ACCESS via env) controls the gemba-testnet-1 drip account
// (chain/testnet: tnfaucet) — a testnet-only key, never a mainnet key (CLAUDE.md §3).

import { ethers } from 'ethers';
import { isEvmAddress } from './validation.js';

export function createFaucet({ rpcUrl, faucetKey, dripAmountGmb }) {
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(faucetKey, provider);
  const value = ethers.parseEther(String(dripAmountGmb));

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

    /** Send the drip to `to`. Returns the tx hash. Throws on failure (fail loud). Serialized. */
    async drip(to) {
      if (!isEvmAddress(to)) throw new Error('invalid recipient address');
      return serialize(async () => {
        const tx = await wallet.sendTransaction({ to, value });
        const receipt = await tx.wait();
        if (!receipt || receipt.status !== 1) throw new Error('drip transaction failed');
        return receipt.hash;
      });
    },
  };
}
