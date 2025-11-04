// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title ChaChing1155
/// @notice ERC-1155 implementation for $CHING points. Token IDs represent arbitrary tokens.
///         Metadata is set at ID creation time and can be updated by METADATA_ROLE. 
///         Minting/Burning controlled via MINTER_ROLE/BURNER_ROLE.
contract ChaChing1155 is ERC1155, ERC1155Supply, AccessControl {
    using Strings for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");

    struct TokenMeta {
        string name;
        string symbol;
        string description;
        string image;
        string attributesJSON; // arbitrary attributes JSON fragment
    }

    // tokenId => metadata
    mapping(uint256 => TokenMeta) private _tokenMeta;
    // tokenId => exists flag
    mapping(uint256 => bool) private _tokenExists;
    // Array of all token IDs (for enumeration)
    uint256[] private _allTokenIds;
    // tokenId => index in _allTokenIds array
    mapping(uint256 => uint256) private _tokenIdIndex;

    // Base URI used as prefix for on-chain JSON, off-chain servers can override via setURI
    string private _baseUri;

    // Contract-level metadata for explorers
    string public name;
    string public symbol;

    event TokenCreated(uint256 indexed tokenId, string name, string symbol, string description, string image);
    event TokenMetadataUpdated(uint256 indexed tokenId);

    constructor(string memory baseUri, address admin, string memory contractName, string memory contractSymbol) ERC1155(baseUri) {
        _baseUri = baseUri;
        name = contractName;
        symbol = contractSymbol;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(METADATA_ROLE, admin);
    }

    /// @notice Creates a token with initial metadata.
    function createToken(
        uint256 tokenId,
        TokenMeta calldata meta
    ) external onlyRole(METADATA_ROLE) {
        _createToken(tokenId, meta);
    }

    /// @dev Internal function to create a token with validation
    function _createToken(
        uint256 tokenId,
        TokenMeta calldata meta
    ) internal {
        require(!_tokenExists[tokenId], "ChaChing1155: token exists");
        require(bytes(meta.name).length > 0, "ChaChing1155: name required");
        require(bytes(meta.symbol).length > 0, "ChaChing1155: symbol required");

        _tokenMeta[tokenId] = TokenMeta({
            name: meta.name,
            symbol: meta.symbol,
            description: meta.description,
            image: meta.image,
            attributesJSON: meta.attributesJSON
        });
        _tokenExists[tokenId] = true;

        // Add to enumeration array
        _tokenIdIndex[tokenId] = _allTokenIds.length;
        _allTokenIds.push(tokenId);

        emit TokenCreated(tokenId, meta.name, meta.symbol, meta.description, meta.image);
    }

    function setTokenMetadata(uint256 tokenId, TokenMeta calldata meta) external onlyRole(METADATA_ROLE) {
        require(_tokenExists[tokenId], "ChaChing1155: token not found");
        require(bytes(meta.name).length > 0, "ChaChing1155: name required");
        require(bytes(meta.symbol).length > 0, "ChaChing1155: symbol required");
        TokenMeta storage m = _tokenMeta[tokenId];
        m.name = meta.name;
        m.symbol = meta.symbol;
        m.description = meta.description;
        m.image = meta.image;
        m.attributesJSON = meta.attributesJSON;
        emit TokenMetadataUpdated(tokenId);
    }

    function getTokenMetadata(uint256 tokenId) external view returns (TokenMeta memory) {
        require(_tokenExists[tokenId], "ChaChing1155: token not found");
        return _tokenMeta[tokenId];
    }

    function tokenExists(uint256 tokenId) external view returns (bool) {
        return _tokenExists[tokenId];
    }

    /// @notice Get the total number of token types that have been created
    /// @dev Useful for explorers to enumerate all tokens
    function totalTokenTypes() external view returns (uint256) {
        return _allTokenIds.length;
    }

    /// @notice Get a token ID by index
    /// @dev Useful for explorers to enumerate all tokens. Index should be < totalTokenTypes()
    /// @param index The index in the enumeration array
    /// @return tokenId The token ID at the given index
    function tokenByIndex(uint256 index) external view returns (uint256) {
        require(index < _allTokenIds.length, "ChaChing1155: index out of bounds");
        return _allTokenIds[index];
    }

    /// @notice Get all token IDs (may be gas-expensive for large arrays)
    /// @dev Useful for explorers to get all token IDs at once
    /// @return tokenIds Array of all token IDs that have been created
    function getAllTokenIds() external view returns (uint256[] memory) {
        return _allTokenIds;
    }

    function mint(address to, uint256 id, uint256 amount, bytes calldata data) external onlyRole(MINTER_ROLE) {
        require(_tokenExists[id], "ChaChing1155: token not found");
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data)
        external
        onlyRole(MINTER_ROLE)
    {
        for (uint256 i = 0; i < ids.length; i++) {
            require(_tokenExists[ids[i]], "ChaChing1155: token not found");
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
        if (!_tokenExists[id]) {
            return super.uri(id);
        }
        TokenMeta memory m = _tokenMeta[id];
        // Build on-chain JSON; wallets vary, dashboard will rely on subgraph mapping
        // Build metadata following ERC1155 Metadata URI JSON Schema
        // https://eips.ethereum.org/EIPS/eip-1155#metadata
        string memory json = string(
            abi.encodePacked(
                '{',
                '"name":"', _escapeJSON(m.name), '",',
                '"description":"', _escapeJSON(m.description), '",',
                '"image":"', _escapeJSON(m.image), '",',
                bytes(m.attributesJSON).length == 0 ? '' : string(abi.encodePacked('"attributes":', m.attributesJSON, ',')),
                '"properties":{',
                '"symbol":"', _escapeJSON(m.symbol), '"',
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

    /// @dev Escapes special characters for JSON string values.
    /// Escapes: " \ / \b \f \n \r \t
    function _escapeJSON(string memory str) internal pure returns (string memory) {
        bytes memory input = bytes(str);
        uint256 len = input.length;
        if (len == 0) return str;

        // Count how many escape sequences we need (worst case: every char needs escaping = 2x size)
        uint256 escapeCount = 0;
        for (uint256 i = 0; i < len; i++) {
            uint8 c = uint8(input[i]);
            if (c == 0x22 || c == 0x5C || c == 0x2F || c == 0x08 || c == 0x0C || c == 0x0A || c == 0x0D || c == 0x09) {
                escapeCount++;
            }
        }

        if (escapeCount == 0) return str; // No escaping needed

        // Allocate new bytes with extra space for escape characters
        bytes memory result = new bytes(len + escapeCount);
        uint256 j = 0;

        for (uint256 i = 0; i < len; i++) {
            uint8 c = uint8(input[i]);
            if (c == 0x22) {
                // " -> \"
                result[j++] = 0x5C; // \
                result[j++] = 0x22; // "
            } else if (c == 0x5C) {
                // \ -> \\
                result[j++] = 0x5C; // \
                result[j++] = 0x5C; // \
            } else if (c == 0x2F) {
                // / -> \/ (optional but safe)
                result[j++] = 0x5C; // \
                result[j++] = 0x2F; // /
            } else if (c == 0x08) {
                // backspace -> \b
                result[j++] = 0x5C; // \
                result[j++] = 0x62; // b
            } else if (c == 0x0C) {
                // form feed -> \f
                result[j++] = 0x5C; // \
                result[j++] = 0x66; // f
            } else if (c == 0x0A) {
                // newline -> \n
                result[j++] = 0x5C; // \
                result[j++] = 0x6E; // n
            } else if (c == 0x0D) {
                // carriage return -> \r
                result[j++] = 0x5C; // \
                result[j++] = 0x72; // r
            } else if (c == 0x09) {
                // tab -> \t
                result[j++] = 0x5C; // \
                result[j++] = 0x74; // t
            } else {
                result[j++] = bytes1(c);
            }
        }

        return string(result);
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


