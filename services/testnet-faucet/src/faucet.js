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

  return {
    address: wallet.address,

    async balance() {
      return provider.getBalance(wallet.address);
    },

    /** Send the drip to `to`. Returns the tx hash. Throws on failure (fail loud). */
    async drip(to) {
      if (!isEvmAddress(to)) throw new Error('invalid recipient address');
      const tx = await wallet.sendTransaction({ to, value });
      const receipt = await tx.wait();
      if (!receipt || receipt.status !== 1) throw new Error('drip transaction failed');
      return receipt.hash;
    },
  };
}
