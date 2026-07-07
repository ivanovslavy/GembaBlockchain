// Robust sweep: FIRE one tx per worker wallet → funder (no tx.wait → can't hang). One tx per
// wallet, so no cross-wallet nonce sequencing. Verify by polling the funder balance afterwards.
import "dotenv/config";
import { Wallet, JsonRpcProvider, Network, parseUnits } from "ethers";
import { loadWallets } from "../lib/wallets.js";
const env = process.env;
const net = Network.from(Number(env.CHAIN_ID));
const provider = new JsonRpcProvider(env.RPC_URLS.split(",")[0].trim(), net, { staticNetwork: net });
const funder = new Wallet(env.FUNDER_PK).address;
const maxFee = parseUnits("8", "gwei"), prio = parseUnits("2", "gwei"), gasCost = maxFee * 25000n;
const chainId = Number(env.CHAIN_ID);
const recs = loadWallets();
console.log(`sweeping ${recs.length} → ${funder} (fire-and-forget)…`);
let sent = 0, skip = 0, fail = 0;
const POOL = 20;
for (let i = 0; i < recs.length; i += POOL) {
  await Promise.all(recs.slice(i, i + POOL).map(async (r) => {
    try {
      const bal = await provider.getBalance(r.address);
      if (bal <= gasCost) { skip++; return; }
      const w = new Wallet(r.privateKey, provider);
      const nonce = await provider.getTransactionCount(r.address, "latest");
      await w.sendTransaction({ to: funder, value: bal - gasCost, nonce, type: 2, maxFeePerGas: maxFee, maxPriorityFeePerGas: prio, gasLimit: 21000n, chainId });
      sent++;
    } catch (e) { fail++; }
  }));
  process.stdout.write(`\r  ${Math.min(i + POOL, recs.length)}/${recs.length} sent=${sent} skip=${skip} fail=${fail}  `);
}
console.log(`\ndone: submitted ${sent}, skipped ${skip}, failed ${fail} (txs will mine in next blocks)`);
process.exit(0);
