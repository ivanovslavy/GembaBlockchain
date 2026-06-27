# GembaBlockchain regenesis contract addresses (2026-06-27, chain gemba-testnet-1 / EVM 821207)

Deployed via CREATE2 (Arachnid factory 0x4e59…, founder deployer) — deterministic across future regeneses.
**These REPLACE the pre-regenesis CREATE addresses — update all dApp configs.**

| Contract | Address |
|---|---|
| GembaTimelock | 0xa75aC1AF72D54e34c5646534F985Be7a172C37C1 |
| GembaVotes | 0x0056ab3c91FF5ba8eCdBA8c7C453fd9F424F7F39 |
| GembaGovernor | 0xCCd9f78047E1BB8Bec419490E80409bfBf3B7b72 |
| EmergencyPause | 0x372462Fc8e28c558E2A1bcE6b9CF56a47c71DeA0 |
| Faucet (reserve) | 0x9406B634Eae1856d13251245d7D472D9b6594F56 |
| FoundationTreasury | 0x353CC67C2000fC9b142C0aa505a2e45DA693CDe0 |
| DAOReserve | 0x68093A1C9682df9D1C59586b2Cfc04ed132e7eE5 |
| ContingencyReserve | 0xCBbf84966335e0846cffB52d8624a9aeF58227b4 |
| GembaDripFaucet | 0x0D16a7a490eB2f4766480424E28EE0187d5c74AB |
| GembaOnRamp | 0xC35E5F9AD571499785060aa63e3Eb492DbB3Fd17 |
| GembaTicketing | 0xDe541f5E11af36cAE643D04F2e49fA54Cf14B6ce |
| GembaPerks | 0x0c4ab65FC5A295995A0ef50714aA4e2f33b6ada6 |
| GembaForwarder | 0x5c7A951ed32c3ce77f4b6e6585018eB5b32C426E |
| WorkplaceCheckIn | 0xbD57C7CD844ad0aC23a4e1D6B9F016E3FE89bE19 |
| AccessControlNFT | 0xE2DCB80ee598Dd0eb0dda8179A51c02b7C266a98 |

Funding: Foundation 15M, DAO 10M, Contingency 10M (all owned by Timelock). Faucet reserve's 30M
stays in the Cosmos faucet module account (feesplit/slash accrual); Cosmos→EVM faucet seam is the
documented follow-up. DripFaucet seeded 10,000 GMB. Guardians: founder/foundation/dao (2-of-3).
