// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title GembaTicketing
/// @notice Event tickets as ERC-1155 (CLAUDE.md §9, "GembaTicket-style"). A token
/// id is an EVENT; a balance is how many tickets the holder owns. Organizers create
/// events and either issue tickets directly (comp / perks) or sell them for GMB;
/// attendees redeem (check-in) at the gate, burning the ticket. No PII on-chain.
/// Follows docs/security-standards.md (CEI + nonReentrant on the minting/value
/// paths — ERC-1155 mint triggers the recipient acceptance callback, an external
/// call — events on every state change, custom errors, fail loud).
contract GembaTicketing is ERC1155, AccessControl, ReentrancyGuard {
    bytes32 public constant ORGANIZER_ROLE = keccak256("ORGANIZER_ROLE");
    bytes32 public constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE"); // gate scanners

    struct EventInfo {
        uint256 maxSupply;
        uint256 minted;
        uint256 price; // GMB per ticket (native, in agmb); 0 = not for sale
        bool exists;
        bool active;
    }

    mapping(uint256 => EventInfo) public events;
    /// @notice GMB collected from ticket sales, held in the contract.
    uint256 public proceeds;

    event EventCreated(uint256 indexed eventId, uint256 maxSupply, uint256 price);
    event EventActiveSet(uint256 indexed eventId, bool active);
    event TicketIssued(address indexed to, uint256 indexed eventId, uint256 amount, address indexed by);
    event TicketBought(address indexed buyer, uint256 indexed eventId, uint256 amount, uint256 paid);
    event TicketRedeemed(address indexed holder, uint256 indexed eventId, address indexed by);
    event ProceedsWithdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error EventExists();
    error NoSuchEvent();
    error EventInactive();
    error ExceedsSupply();
    error WrongPayment();
    error InsufficientBalance();
    error NativeSendFailed();
    error NotTicketHolder();
    error DirectPaymentNotAllowed();

    constructor(address admin) ERC1155("") {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // --- organizer: create / configure events ---

    function createEvent(uint256 eventId, uint256 maxSupply, uint256 price) external onlyRole(ORGANIZER_ROLE) {
        if (events[eventId].exists) revert EventExists();
        if (maxSupply == 0) revert ZeroAmount();
        events[eventId] = EventInfo({maxSupply: maxSupply, minted: 0, price: price, exists: true, active: true});
        emit EventCreated(eventId, maxSupply, price);
    }

    function setEventActive(uint256 eventId, bool active) external onlyRole(ORGANIZER_ROLE) {
        if (!events[eventId].exists) revert NoSuchEvent();
        events[eventId].active = active;
        emit EventActiveSet(eventId, active);
    }

    /// @notice Direct issue (comp tickets / perks). Organizer only.
    function issue(address to, uint256 eventId, uint256 amount) external onlyRole(ORGANIZER_ROLE) nonReentrant {
        _mintChecked(to, eventId, amount);
        emit TicketIssued(to, eventId, amount, msg.sender);
    }

    // --- attendees: buy with GMB ---

    /// @notice Buy `amount` tickets for event `eventId`, paying exactly price*amount GMB.
    /// @dev CEI: validate, take payment + bump supply (effects), then mint (the
    /// ERC-1155 acceptance check is the external call); `nonReentrant`.
    function buy(uint256 eventId, uint256 amount) external payable nonReentrant {
        EventInfo storage e = events[eventId];
        if (!e.exists) revert NoSuchEvent();
        if (!e.active) revert EventInactive();
        if (amount == 0) revert ZeroAmount();
        uint256 cost = e.price * amount;
        if (msg.value != cost) revert WrongPayment();

        proceeds += cost;
        _mintChecked(msg.sender, eventId, amount);
        emit TicketBought(msg.sender, eventId, amount, cost);
    }

    function _mintChecked(address to, uint256 eventId, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        EventInfo storage e = events[eventId];
        if (!e.exists) revert NoSuchEvent();
        if (e.minted + amount > e.maxSupply) revert ExceedsSupply();
        e.minted += amount; // effect before the mint acceptance-check interaction
        _mint(to, eventId, amount, "");
    }

    // --- redeem (check-in) ---

    /// @notice Attendee self check-in: burns one of their own tickets.
    function redeem(uint256 eventId) external {
        _redeem(msg.sender, eventId, msg.sender);
    }

    /// @notice Gate scanner redeems a holder's ticket at the event.
    function redeemFrom(address holder, uint256 eventId) external onlyRole(REDEEMER_ROLE) {
        _redeem(holder, eventId, msg.sender);
    }

    function _redeem(address holder, uint256 eventId, address by) internal {
        if (balanceOf(holder, eventId) == 0) revert NotTicketHolder();
        _burn(holder, eventId, 1); // burn has no acceptance callback (no external call)
        emit TicketRedeemed(holder, eventId, by);
    }

    // --- admin: withdraw sale proceeds ---

    function withdrawProceeds(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > proceeds) revert InsufficientBalance();
        proceeds -= amount; // effect before interaction
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert NativeSendFailed();
        emit ProceedsWithdrawn(to, amount);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Reject stray native GMB. Tickets are paid for ONLY via `buy()` (which
    /// tracks `proceeds`); any other inbound value would be untracked and stuck, so
    /// we fail loud (docs/security-standards.md) instead of silently accepting it.
    receive() external payable {
        revert DirectPaymentNotAllowed();
    }

    fallback() external payable {
        revert DirectPaymentNotAllowed();
    }
}
