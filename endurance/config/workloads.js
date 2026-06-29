// Endurance workload — "everything a real chain does", state-guarded so NOTHING reverts.
//
// CONFIRMATION-GATED model: a producer op (mint / deposit / addLiq / list / deploy / propose…)
// does NOT mutate consumable state in build(); instead it attaches `req._apply`, which the
// engine runs ONLY when that tx actually MINES (collector.onResolve). A consumer op
// (transfer / withdraw / buy / call / vote…) therefore only ever acts on state that is
// CONFIRMED on-chain — a producer that times out leaves no phantom state, so the consumer can
// never revert. Combined with MAX_INFLIGHT_PER_WALLET=1 (no per-wallet nonce gaps over the
// WAN), this yields 0 reverts / ~100% mined over 24h. No adversarial ops.
//
// build(ctx, from) -> {to, data, value, gas, _apply?}|null   (null = "not ready", engine re-picks)
//   _apply(res) runs on mine; for credits it adds, for queues it pushes a now-confirmed entry.

import { TypedDataEncoder } from "ethers";

const G = (n) => BigInt(n);
const randOf = (a) => a[(Math.random() * a.length) | 0];
const randPair = (ctx) => randOf(ctx.pairs);
const QCAP = 300;
const cap = (q) => { if (q.length > QCAP) q.shift(); };

// tiny amounts vs huge seeded balances/reserves → 24h never depletes
const SWAP_IN = 10n ** 18n, ADD_LIQ = 10n ** 18n, LP_REMOVE = 10n ** 16n, LP_CREDIT = ADD_LIQ / 4n;
const NSWAP_IN = 10n ** 15n, NADD_TOK = 10n ** 18n, NADD_NATIVE = 10n ** 15n, NLP_REMOVE = 10n ** 13n, NLP_CREDIT = 10n ** 13n;
const WRAP_IN = 10n ** 15n, UNWRAP_OUT = 10n ** 14n;
const ECO_DEP = 10n ** 9n, ECO_WD = 4n * 10n ** 8n;
const STAKE_IN = 10n ** 18n, STAKE_WD = 4n * 10n ** 17n;
const RWD_STAKE = 10n ** 18n, RWD_UNSTAKE = 4n * 10n ** 17n;
const VAULT_DEP = 10n ** 18n, VAULT_WD = 4n * 10n ** 17n;
const MKT_PRICE = 10n ** 9n, ROY_PRICE = 10n ** 9n;
const AUC_RESERVE = 10n ** 9n, DUTCH_START = 2n * 10n ** 9n, DUTCH_FLOOR = 10n ** 8n, DUTCH_DECAY = 1000000n;
const PERMIT_VALUE = 10n ** 20n, PERMIT_XFER = 10n ** 15n, VOUCHER_AMT = 10n ** 18n;
const ERC20_MINT = 10n ** 24n, ERC1155_AMT = 1000000n;
const DEADLINE = 19999999999n, MAXU = (1n << 255n);
// confirmation-relative time windows (ms) for the multi-phase lifecycles (auction / governance)
const ENG_DUR = 180, GOV_VOTE = 40, GOV_TL = 40; // on-chain seconds (mirror the contracts)

