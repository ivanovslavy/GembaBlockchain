// Compile the endurance contracts with Foundry (run locally where forge exists) and extract
// {abi, bytecode} into endurance/artifacts/<Name>.json so the engine on the Pi needs only
// Node — no forge/solc on the Pi. Mirrors stress/scripts/build-artifacts.mjs.
import { execSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const contracts = join(root, "contracts");
const artifacts = join(root, "artifacts");
mkdirSync(artifacts, { recursive: true });

console.log("forge build…");
execSync("forge build", { cwd: contracts, stdio: "inherit" });

// contract name -> source file (out/<file>.sol/<Name>.json)
const MAP = {
  EndERC20: "Tokens.sol", EndERC721: "Tokens.sol", EndERC1155: "Tokens.sol",
  EcoRegistry: "Ecosystem.sol", EcoToken: "Ecosystem.sol", EcoBank: "Ecosystem.sol",
  Diamond: "Diamond.sol", CounterFacet: "Diamond.sol", RegistryFacet: "Diamond.sol", LoupeFacet: "Diamond.sol",
  ChildCounter: "Factory.sol", MiniFactory: "Factory.sol",
  EnduranceMarket: "Market.sol",
  EnduranceStaking: "Staking.sol",
  Pinger: "Batch.sol", Workbench: "Batch.sol", BatchExecutor: "Batch.sol",
  // --- expansion ---
  CloneTarget: "Clones.sol", CloneFactory: "Clones.sol",
  MiniVault: "DeFi.sol", RewardStaking: "DeFi.sol",
  AuctionHouse: "Auctions.sol",
  BatchMintNFT: "NftExtras.sol", NftStaking: "NftExtras.sol", RoyaltyNFT: "NftExtras.sol", RoyaltyMarket: "NftExtras.sol",
  MiniGov: "Governance.sol", GovTarget: "Governance.sol",
  HopA: "Composite.sol", HopB: "Composite.sol", HopC: "Composite.sol", HopD: "Composite.sol", HopE: "Composite.sol",
  Disperse: "Composite.sol", EventsHeavy: "Composite.sol",
  PermitToken: "SignedFlows.sol", VoucherMinter: "SignedFlows.sol",
  FeeOnTransferToken: "EdgeTokens.sol", RebasingToken: "EdgeTokens.sol",
};

for (const [name, file] of Object.entries(MAP)) {
  const j = JSON.parse(readFileSync(join(contracts, "out", file, `${name}.json`), "utf8"));
  writeFileSync(join(artifacts, `${name}.json`), JSON.stringify({ abi: j.abi, bytecode: j.bytecode.object }, null, 0));
  console.log(`  ✓ ${name}`);
}
console.log("artifacts written →", artifacts);
