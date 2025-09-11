// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title TickerRegistry
/// @notice Maps ERC-1155 tokenIds to human-friendly tickers (e.g., CHING-AXL-E1),
///         ensuring global uniqueness per chain. Only accounts with CONTROLLER_ROLE
///         may set or update a ticker for a given tokenId.
contract TickerRegistry is AccessControl {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    // tokenId => ticker string
    mapping(uint256 => string) private _tokenIdToTicker;
    // ticker (uppercase) => taken
    mapping(string => bool) private _tickerTaken;
    // ticker (uppercase) => last change timestamp
    mapping(string => uint256) private _tickerLastSetAt;

    uint256 public renameCooldown = 7 days; // rate limit between changes per tokenId
    uint256 public renameTimelock = 1 days; // delay before a new ticker becomes active (optional)

    // tokenId => pending ticker change (norm -> activation time)
    struct PendingChange { string ticker; uint256 activateAt; }
    mapping(uint256 => PendingChange) private _pending;

    event TickerSet(uint256 indexed tokenId, string ticker, address indexed caller);
    event TickerCleared(uint256 indexed tokenId, string oldTicker, address indexed caller);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function getTicker(uint256 tokenId) external view returns (string memory) {
        return _tokenIdToTicker[tokenId];
    }

    function isTickerTaken(string memory ticker) external view returns (bool) {
        return _tickerTaken[_normalize(ticker)];
    }

    function getPending(uint256 tokenId) external view returns (string memory ticker, uint256 activateAt) {
        PendingChange memory p = _pending[tokenId];
        return (p.ticker, p.activateAt);
    }

    /// @notice Sets or updates the ticker for a tokenId. Enforces global uniqueness.
    function setTicker(uint256 tokenId, string calldata ticker) external onlyRole(CONTROLLER_ROLE) {
        string memory norm = _normalize(ticker);
        require(_isValidTicker(norm), "TickerRegistry: invalid ticker");
        // rate limiting per tokenId
        PendingChange memory p = _pending[tokenId];
        require(p.activateAt == 0 || block.timestamp >= p.activateAt, "TickerRegistry: change pending");
        string memory current = _tokenIdToTicker[tokenId];
        if (bytes(current).length != 0) {
            string memory currentNorm = _normalize(current);
            if (keccak256(bytes(currentNorm)) == keccak256(bytes(norm))) {
                return; // no-op
            }
            require(block.timestamp >= _tickerLastSetAt[currentNorm] + renameCooldown, "TickerRegistry: cooldown");
        }
        require(!_tickerTaken[norm], "TickerRegistry: ticker already taken");

        uint256 activateAt = block.timestamp + renameTimelock;
        _pending[tokenId] = PendingChange({ ticker: norm, activateAt: activateAt });
    }

    /// @notice Finalize a pending ticker change after timelock.
    function finalizeTicker(uint256 tokenId) external onlyRole(CONTROLLER_ROLE) {
        PendingChange memory p = _pending[tokenId];
        require(p.activateAt != 0 && block.timestamp >= p.activateAt, "TickerRegistry: not ready");
        string memory current = _tokenIdToTicker[tokenId];
        if (bytes(current).length != 0) {
            string memory currentNorm = _normalize(current);
            _tickerTaken[currentNorm] = false;
            emit TickerCleared(tokenId, current, msg.sender);
        }
        string memory norm = p.ticker;
        require(!_tickerTaken[norm], "TickerRegistry: ticker taken");
        _tokenIdToTicker[tokenId] = norm;
        _tickerTaken[norm] = true;
        _tickerLastSetAt[norm] = block.timestamp;
        delete _pending[tokenId];
        emit TickerSet(tokenId, norm, msg.sender);
    }

    /// @notice Clears the ticker for a tokenId. Intended for migrations.
    function clearTicker(uint256 tokenId) external onlyRole(CONTROLLER_ROLE) {
        string memory current = _tokenIdToTicker[tokenId];
        require(bytes(current).length != 0, "TickerRegistry: none set");
        string memory currentNorm = _normalize(current);
        delete _tokenIdToTicker[tokenId];
        _tickerTaken[currentNorm] = false;
        emit TickerCleared(tokenId, current, msg.sender);
    }

    function setRenamePolicy(uint256 cooldownSeconds, uint256 timelockSeconds) external onlyRole(DEFAULT_ADMIN_ROLE) {
        renameCooldown = cooldownSeconds;
        renameTimelock = timelockSeconds;
    }

    function _normalize(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 97 && c <= 122) {
                b[i] = bytes1(c - 32); // to upper
            }
        }
        return string(b);
    }

    function _isValidTicker(string memory s) internal pure returns (bool) {
        bytes memory b = bytes(s);
        if (b.length < 3 || b.length > 16) return false; // allow up to 16 incl. epoch suffix
        uint8 c0 = uint8(b[0]);
        if (!(c0 >= 65 && c0 <= 90)) return false; // must start with letter
        for (uint256 i = 1; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            bool isLetter = (c >= 65 && c <= 90);
            bool isDigit = (c >= 48 && c <= 57);
            bool isDash = (c == 45);
            if (!(isLetter || isDigit || isDash)) return false;
        }
        return true;
    }
}


