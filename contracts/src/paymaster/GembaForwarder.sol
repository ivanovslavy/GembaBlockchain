// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ERC2771Forwarder} from "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";

/// @title GembaForwarder
/// @notice The meta-transaction relay endpoint for sponsored gas (CLAUDE.md §9,
/// "Paymaster"; docs/risks.md ADR-011). It is an EIP-2771 trusted forwarder:
///
///  1. An EMPLOYEE signs a `ForwardRequest` off-chain (EIP-712). They pay nothing
///     and need no GMB.
///  2. The institution's RELAYER submits it via `execute()`, paying the gas from
///     the sponsoring wallet.
///  3. The forwarder verifies the employee's signature and forwards the call to the
///     target, which (being ERC2771Context-aware) sees the EMPLOYEE as `msg.sender`.
///
/// The forwarder cannot move funds beyond the call the employee signed: it only
/// relays signature-verified requests (ADR-011 "Paymaster constraints"). Per
/// ADR-011 the relayer is a per-institution operational dependency, and the
/// employee always retains the direct-submit fallback (sign + send themselves).
///
/// ERC-4337 (account abstraction) is a deliberate later upgrade — meta-tx relay is
/// the faster start (CLAUDE.md §9, Phase 4).
contract GembaForwarder is ERC2771Forwarder {
    constructor() ERC2771Forwarder("GembaForwarder") {}
}
