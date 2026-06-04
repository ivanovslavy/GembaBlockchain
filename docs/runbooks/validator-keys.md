# Runbook — validator key management (tmkms recommended)

A validator has two keys; protect them differently (CLAUDE.md §14, Phase 9).

| Key | File | Risk if leaked | Where it should live |
|---|---|---|---|
| **Consensus key** | `priv_validator_key.json` | **double-sign → slash + tombstone** (§5.6) | a remote signer (**tmkms**) / HSM, never on the validator host |
| **Node key** | `node_key.json` | peer identity spoofing | on the host, lower risk |
| **Operator account** | keyring mnemonic | controls the validator's bonded stake & rewards | hardware wallet / offline; never in `test` keyring |

**Never commit any of these** — `.gitignore` excludes them; `.env`/secret store only.

## tmkms (recommended remote signer)

[tmkms](https://github.com/iqlusioninc/tmkms) holds the consensus key on a separate,
hardened machine and signs blocks for the validator over an authenticated
connection. The validator process never has the consensus private key, and tmkms
enforces **double-sign protection** (it tracks the last signed height/round/step and
refuses to sign conflicting votes — the single most important protection against an
accidental double-sign during failover).

Setup outline:
1. Provision a dedicated, locked-down signer host (no public ports except the
   tmkms↔validator link).
2. Import the consensus key into tmkms (softsign) or, better, a YubiHSM2.
3. Configure tmkms `chain_id = "gemba-1"` and the validator address.
4. On the validator, set `priv_validator_laddr` (config.toml) so it requests
   signatures from tmkms instead of reading `priv_validator_key.json`; remove the
   local key file from the validator host.
5. Run exactly **one** signer per validator (two signers for one validator = a
   double-sign waiting to happen).

## Failover (the double-sign trap)

The classic way validators get slashed is running two instances that both sign.
With tmkms's state file you get protection, but the rule stands: **never run two
signers for the same validator at the same time.** On failover, confirm the old
instance/signer is fully stopped before starting the new one. Keep an encrypted
backup of the consensus key offline for disaster recovery (see `backups.md`), but
restore it to only one signer.