function defs(ctx) {
  const I = ctx.iface, A = ctx.addr, pool = ctx.addresses;
  const others = (f) => { let a = randOf(pool); return a === f ? randOf(pool) : a; };
  const ago = (ts) => Date.now() - ts;

  return {
    // ===== native + ERC20 =====
    nativeTransfer: { build: (c, f) => ({ to: others(f), value: 1n, gas: G(21000) }) },
    erc20Mint:      { build: (c, f) => ({ to: A.tka, data: I.erc20.encodeFunctionData("mint", [f, ERC20_MINT]), gas: G(75000) }) },
    erc20Transfer:  { build: (c, f) => ({ to: randOf([A.tka, A.tkb]), data: I.erc20.encodeFunctionData("transfer", [others(f), 1n]), gas: G(70000) }) },
    erc20Approve:   { build: (c, f) => ({ to: randOf([A.tka, A.tkb, A.tkc]), data: I.erc20.encodeFunctionData("approve", [A.router, MAXU]), gas: G(60000) }) },

    // ===== ERC721 (caller-chosen id; confirmation-gated transfer) =====
    nftMint:     { build: (c, f) => { const id = c.nftSeq++; const r = { to: A.nft, data: I.erc721.encodeFunctionData("mint", [f, id]), gas: G(120000) }; r._apply = () => { (c.nftOwned[f] ||= []).push({ id }); cap(c.nftOwned[f]); }; return r; } },
    nftTransfer: { build: (c, f) => { const q = c.nftOwned[f]; if (!q || !q.length) return null; const e = q.shift(); return { to: A.nft, data: I.erc721.encodeFunctionData("transferFrom", [f, others(f), e.id]), gas: G(90000) }; } },

    // ===== ERC1155 =====
    erc1155Mint:     { build: (c, f) => { const id = G(c.indexOf(f) ?? 0); const r = { to: A.erc1155, data: I.erc1155.encodeFunctionData("mint", [f, id, ERC1155_AMT]), gas: G(75000) }; r._apply = () => { c.has1155[f] = true; }; return r; } },
    erc1155Transfer: { build: (c, f) => { if (!c.has1155[f]) return null; const id = G(c.indexOf(f) ?? 0); return { to: A.erc1155, data: I.erc1155.encodeFunctionData("safeTransferFrom", [f, others(f), id, 1n, "0x"]), gas: G(75000) }; } },

    // ===== wrap / unwrap GMB (live WGMB) =====
    wrapGMB:   { build: (c, f) => { const r = { to: A.wgmb, data: I.wgmb.encodeFunctionData("deposit", []), value: WRAP_IN, gas: G(70000) }; r._apply = () => { c.wgmb[f] = (c.wgmb[f] || 0n) + WRAP_IN; }; return r; } },
    unwrapGMB: { build: (c, f) => { if ((c.wgmb[f] || 0n) < UNWRAP_OUT) return null; c.wgmb[f] -= UNWRAP_OUT; return { to: A.wgmb, data: I.wgmb.encodeFunctionData("withdraw", [UNWRAP_OUT]), gas: G(70000) }; } },

    // ===== real GembaSwap router trading (live) =====
    dexSwap:      { build: (c, f) => { const p = randPair(c); const path = Math.random() < 0.5 ? [p.a, p.b] : [p.b, p.a]; return { to: A.router, data: I.router.encodeFunctionData("swapExactTokensForTokens", [SWAP_IN, 0n, path, f, DEADLINE]), gas: G(240000) }; } },
    dexAddLiq:    { build: (c, f) => { const p = randPair(c); const r = { to: A.router, data: I.router.encodeFunctionData("addLiquidity", [p.a, p.b, ADD_LIQ, ADD_LIQ, 0n, 0n, f, DEADLINE]), gas: G(280000) }; r._apply = () => { (c.lp[f] ||= {}); c.lp[f][p.lp] = (c.lp[f][p.lp] || 0n) + LP_CREDIT; }; return r; } },
    dexRemoveLiq: { build: (c, f) => { const m = c.lp[f]; if (!m) return null; for (const p of c.pairs) { if ((m[p.lp] || 0n) >= LP_REMOVE) { m[p.lp] -= LP_REMOVE; return { to: A.router, data: I.router.encodeFunctionData("removeLiquidity", [p.a, p.b, LP_REMOVE, 0n, 0n, f, DEADLINE]), gas: G(260000) }; } } return null; } },
    // fee-on-transfer + rebasing tokens via the SupportingFeeOnTransferTokens path
    feeSwap:    { build: (c, f) => ({ to: A.router, data: I.router.encodeFunctionData("swapExactTokensForTokensSupportingFeeOnTransferTokens", [SWAP_IN, 0n, [A.feeToken, A.tka], f, DEADLINE]), gas: G(260000) }) },
    rebaseSwap: { build: (c, f) => ({ to: A.router, data: I.router.encodeFunctionData("swapExactTokensForTokensSupportingFeeOnTransferTokens", [SWAP_IN, 0n, [A.rebaseToken, A.tka], f, DEADLINE]), gas: G(260000) }) },
    rebaseUp:   { build: (c, f) => ({ to: A.rebaseToken, data: I.rebase.encodeFunctionData("rebase", [10n]), gas: G(80000) }) }, // +0.1%

    // ===== live GembaNativePool (native-GMB liquidity + native swaps) =====
    nativeSwapIn:  { build: (c, f) => ({ to: A.nativePool, data: I.nativePool.encodeFunctionData("swapExactNativeForTokens", [0n, f, DEADLINE]), value: NSWAP_IN, gas: G(230000) }) },
    nativeSwapOut: { build: (c, f) => ({ to: A.nativePool, data: I.nativePool.encodeFunctionData("swapExactTokensForNative", [NSWAP_IN, 0n, f, DEADLINE]), gas: G(230000) }) },
    nativeAddLiq:  { build: (c, f) => { const r = { to: A.nativePool, data: I.nativePool.encodeFunctionData("addLiquidity", [NADD_TOK, 0n, 0n, f, DEADLINE]), value: NADD_NATIVE, gas: G(320000) }; r._apply = () => { c.nlp[f] = (c.nlp[f] || 0n) + NLP_CREDIT; }; return r; } },
    nativeRemoveLiq: { build: (c, f) => { if ((c.nlp[f] || 0n) < NLP_REMOVE) return null; c.nlp[f] -= NLP_REMOVE; return { to: A.nativePool, data: I.nativePool.encodeFunctionData("removeLiquidity", [NLP_REMOVE, 0n, 0n, f, DEADLINE]), gas: G(260000) }; } },

    // ===== multi-contract A->B->C (EcosystemSim) =====
    ecoDeposit:  { build: (c, f) => { const r = { to: A.ecoBank, data: I.ecoBank.encodeFunctionData("deposit", []), value: ECO_DEP, gas: G(280000) }; r._apply = () => { c.eco[f] = (c.eco[f] || 0n) + ECO_DEP; }; return r; } },
    ecoWithdraw: { build: (c, f) => { if ((c.eco[f] || 0n) < ECO_WD) return null; c.eco[f] -= ECO_WD; return { to: A.ecoBank, data: I.ecoBank.encodeFunctionData("withdraw", [ECO_WD]), gas: G(130000) }; } },

    // ===== Diamond (EIP-2535) =====
    diamondBump: { build: (c, f) => ({ to: A.diamond, data: I.counter.encodeFunctionData("increment", []), gas: G(110000) }) },
    diamondSet:  { build: (c, f) => ({ to: A.diamond, data: I.registry.encodeFunctionData("setEntry", [G((Math.random() * 1e9) | 0)]), gas: G(180000) }) },

    // ===== deploy-during-run + call the child =====
    deployChild:       { build: (c, f) => { const r = { to: undefined, data: c.childBytecode, gas: G(280000) }; r._apply = (res) => { (c.eoaChildren[f] ||= []).push({ addr: c.createAddr(f, res.nonce) }); cap(c.eoaChildren[f]); }; return r; } },
    callDeployedChild: { build: (c, f) => { const q = c.eoaChildren[f]; if (!q || !q.length) return null; return { to: q[0].addr, data: I.child.encodeFunctionData("bump", []), gas: G(95000) }; } },
    factoryDeploy:     { build: (c, f) => { const salt = c.salt++; const addr = c.create2Addr(salt); const r = { to: A.miniFactory, data: I.factory.encodeFunctionData("createChild", [salt]), gas: G(240000) }; r._apply = () => { (c.factoryChildren[f] ||= []).push({ addr }); cap(c.factoryChildren[f]); }; return r; } },
    factoryCallChild:  { build: (c, f) => { const q = c.factoryChildren[f]; if (!q || !q.length) return null; return { to: q[0].addr, data: I.child.encodeFunctionData("setValue", [G((Math.random() * 1e6) | 0)]), gas: G(95000) }; } },

    // ===== EIP-1167 clones =====
    cloneAndInit:       { build: (c, f) => ({ to: A.cloneFactory, data: I.cloneFactory.encodeFunctionData("cloneAndInit", [G((Math.random() * 1e6) | 0)]), gas: G(260000) }) }, // deploy+init+use in 1 tx
    cloneDeterministic: { build: (c, f) => { const salt = c.cloneSalt++; const saltHex = c.salt32(salt); const addr = c.cloneAddr(saltHex); const r = { to: A.cloneFactory, data: I.cloneFactory.encodeFunctionData("cloneDeterministic", [saltHex]), gas: G(220000) }; r._apply = () => { (c.clones[f] ||= []).push({ addr, inited: false }); cap(c.clones[f]); }; return r; } },
    cloneInit:          { build: (c, f) => { const q = c.clones[f]; if (!q) return null; const e = q.find((x) => !x.inited); if (!e) return null; e.inited = true; return { to: e.addr, data: I.cloneTarget.encodeFunctionData("init", [f, G((Math.random() * 1e6) | 0)]), gas: G(120000) }; } },
    cloneCall:          { build: (c, f) => { const q = c.clones[f]; if (!q || !q.length) return null; return { to: q[0].addr, data: I.cloneTarget.encodeFunctionData("ping", []), gas: G(90000) }; } },

    // ===== NFT marketplace with escrow (list/buy between participants) =====
    mktMint: { build: (c, f) => { const id = c.mktSeq++; const r = { to: A.marketNft, data: I.erc721.encodeFunctionData("mint", [f, id]), gas: G(120000) }; r._apply = () => { (c.mktOwned[f] ||= []).push({ id }); cap(c.mktOwned[f]); }; return r; } },
    mktList: { build: (c, f) => { const q = c.mktOwned[f]; if (!q || !q.length) return null; const e = q.shift(); const r = { to: A.market, data: I.market.encodeFunctionData("list", [e.id, MKT_PRICE]), gas: G(220000) }; r._apply = () => { c.mktListed.push({ id: e.id, seller: f, price: MKT_PRICE, bought: false }); if (c.mktListed.length > 6000) { c.mktListed = c.mktListed.slice(-3000); c.mktCursor = 0; } }; return r; } },
    mktBuy:  { build: (c, f) => { const L = c.mktListed; while (c.mktCursor < L.length && L[c.mktCursor].bought) c.mktCursor++; for (let i = c.mktCursor, n = 0; i < L.length && n < 400; i++, n++) { const e = L[i]; if (!e.bought && e.seller !== f) { e.bought = true; return { to: A.market, data: I.market.encodeFunctionData("buy", [e.id]), value: e.price, gas: G(200000) }; } } return null; } },

    // ===== NFT marketplace with EIP-2981 royalties =====
    royaltyMint:   { build: (c, f) => { const id = c.roySeq++; const r = { to: A.royaltyNft, data: I.royaltyNft.encodeFunctionData("mint", [f, id]), gas: G(120000) }; r._apply = () => { (c.royOwned[f] ||= []).push({ id }); cap(c.royOwned[f]); }; return r; } },
    royaltyList:   { build: (c, f) => { const q = c.royOwned[f]; if (!q || !q.length) return null; const e = q.shift(); const r = { to: A.royaltyMarket, data: I.royaltyMarket.encodeFunctionData("list", [e.id, ROY_PRICE]), gas: G(220000) }; r._apply = () => { c.royListed.push({ id: e.id, seller: f, price: ROY_PRICE, taken: false }); if (c.royListed.length > 6000) { c.royListed = c.royListed.slice(-3000); c.royCursor = 0; } }; return r; } },
    royaltyBuy:    { build: (c, f) => { const L = c.royListed; while (c.royCursor < L.length && L[c.royCursor].taken) c.royCursor++; for (let i = c.royCursor, n = 0; i < L.length && n < 400; i++, n++) { const e = L[i]; if (!e.taken && e.seller !== f) { e.taken = true; return { to: A.royaltyMarket, data: I.royaltyMarket.encodeFunctionData("buy", [e.id]), value: e.price, gas: G(230000) }; } } return null; } },
    royaltyCancel: { build: (c, f) => { const L = c.royListed; for (let i = 0, n = 0; i < L.length && n < 200; i++, n++) { const e = L[i]; if (!e.taken && e.seller === f) { e.taken = true; return { to: A.royaltyMarket, data: I.royaltyMarket.encodeFunctionData("cancel", [e.id]), gas: G(160000) }; } } return null; } },

    // ===== ERC721A-style batch mint + NFT staking =====
    batchMint:        { build: (c, f) => { const n = 3 + ((Math.random() * 6) | 0); const start = c.batchSeq; c.batchSeq += BigInt(n); const r = { to: A.batchNft, data: I.batchNft.encodeFunctionData("mintBatch", [f, start, G(n)]), gas: G(120000 + 30000 * n) }; r._apply = () => { for (let i = 0; i < n; i++) (c.batchIds[f] ||= []).push({ id: start + BigInt(i) }); cap(c.batchIds[f] ||= []); }; return r; } },
    nftStakeStake:    { build: (c, f) => { const q = c.batchIds[f]; if (!q || !q.length) return null; const e = q.shift(); const r = { to: A.nftStaking, data: I.nftStaking.encodeFunctionData("stake", [e.id]), gas: G(200000) }; r._apply = () => { (c.nftStaked[f] ||= []).push({ id: e.id }); cap(c.nftStaked[f]); }; return r; } },
    nftStakeUnstake:  { build: (c, f) => { const q = c.nftStaked[f]; if (!q || !q.length) return null; const e = q.shift(); return { to: A.nftStaking, data: I.nftStaking.encodeFunctionData("unstake", [e.id]), gas: G(220000) }; } },

    // ===== ERC-4626-style vault =====
    vaultDeposit:  { build: (c, f) => { const r = { to: A.vault, data: I.vault.encodeFunctionData("deposit", [VAULT_DEP]), gas: G(200000) }; r._apply = () => { c.vault[f] = (c.vault[f] || 0n) + VAULT_DEP; }; return r; } },
    vaultMint:     { build: (c, f) => { const r = { to: A.vault, data: I.vault.encodeFunctionData("mint", [VAULT_DEP]), gas: G(200000) }; r._apply = () => { c.vault[f] = (c.vault[f] || 0n) + VAULT_DEP; }; return r; } },
    vaultWithdraw: { build: (c, f) => { if ((c.vault[f] || 0n) < VAULT_WD) return null; c.vault[f] -= VAULT_WD; const fn = Math.random() < 0.5 ? "withdraw" : "redeem"; return { to: A.vault, data: I.vault.encodeFunctionData(fn, [VAULT_WD]), gas: G(160000) }; } },

    // ===== staking (plain + time-based reward) =====
    stakeDeposit:  { build: (c, f) => { const r = { to: A.staking, data: I.staking.encodeFunctionData("stake", [STAKE_IN]), gas: G(220000) }; r._apply = () => { c.stake[f] = (c.stake[f] || 0n) + STAKE_IN; }; return r; } },
    stakeWithdraw: { build: (c, f) => { if ((c.stake[f] || 0n) < STAKE_WD) return null; c.stake[f] -= STAKE_WD; return { to: A.staking, data: I.staking.encodeFunctionData("withdraw", [STAKE_WD]), gas: G(160000) }; } },
    rwdStake:      { build: (c, f) => { const r = { to: A.rewardStaking, data: I.rewardStaking.encodeFunctionData("stake", [RWD_STAKE]), gas: G(260000) }; r._apply = () => { c.rwd[f] = (c.rwd[f] || 0n) + RWD_STAKE; }; return r; } },
    rwdClaim:      { build: (c, f) => { if (!(c.rwd[f] > 0n)) return null; return { to: A.rewardStaking, data: I.rewardStaking.encodeFunctionData("claim", []), gas: G(180000) }; } },
    rwdUnstake:    { build: (c, f) => { if ((c.rwd[f] || 0n) < RWD_UNSTAKE) return null; c.rwd[f] -= RWD_UNSTAKE; return { to: A.rewardStaking, data: I.rewardStaking.encodeFunctionData("unstake", [RWD_UNSTAKE]), gas: G(220000) }; } },

    // ===== auctions (English one-bid lifecycle + Dutch) =====
    auctionMint:   { build: (c, f) => { const id = c.aucSeq++; const r = { to: A.auctionNft, data: I.erc721.encodeFunctionData("mint", [f, id]), gas: G(120000) }; r._apply = () => { (c.aucOwned[f] ||= []).push({ id }); cap(c.aucOwned[f]); }; return r; } },
    createEnglish: { build: (c, f) => { const q = c.aucOwned[f]; if (!q || !q.length) return null; const e = q.shift(); const r = { to: A.auctionHouse, data: I.auctionHouse.encodeFunctionData("createEnglish", [e.id, AUC_RESERVE, G(ENG_DUR)]), gas: G(220000) }; r._apply = () => { c.auctions.push({ kind: "eng", id: e.id, seller: f, ts: Date.now(), bidBuilt: false, settleBuilt: false }); }; return r; } },
    bidEnglish:    { build: (c, f) => { for (const a of c.auctions) { if (a.kind === "eng" && !a.bidBuilt && a.seller !== f && ago(a.ts) > 3000 && ago(a.ts) < 110000) { a.bidBuilt = true; return { to: A.auctionHouse, data: I.auctionHouse.encodeFunctionData("bidEnglish", [a.id]), value: AUC_RESERVE, gas: G(130000) }; } } return null; } },
    settleEnglish: { build: (c, f) => { for (const a of c.auctions) { if (a.kind === "eng" && !a.settleBuilt && ago(a.ts) > 200000) { a.settleBuilt = true; return { to: A.auctionHouse, data: I.auctionHouse.encodeFunctionData("settleEnglish", [a.id]), gas: G(230000) }; } } return null; } },
    createDutch:   { build: (c, f) => { const q = c.aucOwned[f]; if (!q || !q.length) return null; const e = q.shift(); const r = { to: A.auctionHouse, data: I.auctionHouse.encodeFunctionData("createDutch", [e.id, DUTCH_START, DUTCH_FLOOR, G(DUTCH_DECAY)]), gas: G(220000) }; r._apply = () => { c.auctions.push({ kind: "dutch", id: e.id, seller: f, ts: Date.now(), bidBuilt: false }); }; return r; } },
    buyDutch:      { build: (c, f) => { for (const a of c.auctions) { if (a.kind === "dutch" && !a.bidBuilt && a.seller !== f && ago(a.ts) > 3000) { a.bidBuilt = true; return { to: A.auctionHouse, data: I.auctionHouse.encodeFunctionData("buyDutch", [a.id]), value: DUTCH_START, gas: G(230000) }; } } return null; } },

    // ===== mini governance: propose -> vote -> queue -> execute =====
    govPropose: { build: (c, f) => { const pid = c.govPid++; const r = { to: A.miniGov, data: I.miniGov.encodeFunctionData("propose", [pid, A.govTarget]), gas: G(120000) }; r._apply = () => { c.props.push({ pid, ts: Date.now(), voters: new Set(), confVotes: 0, queueBuilt: false, queued: false, qts: 0, execBuilt: false }); }; return r; } },
    govVote:    { build: (c, f) => { for (const p of c.props) { if (!p.voters.has(f) && ago(p.ts) > 3000 && ago(p.ts) < 30000) { p.voters.add(f); const r = { to: A.miniGov, data: I.miniGov.encodeFunctionData("vote", [p.pid]), gas: G(90000) }; r._apply = () => { p.confVotes++; }; return r; } } return null; } },
    govQueue:   { build: (c, f) => { for (const p of c.props) { if (!p.queueBuilt && p.confVotes >= 1 && ago(p.ts) > (GOV_VOTE + 10) * 1000) { p.queueBuilt = true; const r = { to: A.miniGov, data: I.miniGov.encodeFunctionData("queue", [p.pid]), gas: G(100000) }; r._apply = () => { p.queued = true; p.qts = Date.now(); }; return r; } } return null; } },
    govExecute: { build: (c, f) => { for (const p of c.props) { if (p.queued && !p.execBuilt && ago(p.qts) > (GOV_TL + 10) * 1000) { p.execBuilt = true; return { to: A.miniGov, data: I.miniGov.encodeFunctionData("execute", [p.pid]), gas: G(140000) }; } } return null; } },

    // ===== deep cross-contract chain + safe reentrant callback =====
    deepChainRun: { build: (c, f) => ({ to: A.hopA, data: I.hopA.encodeFunctionData("run", []), gas: G(220000) }) },
    deepCallback: { build: (c, f) => ({ to: A.hopA, data: I.hopA.encodeFunctionData("runWithCallback", []), gas: G(130000) }) },

    // ===== disperse (one tx, many recipients) + events-heavy =====
    disperseMany: { build: (c, f) => { const n = 4 + ((Math.random() * 5) | 0); const to = [], amt = []; let sum = 0n; for (let i = 0; i < n; i++) { to.push(others(f)); amt.push(1n); sum += 1n; } return { to: A.disperse, data: I.disperse.encodeFunctionData("disperseNative", [to, amt]), value: sum, gas: G(60000 + 40000 * n) }; } },
    eventsBurst:  { build: (c, f) => { const n = 8 + ((Math.random() * 24) | 0); return { to: A.eventsHeavy, data: I.eventsHeavy.encodeFunctionData("emitMany", [G(n)]), gas: G(40000 + 6000 * n) }; } },

    // ===== batched multicall + SSTORE/compute =====
    batchMulticall: { build: (c, f) => { const n = 2 + ((Math.random() * 7) | 0); return { to: A.batch, data: I.batch.encodeFunctionData("pingMany", [A.pinger, G(n)]), gas: G(90000 + 45000 * n) }; } },
    workbenchSet:   { build: (c, f) => ({ to: A.workbench, data: I.workbench.encodeFunctionData("set", [G((Math.random() * 1e9) | 0), G((Math.random() * 1e9) | 0)]), gas: G(55000) }) },
    workbenchLoop:  { build: (c, f) => ({ to: A.workbench, data: I.workbench.encodeFunctionData("loop", [50n]), gas: G(450000) }) },

    // ===== signature flows (ecrecover / EIP-712), signed SYNCHRONOUSLY via SigningKey =====
    // EIP-2612 permit: owner signs off-chain -> permit() sets allowance -> a DIFFERENT wallet
    // (the spender) later does transferFrom (delegated approval). MAX_INFLIGHT=1 serializes an
    // owner's permits, so the permit nonce never races.
    permit: { build: (c, f) => {
        // serialize permits per owner across the FULL build->resolve cycle (nonces[owner] is a
        // strict on-chain counter); take the nonce OPTIMISTICALLY (like the account nonce) and
        // re-sync from chain on any failure.
        if (c.permitInFlight[f]) return null;
        const spender = others(f);
        const nonce = c.permitNonce[f] ?? 0n;
        c.permitNonce[f] = nonce + 1n; c.permitInFlight[f] = true;
        const digest = TypedDataEncoder.hash(c.permitDomain, c.permitTypes, { owner: f, spender, value: PERMIT_VALUE, nonce, deadline: DEADLINE });
        const sg = c.signingKeyOf(f).sign(digest);
        const r = { to: A.permitToken, data: I.permit.encodeFunctionData("permit", [f, spender, PERMIT_VALUE, DEADLINE, sg.v, sg.r, sg.s]), gas: G(110000) };
        r._apply = () => { (c.permitsBySpender[spender] ||= []).push({ owner: f, remaining: PERMIT_VALUE }); }; // success: allowance set
        r._onResolve = (ok) => { c.permitInFlight[f] = false; if (!ok) c.resyncPermitNonce?.(f); };             // any: free + heal
        return r;
      } },
    permitTransferFrom: { build: (c, f) => { const q = c.permitsBySpender[f]; if (!q || !q.length) return null; const e = q[0]; if (e.remaining < PERMIT_XFER) { q.shift(); return null; } e.remaining -= PERMIT_XFER; return { to: A.permitToken, data: I.permit.encodeFunctionData("transferFrom", [e.owner, f, PERMIT_XFER]), gas: G(80000) }; } },
    // EIP-712 signed voucher: authorized signer (founder) signs a unique-id voucher -> redeem mints.
    voucherRedeem: { build: (c, f) => {
        const id = c.voucherId++;
        const digest = TypedDataEncoder.hash(c.voucherDomain, c.voucherTypes, { to: f, id, amount: VOUCHER_AMT, deadline: DEADLINE });
        const sg = c.voucherSigningKey.sign(digest);
        return { to: A.voucherMinter, data: I.voucher.encodeFunctionData("redeem", [f, id, VOUCHER_AMT, DEADLINE, sg.v, sg.r, sg.s]), gas: G(120000) };
      } },
  };
}

