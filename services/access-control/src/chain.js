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

  return {
    async grantAccess(wallet, zone) {
      const tx = await nft.grantAccess(wallet, zone);
      const receipt = await tx.wait();
      return receipt.hash;
    },
    async revokeAccess(wallet, zone) {
      const tx = await nft.revokeAccess(wallet, zone);
      const receipt = await tx.wait();
      return receipt.hash;
    },
    async hasAccess(wallet, zone) {
      return nft.hasAccess(wallet, zone);
    },
  };
}
