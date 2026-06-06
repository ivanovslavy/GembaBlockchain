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
