import "dotenv/config";
import { Interface } from "ethers";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { makeProviders } from "../lib/provider.js";
import { loadWallets } from "../lib/wallets.js";

// Static eth_call of each workload type → prints the exact revert reason (why it fails).
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const art = (n) => JSON.parse(readFileSync(join(root, "artifacts", `${n}.json`), "utf8"));
const dep = JSON.parse(readFileSync(join(root, "deployed.json"), "utf8"));
const A = dep.addresses;
const I = { erc20: new Interface(art("StressERC20").abi), erc1155: new Interface(art("StressERC1155").abi), erc721: new Interface(art("StressERC721").abi), storage: new Interface(art("Storage").abi), dex: new Interface(art("StressDex").abi) };
const providers = makeProviders(process.env.RPC_URLS.split(","), process.env.CHAIN_ID);
const p = providers.primary;
const w = loadWallets();
const from = w[5].address, id5 = BigInt(w[5].index), rand = w[9].address;

// state of the sample wallet
const bal0 = BigInt(await p.call({ to: A.t0, data: I.erc20.encodeFunctionData("balanceOf", [from]) }));
const allw = BigInt(await p.call({ to: A.t0, data: I.erc20.encodeFunctionData("allowance", [from, A.dex]) }));
const b1155 = BigInt(await p.call({ to: A.erc1155, data: I.erc1155.encodeFunctionData("balanceOf", [id5, from]) }));
console.log(`sample ${from}: ST0 balance=${bal0 > 0n} allowance(dex)=${allw > 0n} erc1155[id${w[5].index}]=${b1155}`);

const calls = [
  ["erc20Transfer", A.t0, I.erc20.encodeFunctionData("transfer", [rand, 1n])],
  ["erc20Mint", A.t0, I.erc20.encodeFunctionData("mint", [from, 1n])],
  ["erc1155Transfer", A.erc1155, I.erc1155.encodeFunctionData("safeTransferFrom", [from, rand, id5, 1n, "0x"])],
  ["erc721Mint", A.erc721, I.erc721.encodeFunctionData("mint", [rand])],
  ["dexSwap", A.dex, I.dex.encodeFunctionData("swap", [A.t0, A.t1, 1000n, 0n])],
  ["dexAddLiq", A.dex, I.dex.encodeFunctionData("addLiquidity", [A.t0, A.t1, 100000n, 100000n])],
  ["dexRemoveLiq", A.dex, I.dex.encodeFunctionData("removeLiquidity", [A.t0, A.t1, 1000n])],
  ["storageSet", A.storage, I.storage.encodeFunctionData("set", [1n, 1n])],
  ["revertOp", A.storage, I.storage.encodeFunctionData("boom", [])],
];
for (const [name, to, data] of calls) {
  try { await p.call({ from, to, data }); console.log(`  ✓ ${name}: OK`); }
  catch (e) { console.log(`  ✗ ${name}: ${e.reason || e.shortMessage || (e.info?.error?.message) || e.message}`.slice(0, 140)); }
}
process.exit(0);
