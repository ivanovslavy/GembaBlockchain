// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

// Self-contained, dependency-free test tokens for the 24h endurance run. NOT production
// tokens — open `mint` (no access control), on purpose: the goal is to drive diverse,
// revert-safe EVM work (transfers, mints, approvals, DEX trading, staking). Mirrors the
// proven stress harness token shapes so the workload guards behave identically.

/// @notice Open-mint ERC-20. `mint` callable by anyone so the load generator (and the
/// faucet's IMintableToken seam) can always top a wallet up — swaps/staking never fail
/// for balance.
contract EndERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory n, string memory s) { name = n; symbol = s; }

    function mint(address to, uint256 a) external { totalSupply += a; balanceOf[to] += a; emit Transfer(address(0), to, a); }
    function approve(address sp, uint256 a) external returns (bool) { allowance[msg.sender][sp] = a; emit Approval(msg.sender, sp, a); return true; }
    function transfer(address to, uint256 a) external returns (bool) { _t(msg.sender, to, a); return true; }
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        _t(f, to, a); return true;
    }
    function _t(address f, address to, uint256 a) internal { balanceOf[f] -= a; balanceOf[to] += a; emit Transfer(f, to, a); }
}

/// @notice Caller-chosen-id ERC-721 (so the load generator can mint deterministic ids to
/// itself and transfer / list the ones it owns).
contract EndERC721 {
    string public name;
    string public symbol;
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Approval(address indexed owner, address indexed approved, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed op, bool ok);

    constructor(string memory n, string memory s) { name = n; symbol = s; }

    function mint(address to, uint256 id) external {
        require(ownerOf[id] == address(0), "exists");
        ownerOf[id] = to; balanceOf[to]++; emit Transfer(address(0), to, id);
    }
    function approve(address to, uint256 id) external {
        require(ownerOf[id] == msg.sender || isApprovedForAll[ownerOf[id]][msg.sender], "auth");
        getApproved[id] = to; emit Approval(ownerOf[id], to, id);
    }
    function setApprovalForAll(address op, bool ok) external { isApprovedForAll[msg.sender][op] = ok; emit ApprovalForAll(msg.sender, op, ok); }
    function transferFrom(address from, address to, uint256 id) public {
        require(ownerOf[id] == from, "own");
        require(msg.sender == from || getApproved[id] == msg.sender || isApprovedForAll[from][msg.sender], "auth");
        ownerOf[id] = to; balanceOf[from]--; balanceOf[to]++; delete getApproved[id]; emit Transfer(from, to, id);
    }
    // ERC-721 receiver hook is not invoked (transfers go to EOAs / our market which accepts) — kept minimal.
}

/// @notice Open-mint ERC-1155 (multi-token). Bounded use; ids chosen by the generator.
contract EndERC1155 {
    mapping(uint256 => mapping(address => uint256)) public balanceOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    event TransferSingle(address indexed op, address indexed from, address indexed to, uint256 id, uint256 value);
    event ApprovalForAll(address indexed owner, address indexed op, bool ok);

    function mint(address to, uint256 id, uint256 amt) external { balanceOf[id][to] += amt; emit TransferSingle(msg.sender, address(0), to, id, amt); }
    function setApprovalForAll(address op, bool ok) external { isApprovedForAll[msg.sender][op] = ok; emit ApprovalForAll(msg.sender, op, ok); }
    function safeTransferFrom(address from, address to, uint256 id, uint256 amt, bytes calldata) external {
        require(msg.sender == from || isApprovedForAll[from][msg.sender], "auth");
        balanceOf[id][from] -= amt; balanceOf[id][to] += amt; emit TransferSingle(msg.sender, from, to, id, amt);
    }
}
