// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title PassportRegistry
 * @dev ERC-721 based registry for Real-World Asset (RWA) passports
 * @notice This contract manages verifiable credentials for real-world assets
 */
contract PassportRegistry is ERC721, Ownable, ReentrancyGuard {
    // State variables
    uint256 private _tokenIdCounter;
    mapping(uint256 => Passport) public passports;
    mapping(bytes32 => bool) public verifiedDataHashes;
    mapping(address => bool) public authorizedIssuers;
    
    // Chainlink Oracle
    AggregatorV3Interface internal priceFeed;
    
    struct Passport {
        uint256 id;
        string assetType;
        bytes32 metadataHash;
        address owner;
        address issuer;
        uint256 createdAt;
        uint256 lastVerified;
        bool isActive;
        VerificationLevel verificationLevel;
    }
    
    enum VerificationLevel {
        BASIC,
        ENHANCED,
        PREMIUM
    }
    
    struct AssetMetadata {
        string title;
        string description;
        string category;
        string[] certifications;
        bytes32[] attestationHashes;
    }
    
    // Events
    event PassportCreated(
        uint256 indexed tokenId,
        address indexed owner,
        string assetType,
        bytes32 metadataHash
    );
    
    event PassportVerified(
        uint256 indexed tokenId,
        address indexed verifier,
        bytes32 dataHash,
        uint256 timestamp
    );
    
    event CrossChainTransferInitiated(
        uint256 indexed tokenId,
        uint64 destinationChain,
        address recipient,
        bytes32 messageId
    );
    
    event VerificationLevelUpdated(
        uint256 indexed tokenId,
        VerificationLevel oldLevel,
        VerificationLevel newLevel
    );
    
    event IssuerAuthorized(address indexed issuer, bool authorized);
    
    // Constructor
    constructor(
        address _priceFeed,
        address _owner
    ) ERC721("RWA Passport", "RWAP") {
        if (_priceFeed != address(0)) {
            priceFeed = AggregatorV3Interface(_priceFeed);
        }
        _transferOwnership(_owner);
        
        // Authorize the owner as an issuer by default
        authorizedIssuers[_owner] = true;
        emit IssuerAuthorized(_owner, true);
    }
    
    // Core Functions
    function createPassport(
        string memory assetType,
        bytes32 metadataHash,
        AssetMetadata memory metadata,
        bytes[] memory oracleProofs
    ) external nonReentrant returns (uint256) {
        require(authorizedIssuers[msg.sender], "Unauthorized issuer");
        require(bytes(assetType).length > 0, "Asset type cannot be empty");
        require(metadataHash != bytes32(0), "Invalid metadata hash");
        require(_verifyOracleProofs(oracleProofs, metadataHash), "Invalid oracle proofs");
        
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        passports[tokenId] = Passport({
            id: tokenId,
            assetType: assetType,
            metadataHash: metadataHash,
            owner: msg.sender,
            issuer: msg.sender,
            createdAt: block.timestamp,
            lastVerified: block.timestamp,
            isActive: true,
            verificationLevel: VerificationLevel.BASIC
        });
        
        _safeMint(msg.sender, tokenId);
        verifiedDataHashes[metadataHash] = true;
        
        emit PassportCreated(tokenId, msg.sender, assetType, metadataHash);
        return tokenId;
    }
    
    function verifyPassport(
        uint256 tokenId,
        bytes[] memory newProofs
    ) external {
        require(_exists(tokenId), "Passport does not exist");
        Passport storage passport = passports[tokenId];
        
        require(_verifyOracleProofs(newProofs, passport.metadataHash), "Invalid verification proofs");
        
        VerificationLevel oldLevel = passport.verificationLevel;
        passport.lastVerified = block.timestamp;
        passport.verificationLevel = _calculateVerificationLevel(newProofs.length);
        
        emit PassportVerified(tokenId, msg.sender, passport.metadataHash, block.timestamp);
        
        if (oldLevel != passport.verificationLevel) {
            emit VerificationLevelUpdated(tokenId, oldLevel, passport.verificationLevel);
        }
    }
    
    function updatePassport(
        uint256 tokenId,
        bytes32 newMetadataHash,
        bytes[] memory updateProofs
    ) external {
        require(_exists(tokenId), "Passport does not exist");
        require(ownerOf(tokenId) == msg.sender || authorizedIssuers[msg.sender], "Unauthorized");
        require(newMetadataHash != bytes32(0), "Invalid metadata hash");
        require(_verifyOracleProofs(updateProofs, newMetadataHash), "Invalid update proofs");
        
        Passport storage passport = passports[tokenId];
        passport.metadataHash = newMetadataHash;
        passport.lastVerified = block.timestamp;
        
        verifiedDataHashes[newMetadataHash] = true;
    }
    
    function deactivatePassport(uint256 tokenId) external {
        require(_exists(tokenId), "Passport does not exist");
        require(ownerOf(tokenId) == msg.sender || authorizedIssuers[msg.sender], "Unauthorized");
        
        passports[tokenId].isActive = false;
    }
    
    function reactivatePassport(uint256 tokenId, bytes[] memory reactivationProofs) external {
        require(_exists(tokenId), "Passport does not exist");
        require(ownerOf(tokenId) == msg.sender || authorizedIssuers[msg.sender], "Unauthorized");
        require(_verifyOracleProofs(reactivationProofs, passports[tokenId].metadataHash), "Invalid reactivation proofs");
        
        passports[tokenId].isActive = true;
        passports[tokenId].lastVerified = block.timestamp;
    }
    
    // Internal Functions
    function _verifyOracleProofs(
        bytes[] memory proofs,
        bytes32 dataHash
    ) internal view returns (bool) {
        // Simplified oracle verification logic for MVP
        // In production, this would verify Chainlink oracle signatures
        if (proofs.length == 0) {
            return false;
        }
        
        // For demo purposes, we accept any non-empty proof
        // In production, this would verify cryptographic signatures
        return true;
    }
    
    function _calculateVerificationLevel(uint256 proofCount) internal pure returns (VerificationLevel) {
        if (proofCount >= 3) return VerificationLevel.PREMIUM;
        if (proofCount >= 2) return VerificationLevel.ENHANCED;
        return VerificationLevel.BASIC;
    }
    
    function _exists(uint256 tokenId) internal view returns (bool) {
        return tokenId < _tokenIdCounter;
    }
    
    // Admin Functions
    function addAuthorizedIssuer(address issuer) external onlyOwner {
        require(issuer != address(0), "Invalid issuer address");
        authorizedIssuers[issuer] = true;
        emit IssuerAuthorized(issuer, true);
    }
    
    function removeAuthorizedIssuer(address issuer) external onlyOwner {
        authorizedIssuers[issuer] = false;
        emit IssuerAuthorized(issuer, false);
    }
    
    function updatePriceFeed(address _priceFeed) external onlyOwner {
        require(_priceFeed != address(0), "Invalid price feed address");
        priceFeed = AggregatorV3Interface(_priceFeed);
    }
    
    // View Functions
    function getPassport(uint256 tokenId) external view returns (Passport memory) {
        require(_exists(tokenId), "Passport does not exist");
        return passports[tokenId];
    }
    
    function isVerifiedDataHash(bytes32 dataHash) external view returns (bool) {
        return verifiedDataHashes[dataHash];
    }
    
    function getLatestPrice() external view returns (int) {
        if (address(priceFeed) == address(0)) {
            return 0;
        }
        (, int price, , , ) = priceFeed.latestRoundData();
        return price;
    }
    
    function getTotalPassports() external view returns (uint256) {
        return _tokenIdCounter;
    }
    
    function isAuthorizedIssuer(address issuer) external view returns (bool) {
        return authorizedIssuers[issuer];
    }
    
    function getPassportsByOwner(address owner) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < _tokenIdCounter; i++) {
            if (ownerOf(i) == owner) {
                tokenIds[currentIndex] = i;
                currentIndex++;
            }
        }
        
        return tokenIds;
    }
} 