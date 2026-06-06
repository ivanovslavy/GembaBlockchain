// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @title HelloGemba
/// @notice Phase 1 smoke-test contract: proves Solidity deploys and executes on
/// GembaBlockchain's EVM (chainId 821206). Not a production contract — the real
/// treasury/governance/app contracts arrive in Phase 3+ (CLAUDE.md §9).
contract HelloGemba {
    string public greeting;
    address public immutable deployer;

    event GreetingChanged(address indexed by, string greeting);

    error NotDeployer();

    constructor(string memory _greeting) {
        greeting = _greeting;
        deployer = msg.sender;
    }

    /// @notice Update the greeting. Restricted to the deployer (the smoke test
    /// shouldn't let arbitrary callers mutate state).
    function setGreeting(string calldata _greeting) external {
        if (msg.sender != deployer) revert NotDeployer();
        greeting = _greeting;
        emit GreetingChanged(msg.sender, _greeting);
    }
}
