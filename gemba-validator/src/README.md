# Bundled node source

`src/chain/` is a **snapshot of the GembaBlockchain node source** (`chain/` from the
main repo) so this package builds `gembad` with no external/private dependency.
`install.sh` runs `src/chain/gembad/build-gembad.sh`, which also fetches the pinned,
public `cosmos/evm` at build time and wires in these Gemba modules.

**Maintainers — to refresh after a chain change (run from the main repo root):**
```bash
rm -rf gemba-validator/src/chain
git archive HEAD chain | tar -x -C gemba-validator/src/
# then publish the gemba-validator/ contents to the public validator repo
```
Only git-tracked files are exported, so node data and keys are never bundled.

**Which commit (2026-11-03):** the bundle must build the binary the LIVE chain runs, not HEAD —
a joining validator on different consensus rules drops out on the first divergent transaction.
It is exported from **`85a9adc`** (cosmos/evm v0.7.4 + three tracked patches + valgate fix = the
live testnet binary since block 4 838 522, 2026-11-03): `git archive 85a9adc chain | tar -x -C gemba-validator/src/`.
Until that halt-height upgrade it was `39daa6e`. A validator joining by replaying from genesis needs
BOTH binaries — see `docs/runbooks/pruned-explorer-node-setup.md`.
