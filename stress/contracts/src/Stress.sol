// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

// Minimal, dependency-free contracts for load generation. NOT production tokens —
// open mint, no access control, on purpose: the goal is to drive diverse EVM work
// (transfers, mints, approvals, SSTORE, deploys, AMM swaps, gas bombs, reverts).
// Keyspaces are bounded where possible to limit state growth (75GB disk budget).

contract StressERC20 {
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

contract StressERC721 {
    string public name;
    string public symbol;
    uint256 public nextId = 1;
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Approval(address indexed owner, address indexed approved, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed op, bool ok);

    constructor(string memory n, string memory s) { name = n; symbol = s; }
    function mint(address to) external returns (uint256 id) { id = nextId++; ownerOf[id] = to; balanceOf[to]++; emit Transfer(address(0), to, id); }
    function setApprovalForAll(address op, bool ok) external { isApprovedForAll[msg.sender][op] = ok; emit ApprovalForAll(msg.sender, op, ok); }
    function transferFrom(address from, address to, uint256 id) public {
        require(ownerOf[id] == from, "own");
        require(msg.sender == from || getApproved[id] == msg.sender || isApprovedForAll[from][msg.sender], "auth");
        ownerOf[id] = to; balanceOf[from]--; balanceOf[to]++; delete getApproved[id]; emit Transfer(from, to, id);
    }
}

contract StressERC1155 {
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

// SSTORE / compute / big-calldata / revert targets. Bounded keyspace (mod 1024).
contract Storage {
    mapping(uint256 => uint256) public store;
    uint256 public counter;
    function set(uint256 key, uint256 val) external { store[key % 1024] = val; counter++; }
    function loop(uint256 n) external { uint256 x = counter; for (uint256 i = 0; i < n; i++) x = uint256(keccak256(abi.encode(x, i))); store[x % 1024] = x; counter++; }
    function sink(bytes calldata) external { counter++; }      // big-calldata target
    function boom() external pure { revert("boom"); }          // intentional revert
}

// Consumes ~unbounded gas (capped by the tx gas limit) — block-fill / gas-bomb test.
contract GasBomb {
    uint256 public acc;
    function burn(uint256 rounds) external { uint256 x = acc; for (uint256 i = 0; i < rounds; i++) x = uint256(keccak256(abi.encode(x, i, block.number))); acc = x; }
}

// Fund many wallets in one tx (avoids N sequential funding txs from the funder).
contract Disperse {
    function disperse(address[] calldata to, uint256[] calldata amt) external payable {
        for (uint256 i = 0; i < to.length; i++) { (bool ok, ) = to[i].call{value: amt[i]}(""); require(ok, "send"); }
        uint256 bal = address(this).balance;
        if (bal > 0) { (bool ok, ) = msg.sender.call{value: bal}(""); require(ok, "refund"); }
    }
}

interface IERC20 { function transferFrom(address, address, uint256) external returns (bool); function transfer(address, uint256) external returns (bool); }

// Self-contained constant-product multi-pool AMM (0.3% fee) — swap / add / remove
// liquidity load + slippage reverts. Not production math; sufficient for stress.
contract StressDex {
    struct Pool { uint256 rA; uint256 rB; } // rA=reserve(token0), rB=reserve(token1)
    mapping(bytes32 => Pool) public pools;
    mapping(bytes32 => mapping(address => uint256)) public lp;
    mapping(bytes32 => uint256) public totalLp;

    function _key(address a, address b) internal pure returns (bytes32 k, address t0, address t1) {
        (t0, t1) = a < b ? (a, b) : (b, a); k = keccak256(abi.encodePacked(t0, t1));
    }
    function addLiquidity(address a, address b, uint256 amtA, uint256 amtB) external {
        (bytes32 k, address t0, address t1) = _key(a, b);
        (uint256 a0, uint256 a1) = a == t0 ? (amtA, amtB) : (amtB, amtA);
        IERC20(t0).transferFrom(msg.sender, address(this), a0);
        IERC20(t1).transferFrom(msg.sender, address(this), a1);
        Pool storage p = pools[k];
        uint256 share = totalLp[k] == 0 ? (a0 + a1) : (a0 * totalLp[k] / (p.rA == 0 ? 1 : p.rA));
        p.rA += a0; p.rB += a1; lp[k][msg.sender] += share; totalLp[k] += share;
    }
    function removeLiquidity(address a, address b, uint256 share) external {
        (bytes32 k, address t0, address t1) = _key(a, b);
        Pool storage p = pools[k]; uint256 tl = totalLp[k]; require(tl > 0, "noliq");
        uint256 outA = p.rA * share / tl; uint256 outB = p.rB * share / tl;
        p.rA -= outA; p.rB -= outB; lp[k][msg.sender] -= share; totalLp[k] -= share;
        IERC20(t0).transfer(msg.sender, outA); IERC20(t1).transfer(msg.sender, outB);
    }
    function swap(address tokenIn, address tokenOut, uint256 amtIn, uint256 minOut) external {
        (bytes32 k, address t0, ) = _key(tokenIn, tokenOut);
        Pool storage p = pools[k]; bool inIs0 = tokenIn == t0;
        (uint256 rin, uint256 rout) = inIs0 ? (p.rA, p.rB) : (p.rB, p.rA);
        require(rin > 0 && rout > 0, "noliq");
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amtIn);
        uint256 amtInFee = amtIn * 997 / 1000;
        uint256 out = rout * amtInFee / (rin + amtInFee);
        require(out >= minOut, "slip");
        if (inIs0) { p.rA += amtIn; p.rB -= out; } else { p.rB += amtIn; p.rA -= out; }
        IERC20(tokenOut).transfer(msg.sender, out);
    }
}
