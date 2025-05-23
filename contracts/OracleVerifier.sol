// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title OracleVerifier
 * @dev Handles external data verification through Chainlink oracles
 * @notice This contract verifies real-world asset data using multiple oracle sources
 */
contract OracleVerifier is ChainlinkClient, Ownable, ReentrancyGuard {
    using Chainlink for Chainlink.Request;
    
    // Oracle configuration
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;
    
    // Price feeds
    mapping(string => AggregatorV3Interface) public priceFeeds;
    
    // Verification requests
    mapping(bytes32 => VerificationRequest) public verificationRequests;
    mapping(bytes32 => bool) public verifiedData;
    mapping(address => bool) public authorizedVerifiers;
    
    struct VerificationRequest {
        address requester;
        string assetType;
        bytes32 dataHash;
        string externalId;
        uint256 timestamp;
        bool fulfilled;
        bool verified;
        string result;
    }
    
    struct AssetVerificationData {
        string assetType;
        string externalId;
        string verificationEndpoint;
        bytes32 expectedHash;
        uint256 minConfidence;
    }
    
    // Events
    event VerificationRequested(
        bytes32 indexed requestId,
        address indexed requester,
        string assetType,
        bytes32 dataHash
    );
    
    event VerificationFulfilled(
        bytes32 indexed requestId,
        bool verified,
        string result
    );
    
    event PriceFeedUpdated(string indexed asset, address indexed priceFeed);
    event VerifierAuthorized(address indexed verifier, bool authorized);
    
    // Constructor
    constructor(
        address _oracle,
        bytes32 _jobId,
        uint256 _fee,
        address _link
    ) {
        setChainlinkToken(_link);
        oracle = _oracle;
        jobId = _jobId;
        fee = _fee;
        _transferOwnership(msg.sender);
        
        // Authorize owner as verifier
        authorizedVerifiers[msg.sender] = true;
        emit VerifierAuthorized(msg.sender, true);
    }
    
    // Core verification functions
    function requestAssetVerification(
        AssetVerificationData memory verificationData
    ) external nonReentrant returns (bytes32 requestId) {
        require(authorizedVerifiers[msg.sender], "Unauthorized verifier");
        require(bytes(verificationData.assetType).length > 0, "Invalid asset type");
        require(verificationData.expectedHash != bytes32(0), "Invalid data hash");
        
        Chainlink.Request memory request = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );
        
        // Set the URL to perform the GET request on
        request.add("get", verificationData.verificationEndpoint);
        request.add("path", "verified");
        request.addInt("times", 1);
        
        // Send the request
        requestId = sendChainlinkRequestTo(oracle, request, fee);
        
        // Store the request
        verificationRequests[requestId] = VerificationRequest({
            requester: msg.sender,
            assetType: verificationData.assetType,
            dataHash: verificationData.expectedHash,
            externalId: verificationData.externalId,
            timestamp: block.timestamp,
            fulfilled: false,
            verified: false,
            result: ""
        });
        
        emit VerificationRequested(
            requestId,
            msg.sender,
            verificationData.assetType,
            verificationData.expectedHash
        );
        
        return requestId;
    }
    
    function fulfill(bytes32 _requestId, bool _verified) public recordChainlinkFulfillment(_requestId) {
        VerificationRequest storage request = verificationRequests[_requestId];
        require(!request.fulfilled, "Request already fulfilled");
        
        request.fulfilled = true;
        request.verified = _verified;
        request.result = _verified ? "VERIFIED" : "FAILED";
        
        if (_verified) {
            verifiedData[request.dataHash] = true;
        }
        
        emit VerificationFulfilled(_requestId, _verified, request.result);
    }
    
    // Mock verification for demo purposes
    function mockVerifyAsset(
        string memory assetType,
        bytes32 dataHash,
        string memory externalId
    ) external returns (bool) {
        require(authorizedVerifiers[msg.sender], "Unauthorized verifier");
        
        // For demo purposes, we'll verify based on simple criteria
        bool isVerified = _performMockVerification(assetType, externalId);
        
        if (isVerified) {
            verifiedData[dataHash] = true;
        }
        
        // Create a mock request record
        bytes32 mockRequestId = keccak256(abi.encodePacked(
            msg.sender,
            assetType,
            dataHash,
            block.timestamp
        ));
        
        verificationRequests[mockRequestId] = VerificationRequest({
            requester: msg.sender,
            assetType: assetType,
            dataHash: dataHash,
            externalId: externalId,
            timestamp: block.timestamp,
            fulfilled: true,
            verified: isVerified,
            result: isVerified ? "MOCK_VERIFIED" : "MOCK_FAILED"
        });
        
        emit VerificationRequested(mockRequestId, msg.sender, assetType, dataHash);
        emit VerificationFulfilled(mockRequestId, isVerified, isVerified ? "MOCK_VERIFIED" : "MOCK_FAILED");
        
        return isVerified;
    }
    
    function _performMockVerification(
        string memory assetType,
        string memory externalId
    ) internal pure returns (bool) {
        // Mock verification logic for demo
        bytes32 assetHash = keccak256(abi.encodePacked(assetType));
        bytes32 artHash = keccak256(abi.encodePacked("art"));
        bytes32 carbonHash = keccak256(abi.encodePacked("carbon_credit"));
        bytes32 propertyHash = keccak256(abi.encodePacked("property"));
        
        // Verify based on asset type and external ID patterns
        if (assetHash == artHash) {
            return bytes(externalId).length > 0;
        } else if (assetHash == carbonHash) {
            return bytes(externalId).length > 0;
        } else if (assetHash == propertyHash) {
            return bytes(externalId).length > 0;
        }
        
        return false;
    }
    
    // Price feed functions
    function addPriceFeed(string memory asset, address priceFeedAddress) external onlyOwner {
        require(priceFeedAddress != address(0), "Invalid price feed address");
        priceFeeds[asset] = AggregatorV3Interface(priceFeedAddress);
        emit PriceFeedUpdated(asset, priceFeedAddress);
    }
    
    function getLatestPrice(string memory asset) external view returns (int256) {
        AggregatorV3Interface priceFeed = priceFeeds[asset];
        require(address(priceFeed) != address(0), "Price feed not found");
        
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return price;
    }
    
    function getPriceWithTimestamp(string memory asset) external view returns (int256, uint256) {
        AggregatorV3Interface priceFeed = priceFeeds[asset];
        require(address(priceFeed) != address(0), "Price feed not found");
        
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        return (price, updatedAt);
    }
    
    // Batch verification
    function batchVerifyAssets(
        AssetVerificationData[] memory verificationDataArray
    ) external returns (bytes32[] memory requestIds) {
        require(authorizedVerifiers[msg.sender], "Unauthorized verifier");
        require(verificationDataArray.length > 0, "Empty verification array");
        require(verificationDataArray.length <= 10, "Too many verifications");
        
        requestIds = new bytes32[](verificationDataArray.length);
        
        for (uint256 i = 0; i < verificationDataArray.length; i++) {
            requestIds[i] = requestAssetVerification(verificationDataArray[i]);
        }
        
        return requestIds;
    }
    
    // View functions
    function isDataVerified(bytes32 dataHash) external view returns (bool) {
        return verifiedData[dataHash];
    }
    
    function getVerificationRequest(bytes32 requestId) external view returns (VerificationRequest memory) {
        return verificationRequests[requestId];
    }
    
    function isAuthorizedVerifier(address verifier) external view returns (bool) {
        return authorizedVerifiers[verifier];
    }
    
    // Admin functions
    function addAuthorizedVerifier(address verifier) external onlyOwner {
        require(verifier != address(0), "Invalid verifier address");
        authorizedVerifiers[verifier] = true;
        emit VerifierAuthorized(verifier, true);
    }
    
    function removeAuthorizedVerifier(address verifier) external onlyOwner {
        authorizedVerifiers[verifier] = false;
        emit VerifierAuthorized(verifier, false);
    }
    
    function updateOracleConfig(
        address _oracle,
        bytes32 _jobId,
        uint256 _fee
    ) external onlyOwner {
        oracle = _oracle;
        jobId = _jobId;
        fee = _fee;
    }
    
    function withdrawLink() external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }
    
    function getOracleConfig() external view returns (address, bytes32, uint256) {
        return (oracle, jobId, fee);
    }
} 