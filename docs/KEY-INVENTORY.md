# GembaBlockchain — key inventory (WHERE every key lives)

> **Locations only — NO secret values here.** All actual private keys/mnemonics live in
> **gitignored** files (the repo is public). This doc answers "where is key X" so nobody
> has to re-discover it. Post-regenesis 2026-06-27.

## Validator keys
### Consensus / vote keys (`priv_validator_key.json` — these SIGN blocks)
| Validator | Lives on box | Path | Consensus pubkey |
|---|---|---|---|
| val0 (rpc1) | 13.140.139.82 | `/root/.gembad/config/priv_validator_key.json` | `ykx8dLaSQvvs52Ik3AbwgGHjAYtZ1Rn60PJUx4udKiQ=` |
| val1 (rpc2) | 13.140.139.83 | `/root/.gembad/config/priv_validator_key.json` | `6IL/blncaykWL4JI09khpJ/fAq6GunBBRQBChLgjUg8=` |
| val2 (rpc3) | 13.140.139.84 | `/root/.gembad/config/priv_validator_key.json` | `hhk3PonUtHTiOhu3NkPZstDuyIVt3wxpt2PyJpNjXec=` |
| val3 | jellyfin (192.168.100.100) | `/home/slavy/.gembad-testnet-node2/config/priv_validator_key.json` | `H83xdDuW8zNQSKcfrycuaKAvHpbQdgDgN3DQ9x9Zj4g=` |

**Backups of the consensus + node keys:** `wallet-backup/tmp-regenesis/node0…node3/config/{priv_validator_key.json,node_key.json}` (on this dev machine, gitignored). `val0.info…val3.info` are the keyring exports.

### Operator keys (val0–val3 EOA — sign staking/unjail/compound txs)
In **`wallet-backup/PRIVATE-KEYS.md`** (gitignored) + imported into each box's keyring as `valop-operator` (Contabo) / `val3op` (jellyfin, keyring at `/home/slavy/.gembad-testnet-node2`).
| Key | EVM addr | cosmos (valoper operator) |
|---|---|---|
| val0 | 0xE685734337FD4Dd6d0AcFA778e62EcF3C36efb4b | cosmos1u6zhxs… |
| val1 | 0x2D15EfA53C6B4B833DE158E88bb0c825C190219A | cosmos19527lf… |
| val2 | 0x6748152eB8292003A468C7543bFFB8bC5c62718C | cosmos1vayp2t… |
| val3 | 0x7b75ca2344eae5D0317CEB0bB6878Cc4354dBc84 | cosmos10d6u5g… |

## Treasury / reserve / founder keys — all in `wallet-backup/PRIVATE-KEYS.md` (gitignored)
| Key | EVM addr | Role |
|---|---|---|
| founder | 0x5578c75F22dE0bf1caA4BdD46BA28406C696a5dC | deployer of everything, 5M, non-voting. Also at `scratchpad/founder.pk`. |
| faucetreserve | 0x81a82830E7123e33538d41efDF8C4bACeEb8253a | intended → Faucet contract (faucet 30M currently in the Cosmos module, see token doc) |
| foundation | 0xb22e0CBe56B6651Cd55D354Afe73E2Dc818B5041 | funded FoundationTreasury (15M) |
| dao | 0x8453C623091ed59d5abCda21c19BDDf0eEdB6665 | funded DAOReserve (10M) |
| contingency | 0xdf183ec4674b228cafeA536Ad93ee66De7569F47 | funded ContingencyReserve (10M) |
| tnfaucet-v2 | 0x8fE8E51F28da72a3E2AB50B63a3036E9e71C4194 | drip-faucet service key (ROTATED 2026-06-24, pentest P-1). |
| ~~tnfaucet (old)~~ | ~~0x40a0cb1C63e026A81B55EE1308586E21eec1eFa9~~ | **COMPROMISED (pentest P-1) — DO NOT USE.** Was the old EmergencyPause guardian; replaced. |

Other backups in `wallet-backup/`: `gemba-testnet-1-export.json`/`.txt` (full keyring export), `keyring-raw/`, `gembapass-operator.md`.

## dApp backend wallets (each in that dApp's `.env` on the prod server 46.225.1.162, gitignored)
| dApp | Wallet | EVM addr | File / env var |
|---|---|---|---|
| GembaTicket | platform relayer (pays all gas: clones + gasless mints) | 0x8eB8Bf106EbC9834a2586D04F73866C7436Ce298 | `/gembaticket.com/blockchain/.env` + `/gembaticket.com/backend/.env` → `PLATFORM_SIGNER_KEY` |
| GembaTicket | mint signer (off-chain only, no gas) | 0x3418196aBeC513A95dF013751bcE036C7b27fa5a | `…/.env` → `MINT_SIGNER_KEY` |
| GembaPass | operator/issuer (pays issue/revoke gas) | 0xf886770683572DB6EFE69c76b0C865205C81C80e | `/gembapass.com/.env` → `OPERATOR_PRIVATE_KEY` (backup: `wallet-backup/gembapass-operator.md`) |
| GembaWin | deploy/owner = founder (above) | 0x5578…5dC | `…/gembawin/blockchain/.env` → `PRIVATE_KEY` |
| EduChain / Escrow | deploy = founder (client-side dApps, no backend relayer) | 0x5578…5dC | `…/blockchain/.env` → `USER1_PRIVATE_KEY` |

GembaPass per-employee custodial wallets: created+AES-encrypted in its Postgres DB (key `CUSTODY_MASTER_KEY` in `/gembapass.com/.env`), not in any keyfile.
