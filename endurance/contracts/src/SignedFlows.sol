// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

// Signature / gasless flows that exercise ecrecover + EIP-712 typed data:
//   • PermitToken  — EIP-2612: an owner signs a permit off-chain; permit() sets the allowance;
//                    a DIFFERENT participant then does transferFrom (delegated approval).
//   • VoucherMinter— EIP-712 signed mint voucher: an authorized signer signs a voucher off-chain;
//                    anyone redeems it on-chain to mint tokens (typed-data verification).

contract PermitToken {
    string public constant name = "Permit Token";
    string public constant symbol = "PRMT";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)), keccak256(bytes("1")), block.chainid, address(this)
        ));
    }

    function mint(address to, uint256 a) external { totalSupply += a; balanceOf[to] += a; emit Transfer(address(0), to, a); }
    function approve(address sp, uint256 a) external returns (bool) { allowance[msg.sender][sp] = a; emit Approval(msg.sender, sp, a); return true; }
    function transfer(address to, uint256 a) external returns (bool) { _t(msg.sender, to, a); return true; }
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        _t(f, to, a); return true;
    }
    function _t(address f, address to, uint256 a) internal { balanceOf[f] -= a; balanceOf[to] += a; emit Transfer(f, to, a); }

    /// @notice EIP-2612 permit — set allowance from an off-chain signature.
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(block.timestamp <= deadline, "expired");
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address rec = ecrecover(digest, v, r, s);
        require(rec != address(0) && rec == owner, "bad sig");
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }
}

contract VoucherMinter {
    string public constant name = "Voucher Token";
    string public constant symbol = "VCHR";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => bool) public used; // voucher id => redeemed (replay protection)

    address public immutable authorizedSigner;
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant VOUCHER_TYPEHASH = keccak256("Voucher(address to,uint256 id,uint256 amount,uint256 deadline)");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Redeemed(address indexed to, uint256 indexed id, uint256 amount);

    constructor(address signer) {
        require(signer != address(0), "signer");
        authorizedSigner = signer;
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)), keccak256(bytes("1")), block.chainid, address(this)
        ));
    }

    /// @notice Redeem an EIP-712 voucher signed by the authorized signer -> mint to `to`.
    function redeem(address to, uint256 id, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(block.timestamp <= deadline, "expired");
        require(!used[id], "used");
        bytes32 structHash = keccak256(abi.encode(VOUCHER_TYPEHASH, to, id, amount, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address rec = ecrecover(digest, v, r, s);
        require(rec == authorizedSigner, "bad sig");
        used[id] = true; // effects
        totalSupply += amount; balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
        emit Redeemed(to, id, amount);
    }
}
