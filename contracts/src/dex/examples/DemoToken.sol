// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title DemoToken
/// @notice A minimal mintable ERC-20 — example "developer token" used to demonstrate
/// GembaSwap liquidity/swaps on the testnet. Not part of the protocol; developers
/// deploy their own tokens. The deployer can mint (testnet convenience only).
contract DemoToken is ERC20 {
    address public immutable deployer;
    error NotDeployer();

    constructor(string memory name_, string memory symbol_, uint256 initialSupply) ERC20(name_, symbol_) {
        deployer = msg.sender;
        if (initialSupply > 0) _mint(msg.sender, initialSupply);
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != deployer) revert NotDeployer();
        _mint(to, amount);
    }
}
