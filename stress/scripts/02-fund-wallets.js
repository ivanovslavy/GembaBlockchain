import "dotenv/config";
import { Wallet, JsonRpcProvider, Contract, Network, parseEther } from "ethers";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadWallets } from "../lib/wallets.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const art = (n) => JSON.parse(readFileSync(join(root, "artifacts", `${n}.json`), "utf8"));
const env = process.env;
const dep = JSON.parse(readFileSync(join(root, "deployed.json"), "utf8"));

const net = Network.from(Number(env.CHAIN_ID));
const provider = new JsonRpcProvider(env.RPC_URLS.split(",")[0].trim(), net, { staticNetwork: net });
const funder = new Wallet(env.FUNDER_PK, provider);
const wallets = loadWallets();
const per = parseEther(env.FUND_PER_WALLET || "2.0");

const disperse = new Contract(dep.addresses.disperse, art("Disperse").abi, funder);
const BATCH = 100;
console.log(`dispersing ${env.FUND_PER_WALLET} GMB to ${wallets.length} wallets in batches of ${BATCH}…`);
for (let i = 0; i < wallets.length; i += BATCH) {
  const slice = wallets.slice(i, i + BATCH);
  const addrs = slice.map((w) => w.address);
  const amts = slice.map(() => per);
  const total = per * BigInt(slice.length);
  const tx = await disperse.disperse(addrs, amts, { value: total });
  await tx.wait();
  console.log(`  ✓ funded ${Math.min(i + BATCH, wallets.length)}/${wallets.length}`);
}
const bal = await provider.getBalance(wallets[0].address);
console.log(`✓ funding done. sample wallet ${wallets[0].address} = ${bal} wei`);
console.log("  (wallets self-bootstrap token balances + approvals via the workload mix; early reverts are expected & logged)");
process.exit(0);
