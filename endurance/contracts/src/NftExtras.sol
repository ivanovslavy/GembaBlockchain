// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "./Common.sol";

interface IMintN { function mint(address to, uint256 a) external; }

// ERC721A-style batch mint (mint many NFTs in one tx) — caller-chooses the start id; the
// harness uses unique, non-overlapping ranges so no id ever collides.
contract BatchMintNFT {
    string public name = "Endurance Batch NFT";
    string public symbol = "EBN";
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed op, bool ok);

    function setApprovalForAll(address op, bool ok) external { isApprovedForAll[msg.sender][op] = ok; emit ApprovalForAll(msg.sender, op, ok); }
    function mintBatch(address to, uint256 startId, uint256 count) external {
        require(count > 0 && count <= 20, "count");
        for (uint256 i = 0; i < count; i++) {
            uint256 id = startId + i;
            require(ownerOf[id] == address(0), "exists");
            ownerOf[id] = to; emit Transfer(address(0), to, id);
        }
        balanceOf[to] += count;
    }
    function transferFrom(address from, address to, uint256 id) public {
        require(ownerOf[id] == from, "own");
        require(msg.sender == from || isApprovedForAll[from][msg.sender], "auth");
        ownerOf[id] = to; balanceOf[from]--; balanceOf[to]++; emit Transfer(from, to, id);
    }
}

// Stake an ERC721 to earn an ERC20 over time; unstake returns the NFT + mints accrued reward.
contract NftStaking is ReentrancyGuard {
    BatchMintNFT public immutable nft;
    IMintN public immutable rewardToken;
    uint256 public constant REWARD_PER_SEC = 1e9;

    struct Stake { address owner; uint64 since; }
    mapping(uint256 => Stake) public stakes; // tokenId => stake
    mapping(address => uint256) public stakedCount;

    event NftStaked(address indexed who, uint256 indexed id);
    event NftUnstaked(address indexed who, uint256 indexed id, uint256 reward);

    constructor(BatchMintNFT n, IMintN r) { nft = n; rewardToken = r; }

    function stake(uint256 id) external nonReentrant {
        require(nft.ownerOf(id) == msg.sender, "owner");
        nft.transferFrom(msg.sender, address(this), id); // escrow (requires approval)
        stakes[id] = Stake(msg.sender, uint64(block.timestamp));
        stakedCount[msg.sender] += 1;
        emit NftStaked(msg.sender, id);
    }
    function unstake(uint256 id) external nonReentrant {
        Stake memory s = stakes[id];
        require(s.owner == msg.sender, "not staker");
        uint256 reward = (block.timestamp - s.since) * REWARD_PER_SEC;
        delete stakes[id]; stakedCount[msg.sender] -= 1; // effects
        nft.transferFrom(address(this), msg.sender, id);
        if (reward > 0) rewardToken.mint(msg.sender, reward);
        emit NftUnstaked(msg.sender, id, reward);
    }
}

// ERC721 with EIP-2981 royalties (creator recorded at mint) + a marketplace that pays the
// royalty to the creator on each sale. list / buy / cancel, keyed by tokenId.
contract RoyaltyNFT {
    string public name = "Endurance Royalty NFT";
    string public symbol = "ERN";
    uint96 public constant ROYALTY_BPS = 500; // 5%
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public creatorOf;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed op, bool ok);

    function setApprovalForAll(address op, bool ok) external { isApprovedForAll[msg.sender][op] = ok; emit ApprovalForAll(msg.sender, op, ok); }
    function mint(address to, uint256 id) external { require(ownerOf[id] == address(0), "exists"); ownerOf[id] = to; creatorOf[id] = to; balanceOf[to]++; emit Transfer(address(0), to, id); }
    function transferFrom(address from, address to, uint256 id) public {
        require(ownerOf[id] == from, "own");
        require(msg.sender == from || isApprovedForAll[from][msg.sender], "auth");
        ownerOf[id] = to; balanceOf[from]--; balanceOf[to]++; emit Transfer(from, to, id);
    }
    // EIP-2981
    function royaltyInfo(uint256 id, uint256 salePrice) external view returns (address receiver, uint256 amount) {
        return (creatorOf[id], salePrice * ROYALTY_BPS / 10000);
    }
}

contract RoyaltyMarket is ReentrancyGuard {
    RoyaltyNFT public immutable nft;
    struct Listing { address seller; uint96 price; bool active; }
    mapping(uint256 => Listing) public listings;

    event Listed(uint256 indexed id, address indexed seller, uint96 price);
    event Bought(uint256 indexed id, address indexed buyer, uint96 price, uint256 royalty);
    event Cancelled(uint256 indexed id);

    constructor(RoyaltyNFT n) { nft = n; }

    function list(uint256 id, uint96 price) external {
        require(nft.ownerOf(id) == msg.sender, "owner");
        nft.transferFrom(msg.sender, address(this), id); // escrow
        listings[id] = Listing(msg.sender, price, true);
        emit Listed(id, msg.sender, price);
    }
    function cancel(uint256 id) external nonReentrant {
        Listing memory l = listings[id];
        require(l.active && l.seller == msg.sender, "no listing");
        listings[id].active = false;
        nft.transferFrom(address(this), msg.sender, id);
        emit Cancelled(id);
    }
    function buy(uint256 id) external payable nonReentrant {
        Listing memory l = listings[id];
        require(l.active, "no listing");
        require(msg.value == l.price, "value");
        listings[id].active = false; // effects
        (address creator, uint256 royalty) = nft.royaltyInfo(id, l.price);
        nft.transferFrom(address(this), msg.sender, id);
        if (royalty > 0 && creator != address(0)) { (bool r, ) = payable(creator).call{value: royalty}(""); require(r, "royalty"); }
        (bool ok, ) = payable(l.seller).call{value: msg.value - royalty}(""); require(ok, "pay");
        emit Bought(id, msg.sender, l.price, royalty);
    }
}
