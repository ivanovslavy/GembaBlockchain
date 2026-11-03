# EVM compatibility — what the gembad EVM actually does (measured 2026-11-03)

Every row below was measured on a throwaway local 4-validator devnet
(`security/devnet/up.sh`, chain-id `gemba-1`, EVM 821206) by
[`security/devnet/evm-compat/prague-suite.sh`](../security/devnet/evm-compat/prague-suite.sh),
once on the **then-live testnet binary** (`39daa6e`, live until block 4 838 522, sha256 `fd9deac7…b3e0`, copied from
node2) and once on the upgrade candidate (`v0.7.4` + the three tracked patches + valgate fix).
Nothing here was probed against the live chain except two read-only calls noted in the text.
Re-run it any time: `RPC=… PK=… PK2=… ./prague-suite.sh` — every line prints the raw value
that decided it.

The EVM is go-ethereum `v1.17.2-cosmos-0` inside cosmos/evm. Its chain config (cosmos/evm
`DefaultChainConfig`, not overridden by our genesis) activates everything up to **Prague at
time 0**; **Osaka is not scheduled** (`OsakaTime = nil`).

| # | feature | live binary `39daa6e` | candidate (v0.7.4 + patches) |
|---|---|---|---|
| T1 | `BLOBBASEFEE` (0x4a) via `eth_call` | ❌ `runtime error: invalid memory address or nil pointer dereference` (node stays up) | ✅ returns 0 |
| T2 | `BLOBBASEFEE` inside a **transaction** | ❌ panics in the EVM; baseapp recovers it, the tx **is included** as a Cosmos-level failure — `code 111222`, `gas_used 0`, **no EVM receipt** (wallets wait forever), nonce consumed | ✅ `status 1`, value 0 stored |
| T3 | Cancun: `TSTORE`/`TLOAD`, `MCOPY`, `BLOBHASH`, `BASEFEE`, `PUSH0` | ✅ all | ✅ all |
| T4 | **EIP-7702** type-4 SetCode tx (sponsored) | ✅ included; authority code = `0xef0100‖delegate` | ✅ same |
| T4 | call / tx to the delegated EOA | ✅ runs the delegate code in the EOA's context (ADDRESS = EOA, writes the EOA's own storage) | ✅ same |
| T4 | clear delegation (authorize `address(0)`) | ✅ code back to `0x`; the EOA transacts normally afterwards | ✅ same |
| T5 | **EIP-2537** BLS12-381 precompiles (G1ADD at 0x0b) | ✅ present | ✅ present |
| T6 | **EIP-2935** history contract `0x0000F908…2935` | ⚠️ **not deployed** (also not on the live testnet — `eth_getCode` = `0x`) | ⚠️ same (genesis matter, not binary) |
| T6 | `BLOCKHASH(n)` for any past block | ⚠️ **returns 0** — cosmos/evm serves historical hashes FROM that contract, so without it every past block hash is zero. Confirmed read-only on the live testnet: `BLOCKHASH(latest−2)` = `0x00…00` | ⚠️ same |
| T7 | **EIP-7623** calldata floor | ✅ active (1000 non-zero bytes to an EOA estimate 61,000 gas, pre-Prague 37,000) | ✅ same |
| T8 | Osaka `CLZ` (0x1e) | — `invalid opcode` (not scheduled, as configured) | — same |
| — | `eth_blobBaseFee` JSON-RPC method | not implemented (`-32601`) | not implemented |
| — | blob (type-3) transactions | not supported by cosmos/evm | not supported |

## BLOBBASEFEE — root cause, fix, and why it needs a coordinated upgrade

**Root cause.** cosmos/evm builds the EVM's `vm.BlockContext` in
`x/vm/keeper/state_transition.go` (`NewEVMWithOverridePrecompiles`) and never sets
`BlobBaseFee`. go-ethereum's `opBlobBaseFee` does
`blobBaseFee, _ := uint256.FromBig(evm.Context.BlobBaseFee)`; `FromBig(nil)` returns a **nil**
`*uint256.Int`, and `Stack.push` dereferences it. Stack (from the devnet):
`core/vm.(*Stack).push ← core/vm.opBlobBaseFee (eips.go:295) ← EVM.Run ← … ← x/vm/keeper.ApplyMessageWithConfig`.
In `eth_call` the gRPC layer recovers the panic and returns it as the error; in `FinalizeBlock`
baseapp's `runTx` recovers it (`panic recovered in runTx`) and records `ErrPanic` (code 111222).
Every node fails it the same way, so the chain never split over it — the defect is that a
legitimate opcode is unusable and a transaction using it vanishes from the wallet's view.

**Upstream.** Not fixed in v0.7.4, v1.0.0-rc2 or `main` (`bd334caa`, 2026-11-02): none sets
`BlobBaseFee` in the block context. Worth reporting upstream.

**Fix** — [`chain/gembad/gembad-blobbasefee.patch`](../chain/gembad/gembad-blobbasefee.patch),
one field: `BlobBaseFee: big.NewInt(0)`. Zero is the honest value for a chain with no blob
market, and it is what `eth_feeHistory` already reports for every block. Applies cleanly to
v0.7.3 and v0.7.4; wired into `build-gembad.sh`.

**Consensus classification: STATE-MACHINE-BREAKING — measured, not assumed.** A transaction
that executes `BLOBBASEFEE` fails (code 111222) on the old binary and succeeds on the new one,
so the results hash and the app hash differ. The rehearsal proved it: with three nodes on the
candidate and one put back on `39daa6e`, a single `BLOBBASEFEE` transaction made the old node
log `wrong Block.Header.AppHash` → `CONSENSUS FAILURE` while the other three carried on.
Therefore it ships **only** through a coordinated `halt-height` upgrade (or at genesis) —
never a rolling or canary swap.

## EIP-2935 / BLOCKHASH — a separate finding, not fixed here

`BLOCKHASH` of any past block returns zero on the live testnet today. cosmos/evm stores block
hashes in the EIP-2935 system contract on every block (`SetHeaderHash`) **only if that
contract exists**, and our genesis has `"preinstalls": []`. Any contract that reads
`blockhash()` (commit-reveal, lotteries, "randomness") gets `0x00…00`. Fixes, Slavy's call:

- **testnet:** a governance `MsgRegisterPreinstalls` for the EIP-2935 preinstall — a
  consensus-relevant governance transaction, deliberately not sent; hashes would start
  accumulating from that block on (history before it stays zero);
- **mainnet:** put the EIP-2935 preinstall (cosmos/evm `DefaultPreinstalls`) in the genesis.

Proven on the devnet: `PREINSTALL_EIP2935=1 security/devnet/up.sh` adds it to the genesis, the
contract then has code at `0x0000F908…2935`, and `BLOCKHASH(latest−2)` equals the hash
`eth_getBlockByNumber` reports for that block (suite T6 PASS).

## Prague / EIP-7702 — bottom line

EIP-7702 works end to end on the binary the testnet runs today and on the candidate:
sponsored SetCode transactions, delegated execution in the EOA's own context and storage,
revocation, and normal use of the EOA afterwards. BLS12-381 precompiles and the EIP-7623
calldata floor are active. Not covered by the suite: authorization edge cases (wrong chain id,
stale nonce, multiple authorizations in one tx), and wallet/tooling support beyond Foundry's
`cast` — those are the next tests worth writing before advertising 7702 to integrators.
