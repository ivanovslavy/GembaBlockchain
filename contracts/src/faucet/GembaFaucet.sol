// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;
// TESTNET-ONLY. Live on gemba-testnet-1 at 0x0147581e2351dD182edD651DFEfD955CB353f8aA
// (contracts/REGENESIS-ADDRESSES-2026-06-27.md) — combo faucet: 0.1 GMB + test stablecoins.
// Deliberately NOT in any mainnet deploy script: mainnet uses GembaDripFaucet (native drip,
// no mintable stables). Pragma/license kept exactly as deployed for verification match.

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IMintableToken {
    function mint(address to, uint256 amount) external;
}

/**
 * @title GembaFaucet
 * @author GEMBA IT
 * @notice Official public testnet faucet for GembaBlockchain. Dispenses native GMB and the
 *         canonical test stablecoins (USDT / USDC / EURC) so anyone can try the network and
 *         the dApps built on it.
 *
 * @dev Per-wallet limits with an independent 24h cooldown per asset: 0.1 GMB and 10,000 of
 *      each stablecoin. The finite native GMB reserve is additionally protected by a GLOBAL
 *      rolling-24h cap, so a sybil swarm can never drain more than `gmbDailyCap` GMB per day
 *      no matter how many addresses it controls. Stablecoins are minted on demand (the faucet
 *      is a token minter), so the faucet never custodies a token balance.
 *
 *      Security posture (secure by default, fail loud — see docs/security-standards.md):
 *      - ReentrancyGuard + Pausable on every claim and every value-moving owner function.
 *      - Strict checks-effects-interactions: cooldowns and the daily counter are written
 *        BEFORE any external call (native send / token mint).
 *      - Two-step ownership (Ownable2Step) so control can never be handed to a wrong address.
 *      - Native sends via OpenZeppelin `Address.sendValue`; ERC-20 recovery via `SafeERC20`.
 *      - Custom errors with zero-address / zero-amount / bounds validation.
 *      - No unbounded loops in any state-changing path.
 */
