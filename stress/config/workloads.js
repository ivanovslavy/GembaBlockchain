// Weighted workload sets. Each item: {type, weight, build(ctx, from) -> {to,data,value,gas}|null}.
// Returning null = skip (engine re-picks). Amounts are tiny vs seeded balances so the
// run never depletes funds. "all" includes adversarial ops; "soak" avoids state bloat.
const G = (n) => BigInt(n); // gas limit helper
const randOf = (a) => a[(Math.random() * a.length) | 0];

function defs(ctx) {
  const I = ctx.iface, A = ctx.addr, pool = ctx.addresses;
  const bigBytes = "0x" + "ab".repeat(50000); // ~50KB calldata

  return {
    nativeTransfer: { gas: G(21000), build: (_, f) => ({ to: randOf(pool), value: 1n, gas: G(21000) }) },
    erc20Mint:      { gas: G(70000), build: (_, f) => ({ to: A.t0, data: I.erc20.encodeFunctionData("mint", [f, 10n ** 24n]), gas: G(70000) }) },
    erc20Transfer:  { gas: G(65000), build: (_, f) => ({ to: randOf([A.t0, A.t1]), data: I.erc20.encodeFunctionData("transfer", [randOf(pool), 1n]), gas: G(65000) }) },
    erc20Approve:   { gas: G(60000), build: (_, f) => ({ to: randOf([A.t0, A.t1]), data: I.erc20.encodeFunctionData("approve", [A.dex, (1n << 255n)]), gas: G(60000) }) },
    erc1155Mint:    { gas: G(70000), build: (_, f) => ({ to: A.erc1155, data: I.erc1155.encodeFunctionData("mint", [f, G(ctx.indexOf(f) ?? 0), 1000000n]), gas: G(70000) }) },
    erc1155Transfer:{ gas: G(70000), build: (_, f) => ({ to: A.erc1155, data: I.erc1155.encodeFunctionData("safeTransferFrom", [f, randOf(pool), G(ctx.indexOf(f) ?? 0), 1n, "0x"]), gas: G(70000) }) },
    erc721Mint:     { gas: G(120000), build: (_, f) => (ctx.nft.count++ < ctx.maxNft ? { to: A.erc721, data: I.erc721.encodeFunctionData("mint", [randOf(pool)]), gas: G(120000) } : null) },
    storageSet:     { gas: G(50000), build: (_, f) => ({ to: A.storage, data: I.storage.encodeFunctionData("set", [BigInt((Math.random() * 1e9) | 0), BigInt((Math.random() * 1e9) | 0)]), gas: G(50000) }) },

    // DEX
    dexSwap:        { gas: G(160000), build: (_, f) => ({ to: A.dex, data: I.dex.encodeFunctionData("swap", [A.t0, A.t1, 1000n, 0n]), gas: G(160000) }) },
    dexAddLiq:      { gas: G(220000), build: (_, f) => { ctx.liqProviders.add(f); return { to: A.dex, data: I.dex.encodeFunctionData("addLiquidity", [A.t0, A.t1, 100000n, 100000n]), gas: G(220000) }; } },
    // only wallets that have added liquidity may remove (else lp underflow → Panic 0x11)
    dexRemoveLiq:   { gas: G(180000), build: (_, f) => ctx.liqProviders.has(f) ? { to: A.dex, data: I.dex.encodeFunctionData("removeLiquidity", [A.t0, A.t1, 1000n]), gas: G(180000) } : null },
    storageLoop:    { gas: G(450000), build: (_, f) => ({ to: A.storage, data: I.storage.encodeFunctionData("loop", [50n]), gas: G(450000) }) },
    deploy:         { gas: G(700000), build: (_, f) => ({ to: undefined, data: ctx.deployBytecode, gas: G(700000) }) },

    // Adversarial
    gasBomb:        { gas: G(5000000), build: (_, f) => ({ to: A.gasbomb, data: I.gasbomb.encodeFunctionData("burn", [2000n]), gas: G(5000000) }) },
    bigCalldata:    { gas: G(2600000), build: (_, f) => ({ to: A.storage, data: I.storage.encodeFunctionData("sink", [bigBytes]), gas: G(2600000) }) }, // ~50KB calldata needs >2.02M (EIP-7623 floor)
    revertOp:       { gas: G(60000), build: (_, f) => ({ to: A.storage, data: I.storage.encodeFunctionData("boom", []), gas: G(60000) }) },
  };
}

const SETS = {
  core: { nativeTransfer: 38, erc20Mint: 8, erc20Transfer: 25, erc20Approve: 5, erc1155Mint: 4, erc1155Transfer: 10, erc721Mint: 5, storageSet: 5 },
  all:  { nativeTransfer: 28, erc20Mint: 6, erc20Transfer: 18, erc20Approve: 5, erc1155Mint: 3, erc1155Transfer: 8, erc721Mint: 6, storageSet: 5,
          dexSwap: 12, dexAddLiq: 4, dexRemoveLiq: 2, storageLoop: 4, deploy: 2, gasBomb: 2, bigCalldata: 2, revertOp: 3 },
  soak: { nativeTransfer: 48, erc20Mint: 4, erc20Transfer: 26, erc1155Mint: 2, erc1155Transfer: 12, dexSwap: 6, storageSet: 2 },
};

export function buildWorkloadSet(name, ctx) {
  const d = defs(ctx);
  const weights = SETS[name] || SETS.all;
  const items = [];
  for (const [type, weight] of Object.entries(weights)) items.push({ type, weight, build: d[type].build });
  const total = items.reduce((s, x) => s + x.weight, 0);
  // weighted picker
  return {
    items,
    pick() {
      let r = Math.random() * total;
      for (const it of items) { r -= it.weight; if (r <= 0) return it; }
      return items[0];
    },
  };
}
