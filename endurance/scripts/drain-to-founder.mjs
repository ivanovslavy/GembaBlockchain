import "dotenv/config";
import { Wallet, JsonRpcProvider, Network, parseUnits, formatEther } from "ethers";
import { loadWallets } from "../lib/wallets.js";

// Returns all worker-wallet native GMB to the founder. Run after the 24h run (or to stop &
// recover). Uses the public DNS RPCs (never the validators directly).
const FOUNDER = "0x5578c75F22dE0bf1caA4BdD46BA28406C696a5dC";
const net = Network.from(Number(process.env.CHAIN_ID));
const urls = process.env.RPC_URLS.split(",").map((u) => u.trim());
const providers = urls.map((u) => new JsonRpcProvider(u, net, { staticNetwork: net }));
const provFor = (i) => providers[i % providers.length];
const provider = providers[0];

const wallets = loadWallets();
const base = (await provider.getBlock("latest")).baseFeePerGas || parseUnits("5", "gwei");
const tip = parseUnits(process.env.PRIORITY_FEE_GWEI || "2", "gwei");
const maxFee = base * 3n + tip;
const gasResv = 21000n * maxFee;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const chunks = (a, n) => { const o = []; for (let i = 0; i < a.length; i += n) o.push(a.slice(i, i + n)); return o; };

console.log("draining", wallets.length, "wallets → founder", FOUNDER);
let returned = 0n; const sent = [];
for (const ch of chunks(wallets, 10)) {
  await Promise.all(ch.map(async (rec) => {
    const p = provFor(rec.index);
    const sw = new Wallet(rec.privateKey, p);
    const bal = await p.getBalance(rec.address);
    if (bal > gasResv) {
      try {
        const tx = await sw.sendTransaction({ to: FOUNDER, value: bal - gasResv, maxFeePerGas: maxFee, maxPriorityFeePerGas: tip, gasLimit: 21000n });
        sent.push(tx.hash); returned += bal - gasResv;
      } catch (e) { console.log("  skip", rec.index, String(e.message).slice(0, 60)); }
    }
  }));
  await sleep(400);
}
console.log("submitted", sent.length, "drain txs; waiting last…");
if (sent.length) await provider.waitForTransaction(sent[sent.length - 1], 1);
console.log("RETURNED to founder:", formatEther(returned), "GMB (approx; minus gas)");
process.exit(0);