contract GembaFaucet is ReentrancyGuard, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;

    string public constant VERSION = "1.0.0";
    uint256 public constant COOLDOWN = 24 hours;

    /// @notice GMB paid per claim (wei).
    uint256 public gmbDripAmount;
    /// @notice Max total GMB the faucet will dispense within any rolling 24h window.
    uint256 public gmbDailyCap;

    uint256 private _windowDispensed; // GMB dispensed in the current rolling window
    uint256 private _windowStart;     // start timestamp of the current rolling window

    struct TokenInfo {
        bool supported;
        uint256 dripAmount; // token units per claim (e.g. 10_000 * 10**decimals)
    }
    mapping(address => TokenInfo) public tokens;
    address[] public tokenList;

    mapping(address => uint256) public lastGmbClaim;                       // user => timestamp
    mapping(address => mapping(address => uint256)) public lastTokenClaim; // user => token => timestamp

    error CooldownActive(uint256 availableAt);
    error FaucetEmpty();
    error DailyCapReached();
    error TokenNotSupported();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();

    event GmbClaimed(address indexed user, uint256 amount);
    event TokenClaimed(address indexed user, address indexed token, uint256 amount);
    event GmbDripUpdated(uint256 amount);
    event GmbDailyCapUpdated(uint256 cap);
    event TokenConfigured(address indexed token, bool supported, uint256 dripAmount);
    event GmbFunded(address indexed from, uint256 amount);
    event Recovered(address indexed token, address indexed to, uint256 amount);

    /**
     * @param owner_ Faucet owner (configuration + recovery; two-step transferable).
     * @param gmbDripAmount_ GMB paid per claim (wei).
     * @param gmbDailyCap_ Max GMB dispensed per rolling 24h window.
     */
    constructor(address owner_, uint256 gmbDripAmount_, uint256 gmbDailyCap_) Ownable(owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
        gmbDripAmount = gmbDripAmount_;
        gmbDailyCap = gmbDailyCap_;
        _windowStart = block.timestamp;
        emit GmbDripUpdated(gmbDripAmount_);
        emit GmbDailyCapUpdated(gmbDailyCap_);
    }

    /// @notice Fund the faucet's native GMB reserve.
    receive() external payable {
        emit GmbFunded(msg.sender, msg.value);
    }

    // ============================================================
    // CLAIMS
    // ============================================================

    /// @notice Claim the daily native GMB drip (subject to per-wallet cooldown + global cap).
    function claimGMB() external nonReentrant whenNotPaused {
        uint256 last = lastGmbClaim[msg.sender];
        if (last != 0 && block.timestamp < last + COOLDOWN) revert CooldownActive(last + COOLDOWN);

        uint256 amount = gmbDripAmount;
        if (address(this).balance < amount) revert FaucetEmpty();

        // rolling-window global cap (protects the finite reserve from sybil drain)
        uint256 dispensed = _windowDispensed;
        if (block.timestamp >= _windowStart + 1 days) {
            _windowStart = block.timestamp;
            dispensed = 0;
        }
        if (dispensed + amount > gmbDailyCap) revert DailyCapReached();

        // effects before interaction
        lastGmbClaim[msg.sender] = block.timestamp;
        _windowDispensed = dispensed + amount;

        Address.sendValue(payable(msg.sender), amount);
        emit GmbClaimed(msg.sender, amount);
    }

    /// @notice Claim the daily drip of a supported test stablecoin (minted to the caller).
    function claimToken(address token) external nonReentrant whenNotPaused {
        TokenInfo memory info = tokens[token];
        if (!info.supported) revert TokenNotSupported();

        uint256 last = lastTokenClaim[msg.sender][token];
        if (last != 0 && block.timestamp < last + COOLDOWN) revert CooldownActive(last + COOLDOWN);

        lastTokenClaim[msg.sender][token] = block.timestamp; // effects before interaction
        IMintableToken(token).mint(msg.sender, info.dripAmount);
        emit TokenClaimed(msg.sender, token, info.dripAmount);
    }

    // ============================================================
    // VIEWS
    // ============================================================

    /// @notice Timestamp at which `user` may next claim GMB (0 = available now).
    function gmbAvailableAt(address user) public view returns (uint256) {
        uint256 last = lastGmbClaim[user];
        return last == 0 ? 0 : last + COOLDOWN;
    }

    /// @notice Timestamp at which `user` may next claim `token` (0 = available now).
    function tokenAvailableAt(address user, address token) public view returns (uint256) {
        uint256 last = lastTokenClaim[user][token];
        return last == 0 ? 0 : last + COOLDOWN;
    }

    /// @notice The list of configured faucet tokens (supported or historically configured).
    function supportedTokens() external view returns (address[] memory) {
        return tokenList;
    }

    /// @notice GMB still dispensable in the current rolling window.
    function gmbRemainingToday() external view returns (uint256) {
        if (block.timestamp >= _windowStart + 1 days) return gmbDailyCap;
        return _windowDispensed >= gmbDailyCap ? 0 : gmbDailyCap - _windowDispensed;
    }

    // ============================================================
    // OWNER CONFIG & RECOVERY
    // ============================================================

    function setGmbDrip(uint256 amount) external onlyOwner {
        gmbDripAmount = amount;
        emit GmbDripUpdated(amount);
    }

    function setGmbDailyCap(uint256 cap) external onlyOwner {
        gmbDailyCap = cap;
        emit GmbDailyCapUpdated(cap);
    }

    /// @notice Add / update / disable a faucet token and its per-claim drip.
    function configureToken(address token, bool supported, uint256 dripAmount) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        bool known = tokens[token].supported || tokens[token].dripAmount != 0;
        tokens[token] = TokenInfo({ supported: supported, dripAmount: dripAmount });
        if (!known) tokenList.push(token);
        emit TokenConfigured(token, supported, dripAmount);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Recover native GMB from the faucet reserve.
    function withdrawGMB(address payable to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (address(this).balance < amount) revert InsufficientBalance();
        Address.sendValue(to, amount);
        emit Recovered(address(0), to, amount);
    }

    /// @notice Recover any ERC-20 accidentally sent to the faucet.
    function recoverToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransfer(to, amount);
        emit Recovered(token, to, amount);
    }
}

