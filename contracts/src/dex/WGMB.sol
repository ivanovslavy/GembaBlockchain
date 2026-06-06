// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @title WGMB — Wrapped GMB
/// @notice Canonical wrapped native GMB (WETH9-style): deposit native GMB to mint
/// WGMB 1:1, withdraw to burn and get native back. Native GMB is not an ERC-20, so
/// AMMs and other ERC-20 tooling use WGMB. This is **third-party developer
/// infrastructure** — GembaBlockchain itself provides no liquidity and runs no
/// exchange for GMB (CLAUDE.md §2, §8); these contracts only let ecosystem
/// developers build and test their OWN ERC-20 tokens.
contract WGMB {
    string public constant name = "Wrapped GMB";
    string public constant symbol = "WGMB";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    error InsufficientBalance();
    error InsufficientAllowance();
    error NativeSendFailed();

    /// @notice Wrap native GMB sent with the call into WGMB 1:1.
    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Unwrap `wad` WGMB back into native GMB 1:1.
    function withdraw(uint256 wad) external {
        if (balanceOf[msg.sender] < wad) revert InsufficientBalance();
        balanceOf[msg.sender] -= wad;
        (bool ok, ) = payable(msg.sender).call{value: wad}("");
        if (!ok) revert NativeSendFailed();
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() external view returns (uint256) {
        return address(this).balance;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        return transferFrom(msg.sender, to, value);
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        if (balanceOf[from] < value) revert InsufficientBalance();
        if (from != msg.sender) {
            uint256 allowed = allowance[from][msg.sender];
            if (allowed != type(uint256).max) {
                if (allowed < value) revert InsufficientAllowance();
                allowance[from][msg.sender] = allowed - value;
            }
        }
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }

    receive() external payable {
        deposit();
    }
}
