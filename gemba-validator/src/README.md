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
It is exported from **`39daa6e`** (cosmos/evm v0.7.3 + mempool patch = the live testnet binary).
After the halt-height upgrade in `docs/runbooks/validator-binary-refresh-2026-10.md`, re-export it
from **`85a9adc`**: `git archive 85a9adc chain | tar -x -C gemba-validator/src/`.
