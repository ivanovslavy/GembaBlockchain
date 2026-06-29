// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "./Common.sol";

interface IEndERC721 {
    function ownerOf(uint256 id) external view returns (address);
    function transferFrom(address from, address to, uint256 id) external;
}

// EnduranceMarket: an NFT marketplace with ESCROW. A seller lists an owned NFT (the NFT is
// pulled into the market = escrow); a buyer pays native GMB and receives the NFT; the seller
// is paid in the same tx. Listings are keyed by tokenId (deterministic — the harness knows
// the id it minted), so the buy op is buildable client-side. CEI + nonReentrant on buy.
//
// Revert-safety (enforced by the workload guards, never by the chain):
//   - list:  seller owns the id (minted earlier, settle-delayed) + has setApprovalForAll(market).
//   - buy:   listing is active (each id is bought at most once, tracked client-side) and
//            msg.value == price.
contract EnduranceMarket is ReentrancyGuard {
    IEndERC721 public immutable nft;

    struct Listing { address seller; uint96 price; bool active; }
    mapping(uint256 => Listing) public listings; // tokenId => listing

    error NotOwner();
    error NotListed();
    error WrongValue();
    error PayFailed();

    event Listed(uint256 indexed id, address indexed seller, uint256 price);
    event Bought(uint256 indexed id, address indexed buyer, address indexed seller, uint256 price);

    constructor(IEndERC721 nft_) { nft = nft_; }

    /// @notice List an owned NFT for sale; the NFT is escrowed in the market.
    function list(uint256 id, uint96 price) external {
        if (nft.ownerOf(id) != msg.sender) revert NotOwner();
        nft.transferFrom(msg.sender, address(this), id); // escrow (requires market approval)
        listings[id] = Listing({ seller: msg.sender, price: price, active: true });
        emit Listed(id, msg.sender, price);
    }

    /// @notice Buy a listed NFT: pay exactly `price`, receive the NFT, seller is paid.
    function buy(uint256 id) external payable nonReentrant {
        Listing memory l = listings[id];
        if (!l.active) revert NotListed();
        if (msg.value != l.price) revert WrongValue();
        listings[id].active = false; // effects before interaction
        nft.transferFrom(address(this), msg.sender, id);
        (bool ok, ) = payable(l.seller).call{value: msg.value}("");
        if (!ok) revert PayFailed();
        emit Bought(id, msg.sender, l.seller, l.price);
    }
}
