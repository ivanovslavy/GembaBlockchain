// On-chain integration with AccessControlNFT. The service holds the ISSUER key (an
// institution's access-control admin key) in the environment — NEVER committed
// (CLAUDE.md §3). It mints/revokes anonymous capability tokens; it never writes PII
// on-chain.

import { ethers } from 'ethers';

const ABI = [
  'function grantAccess(address holder, uint256 zone)',
  'function revokeAccess(address holder, uint256 zone)',
  'function hasAccess(address holder, uint256 zone) view returns (bool)',
];

export function createChainClient({ rpcUrl, issuerKey, contractAddress }) {
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const signer = new ethers.Wallet(issuerKey, provider);
  const nft = new ethers.Contract(contractAddress, ABI, signer);

  // Serialize sends from the single ISSUER wallet so concurrent grants/revokes (or a grant
  // racing the outbox retry worker) can't read the same pending nonce and collide (audit L-4;
  // same fix as the faucet's finding #8).
  let queue = Promise.resolve();
  function serialize(fn) {
    const run = queue.then(fn, fn);
    queue = run.then(() => {}, () => {});
    return run;
  }

  return {
    async grantAccess(wallet, zone) {
      return serialize(async () => {
        const tx = await nft.grantAccess(wallet, zone);
        const receipt = await tx.wait();
        return receipt.hash;
      });
    },
    async revokeAccess(wallet, zone) {
      return serialize(async () => {
        const tx = await nft.revokeAccess(wallet, zone);
        const receipt = await tx.wait();
        return receipt.hash;
      });
    },
    async hasAccess(wallet, zone) {
      return nft.hasAccess(wallet, zone);
    },
  };
}
