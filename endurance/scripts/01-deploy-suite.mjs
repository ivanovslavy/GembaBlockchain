import "dotenv/config";
import { Wallet, JsonRpcProvider, Network, ContractFactory, Contract, Interface, parseUnits } from "ethers";
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const art = (n) => JSON.parse(readFileSync(join(root, "artifacts", `${n}.json`), "utf8"));
const env = process.env;
if (!env.FUNDER_PK) throw new Error("FUNDER_PK (founder/deployer) not set in .env");

// LIVE infra (testnet) — never re-deployed, only used.
const LIVE = {
  router: "0x49Da581bf5C09aE24312574D4835d416EE5eEfd5",
  dexFactory: "0x15752A99d2e06d001F5d228AA158EbD687276DB4",
  wgmb: "0x4A74DB9c9cE285960d01B53a626945DDd100e8d8",
  faucet: "0x0147581e2351dD182edD651DFEfD955CB353f8aA",
  nativePoolFactory: "0x92F048fDF7fB98F800C4cF3c78F779681A208a99",
};

const net = Network.from(Number(env.CHAIN_ID));
const provider = new JsonRpcProvider(env.RPC_URLS.split(",")[0].trim(), net, { staticNetwork: net });
const funder = new Wallet(env.FUNDER_PK, provider);
const TIP = parseUnits(env.PRIORITY_FEE_GWEI || "2", "gwei");
async function feeOv() { const b = (await provider.getBlock("latest")).baseFeePerGas || parseUnits("5", "gwei"); return { maxFeePerGas: b * 3n + TIP, maxPriorityFeePerGas: TIP }; }

console.log("deployer (founder):", funder.address, "bal:", (await provider.getBalance(funder.address)).toString());

async function deploy(name, args = []) {
  const a = art(name);
  const f = new ContractFactory(a.abi, a.bytecode, funder);
  const c = await f.deploy(...args, await feeOv());
  await c.waitForDeployment();
  const addr = await c.getAddress();
  console.log(`  ✓ ${name} → ${addr}`);
  return addr;
}
const sel = (name, fn) => new Interface(art(name).abi).getFunction(fn).selector;

console.log("deploying contract suite…");
const tka = await deploy("EndERC20", ["Endurance Token A", "ETKA"]);
const tkb = await deploy("EndERC20", ["Endurance Token B", "ETKB"]);
const tkc = await deploy("EndERC20", ["Endurance Token C", "ETKC"]);
const erc1155 = await deploy("EndERC1155");
const nft = await deploy("EndERC721", ["Endurance NFT", "ENFT"]);
const marketNft = await deploy("EndERC721", ["Endurance Market NFT", "EMKT"]);

// EcosystemSim (multi-contract A->B->C): registry <- token <- bank
const ecoRegistry = await deploy("EcoRegistry");
const ecoToken = await deploy("EcoToken", [ecoRegistry]);
const ecoBank = await deploy("EcoBank", [ecoToken]);
{
  const c = new Contract(ecoRegistry, art("EcoRegistry").abi, funder);
  await (await c.setToken(ecoToken, await feeOv())).wait();
  console.log("  ✓ EcoRegistry.setToken(EcoToken)");
}

// Diamond (EIP-2535) + facets
const counterFacet = await deploy("CounterFacet");
const registryFacet = await deploy("RegistryFacet");
const loupeFacet = await deploy("LoupeFacet");
const cuts = [
  [counterFacet, [sel("CounterFacet", "increment"), sel("CounterFacet", "counter")]],
  [registryFacet, [sel("RegistryFacet", "setEntry"), sel("RegistryFacet", "entryOf"), sel("RegistryFacet", "pingsOf"), sel("RegistryFacet", "totalPings")]],
  [loupeFacet, [sel("LoupeFacet", "facetForSelector"), sel("LoupeFacet", "allSelectors"), sel("LoupeFacet", "diamondOwner")]],
];
const diamond = await deploy("Diamond", [cuts, funder.address]);

const miniFactory = await deploy("MiniFactory");
const childInitCodeHash = await new Contract(miniFactory, art("MiniFactory").abi, provider).childInitCodeHash();
console.log("  ✓ childInitCodeHash:", childInitCodeHash);

const market = await deploy("EnduranceMarket", [marketNft]);
const staking = await deploy("EnduranceStaking", [tka]);
const pinger = await deploy("Pinger");
const workbench = await deploy("Workbench");
const batch = await deploy("BatchExecutor");

