// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title ChaChing1155
/// @notice ERC-1155 implementation for $CHING points. Token IDs represent Epochs,
///         not Orgs directly. Metadata is set at ID creation time and can be updated
///         by METADATA_ROLE. Minting/Burning controlled via MINTER_ROLE/BURNER_ROLE.
contract ChaChing1155 is ERC1155, ERC1155Supply, AccessControl {
    using Strings for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");

    struct EpochMeta {
        string name; // e.g., "$CHING — AxLabs Team (Epoch 5)"
        string symbol; // e.g., "CHING-AXL"
        string description;
        string image;
        string teamSlug; // optional, mutable display/search field
        string attributesJSON; // arbitrary attributes JSON fragment
        bool exists;
    }

    // tokenId => metadata
    mapping(uint256 => EpochMeta) private _epochMeta;

    // tokenId => immutable identifiers
    mapping(uint256 => bytes32) private _epochTeamId;
    mapping(uint256 => bytes32) private _epochEpochId;

    // Base URI used as prefix for on-chain JSON, off-chain servers can override via setURI
    string private _baseUri;

    event EpochCreated(uint256 indexed tokenId, string name, string symbol);
    event EpochMetadataUpdated(uint256 indexed tokenId);

    constructor(string memory baseUri, address admin) ERC1155(baseUri) {
        _baseUri = baseUri;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(METADATA_ROLE, admin);
    }

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
    ) external onlyRole(METADATA_ROLE) returns (uint256 tokenId) {
        tokenId = deriveEpochTokenId(teamId, epochId);
        require(!_epochMeta[tokenId].exists, "ChaChing1155: epoch exists");
        _epochMeta[tokenId] = EpochMeta({
            name: meta.name,
            symbol: meta.symbol,
            description: meta.description,
            image: meta.image,
            teamSlug: meta.teamSlug,
            attributesJSON: meta.attributesJSON,
            exists: true
        });
        _epochTeamId[tokenId] = teamId;
        _epochEpochId[tokenId] = epochId;
        emit EpochCreated(tokenId, meta.name, meta.symbol);
    }

    /// @notice Creates an epoch tokenId with initial metadata. Name/symbol defined here, not derived from org.
    function createEpoch(
        uint256 tokenId,
        bytes32 teamId,
        bytes32 epochId,
        EpochMeta calldata meta
    ) external onlyRole(METADATA_ROLE) {
        require(!_epochMeta[tokenId].exists, "ChaChing1155: epoch exists");
        require(bytes(meta.name).length > 0, "ChaChing1155: name required");
        require(bytes(meta.symbol).length > 0, "ChaChing1155: symbol required");

        _epochMeta[tokenId] = EpochMeta({
            name: meta.name,
            symbol: meta.symbol,
            description: meta.description,
            image: meta.image,
            teamSlug: meta.teamSlug,
            attributesJSON: meta.attributesJSON,
            exists: true
        });
        _epochTeamId[tokenId] = teamId;
        _epochEpochId[tokenId] = epochId;

        emit EpochCreated(tokenId, meta.name, meta.symbol);
    }

    function setEpochMetadata(uint256 tokenId, EpochMeta calldata meta) external onlyRole(METADATA_ROLE) {
        require(_epochMeta[tokenId].exists, "ChaChing1155: epoch not found");
        require(bytes(meta.name).length > 0, "ChaChing1155: name required");
        require(bytes(meta.symbol).length > 0, "ChaChing1155: symbol required");
        EpochMeta storage m = _epochMeta[tokenId];
        m.name = meta.name;
        m.symbol = meta.symbol;
        m.description = meta.description;
        m.image = meta.image;
        m.teamSlug = meta.teamSlug;
        m.attributesJSON = meta.attributesJSON;
        emit EpochMetadataUpdated(tokenId);
    }

    function mint(address to, uint256 id, uint256 amount, bytes calldata data) external onlyRole(MINTER_ROLE) {
        require(_epochMeta[id].exists, "ChaChing1155: epoch not found");
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data)
        external
        onlyRole(MINTER_ROLE)
    {
        for (uint256 i = 0; i < ids.length; i++) {
            require(_epochMeta[ids[i]].exists, "ChaChing1155: epoch not found");
        }
        _mintBatch(to, ids, amounts, data);
    }

    function burn(address from, uint256 id, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, id, amount);
    }

    function burnBatch(address from, uint256[] calldata ids, uint256[] calldata amounts) external onlyRole(BURNER_ROLE) {
        _burnBatch(from, ids, amounts);
    }

    function uri(uint256 id) public view override returns (string memory) {
        if (!_epochMeta[id].exists) {
            return super.uri(id);
        }
        EpochMeta memory m = _epochMeta[id];
        bytes32 teamId = _epochTeamId[id];
        bytes32 epochId = _epochEpochId[id];
        // Build on-chain JSON; wallets vary, dashboard will rely on subgraph mapping
        string memory json = string(
            abi.encodePacked(
                '{',
                '"name":"', m.name, '",',
                '"symbol":"', m.symbol, '",',
                '"description":"', m.description, '",',
                '"image":"', m.image, '",',
                '"attributes":', bytes(m.attributesJSON).length == 0 ? '[]' : m.attributesJSON, ',',
                '"properties":{',
                    '"team_slug":"', m.teamSlug, '",',
                    '"team_id":"', _toHexString(teamId), '",',
                    '"epoch_id":"', _toHexString(epochId), '"',
                '}',
                '}'
            )
        );
        string memory encoded = _base64(bytes(json));
        return string(abi.encodePacked("data:application/json;base64,", encoded));
    }

    function setURI(string memory newuri) external onlyRole(METADATA_ROLE) {
        _baseUri = newuri;
        _setURI(newuri);
    }

    // ----- internal helpers -----
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal override(ERC1155, ERC1155Supply) {
        super._update(from, to, ids, amounts);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Minimal base64 to avoid external libs.
    function _base64(bytes memory data) internal pure returns (string memory) {
        string memory TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 len = data.length;
        if (len == 0) return "";
        uint256 encodedLen = 4 * ((len + 2) / 3);
        bytes memory result = new bytes(encodedLen);
        bytes memory table = bytes(TABLE);
        uint256 i = 0;
        uint256 j = 0;
        while (i < len) {
            uint256 a = uint8(data[i++]);
            uint256 b = i < len ? uint8(data[i++]) : 0;
            uint256 c = i < len ? uint8(data[i++]) : 0;
            uint256 triple = (a << 16) | (b << 8) | c;
            result[j++] = table[(triple >> 18) & 0x3F];
            result[j++] = table[(triple >> 12) & 0x3F];
            result[j++] = table[(triple >> 6) & 0x3F];
            result[j++] = table[triple & 0x3F];
        }
        uint256 mod = len % 3;
        if (mod > 0) {
            result[encodedLen - 1] = '=';
            if (mod == 1) {
                result[encodedLen - 2] = '=';
            }
        }
        return string(result);
    }

    function _toHexString(bytes32 data) internal pure returns (string memory) {
        bytes16 hexSymbols = 0x30313233343536373839616263646566; // 0-9a-f
        bytes memory str = new bytes(2 + 64);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < 32; i++) {
            uint8 b = uint8(data[i]);
            str[2 + i * 2] = bytes1(hexSymbols[b >> 4]);
            str[3 + i * 2] = bytes1(hexSymbols[b & 0x0f]);
        }
        return string(str);
    }
}


