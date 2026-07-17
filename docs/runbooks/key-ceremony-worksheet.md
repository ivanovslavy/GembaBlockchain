# Key ceremony worksheet — gemba-1 mainnet (fill during the ceremony)

> Companion to `mainnet-genesis-ceremony.md` Phase 2 and the two scripts:
> `scripts/key-ceremony.sh` (owner machine) + `scripts/ceremony-validator-box.sh`
> (each validator box). **Only PUBLIC data goes on this sheet.** Mnemonics live
> exclusively inside the gpg-encrypted ceremony backups; deploy-time private keys
> are exported with `unsafe-export-eth-key` at the moment of use and never stored.

## A. Owner-machine keys (`key-ceremony.sh generate` → `ceremony-addresses.env`)

| Key | bech32 (genesis builder) | 0x (EVM deploys) | Used by |
|---|---|---|---|
| founder | ______ | ______ | genesis `FOUNDER_ADDR`; deploys via `FOUNDER_PK` export |
| foundation | ______ | ______ | genesis + `FOUNDATION_PK` funding step |
| dao | ______ | ______ | genesis + `DAO_PK` funding step |
| contingency | ______ | ______ | genesis + `CONTINGENCY_PK` funding step (20M!) |
| publicfaucet | ______ | ______ | genesis 100k seed; funds the drip faucet |
| guardian1 | — | ______ | `GUARDIAN1` (EmergencyPause 2-of-3) |
| guardian2 | — | ______ | `GUARDIAN2` |
| guardian3 | — | ______ | `GUARDIAN3` |
| dispenser-owner | — | ______ | `DISPENSER_OWNER` + GembaPay backend signer (`GEMBA_DISPENSER_OWNER_PK`) — FRESH key, testnet one is NOT reused |
| collector-recipient | — | ______ | `COLLECTOR_RECIPIENT` |

- [ ] `key-ceremony.sh backup` done; sha256 of both offline copies verified: ______
- [ ] `key-ceremony.sh restore-test` output **RESTORE TEST OK** logged

## B. Validator boxes (`ceremony-validator-box.sh prepare` on each)

| Box | Operator address (→ `VAL_ADDRS`) | Seed entry (`node-id@ip:26656` → `SEEDS`) | Encrypted backup off-box? |
|---|---|---|---|
| .82 (gmb1) | ______ | ______ | [ ] |
| .83 (gmb2) | ______ | ______ | [ ] |
| .84 (gmb3) | ______ | ______ | [ ] |
| .208 (A1/NAT, docker — no seed entry: NAT box, outbound peers only) | ______ | — | [ ] |

## C. Derived values (assemble after A + B)

- `VAL_ADDRS="<4 bech32 operator addresses, space-separated>"` → genesis builder
- `SEEDS="<4 seed entries, comma-joined>"` → `gemba-validator/network.mainnet.env`
- **`EXCLUDE_EXTRA`** (comma-joined **0x** list, order per `docs/mainnet-exclusion-list.md`):
  founder, foundation, dao, contingency, publicfaucet, val0, val1, val2, val3,
  GembaPayDispenser, GmbCollector, GembaDripFaucet
  *(the last three are CREATE2 — precompute via `forge script` simulation before the
  governance deploy so they go into the initial exclusion set, not a later proposal)*
- [ ] `GENESIS_SHA256` (from `init-gembad-mainnet.sh collect`): ______

## D. Old-key hygiene (same ceremony day)

- [ ] Existing plaintext `wallet-backup/` gpg-encrypted (or moved off-tree); testnet
      keys marked "rotate before mainnet" retired with the testnet
- [ ] Testnet dispenser owner key stays testnet-only; mainnet backend `.env` gets the
      NEW dispenser-owner key (`unsafe-export-eth-key dispenser-owner`)
- [ ] `scratchpad/founder.pk` (testnet artifact) deleted/retired — the mainnet founder
      key exists only in the ceremony keyring + encrypted backups