// Weighted mix. Producers out-weight their consumers so the guards stay fed; pure ops fill in.
const SETS = {
  endurance: {
    nativeTransfer: 10, erc20Mint: 3, erc20Transfer: 7, erc20Approve: 2,
    nftMint: 4, nftTransfer: 3,
    erc1155Mint: 3, erc1155Transfer: 3,
    wrapGMB: 3, unwrapGMB: 2,
    dexSwap: 7, dexAddLiq: 3, dexRemoveLiq: 2, feeSwap: 3, rebaseSwap: 3, rebaseUp: 1,
    nativeSwapIn: 3, nativeSwapOut: 3, nativeAddLiq: 2, nativeRemoveLiq: 1,
    ecoDeposit: 3, ecoWithdraw: 2,
    diamondBump: 3, diamondSet: 2,
    deployChild: 1, callDeployedChild: 2, factoryDeploy: 1, factoryCallChild: 2,
    cloneAndInit: 2, cloneDeterministic: 2, cloneInit: 2, cloneCall: 2,
    mktMint: 4, mktList: 3, mktBuy: 3,
    royaltyMint: 3, royaltyList: 2, royaltyBuy: 2, royaltyCancel: 1,
    batchMint: 3, nftStakeStake: 2, nftStakeUnstake: 2,
    vaultDeposit: 3, vaultMint: 2, vaultWithdraw: 3,
    stakeDeposit: 3, stakeWithdraw: 2, rwdStake: 3, rwdClaim: 2, rwdUnstake: 2,
    auctionMint: 3, createEnglish: 2, bidEnglish: 2, settleEnglish: 2, createDutch: 2, buyDutch: 2,
    govPropose: 2, govVote: 3, govQueue: 1, govExecute: 1,
    deepChainRun: 3, deepCallback: 2,
    disperseMany: 3, eventsBurst: 3,
    batchMulticall: 3, workbenchSet: 3, workbenchLoop: 1,
    permit: 3, permitTransferFrom: 3, voucherRedeem: 3,
  },
};

export function buildWorkloadSet(name, ctx) {
  const d = defs(ctx);
  const weights = SETS[name] || SETS.endurance;
  const items = [];
  for (const [type, weight] of Object.entries(weights)) items.push({ type, weight, build: d[type].build });
  const total = items.reduce((s, x) => s + x.weight, 0);
  return {
    items,
    pick() { let r = Math.random() * total; for (const it of items) { r -= it.weight; if (r <= 0) return it; } return items[0]; },
  };
}
