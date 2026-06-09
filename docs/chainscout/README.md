# Chainscout submission (Blockscout explorer directory)

> ✅ **Testnet (821207) MERGED** — [`blockscout/chainscout` #241](https://github.com/blockscout/chainscout/pull/241).
> GembaScan now appears in Blockscout's chain directory. Mainnet (821206) gets its own entry
> once the mainnet explorer is live (`isTestnet: false`).

> **Separate** from [`../chain-registry/`](../chain-registry/). That one
> (`ethereum-lists/chains`) is what gives the network + native-GMB **icon in
> MetaMask / chainlist.org**. **This** one lists **GembaScan** in
> [Chainscout](https://chains.blockscout.com) — Blockscout's directory of public
> explorers (discoverability only; optional). Two different registries, two
> different PRs.

## Payload

[`gemba-821207.json`](./gemba-821207.json) — the entry to merge into Chainscout's
`data/chains.json`, keyed by chainId `821207`. The `logo` is a URL (Chainscout
fetches it; we self-host it at `https://testnet.gembascan.io/brand/…`), not a file
committed to their repo.

## Submitting (PR to `blockscout/chainscout`)

1. Fork `github.com/blockscout/chainscout`.
2. Add the `"821207": { … }` object from `gemba-821207.json` into `data/chains.json`.
3. Open a PR. The Blockscout team reviews + merges; then GembaScan appears in the
   directory. Requirement (met): the explorer runs a current Blockscout with a
   working `/assets/envs.js`.

> Mainnet (chainId 821206) gets its own Chainscout entry once the mainnet explorer
> is live (`isTestnet: false`).
