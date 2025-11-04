// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {MarketAPI} from "filecoin-solidity-api/contracts/v0.8/MarketAPI.sol";
import {MarketTypes} from "filecoin-solidity-api/contracts/v0.8/types/MarketTypes.sol";
import {CommonTypes} from "filecoin-solidity-api/contracts/v0.8/types/CommonTypes.sol";
import {ChaChing1155} from "./ChaChing1155.sol";

/// @title ChaChingManager
/// @notice Manages epochs, tickers, and contributions for the ChaChing ecosystem.
///         Maps ERC-1155 tokenIds to human-friendly tickers and manages epoch data.
///         Only accounts with CONTROLLER_ROLE may set or update tickers and epochs.
///         Includes Filecoin storage verification for pieceCids.
contract ChaChingManager is AccessControl {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    struct EpochMeta {
        string name; // e.g., "$CHING — AxLabs Team (Epoch 5)"
        string symbol; // e.g., "CHING-AXL"
        string description;
        string image;
        string teamSlug; // optional, mutable display/search field
        string attributesJSON; // arbitrary attributes JSON fragment
    }

    struct Contribution {
        string filecoinPieceCid; // Filecoin piece CID
        string githubId; // GitHub user/organization ID
        uint256 timestamp; // When the contribution was added
        address contributor; // Address that added the contribution
    }

    // tokenId => ticker string
    mapping(uint256 => string) private _tokenIdToTicker;
    // ticker (uppercase) => taken
    mapping(string => bool) private _tickerTaken;
    // ticker (uppercase) => reserved by tokenId (0 = not reserved)
    mapping(string => uint256) private _tickerReservedBy;
    // ticker (uppercase) => last change timestamp
    mapping(string => uint256) private _tickerLastSetAt;

    // Epoch management
    // tokenId => metadata
    mapping(uint256 => EpochMeta) private _epochMeta;
    // tokenId => exists flag
    mapping(uint256 => bool) private _epochExists;
    // tokenId => immutable identifiers
    mapping(uint256 => bytes32) private _epochTeamId;
    mapping(uint256 => bytes32) private _epochEpochId;

    // Contribution management
    // tokenId => array of contributions
    mapping(uint256 => Contribution[]) private _epochContributions;
    // tokenId => contribution count
    mapping(uint256 => uint256) private _contributionCount;

    uint256 public renameCooldown = 7 days; // rate limit between changes per tokenId
    uint256 public renameTimelock = 1 days; // delay before a new ticker becomes active (optional)

    // tokenId => pending ticker change (norm -> activation time)
    struct PendingChange { string ticker; uint256 activateAt; }
    mapping(uint256 => PendingChange) private _pending;

    // ERC1155 contract reference
    ChaChing1155 public chaChing1155;

    event TickerSet(uint256 indexed tokenId, string ticker, address indexed caller);
    event TickerCleared(uint256 indexed tokenId, string oldTicker, address indexed caller);
    event EpochCreated(uint256 indexed tokenId, string name, string symbol);
    event EpochMetadataUpdated(uint256 indexed tokenId);
    event ContributionAdded(uint256 indexed tokenId, uint256 indexed contributionIndex, string filecoinPieceCid, string githubId, address indexed contributor);
    event ChaChing1155Set(address indexed chaChing1155);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONTROLLER_ROLE, admin);
    }

    // ========== TICKER MANAGEMENT ==========

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
        require(_isValidTicker(norm), "ChaChingManager: invalid ticker");
        // rate limiting per tokenId
        PendingChange memory p = _pending[tokenId];
        require(p.activateAt == 0 || block.timestamp >= p.activateAt, "ChaChingManager: change pending");
        string memory current = _tokenIdToTicker[tokenId];
        if (bytes(current).length != 0) {
            string memory currentNorm = _normalize(current);
            if (keccak256(bytes(currentNorm)) == keccak256(bytes(norm))) {
                // Clear any pending change and return
                delete _pending[tokenId];
                return; // no-op
            }
            require(block.timestamp >= _tickerLastSetAt[currentNorm] + renameCooldown, "ChaChingManager: cooldown");
        }
        
        // Release any previous reservation for this token
        if (p.activateAt != 0) {
            string memory oldPendingNorm = p.ticker;
            if (_tickerReservedBy[oldPendingNorm] == tokenId) {
                delete _tickerReservedBy[oldPendingNorm];
            }
        }
        
        // Check if ticker is reserved by this token or not reserved/taken
        uint256 reservedBy = _tickerReservedBy[norm];
        require(reservedBy == 0 || reservedBy == tokenId, "ChaChingManager: ticker reserved by another token");
        require(!_tickerTaken[norm], "ChaChingManager: ticker already taken");

        // Reserve the ticker immediately to prevent race conditions
        _tickerReservedBy[norm] = tokenId;
        
        uint256 activateAt = block.timestamp + renameTimelock;
        _pending[tokenId] = PendingChange({ ticker: norm, activateAt: activateAt });
    }

    /// @notice Finalize a pending ticker change after timelock.
    function finalizeTicker(uint256 tokenId) external onlyRole(CONTROLLER_ROLE) {
        PendingChange memory p = _pending[tokenId];
        require(p.activateAt != 0 && block.timestamp >= p.activateAt, "ChaChingManager: not ready");
        string memory norm = p.ticker;
        
        // Verify this token has reserved the ticker (prevents race condition)
        require(_tickerReservedBy[norm] == tokenId, "ChaChingManager: ticker not reserved by this token");
        
        string memory current = _tokenIdToTicker[tokenId];
        if (bytes(current).length != 0) {
            string memory currentNorm = _normalize(current);
            _tickerTaken[currentNorm] = false;
            emit TickerCleared(tokenId, current, msg.sender);
        }
        
        // Clear reservation and mark as taken
        delete _tickerReservedBy[norm];
        _tokenIdToTicker[tokenId] = norm;
        _tickerTaken[norm] = true;
        _tickerLastSetAt[norm] = block.timestamp;
        delete _pending[tokenId];
        emit TickerSet(tokenId, norm, msg.sender);
    }

    /// @notice Clears the ticker for a tokenId. Intended for migrations.
    function clearTicker(uint256 tokenId) external onlyRole(CONTROLLER_ROLE) {
        string memory current = _tokenIdToTicker[tokenId];
        require(bytes(current).length != 0, "ChaChingManager: none set");
        string memory currentNorm = _normalize(current);
        
        // Clear any pending ticker reservation
        PendingChange memory p = _pending[tokenId];
        if (p.activateAt != 0) {
            string memory pendingNorm = p.ticker;
            if (_tickerReservedBy[pendingNorm] == tokenId) {
                delete _tickerReservedBy[pendingNorm];
            }
            delete _pending[tokenId];
        }
        
        delete _tokenIdToTicker[tokenId];
        _tickerTaken[currentNorm] = false;
        emit TickerCleared(tokenId, current, msg.sender);
    }

    function setRenamePolicy(uint256 cooldownSeconds, uint256 timelockSeconds) external onlyRole(DEFAULT_ADMIN_ROLE) {
        renameCooldown = cooldownSeconds;
        renameTimelock = timelockSeconds;
    }

    /// @notice Set the ChaChing1155 contract address. Must be called by admin.
    /// @dev Note: This contract must have METADATA_ROLE on the ChaChing1155 contract
    ///      to create tokens when epochs are created. Grant this role after setting the address.
    /// @param chaChing1155Address The address of the ChaChing1155 contract
    function setChaChing1155(address chaChing1155Address) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(chaChing1155Address != address(0), "ChaChingManager: invalid address");
        chaChing1155 = ChaChing1155(chaChing1155Address);
        emit ChaChing1155Set(chaChing1155Address);
    }

    // ========== EPOCH MANAGEMENT ==========

    /// @notice Deterministically derive an epoch tokenId from spec inputs.
    /// @dev tokenId = uint256(keccak256(abi.encode(chainId, team_id, epoch_id)))
    function deriveEpochTokenId(
        uint256 chainId,
        bytes32 teamId,
        bytes32 epochId
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(chainId, teamId, epochId)));
    }

    /// @notice Convenience overload using current chain.
    function deriveEpochTokenId(
        bytes32 teamId,
        bytes32 epochId
    ) public view returns (uint256) {
        return deriveEpochTokenId(block.chainid, teamId, epochId);
    }

    /// @notice Derive tokenId from inputs and create the epoch with provided metadata.
    function createEpochDerived(
        bytes32 teamId,
        bytes32 epochId,
        EpochMeta calldata meta
    ) external onlyRole(CONTROLLER_ROLE) returns (uint256 tokenId) {
        tokenId = deriveEpochTokenId(teamId, epochId);
        _createEpoch(tokenId, teamId, epochId, meta);
    }

    /// @notice Creates an epoch tokenId with initial metadata. Name/symbol defined here, not derived from org.
    function createEpoch(
        uint256 tokenId,
        bytes32 teamId,
        bytes32 epochId,
        EpochMeta calldata meta
    ) external onlyRole(CONTROLLER_ROLE) {
        _createEpoch(tokenId, teamId, epochId, meta);
    }

    /// @dev Internal function to create an epoch with validation
    function _createEpoch(
        uint256 tokenId,
        bytes32 teamId,
        bytes32 epochId,
        EpochMeta calldata meta
    ) internal {
        require(!_epochExists[tokenId], "ChaChingManager: epoch exists");
        require(bytes(meta.name).length > 0, "ChaChingManager: name required");
        require(bytes(meta.symbol).length > 0, "ChaChingManager: symbol required");

        _epochMeta[tokenId] = EpochMeta({
            name: meta.name,
            symbol: meta.symbol,
            description: meta.description,
            image: meta.image,
            teamSlug: meta.teamSlug,
            attributesJSON: meta.attributesJSON
        });
        _epochExists[tokenId] = true;
        _epochTeamId[tokenId] = teamId;
        _epochEpochId[tokenId] = epochId;

        // Create token in ChaChing1155 if contract is set
        if (address(chaChing1155) != address(0)) {
            // Convert EpochMeta to TokenMeta (ChaChing1155 doesn't have teamSlug)
            ChaChing1155.TokenMeta memory tokenMeta = ChaChing1155.TokenMeta({
                name: meta.name,
                symbol: meta.symbol,
                description: meta.description,
                image: meta.image,
                attributesJSON: meta.attributesJSON
            });
            // Only create if it doesn't exist yet
            if (!chaChing1155.tokenExists(tokenId)) {
                chaChing1155.createToken(tokenId, tokenMeta);
            }
        }

        emit EpochCreated(tokenId, meta.name, meta.symbol);
    }

    function setEpochMetadata(uint256 tokenId, EpochMeta calldata meta) external onlyRole(CONTROLLER_ROLE) {
        require(_epochExists[tokenId], "ChaChingManager: epoch not found");
        require(bytes(meta.name).length > 0, "ChaChingManager: name required");
        require(bytes(meta.symbol).length > 0, "ChaChingManager: symbol required");
        EpochMeta storage m = _epochMeta[tokenId];
        m.name = meta.name;
        m.symbol = meta.symbol;
        m.description = meta.description;
        m.image = meta.image;
        m.teamSlug = meta.teamSlug;
        m.attributesJSON = meta.attributesJSON;
        emit EpochMetadataUpdated(tokenId);
    }

    function getEpochMetadata(uint256 tokenId) external view returns (EpochMeta memory) {
        require(_epochExists[tokenId], "ChaChingManager: epoch not found");
        return _epochMeta[tokenId];
    }

    function getEpochTeamId(uint256 tokenId) external view returns (bytes32) {
        require(_epochExists[tokenId], "ChaChingManager: epoch not found");
        return _epochTeamId[tokenId];
    }

    function getEpochEpochId(uint256 tokenId) external view returns (bytes32) {
        require(_epochExists[tokenId], "ChaChingManager: epoch not found");
        return _epochEpochId[tokenId];
    }

    function epochExists(uint256 tokenId) external view returns (bool) {
        return _epochExists[tokenId];
    }

    // ========== CONTRIBUTION MANAGEMENT ==========

    /// @notice Add a contribution to an epoch
    /// @param tokenId The epoch token ID
    /// @param filecoinPieceCid The Filecoin piece CID
    /// @param githubId The GitHub user/organization ID
    function addContribution(
        uint256 tokenId,
        string calldata filecoinPieceCid,
        string calldata githubId
    ) external onlyRole(CONTROLLER_ROLE) {
        require(_epochExists[tokenId], "ChaChingManager: epoch not found");
        require(bytes(filecoinPieceCid).length > 0, "ChaChingManager: filecoin piece CID required");
        require(bytes(githubId).length > 0, "ChaChingManager: github ID required");

        Contribution memory newContribution = Contribution({
            filecoinPieceCid: filecoinPieceCid,
            githubId: githubId,
            timestamp: block.timestamp,
            contributor: msg.sender
        });

        _epochContributions[tokenId].push(newContribution);
        _contributionCount[tokenId]++;

        emit ContributionAdded(
            tokenId,
            _contributionCount[tokenId] - 1,
            filecoinPieceCid,
            githubId,
            msg.sender
        );
    }

    /// @notice Get a specific contribution for an epoch
    /// @param tokenId The epoch token ID
    /// @param index The contribution index
    function getContribution(uint256 tokenId, uint256 index) external view returns (Contribution memory) {
        require(_epochExists[tokenId], "ChaChingManager: epoch not found");
        require(index < _epochContributions[tokenId].length, "ChaChingManager: contribution index out of bounds");
        return _epochContributions[tokenId][index];
    }

    /// @notice Get all contributions for an epoch
    /// @param tokenId The epoch token ID
    function getContributions(uint256 tokenId) external view returns (Contribution[] memory) {
        require(_epochExists[tokenId], "ChaChingManager: epoch not found");
        return _epochContributions[tokenId];
    }

    /// @notice Get the number of contributions for an epoch
    /// @param tokenId The epoch token ID
    function getContributionCount(uint256 tokenId) external view returns (uint256) {
        require(_epochExists[tokenId], "ChaChingManager: epoch not found");
        return _contributionCount[tokenId];
    }

    // ========== FILECOIN VERIFICATION ==========

    /// @notice Verify if a pieceCid is stored on Filecoin by checking a specific deal ID
    /// @param pieceCid The Filecoin piece CID to verify
    /// @param dealId The specific deal ID to check
    /// @return true if the pieceCid matches the deal's data commitment, false otherwise
    function isPieceCidStoredInDeal(string calldata pieceCid, uint64 dealId) external view returns (bool) {
        (int256 exitCode, MarketTypes.GetDealDataCommitmentReturn memory dealData) = MarketAPI.getDealDataCommitment(dealId);
        
        if (exitCode != 0) {
            return false; // Deal not found or error
        }
        
        bytes memory pieceCidBytes = bytes(pieceCid);
        return keccak256(dealData.data) == keccak256(pieceCidBytes);
    }

    /// @notice Get deal information for a specific deal ID
    /// @param dealId The deal ID to query
    /// @return provider The storage provider ID
    /// @return client The client address
    /// @return pieceCid The piece CID for this deal
    /// @return isActive Whether the deal is active
    function getDealInfo(uint64 dealId) external view returns (uint64 provider, uint64 client, string memory pieceCid, bool isActive) {
        // Get provider
        (int256 providerExitCode, uint64 dealProvider) = MarketAPI.getDealProvider(dealId);
        provider = providerExitCode == 0 ? dealProvider : 0;
        
        // Get client
        (int256 clientExitCode, uint64 dealClient) = MarketAPI.getDealClient(dealId);
        client = clientExitCode == 0 ? dealClient : 0;
        
        // Get piece CID
        (int256 dataExitCode, MarketTypes.GetDealDataCommitmentReturn memory dealData) = MarketAPI.getDealDataCommitment(dealId);
        pieceCid = dataExitCode == 0 ? string(dealData.data) : "";
        
        // Check if deal is active
        (int256 activationExitCode, MarketTypes.GetDealActivationReturn memory activation) = MarketAPI.getDealActivation(dealId);
        isActive = activationExitCode == 0 && CommonTypes.ChainEpoch.unwrap(activation.activated) > 0;
    }

    /// @notice Add a contribution with Filecoin storage verification
    /// @param tokenId The epoch token ID
    /// @param filecoinPieceCid The Filecoin piece CID
    /// @param githubId The GitHub user/organization ID
    /// @param dealId The deal ID for verification
    function addContributionWithVerification(
        uint256 tokenId,
        string calldata filecoinPieceCid,
        string calldata githubId,
        uint64 dealId
    ) external onlyRole(CONTROLLER_ROLE) {
        require(_epochExists[tokenId], "ChaChingManager: epoch not found");
        require(bytes(filecoinPieceCid).length > 0, "ChaChingManager: filecoin piece CID required");
        require(bytes(githubId).length > 0, "ChaChingManager: github ID required");
        require(dealId > 0, "ChaChingManager: deal ID required for verification");

        // Verify Filecoin storage
        bool isStored = this.isPieceCidStoredInDeal(filecoinPieceCid, dealId);
        require(isStored, "ChaChingManager: pieceCid not verified on Filecoin");

        Contribution memory newContribution = Contribution({
            filecoinPieceCid: filecoinPieceCid,
            githubId: githubId,
            timestamp: block.timestamp,
            contributor: msg.sender
        });

        _epochContributions[tokenId].push(newContribution);
        _contributionCount[tokenId]++;

        emit ContributionAdded(
            tokenId,
            _contributionCount[tokenId] - 1,
            filecoinPieceCid,
            githubId,
            msg.sender
        );
    }

    // ========== INTERNAL HELPERS ==========

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
