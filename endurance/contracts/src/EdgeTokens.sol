// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

// Edge-case ERC-20s, swapped via the router's *SupportingFeeOnTransferTokens path:
//   • FeeOnTransferToken — takes a 1% fee on every transfer (fee accrues to the contract).
//   • RebasingToken      — share-based balances; a positive rebase scales everyone up.
// Both are open-mint. Seeded into their own router pairs at deploy; the run only swaps them
// (fee-supporting path) so reserve/balance drift never causes a revert.

contract FeeOnTransferToken {
    string public constant name = "Fee On Transfer Token";
    string public constant symbol = "FOT";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    uint256 public constant FEE_BPS = 100; // 1%
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 a) external { totalSupply += a; balanceOf[to] += a; emit Transfer(address(0), to, a); }
    function approve(address sp, uint256 a) external returns (bool) { allowance[msg.sender][sp] = a; emit Approval(msg.sender, sp, a); return true; }
    function transfer(address to, uint256 a) external returns (bool) { _t(msg.sender, to, a); return true; }
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        _t(f, to, a); return true;
    }
    function _t(address f, address to, uint256 a) internal {
        uint256 fee = a * FEE_BPS / 10000;
        balanceOf[f] -= a;
        balanceOf[address(this)] += fee;        // fee retained by the token contract
        balanceOf[to] += a - fee;               // recipient gets less (fee-on-transfer)
        emit Transfer(f, to, a - fee);
        if (fee > 0) emit Transfer(f, address(this), fee);
    }
}

contract RebasingToken {
    string public constant name = "Rebasing Token";
    string public constant symbol = "RBT";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;   // total tokens (scaled)
    uint256 public totalShares;   // total internal shares
    mapping(address => uint256) public shares;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Rebased(uint256 addedSupply, uint256 newTotal);

    function _toTokens(uint256 s) internal view returns (uint256) { return totalShares == 0 ? s : s * totalSupply / totalShares; }
    function _toShares(uint256 t) internal view returns (uint256) { return totalSupply == 0 ? t : t * totalShares / totalSupply; }
    function balanceOf(address a) public view returns (uint256) { return _toTokens(shares[a]); }

    function mint(address to, uint256 t) external {
        uint256 s = _toShares(t);
        shares[to] += s; totalShares += s; totalSupply += t;
        emit Transfer(address(0), to, t);
    }
    function approve(address sp, uint256 a) external returns (bool) { allowance[msg.sender][sp] = a; emit Approval(msg.sender, sp, a); return true; }
    function transfer(address to, uint256 t) external returns (bool) { _t(msg.sender, to, t); return true; }
    function transferFrom(address f, address to, uint256 t) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) allowance[f][msg.sender] = al - t;
        _t(f, to, t); return true;
    }
    function _t(address f, address to, uint256 t) internal {
        uint256 s = _toShares(t);
        shares[f] -= s; shares[to] += s;
        emit Transfer(f, to, t);
    }
    /// @notice Positive rebase only (everyone scales up) — never drops the pair balance below
    /// reserves, so swaps stay revert-safe.
    function rebase(uint256 addBps) external {
        uint256 added = totalSupply * addBps / 10000;
        totalSupply += added;
        emit Rebased(added, totalSupply);
    }
}
