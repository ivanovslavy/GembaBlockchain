import "dotenv/config";
import { Wallet, JsonRpcProvider, Network, Contract, parseEther, parseUnits, formatEther } from "ethers";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadWallets } from "../lib/wallets.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const art = (n) => JSON.parse(readFileSync(join(root, "artifacts", `${n}.json`), "utf8"));
const env = process.env;
if (!env.FUNDER_PK) throw new Error("FUNDER_PK not set in .env");
const dep = JSON.parse(readFileSync(join(root, "deployed.json"), "utf8"));
const A = dep.addresses;

const net = Network.from(Number(env.CHAIN_ID));
const urls = env.RPC_URLS.split(",").map((u) => u.trim());
const providers = urls.map((u) => new JsonRpcProvider(u, net, { staticNetwork: net }));
const provFor = (i) => providers[i % providers.length];
const provider = providers[0];
const funder = new Wallet(env.FUNDER_PK, provider);

const wallets = loadWallets();
const FUND = parseEther(env.FUND_PER_WALLET || "15");      // TOP-UP target (native GMB per wallet)
const TOKENS = 10n ** 28n;                                  // each ERC20 minted per wallet
const MAXU = (1n << 255n);
const TIP = parseUnits(env.PRIORITY_FEE_GWEI || "2", "gwei");
const base = (await provider.getBlock("latest")).baseFeePerGas || parseUnits("5", "gwei");
const MAXFEE = base * 3n + TIP;
const feeG = (gas) => ({ maxFeePerGas: MAXFEE, maxPriorityFeePerGas: TIP, gasLimit: gas });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const chunks = (a, n) => { const o = []; for (let i = 0; i < a.length; i += n) o.push(a.slice(i, i + n)); return o; };

const erc20 = art("EndERC20").abi;
const erc721 = art("EndERC721").abi;        // mint/transferFrom/setApprovalForAll (also BatchMintNFT/RoyaltyNFT share setApprovalForAll)
const MINT_TOKENS = [A.tka, A.tkb, A.tkc, A.npToken, A.feeToken, A.rebaseToken, A.permitToken];
// [token, spender] ERC20 approvals
const ERC20_APPROVALS = [
  [A.tka, A.router], [A.tkb, A.router], [A.tkc, A.router],
  [A.pairAB, A.router], [A.pairBC, A.router], [A.pairAC, A.router],
  [A.tka, A.staking], [A.tkb, A.vault], [A.tkc, A.rewardStaking],
  [A.npToken, A.nativePool], [A.feeToken, A.router], [A.rebaseToken, A.router],
];
// [nft, operator] setApprovalForAll
const NFT_APPROVALS = [
  [A.marketNft, A.market], [A.batchNft, A.nftStaking], [A.royaltyNft, A.royaltyMarket], [A.auctionNft, A.auctionHouse],
];

console.log(`seeding ${wallets.length} wallets from founder ${funder.address}`);
console.log(`  fund top-up target=${formatEther(FUND)} GMB | mint ${MINT_TOKENS.length} tokens | ${ERC20_APPROVALS.length + NFT_APPROVALS.length} approvals each`);
console.log(`  funder balance: ${formatEther(await provider.getBalance(funder.address))} GMB`);

// ---------- Phase 1: TOP UP native GMB to target ----------
{
  const bals = [];
  for (const ch of chunks(wallets, 25)) bals.push(...await Promise.all(ch.map((w) => provFor(w.index).getBalance(w.address))));
  let nonce = await provider.getTransactionCount(funder.address, "latest");
  const ops = [];
  for (let i = 0; i < wallets.length; i++) if (bals[i] < FUND) ops.push({ n: nonce++, to: wallets[i].address, value: FUND - bals[i] });
  console.log(`  phase 1: topping up ${ops.length}/${wallets.length} wallets to ${formatEther(FUND)} GMB`);
  let last;
  for (const ch of chunks(ops, 25)) { const rs = await Promise.all(ch.map((o) => funder.sendTransaction({ to: o.to, value: o.value, nonce: o.n, ...feeG(21000n) }))); last = rs[rs.length - 1]; await sleep(250); }
  if (last) await last.wait();
}

// ---------- Phase 2: mint tokens to each wallet (founder) ----------
{
  let nonce = await provider.getTransactionCount(funder.address, "latest");
  const ops = [];
  for (const w of wallets) for (const t of MINT_TOKENS) ops.push({ n: nonce++, t, to: w.address });
  console.log(`  phase 2: ${ops.length} token mints…`);
  let last;
  for (const ch of chunks(ops, 25)) { const rs = await Promise.all(ch.map((o) => new Contract(o.t, erc20, funder).mint(o.to, TOKENS, { nonce: o.n, ...feeG(75000n) }))); last = rs[rs.length - 1]; await sleep(250); }
  if (last) await last.wait();
}

// ---------- Phase 3: per-wallet approvals (worker-sent; must mine before the run) ----------
{
  const lastHashes = []; let done = 0;
  for (const ch of chunks(wallets, 6)) {
    await Promise.all(ch.map(async (rec) => {
      const p = provFor(rec.index);
      const w = new Wallet(rec.privateKey, p);
      let n = await p.getTransactionCount(rec.address, "latest");
      let last;
      for (const [token, spender] of ERC20_APPROVALS) last = await new Contract(token, erc20, w).approve(spender, MAXU, { nonce: n++, ...feeG(60000n) });
      for (const [nft, op] of NFT_APPROVALS) last = await new Contract(nft, erc721, w).setApprovalForAll(op, true, { nonce: n++, ...feeG(70000n) });
      lastHashes.push(last.hash);
    }));
    done += ch.length;
    process.stdout.write(`\r  phase 3: approvals submitted for ${done}/${wallets.length} wallets   `);
    await sleep(700);
  }
  console.log("\n  phase 3: waiting for every wallet's approvals to mine…");
  for (const ch of chunks(lastHashes, 25)) await Promise.all(ch.map((h) => provider.waitForTransaction(h, 1)));
}

// ---------- verify a sample ----------
const w0 = wallets[0], p0 = provFor(0);
console.log("=== sample wallet[0]", w0.address, "===");
console.log("  native:", formatEther(await p0.getBalance(w0.address)), "GMB | TKA:", (await new Contract(A.tka, erc20, p0).balanceOf(w0.address)).toString());
console.log("  router(tka):", (await new Contract(A.tka, erc20, p0).allowance(w0.address, A.router)) > 0n,
  "| vault(tkb):", (await new Contract(A.tkb, erc20, p0).allowance(w0.address, A.vault)) > 0n,
  "| rwdStk(tkc):", (await new Contract(A.tkc, erc20, p0).allowance(w0.address, A.rewardStaking)) > 0n,
  "| nativePool(npt):", (await new Contract(A.npToken, erc20, p0).allowance(w0.address, A.nativePool)) > 0n);
console.log("  nftStaking(batch):", await new Contract(A.batchNft, erc721, p0).isApprovedForAll(w0.address, A.nftStaking),
  "| auctionHouse:", await new Contract(A.auctionNft, erc721, p0).isApprovedForAll(w0.address, A.auctionHouse),
  "| royaltyMarket:", await new Contract(A.royaltyNft, erc721, p0).isApprovedForAll(w0.address, A.royaltyMarket));
console.log("  funder left:", formatEther(await provider.getBalance(funder.address)), "GMB");
console.log("✓ seed complete");
process.exit(0);
