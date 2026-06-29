// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @title SeamProbe
/// @notice Phase 3 devnet probe for the Cosmos<->EVM seam. It exists only to
/// answer one question before we write the real PublicReserve: when the `x/feesplit` Go
/// module deposits GMB at the bank layer into this contract's address, does the
/// contract (a) see it as native balance and (b) control it (spend it)? If yes,
/// `feesplit` can deposit straight into the PublicReserve contract's address.
contract SeamProbe {
    /// @notice deployer — the only address allowed to spend (forward) probe funds.
    address public immutable owner;

    event Received(address indexed from, uint256 amount);
    event Forwarded(address indexed to, uint256 amount);

    error NotOwner();
    error InsufficientBalance();
    error SendFailed();

    constructor() {
        owner = msg.sender;
    }

    /// @notice native GMB balance this contract holds (== its bank balance of agmb).
    function selfBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice spend native GMB the contract holds — proves the contract controls
    /// funds that arrived via a bank-layer deposit (not an EVM transfer). Restricted
    /// to the owner so a stray caller can't drain the probe.
    function forward(address payable to, uint256 amount) external {
        if (msg.sender != owner) revert NotOwner();
        if (address(this).balance < amount) revert InsufficientBalance();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert SendFailed();
        emit Forwarded(to, amount);
    }

    /// @dev Intentionally open: the whole point of the probe is to detect GMB that
    /// the `x/feesplit` bank module (or anyone) deposits into this address, so the
    /// sender is NOT restricted here. It only emits — no state to corrupt, and only
    /// `owner` can ever move the funds back out (see `forward`).
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
