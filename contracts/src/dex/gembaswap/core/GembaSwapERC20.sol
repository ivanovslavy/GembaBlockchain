// SPDX-License-Identifier: GPL-3.0-or-later
//
// Derived from Uniswap V2: contracts/UniswapV2ERC20.sol in https://github.com/Uniswap/v2-core
// Original work Copyright (C) 2020 Uniswap Labs (formerly Uniswap) and the Uniswap V2 authors,
// licensed under the GNU General Public License, version 3 or (at your option) any later version.
// Modified 2026 by GEMBA EOOD for GembaBlockchain:
//   - identifiers renamed UniswapV2* -> GembaSwap* (contracts, interfaces, libraries, revert-string prefixes)
//   - LP token name/symbol changed from 'Uniswap V2'/'UNI-V2' to 'GembaSwap V2'/'GSWAP-V2'
// This file is distributed under GPL-3.0-or-later, NOT the Apache-2.0 licence of the rest of the
// repository. See LICENSE and NOTICE in contracts/src/dex/gembaswap/.
pragma solidity =0.5.16;

import './interfaces/IGembaSwapERC20.sol';
import './libraries/SafeMath.sol';

contract GembaSwapERC20 is IGembaSwapERC20 {
    using SafeMath for uint;

    string public constant name = 'GembaSwap V2';
    string public constant symbol = 'GSWAP-V2';
    uint8 public constant decimals = 18;
    uint  public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    constructor() public {
        uint chainId;
        assembly {
            chainId := chainid
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != uint(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'GembaSwap: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'GembaSwap: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}
