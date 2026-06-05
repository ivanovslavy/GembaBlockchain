# Chain registry submission (MetaMask / chainlist.org icons)

MetaMask and [chainlist.org](https://chainlist.org) read network metadata + icons
from the public **[`ethereum-lists/chains`](https://github.com/ethereum-lists/chains)**
repository — **not** from our explorer. To get the GembaBlockchain network (and its
native GMB icon) to show up with a logo in MetaMask, submit these files there via a PR.

This folder holds the ready-to-submit payloads:

| File here | Goes to (in ethereum-lists/chains) |
|---|---|
| `eip155-821207.json` | `_data/chains/eip155-821207.json` (testnet — **live, submit now**) |
| `eip155-821206.json` | `_data/chains/eip155-821206.json` (mainnet — **submit only after mainnet RPC is live**) |
| `icons/gemba.json` | `_data/icons/gemba.json` (after filling the IPFS CID) |
| `icons/gemba-512.png` | the icon image to pin to IPFS (not committed to ethereum-lists) |

## Steps

1. **Pin the icon to IPFS** to get a CID. Easiest options:
   - [pinata.cloud](https://pinata.cloud) / [web3.storage](https://web3.storage) — upload `icons/gemba-512.png`, copy the CID; **or**
   - your own node: `ipfs add icons/gemba-512.png` → copy the `Qm…`/`bafy…` CID.
2. Put the CID into `icons/gemba.json` → replace `__REPLACE_WITH_PINNED_CID__`
   (keep the `ipfs://` prefix), e.g. `"url": "ipfs://bafkrei…"`.
3. **Fork** `ethereum-lists/chains` to your GitHub account, then:
   ```bash
   git clone git@github.com:<your-user>/chains && cd chains
   cp <repo>/docs/chain-registry/eip155-821207.json _data/chains/
   cp <repo>/docs/chain-registry/icons/gemba.json    _data/icons/
   git checkout -b add-gembablockchain-testnet
   git commit -am "Add GembaBlockchain Testnet (821207) + gemba icon" && git push -u origin HEAD
   gh pr create --repo ethereum-lists/chains --fill   # or open the PR in the GitHub UI
   ```
4. Their CI validates that the **RPC responds with the matching chainId** (ours does:
   `https://testnet.gembascan.io/rpc` → `eth_chainId` = `0xc87d7` = 821207). Once merged,
   chainlist.org shows the network with the icon, and MetaMask picks it up — the icon
   then also represents the **native GMB coin** (MetaMask uses the network icon for the
   native currency).

## Mainnet (821206)

`eip155-821206.json` is a template. **Do not submit it until the mainnet RPC
(`rpc.gembascan.io` or final URL) is live and returns chainId 821206** — ethereum-lists
CI rejects chains whose RPC doesn't answer. Mainnet launch is a hard-gated event
(`CLAUDE.md` §16), so this waits.

## ERC-20 token icons (later)

The above covers the **native** GMB coin. For any future **ERC-20** tokens in the
ecosystem, MetaMask reads icons from a **token list** (Uniswap token-list JSON you host)
or from the token's verified logo. Add those when such tokens exist.
