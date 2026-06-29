// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "./Common.sol";

interface IAucNFT {
    function ownerOf(uint256 id) external view returns (address);
    function transferFrom(address from, address to, uint256 id) external;
}

// English + Dutch auction lifecycles, keyed by tokenId (deterministic so the harness can build
// the bid/buy/settle txs). NFTs are escrowed. Revert-safety is provided by the harness timing
// windows + guards (no competitive bidding war — at most one bid per English auction — and
// Dutch buys pay the start price which always covers the decayed price).
contract AuctionHouse is ReentrancyGuard {
    IAucNFT public immutable nft;

    struct English { address seller; uint96 reserve; uint64 endTime; address highBidder; uint96 highBid; bool settled; bool exists; }
    struct Dutch { address seller; uint96 startPrice; uint96 floorPrice; uint64 startTime; uint64 decayPerSec; bool sold; bool exists; }
    mapping(uint256 => English) public english; // tokenId => auction
    mapping(uint256 => Dutch) public dutch;

    event EnglishCreated(uint256 indexed id, address indexed seller, uint96 reserve, uint64 endTime);
    event EnglishBid(uint256 indexed id, address indexed bidder, uint96 amount);
    event EnglishSettled(uint256 indexed id, address indexed winner, uint96 amount);
    event DutchCreated(uint256 indexed id, address indexed seller, uint96 startPrice);
    event DutchBought(uint256 indexed id, address indexed buyer, uint256 price);

    constructor(IAucNFT n) { nft = n; }

    // ---- English ----
    function createEnglish(uint256 id, uint96 reserve, uint64 duration) external {
        require(!english[id].exists, "exists");
        require(nft.ownerOf(id) == msg.sender, "owner");
        nft.transferFrom(msg.sender, address(this), id); // escrow
        english[id] = English(msg.sender, reserve, uint64(block.timestamp) + duration, address(0), 0, false, true);
        emit EnglishCreated(id, msg.sender, reserve, uint64(block.timestamp) + duration);
    }
    function bidEnglish(uint256 id) external payable nonReentrant {
        English storage a = english[id];
        require(a.exists && !a.settled, "no auction");
        require(block.timestamp < a.endTime, "ended");
        require(msg.value >= a.reserve && msg.value > a.highBid, "low bid");
        address prev = a.highBidder; uint96 prevBid = a.highBid;
        a.highBidder = msg.sender; a.highBid = uint96(msg.value); // effects
        if (prev != address(0)) { (bool ok, ) = payable(prev).call{value: prevBid}(""); require(ok, "refund"); }
        emit EnglishBid(id, msg.sender, uint96(msg.value));
    }
    function settleEnglish(uint256 id) external nonReentrant {
        English storage a = english[id];
        require(a.exists && !a.settled, "no auction");
        require(block.timestamp >= a.endTime, "not ended");
        a.settled = true; // effects
        if (a.highBidder != address(0)) {
            nft.transferFrom(address(this), a.highBidder, id);
            (bool ok, ) = payable(a.seller).call{value: a.highBid}(""); require(ok, "pay");
            emit EnglishSettled(id, a.highBidder, a.highBid);
        } else {
            nft.transferFrom(address(this), a.seller, id); // no bids -> return to seller
            emit EnglishSettled(id, a.seller, 0);
        }
    }

    // ---- Dutch (price decays to a floor, then stays buyable; no expiry) ----
    function createDutch(uint256 id, uint96 startPrice, uint96 floorPrice, uint64 decayPerSec) external {
        require(!dutch[id].exists, "exists");
        require(nft.ownerOf(id) == msg.sender, "owner");
        require(startPrice >= floorPrice, "price");
        nft.transferFrom(msg.sender, address(this), id); // escrow
        dutch[id] = Dutch(msg.sender, startPrice, floorPrice, uint64(block.timestamp), decayPerSec, false, true);
        emit DutchCreated(id, msg.sender, startPrice);
    }
    function currentPrice(uint256 id) public view returns (uint256) {
        Dutch memory d = dutch[id];
        uint256 dropped = uint256(d.decayPerSec) * (block.timestamp - d.startTime);
        uint256 p = uint256(d.startPrice) > dropped ? uint256(d.startPrice) - dropped : 0;
        return p < d.floorPrice ? d.floorPrice : p;
    }
    function buyDutch(uint256 id) external payable nonReentrant {
        Dutch storage d = dutch[id];
        require(d.exists && !d.sold, "no auction");
        uint256 price = currentPrice(id);
        require(msg.value >= price, "underpaid");
        d.sold = true; // effects
        nft.transferFrom(address(this), msg.sender, id);
        if (price > 0) { (bool ok, ) = payable(d.seller).call{value: price}(""); require(ok, "pay"); }
        if (msg.value > price) { (bool ok2, ) = payable(msg.sender).call{value: msg.value - price}(""); require(ok2, "refund"); }
        emit DutchBought(id, msg.sender, price);
    }
}
