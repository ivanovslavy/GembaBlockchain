import { Wallet } from "ethers";
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const FILE = new URL("../wallets.json", import.meta.url);

export function generateWallets(n) {
  const wallets = [];
  for (let i = 0; i < n; i++) {
    const w = Wallet.createRandom();
    wallets.push({ index: i, address: w.address, privateKey: w.privateKey });
  }
  writeFileSync(FILE, JSON.stringify(wallets, null, 2), { mode: 0o600 }); // 0600: throwaway keys, never world-readable
  return wallets;
}

export function loadWallets() {
  if (!existsSync(FILE)) throw new Error("wallets.json not found — run gen-wallets first");
  return JSON.parse(readFileSync(FILE, "utf8"));
}

// Wrap raw wallet records as ethers signers bound to a provider getter.
//
// RELIABILITY FIX #1 — PIN each wallet to ONE RPC (was `() => providers.next()`).
// The Pi run uses MULTIPLE public RPCs (rpc1/2/3). With round-robin, a single wallet's
// consecutive (manual) nonces would land on DIFFERENT nodes; a node that hasn't yet gossip-
// received the lower nonce sees a future-nonce gap and silently won't mine it → timeouts and
// stalled nonce streams. Pinning makes each wallet's whole nonce stream consistent on its RPC
// (the chain still gossips to all validators via P2P, so consensus is unaffected). Wallets are
// spread evenly across the RPCs by index, so ingestion load is still balanced network-wide.
export function asSigners(records, providers) {
  return records.map((r) => {
    const w = new Wallet(r.privateKey);
    const p = providers.all[r.index % providers.all.length]; // pinned, deterministic
    return { index: r.index, address: r.address, wallet: w, provider: () => p };
  });
}
