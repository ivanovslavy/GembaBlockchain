import { Wallet } from "ethers";
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const FILE = new URL("../wallets.json", import.meta.url);

export function generateWallets(n) {
  const wallets = [];
  for (let i = 0; i < n; i++) {
    const w = Wallet.createRandom();
    wallets.push({ index: i, address: w.address, privateKey: w.privateKey });
  }
  writeFileSync(FILE, JSON.stringify(wallets, null, 2));
  return wallets;
}

export function loadWallets() {
  if (!existsSync(FILE)) throw new Error("wallets.json not found — run gen-wallets first");
  return JSON.parse(readFileSync(FILE, "utf8"));
}

// Wrap raw wallet records as ethers signers bound to a provider getter.
export function asSigners(records, providers) {
  return records.map((r) => {
    const w = new Wallet(r.privateKey);
    return { index: r.index, address: r.address, wallet: w, provider: () => providers.next() };
  });
}
