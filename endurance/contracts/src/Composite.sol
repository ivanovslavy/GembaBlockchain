// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "./Common.sol";

// Deep cross-contract chain A->B->C->D->E in one tx, plus a SAFE reentrant-callback pattern
// (A->B->callback-into-A) where the entrypoint is reentrancy-guarded but the callback handler
// is a separate, safe function. Plus a many-recipient disperse and an events-heavy contract
// (exercises the GembaScan indexer under continuous load).

interface ICallback { function onCallback() external; }

contract HopE { uint256 public c; function step() external { c += 1; } }
contract HopD { HopE public e; uint256 public c; constructor(HopE _e) { e = _e; } function step() external { c += 1; e.step(); } }
contract HopC { HopD public d; uint256 public c; constructor(HopD _d) { d = _d; } function step() external { c += 1; d.step(); } }
contract HopB {
    HopC public c; uint256 public n;
    constructor(HopC _c) { c = _c; }
    function step() external { n += 1; c.step(); }
    function callMeBack(address a) external { n += 1; ICallback(a).onCallback(); }
}

contract HopA is ReentrancyGuard {
    HopB public b; uint256 public runs; uint256 public callbacks;
    constructor(HopB _b) { b = _b; }
    /// @notice A->B->C->D->E (5 hops) in one tx.
    function run() external nonReentrant { runs += 1; b.step(); }
    /// @notice A->B->callback-into-A. Entrypoint is reentrancy-guarded; the callback handler is
    /// a separate, intentionally-unguarded function, so the legitimate callback succeeds while a
    /// re-entry into `run`/`runWithCallback` would revert.
    function runWithCallback() external nonReentrant { runs += 1; b.callMeBack(address(this)); }
    function onCallback() external { callbacks += 1; }
}

// One tx paying many recipients (multi-transfer, state-heavy).
contract Disperse is ReentrancyGuard {
    event Dispersed(address indexed by, uint256 count, uint256 total);
    function disperseNative(address[] calldata to, uint256[] calldata amt) external payable nonReentrant {
        require(to.length == amt.length, "len");
        uint256 spent;
        for (uint256 i = 0; i < to.length; i++) {
            (bool ok, ) = payable(to[i]).call{value: amt[i]}(""); require(ok, "send");
            spent += amt[i];
        }
        if (msg.value > spent) { (bool ok, ) = payable(msg.sender).call{value: msg.value - spent}(""); require(ok, "refund"); }
        emit Dispersed(msg.sender, to.length, spent);
    }
}

// Emits many indexed events per tx — drives the explorer / indexer under continuous load.
contract EventsHeavy {
    uint256 public total;
    event Activity(address indexed who, uint256 indexed seq, uint256 indexed kind, uint256 value, bytes32 tag);
    function emitMany(uint256 n) external {
        require(n > 0 && n <= 64, "n");
        for (uint256 i = 0; i < n; i++) {
            emit Activity(msg.sender, i, i % 5, block.timestamp + i, keccak256(abi.encode(msg.sender, i)));
        }
        total += n;
    }
}
