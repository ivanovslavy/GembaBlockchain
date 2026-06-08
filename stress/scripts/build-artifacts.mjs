// Compile contracts with Foundry (run locally where forge exists) and extract
// {abi, bytecode} into stress/artifacts/<Name>.json so the engine on .83 needs only
// Node — no forge/solc on the load box.
import { execSync } from "node:child_process";
import { readFileSync, writeFileSync, readdirSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const contracts = join(root, "contracts");
const artifacts = join(root, "artifacts");
mkdirSync(artifacts, { recursive: true });

console.log("forge build…");
execSync("forge build", { cwd: contracts, stdio: "inherit" });

const names = ["StressERC20", "StressERC721", "StressERC1155", "Storage", "GasBomb", "Disperse", "StressDex", "StressNFT"];
const outDir = join(contracts, "out", "Stress.sol");
for (const n of names) {
  const j = JSON.parse(readFileSync(join(outDir, `${n}.json`), "utf8"));
  writeFileSync(join(artifacts, `${n}.json`), JSON.stringify({ abi: j.abi, bytecode: j.bytecode.object }, null, 0));
  console.log(`  ✓ ${n}`);
}
console.log("artifacts written →", artifacts);
