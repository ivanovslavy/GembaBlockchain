// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @title SeamProbe
/// @notice Phase 3 devnet probe for the Cosmos<->EVM seam. It exists only to
/// answer one question before we write the real Faucet: when the `x/feesplit` Go
/// module deposits GMB at the bank layer into this contract's address, does the
/// contract (a) see it as native balance and (b) control it (spend it)? If yes,
/// `feesplit` can deposit straight into the Faucet contract's address.
contract SeamProbe {
    event Received(address indexed from, uint256 amount);
    event Forwarded(address indexed to, uint256 amount);

    /// @notice native GMB balance this contract holds (== its bank balance of agmb).
    function selfBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice spend native GMB the contract holds — proves the contract controls
    /// funds that arrived via a bank-layer deposit (not an EVM transfer).
    function forward(address payable to, uint256 amount) external {
        require(address(this).balance >= amount, "insufficient");
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "send failed");
        emit Forwarded(to, amount);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
