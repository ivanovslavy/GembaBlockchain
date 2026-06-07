import "dotenv/config";
import { Wallet, JsonRpcProvider, ContractFactory, Contract, Network } from "ethers";
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const art = (n) => JSON.parse(readFileSync(join(root, "artifacts", `${n}.json`), "utf8"));
const env = process.env;
if (!env.FUNDER_PK) throw new Error("FUNDER_PK not set in .env");

const net = Network.from(Number(env.CHAIN_ID));
const provider = new JsonRpcProvider(env.RPC_URLS.split(",")[0].trim(), net, { staticNetwork: net });
const funder = new Wallet(env.FUNDER_PK, provider);
console.log("funder:", funder.address, "balance:", (await provider.getBalance(funder.address)).toString());

async function deploy(name, args = []) {
  const a = art(name);
  const f = new ContractFactory(a.abi, a.bytecode, funder);
  const c = await f.deploy(...args);
  await c.waitForDeployment();
  const addr = await c.getAddress();
  console.log(`  ✓ ${name} → ${addr}`);
  return addr;
}

console.log("deploying suite…");
const t0 = await deploy("StressERC20", ["Stress Token 0", "ST0"]);
const t1 = await deploy("StressERC20", ["Stress Token 1", "ST1"]);
const erc721 = await deploy("StressERC721", ["Stress NFT", "SNFT"]);
const erc1155 = await deploy("StressERC1155");
const storage = await deploy("Storage");
const gasbomb = await deploy("GasBomb");
const disperse = await deploy("Disperse");
const dex = await deploy("StressDex");

// Seed the DEX pool from the funder so swaps have liquidity from the start.
console.log("seeding DEX liquidity…");
const erc20Abi = art("StressERC20").abi;
const SEED = 10n ** 30n;
for (const t of [t0, t1]) {
  const c = new Contract(t, erc20Abi, funder);
  await (await c.mint(funder.address, SEED)).wait();
  await (await c.approve(dex, 1n << 255n)).wait();
}
const dexC = new Contract(dex, art("StressDex").abi, funder);
await (await dexC.addLiquidity(t0, t1, 10n ** 24n, 10n ** 24n)).wait();
console.log("  ✓ pool seeded (ST0/ST1)");

const out = { chainId: Number(env.CHAIN_ID), funder: funder.address, deployedAt: new Date().toISOString(),
  addresses: { t0, t1, erc721, erc1155, storage, gasbomb, disperse, dex } };
writeFileSync(join(root, "deployed.json"), JSON.stringify(out, null, 2));
console.log("✓ deployed.json written");
process.exit(0);