// ---- expansion suite ----
const feeToken = await deploy("FeeOnTransferToken");
const rebaseToken = await deploy("RebasingToken");
const npToken = await deploy("EndERC20", ["Native Pool Token", "ENPT"]);
const permitToken = await deploy("PermitToken");
const voucherMinter = await deploy("VoucherMinter", [funder.address]); // authorized signer = founder (harness has FUNDER_PK)
const rewardToken = await deploy("EndERC20", ["Endurance Reward", "ERWD"]);
const vault = await deploy("MiniVault", [tkb]);
const rewardStaking = await deploy("RewardStaking", [tkc, rewardToken]);
const cloneImpl = await deploy("CloneTarget");
const cloneFactory = await deploy("CloneFactory", [cloneImpl]);
const cloneInitCodeHash = await new Contract(cloneFactory, art("CloneFactory").abi, provider).cloneInitCodeHash();
console.log("  ✓ cloneInitCodeHash:", cloneInitCodeHash);
const auctionNft = await deploy("EndERC721", ["Endurance Auction NFT", "EAUC"]);
const auctionHouse = await deploy("AuctionHouse", [auctionNft]);
const batchNft = await deploy("BatchMintNFT");
const nftStaking = await deploy("NftStaking", [batchNft, rewardToken]);
const royaltyNft = await deploy("RoyaltyNFT");
const royaltyMarket = await deploy("RoyaltyMarket", [royaltyNft]);
const miniGov = await deploy("MiniGov");
const govTarget = await deploy("GovTarget");
const hopE = await deploy("HopE");
const hopD = await deploy("HopD", [hopE]);
const hopC = await deploy("HopC", [hopD]);
const hopB = await deploy("HopB", [hopC]);
const hopA = await deploy("HopA", [hopB]);
const disperse = await deploy("Disperse");
const eventsHeavy = await deploy("EventsHeavy");

const erc20Abi = art("EndERC20").abi;
const MAXU = (1n << 255n);
const DEADLINE = 19999999999n;

// ---- seed GembaSwap router liquidity (5 pairs: ABC + fee-on-transfer + rebasing) ----
console.log("seeding GembaSwap liquidity (live router)…");
const R = 10n ** 26n;
const routerAbi = ["function addLiquidity(address tokenA,address tokenB,uint256 amountADesired,uint256 amountBDesired,uint256 amountAMin,uint256 amountBMin,address to,uint256 deadline) returns (uint256,uint256,uint256)"];
const factoryAbi = ["function getPair(address,address) view returns (address)"];
const router = new Contract(LIVE.router, routerAbi, funder);
const dexFactory = new Contract(LIVE.dexFactory, factoryAbi, provider);
for (const t of [tka, tkb, tkc, feeToken, rebaseToken]) {
  const c = new Contract(t, erc20Abi, funder);
  await (await c.mint(funder.address, R * 5n, await feeOv())).wait();
  await (await c.approve(LIVE.router, MAXU, await feeOv())).wait();
}
const PAIRS = [[tka, tkb], [tkb, tkc], [tka, tkc], [feeToken, tka], [rebaseToken, tka]];
for (const [x, y] of PAIRS) {
  await (await router.addLiquidity(x, y, R, R, 0n, 0n, funder.address, DEADLINE, await feeOv())).wait();
  console.log(`  ✓ liquidity ${x.slice(0, 8)}/${y.slice(0, 8)}`);
}
const pairAB = await dexFactory.getPair(tka, tkb);
const pairBC = await dexFactory.getPair(tkb, tkc);
const pairAC = await dexFactory.getPair(tka, tkc);

// ---- seed the LIVE GembaNativePool for npToken (native GMB <-> token) ----
console.log("seeding GembaNativePool…");
const npFactory = new Contract(LIVE.nativePoolFactory, [
  "function getPool(address) view returns (address)",
  "function createPool(address) returns (address)",
], funder);
if ((await npFactory.getPool(npToken)) === "0x0000000000000000000000000000000000000000") {
  await (await npFactory.createPool(npToken, await feeOv())).wait();
}
const nativePool = await npFactory.getPool(npToken);
const NP_TOK = 10n ** 23n, NP_NATIVE = 10n ** 20n; // token / native reserves
await (await new Contract(npToken, erc20Abi, funder).mint(funder.address, NP_TOK * 5n, await feeOv())).wait();
await (await new Contract(npToken, erc20Abi, funder).approve(nativePool, MAXU, await feeOv())).wait();
await (await new Contract(nativePool, [
  "function addLiquidity(uint256 amountTokenDesired,uint256 amountTokenMin,uint256 amountNativeMin,address to,uint256 deadline) payable returns (uint256,uint256,uint256)",
], funder).addLiquidity(NP_TOK, 0n, 0n, funder.address, DEADLINE, { ...(await feeOv()), value: NP_NATIVE })).wait();
console.log("  ✓ native pool:", nativePool);

const out = {
  chainId: Number(env.CHAIN_ID), deployer: funder.address, deployedAt: new Date().toISOString(),
  childInitCodeHash, cloneInitCodeHash,
  addresses: {
    tka, tkb, tkc, erc1155, nft, marketNft,
    ecoRegistry, ecoToken, ecoBank,
    diamond, counterFacet, registryFacet, loupeFacet,
    miniFactory, market, staking, pinger, workbench, batch,
    // expansion
    feeToken, rebaseToken, npToken, permitToken, voucherMinter, rewardToken, vault, rewardStaking,
    cloneImpl, cloneFactory, auctionNft, auctionHouse, batchNft, nftStaking, royaltyNft, royaltyMarket,
    miniGov, govTarget, hopA, disperse, eventsHeavy, nativePool,
    // live infra
    router: LIVE.router, dexFactory: LIVE.dexFactory, wgmb: LIVE.wgmb, faucet: LIVE.faucet, nativePoolFactory: LIVE.nativePoolFactory,
    pairAB, pairBC, pairAC,
  },
};
writeFileSync(join(root, "deployed.json"), JSON.stringify(out, null, 2));
console.log("✓ deployed.json written");
process.exit(0);
