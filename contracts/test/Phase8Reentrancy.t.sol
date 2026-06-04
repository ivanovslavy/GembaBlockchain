// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {GembaTicketing} from "../src/tickets/GembaTicketing.sol";
import {GembaPerks, IGembaTicketing} from "../src/tickets/GembaPerks.sol";

// re-enters buy() from the ERC-1155 acceptance callback (the external call on mint)
contract BuyReentrant is IERC1155Receiver {
    GembaTicketing t;
    uint256 ev;
    uint256 price;
    bool armed;

    constructor(GembaTicketing t_, uint256 ev_, uint256 price_) {
        t = t_;
        ev = ev_;
        price = price_;
    }

    function attack() external payable {
        armed = true;
        t.buy{value: price}(ev, 1);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4) {
        if (armed) {
            armed = false;
            t.buy{value: price}(ev, 1); // blocked by nonReentrant
        }
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }

    receive() external payable {}
}

// malicious distributor that re-enters payBonus() from receive()
contract BonusReentrant {
    GembaPerks p;
    bool armed;

    function setPerks(GembaPerks p_) external {
        p = p_;
    }

    function attack(uint256 amount) external {
        armed = true;
        p.payBonus(address(this), amount);
    }

    receive() external payable {
        if (armed) {
            armed = false;
            p.payBonus(address(this), 1); // blocked by nonReentrant
        }
    }
}

contract Phase8ReentrancyTest is Test {
    function test_TicketingBuyReentrancyBlocked() public {
        GembaTicketing t = new GembaTicketing(address(this));
        t.grantRole(t.ORGANIZER_ROLE(), address(this));
        t.createEvent(1, 100, 1 ether);

        BuyReentrant attacker = new BuyReentrant(t, 1, 1 ether);
        vm.deal(address(attacker), 10 ether);

        vm.expectRevert(); // re-entry repelled -> the whole buy reverts
        attacker.attack{value: 1 ether}();
        assertEq(t.balanceOf(address(attacker), 1), 0);
    }

    function test_PerksPayBonusReentrancyBlocked() public {
        GembaTicketing t = new GembaTicketing(address(this));
        BonusReentrant attacker = new BonusReentrant();
        GembaPerks p = new GembaPerks(address(this), IGembaTicketing(address(t)), 1000 ether);
        attacker.setPerks(p);
        p.grantRole(p.DISTRIBUTOR_ROLE(), address(attacker)); // attacker is the distributor
        vm.deal(address(p), 100 ether);

        vm.expectRevert(); // re-entry repelled
        attacker.attack(5 ether);
        // pool not drained by the re-entrant attempt
        assertEq(address(p).balance, 100 ether);
    }
}
