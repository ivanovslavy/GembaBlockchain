// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title DemoFeeToken
/// @notice Example **fee-on-transfer** ERC-20 (takes a fee on every transfer) — used to
/// demonstrate GembaSwapRouter02's `...SupportingFeeOnTransferTokens` path on the testnet.
/// Not part of the protocol.
contract DemoFeeToken is ERC20 {
    uint256 public immutable feeBps;
    address public immutable feeSink;
    address public immutable deployer;
    error NotDeployer();

    constructor(string memory name_, string memory symbol_, uint256 feeBps_, address feeSink_, uint256 initialSupply)
        ERC20(name_, symbol_)
    {
        deployer = msg.sender;
        feeBps = feeBps_;
        feeSink = feeSink_;
        if (initialSupply > 0) _mint(msg.sender, initialSupply);
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != deployer) revert NotDeployer();
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value > 0 && feeBps > 0) {
            uint256 fee = (value * feeBps) / 10_000;
            super._update(from, feeSink, fee);
            super._update(from, to, value - fee);
        } else {
            super._update(from, to, value);
        }
    }
}
