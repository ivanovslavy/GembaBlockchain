import "dotenv/config";
import { Wallet, JsonRpcProvider, Network, parseUnits } from "ethers";
import { loadWallets } from "../lib/wallets.js";

// Return all GMB from the worker wallets to the funder (faucet), minus gas.
const env = process.env;
const net = Network.from(Number(env.CHAIN_ID));
const provider = new JsonRpcProvider(env.RPC_URLS.split(",")[0].trim(), net, { staticNetwork: net });
const funderAddr = new Wallet(env.FUNDER_PK).address;
const maxFee = parseUnits(env.MAX_FEE_GWEI || "3", "gwei");
const prio = parseUnits(env.PRIORITY_FEE_GWEI || "1", "gwei");
const gasCost = maxFee * 25000n; // 21000 + buffer
const records = loadWallets();
const chainId = Number(env.CHAIN_ID);

console.log(`sweeping ${records.length} wallets → faucet ${funderAddr}…`);
let returned = 0n, sent = 0, skipped = 0, failed = 0;
const POOL = 60;
for (let i = 0; i < records.length; i += POOL) {
  await Promise.all(records.slice(i, i + POOL).map(async (r) => {
    try {
      const bal = await provider.getBalance(r.address);
      if (bal <= gasCost) { skipped++; return; }
      const value = bal - gasCost;
      const w = new Wallet(r.privateKey, provider);
      const nonce = await provider.getTransactionCount(r.address, "latest");
      const tx = await w.sendTransaction({ to: funderAddr, value, nonce, type: 2, maxFeePerGas: maxFee, maxPriorityFeePerGas: prio, gasLimit: 21000n, chainId });
      await tx.wait(1);
      returned += value; sent++;
    } catch { failed++; }
  }));
  process.stdout.write(`\r  swept ${Math.min(i + POOL, records.length)}/${records.length} (sent ${sent}, skip ${skipped}, fail ${failed})   `);
}
const fbal = await provider.getBalance(funderAddr);
console.log(`\n✓ returned ${Number(returned) / 1e18} GMB to faucet. sent ${sent} skipped ${skipped} failed ${failed}. faucet balance now ${Number(fbal) / 1e18} GMB`);
process.exit(0);
