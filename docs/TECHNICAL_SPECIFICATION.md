# 🔧 Technical Specification

## Overview

The Cross-Chain RWA Passport system is built using a modular architecture with smart contracts deployed across multiple blockchain networks, integrated with Chainlink oracles and CCIP for cross-chain functionality, and secured by Suzaku's restaking protocol.

## 📦 Smart Contract Architecture

### Core Contracts

#### 1. PassportRegistry.sol
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    
    // Constructor
    constructor(
        address _priceFeed,
        address _owner
    ) ERC721("RWA Passport", "RWAP") {
        priceFeed = AggregatorV3Interface(_priceFeed);
        _transferOwnership(_owner);
    }
    
    // Core Functions
    function createPassport(
        string memory assetType,
        bytes32 metadataHash,
        AssetMetadata memory metadata,
        bytes[] memory oracleProofs
    ) external nonReentrant returns (uint256) {
        require(authorizedIssuers[msg.sender], "Unauthorized issuer");
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
        
        passport.lastVerified = block.timestamp;
        passport.verificationLevel = _calculateVerificationLevel(newProofs.length);
        
        emit PassportVerified(tokenId, msg.sender, passport.metadataHash, block.timestamp);
    }
    
    function updatePassport(
        uint256 tokenId,
        bytes32 newMetadataHash,
        bytes[] memory updateProofs
    ) external {
        require(ownerOf(tokenId) == msg.sender || authorizedIssuers[msg.sender], "Unauthorized");
        require(_verifyOracleProofs(updateProofs, newMetadataHash), "Invalid update proofs");
        
        Passport storage passport = passports[tokenId];
        passport.metadataHash = newMetadataHash;
        passport.lastVerified = block.timestamp;
        
        verifiedDataHashes[newMetadataHash] = true;
    }
    
    // Internal Functions
    function _verifyOracleProofs(
        bytes[] memory proofs,
        bytes32 dataHash
    ) internal view returns (bool) {
        // Simplified oracle verification logic
        // In production, this would verify Chainlink oracle signatures
        return proofs.length > 0;
    }
    
    function _calculateVerificationLevel(uint256 proofCount) internal pure returns (VerificationLevel) {
        if (proofCount >= 3) return VerificationLevel.PREMIUM;
        if (proofCount >= 2) return VerificationLevel.ENHANCED;
        return VerificationLevel.BASIC;
    }
    
    // Admin Functions
    function addAuthorizedIssuer(address issuer) external onlyOwner {
        authorizedIssuers[issuer] = true;
    }
    
    function removeAuthorizedIssuer(address issuer) external onlyOwner {
        authorizedIssuers[issuer] = false;
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
        (, int price, , , ) = priceFeed.latestRoundData();
        return price;
    }
}
```

#### 2. CCIPGateway.sol
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CCIPGateway is CCIPReceiver, Ownable {
    // State variables
    IRouterClient private immutable i_router;
    LinkTokenInterface private immutable i_linkToken;
    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => bool) public allowlistedSourceChains;
    mapping(address => bool) public allowlistedSenders;
    mapping(bytes32 => PassportMessage) public receivedMessages;
    
    address public passportRegistry;
    
    struct PassportMessage {
        uint256 passportId;
        string assetType;
        bytes32 metadataHash;
        address originalContract;
        uint64 sourceChainSelector;
        address recipient;
        VerificationProof[] proofs;
        uint256 timestamp;
    }
    
    struct VerificationProof {
        bytes32 dataHash;
        bytes signature;
        address oracle;
        uint256 timestamp;
    }
    
    // Events
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        PassportMessage message,
        address feeToken,
        uint256 fees
    );
    
    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        PassportMessage message
    );
    
    event PassportVerificationRequested(
        uint256 indexed passportId,
        address indexed requester,
        uint64 sourceChain
    );
    
    // Constructor
    constructor(
        address _router,
        address _link,
        address _passportRegistry
    ) CCIPReceiver(_router) {
        i_router = IRouterClient(_router);
        i_linkToken = LinkTokenInterface(_link);
        passportRegistry = _passportRegistry;
    }
    
    // Modifiers
    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        require(allowlistedDestinationChains[_destinationChainSelector], "Destination chain not allowlisted");
        _;
    }
    
    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        require(allowlistedSourceChains[_sourceChainSelector], "Source chain not allowlisted");
        require(allowlistedSenders[_sender], "Sender not allowlisted");
        _;
    }
    
    // Core Functions
    function sendPassportData(
        uint64 destinationChainSelector,
        address receiver,
        uint256 passportId,
        string memory assetType,
        bytes32 metadataHash,
        VerificationProof[] memory proofs
    ) external onlyAllowlistedDestinationChain(destinationChainSelector) returns (bytes32 messageId) {
        // Create passport message
        PassportMessage memory passportMessage = PassportMessage({
            passportId: passportId,
            assetType: assetType,
            metadataHash: metadataHash,
            originalContract: passportRegistry,
            sourceChainSelector: _getChainSelector(),
            recipient: receiver,
            proofs: proofs,
            timestamp: block.timestamp
        });
        
        // Create CCIP message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(passportMessage),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 400_000})
            ),
            feeToken: address(i_linkToken)
        });
        
        // Calculate fees
        uint256 fees = i_router.getFee(destinationChainSelector, evm2AnyMessage);
        
        // Check LINK balance
        require(i_linkToken.balanceOf(address(this)) >= fees, "Not enough LINK to pay fees");
        
        // Approve router to spend LINK
        i_linkToken.approve(address(i_router), fees);
        
        // Send message
        messageId = i_router.ccipSend(destinationChainSelector, evm2AnyMessage);
        
        emit MessageSent(
            messageId,
            destinationChainSelector,
            receiver,
            passportMessage,
            address(i_linkToken),
            fees
        );
        
        return messageId;
    }
    
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override onlyAllowlisted(
        any2EvmMessage.sourceChainSelector,
        abi.decode(any2EvmMessage.sender, (address))
    ) {
        PassportMessage memory receivedMessage = abi.decode(any2EvmMessage.data, (PassportMessage));
        bytes32 messageId = any2EvmMessage.messageId;
        
        // Store received message
        receivedMessages[messageId] = receivedMessage;
        
        emit MessageReceived(
            messageId,
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address)),
            receivedMessage
        );
        
        // Trigger passport verification request
        emit PassportVerificationRequested(
            receivedMessage.passportId,
            receivedMessage.recipient,
            receivedMessage.sourceChainSelector
        );
    }
    
    // Verification Functions
    function verifyPassportFromMessage(
        bytes32 messageId
    ) external view returns (bool isValid, PassportMessage memory message) {
        message = receivedMessages[messageId];
        
        // Basic validation
        isValid = message.timestamp > 0 &&
                  message.metadataHash != bytes32(0) &&
                  message.proofs.length > 0;
        
        // Additional verification logic would go here
        // - Verify oracle signatures
        // - Check source chain validity
        // - Validate proof timestamps
        
        return (isValid, message);
    }
    
    // Admin Functions
    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }
    
    function allowlistSourceChain(uint64 _sourceChainSelector, bool allowed) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }
    
    function allowlistSender(address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
    }
    
    function withdrawLink(address _beneficiary) public onlyOwner {
        uint256 amount = i_linkToken.balanceOf(address(this));
        require(amount > 0, "Nothing to withdraw");
        i_linkToken.transfer(_beneficiary, amount);
    }
    
    // Internal Functions
    function _getChainSelector() internal view returns (uint64) {
        // Return the current chain selector
        // This would be configured per deployment
        if (block.chainid == 43113) return 14767482510784806043; // Fuji
        if (block.chainid == 11155111) return 16015286601757825753; // Sepolia
        revert("Unsupported chain");
    }
    
    // View Functions
    function getRouter() external view returns (address) {
        return address(i_router);
    }
    
    function getLinkToken() external view returns (address) {
        return address(i_linkToken);
    }
    
    function getMessage(bytes32 messageId) external view returns (PassportMessage memory) {
        return receivedMessages[messageId];
    }
}
```

#### 3. OracleVerifier.sol
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract OracleVerifier is ChainlinkClient, Ownable {
    using Chainlink for Chainlink.Request;
    
    // Oracle configuration
    bytes32 private jobId;
    uint256 private fee;
    
    // Data verification mappings
    mapping(bytes32 => bool) public verifiedData;
    mapping(bytes32 => uint256) public verificationTimestamps;
    mapping(address => bool) public trustedOracles;
    
    // Request tracking
    mapping(bytes32 => VerificationRequest) public pendingRequests;
    
    struct VerificationRequest {
        address requester;
        bytes32 dataHash;
        string apiEndpoint;
        uint256 timestamp;
        bool fulfilled;
    }
    
    // Events
    event VerificationRequested(
        bytes32 indexed requestId,
        address indexed requester,
        bytes32 dataHash,
        string apiEndpoint
    );
    
    event VerificationCompleted(
        bytes32 indexed requestId,
        bytes32 dataHash,
        bool isValid,
        uint256 timestamp
    );
    
    event TrustedOracleUpdated(
        address indexed oracle,
        bool trusted
    );
    
    // Constructor
    constructor(
        address _link,
        address _oracle,
        bytes32 _jobId,
        uint256 _fee
    ) {
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        jobId = _jobId;
        fee = _fee;
    }
    
    // Core verification functions
    function requestVerification(
        bytes32 dataHash,
        string memory apiEndpoint
    ) external returns (bytes32 requestId) {
        Chainlink.Request memory request = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );
        
        // Add parameters for the oracle request
        request.add("get", apiEndpoint);
        request.add("path", "verified");
        request.addInt("times", 1);
        
        // Send the request
        requestId = sendChainlinkRequest(request, fee);
        
        // Store request details
        pendingRequests[requestId] = VerificationRequest({
            requester: msg.sender,
            dataHash: dataHash,
            apiEndpoint: apiEndpoint,
            timestamp: block.timestamp,
            fulfilled: false
        });
        
        emit VerificationRequested(requestId, msg.sender, dataHash, apiEndpoint);
        return requestId;
    }
    
    function fulfill(
        bytes32 _requestId,
        bool _verified
    ) public recordChainlinkFulfillment(_requestId) {
        VerificationRequest storage request = pendingRequests[_requestId];
        require(!request.fulfilled, "Request already fulfilled");
        
        request.fulfilled = true;
        
        if (_verified) {
            verifiedData[request.dataHash] = true;
            verificationTimestamps[request.dataHash] = block.timestamp;
        }
        
        emit VerificationCompleted(
            _requestId,
            request.dataHash,
            _verified,
            block.timestamp
        );
    }
    
    // Manual verification for trusted oracles
    function manualVerification(
        bytes32 dataHash,
        bool isValid,
        bytes memory signature
    ) external {
        require(trustedOracles[msg.sender], "Not a trusted oracle");
        
        // Verify signature (simplified for demo)
        require(signature.length > 0, "Invalid signature");
        
        verifiedData[dataHash] = isValid;
        verificationTimestamps[dataHash] = block.timestamp;
        
        emit VerificationCompleted(
            keccak256(abi.encodePacked(dataHash, block.timestamp)),
            dataHash,
            isValid,
            block.timestamp
        );
    }
    
    // Batch verification
    function batchVerify(
        bytes32[] memory dataHashes,
        bool[] memory validities,
        bytes[] memory signatures
    ) external {
        require(trustedOracles[msg.sender], "Not a trusted oracle");
        require(
            dataHashes.length == validities.length && 
            validities.length == signatures.length,
            "Array length mismatch"
        );
        
        for (uint256 i = 0; i < dataHashes.length; i++) {
            verifiedData[dataHashes[i]] = validities[i];
            verificationTimestamps[dataHashes[i]] = block.timestamp;
            
            emit VerificationCompleted(
                keccak256(abi.encodePacked(dataHashes[i], block.timestamp)),
                dataHashes[i],
                validities[i],
                block.timestamp
            );
        }
    }
    
    // View functions
    function isVerified(bytes32 dataHash) external view returns (bool) {
        return verifiedData[dataHash];
    }
    
    function getVerificationTimestamp(bytes32 dataHash) external view returns (uint256) {
        return verificationTimestamps[dataHash];
    }
    
    function isDataFresh(bytes32 dataHash, uint256 maxAge) external view returns (bool) {
        uint256 verificationTime = verificationTimestamps[dataHash];
        return verificationTime > 0 && (block.timestamp - verificationTime) <= maxAge;
    }
    
    // Admin functions
    function updateTrustedOracle(address oracle, bool trusted) external onlyOwner {
        trustedOracles[oracle] = trusted;
        emit TrustedOracleUpdated(oracle, trusted);
    }
    
    function updateJobId(bytes32 _jobId) external onlyOwner {
        jobId = _jobId;
    }
    
    function updateFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }
    
    function withdrawLink() external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }
}
```

#### 4. SuzakuIntegration.sol
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface ISuzakuRestaking {
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function getStakedAmount(address staker) external view returns (uint256);
    function getRewards(address staker) external view returns (uint256);
    function claimRewards() external;
}

contract SuzakuIntegration is Ownable, ReentrancyGuard {
    // Suzaku integration
    ISuzakuRestaking public suzakuContract;
    
    // Security configuration
    mapping(address => bool) public authorizedValidators;
    mapping(address => uint256) public validatorStakes;
    uint256 public minimumStake;
    uint256 public totalStaked;
    
    // L1 security parameters
    struct SecurityConfig {
        uint256 minimumValidators;
        uint256 slashingThreshold;
        uint256 rewardDistributionPeriod;
        bool emergencyPause;
    }
    
    SecurityConfig public securityConfig;
    
    // Events
    event ValidatorAdded(address indexed validator, uint256 stake);
    event ValidatorRemoved(address indexed validator);
    event StakeIncreased(address indexed validator, uint256 amount);
    event StakeSlashed(address indexed validator, uint256 amount, string reason);
    event RewardsDistributed(uint256 totalAmount);
    event SecurityConfigUpdated();
    event EmergencyPauseToggled(bool paused);
    
    // Modifiers
    modifier onlyAuthorizedValidator() {
        require(authorizedValidators[msg.sender], "Not an authorized validator");
        _;
    }
    
    modifier whenNotPaused() {
        require(!securityConfig.emergencyPause, "Contract is paused");
        _;
    }
    
    // Constructor
    constructor(
        address _suzakuContract,
        uint256 _minimumStake,
        uint256 _minimumValidators
    ) {
        suzakuContract = ISuzakuRestaking(_suzakuContract);
        minimumStake = _minimumStake;
        
        securityConfig = SecurityConfig({
            minimumValidators: _minimumValidators,
            slashingThreshold: 10, // 10% slashing threshold
            rewardDistributionPeriod: 7 days,
            emergencyPause: false
        });
    }
    
    // Validator management
    function addValidator(address validator) external onlyOwner {
        require(validator != address(0), "Invalid validator address");
        require(!authorizedValidators[validator], "Validator already authorized");
        
        authorizedValidators[validator] = true;
        
        emit ValidatorAdded(validator, 0);
    }
    
    function removeValidator(address validator) external onlyOwner {
        require(authorizedValidators[validator], "Validator not authorized");
        
        // Unstake validator's tokens
        uint256 stakedAmount = validatorStakes[validator];
        if (stakedAmount > 0) {
            suzakuContract.unstake(stakedAmount);
            totalStaked -= stakedAmount;
            validatorStakes[validator] = 0;
        }
        
        authorizedValidators[validator] = false;
        
        emit ValidatorRemoved(validator);
    }
    
    // Staking functions
    function stakeForSecurity(uint256 amount) external onlyAuthorizedValidator whenNotPaused {
        require(amount >= minimumStake, "Amount below minimum stake");
        
        // Stake with Suzaku
        suzakuContract.stake(amount);
        
        validatorStakes[msg.sender] += amount;
        totalStaked += amount;
        
        emit StakeIncreased(msg.sender, amount);
    }
    
    function unstakeValidator(uint256 amount) external onlyAuthorizedValidator {
        require(validatorStakes[msg.sender] >= amount, "Insufficient staked amount");
        
        // Check if unstaking maintains minimum security
        uint256 remainingStake = validatorStakes[msg.sender] - amount;
        require(remainingStake >= minimumStake || remainingStake == 0, "Must maintain minimum stake");
        
        suzakuContract.unstake(amount);
        
        validatorStakes[msg.sender] -= amount;
        totalStaked -= amount;
    }
    
    // Security functions
    function slashValidator(
        address validator,
        uint256 amount,
        string memory reason
    ) external onlyOwner {
        require(authorizedValidators[validator], "Validator not authorized");
        require(validatorStakes[validator] >= amount, "Insufficient stake to slash");
        
        uint256 slashableAmount = (validatorStakes[validator] * securityConfig.slashingThreshold) / 100;
        require(amount <= slashableAmount, "Slash amount exceeds threshold");
        
        validatorStakes[validator] -= amount;
        totalStaked -= amount;
        
        // The slashed amount is effectively burned/redistributed
        emit StakeSlashed(validator, amount, reason);
    }
    
    // Reward distribution
    function distributeRewards() external onlyOwner {
        uint256 totalRewards = suzakuContract.getRewards(address(this));
        require(totalRewards > 0, "No rewards to distribute");
        
        suzakuContract.claimRewards();
        
        // Distribute rewards proportionally to validators
        // This is a simplified implementation
        emit RewardsDistributed(totalRewards);
    }
    
    // Security configuration
    function updateSecurityConfig(
        uint256 _minimumValidators,
        uint256 _slashingThreshold,
        uint256 _rewardDistributionPeriod
    ) external onlyOwner {
        require(_slashingThreshold <= 50, "Slashing threshold too high"); // Max 50%
        
        securityConfig.minimumValidators = _minimumValidators;
        securityConfig.slashingThreshold = _slashingThreshold;
        securityConfig.rewardDistributionPeriod = _rewardDistributionPeriod;
        
        emit SecurityConfigUpdated();
    }
    
    function toggleEmergencyPause() external onlyOwner {
        securityConfig.emergencyPause = !securityConfig.emergencyPause;
        emit EmergencyPauseToggled(securityConfig.emergencyPause);
    }
    
    // View functions
    function getValidatorStake(address validator) external view returns (uint256) {
        return validatorStakes[validator];
    }
    
    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }
    
    function getActiveValidatorCount() external view returns (uint256) {
        // This would require maintaining a list of active validators
        // Simplified for demo purposes
        return securityConfig.minimumValidators;
    }
    
    function isSecurityThresholdMet() external view returns (bool) {
        return getActiveValidatorCount() >= securityConfig.minimumValidators && 
               totalStaked >= (minimumStake * securityConfig.minimumValidators);
    }
    
    function getSuzakuRewards() external view returns (uint256) {
        return suzakuContract.getRewards(address(this));
    }
}
```

## 🔌 API Specifications

### Frontend API Interface

#### Passport Management API
```typescript
interface PassportAPI {
  // Passport creation
  createPassport(params: CreatePassportParams): Promise<CreatePassportResponse>;
  
  // Passport verification
  verifyPassport(tokenId: number): Promise<VerificationResponse>;
  
  // Cross-chain transfer
  transferPassport(params: TransferParams): Promise<TransferResponse>;
  
  // Passport queries
  getPassport(tokenId: number): Promise<Passport>;
  getPassportsByOwner(owner: string): Promise<Passport[]>;
  
  // Oracle integration
  requestOracleVerification(dataHash: string, apiEndpoint: string): Promise<string>;
  getVerificationStatus(requestId: string): Promise<VerificationStatus>;
}

interface CreatePassportParams {
  assetType: string;
  metadata: AssetMetadata;
  oracleEndpoints: string[];
  verificationLevel: 'BASIC' | 'ENHANCED' | 'PREMIUM';
}

interface CreatePassportResponse {
  tokenId: number;
  transactionHash: string;
  metadataHash: string;
  estimatedVerificationTime: number;
}

interface TransferParams {
  tokenId: number;
  destinationChain: number;
  recipient: string;
  includeVerificationData: boolean;
}

interface Passport {
  id: number;
  assetType: string;
  metadataHash: string;
  owner: string;
  issuer: string;
  createdAt: number;
  lastVerified: number;
  isActive: boolean;
  verificationLevel: 'BASIC' | 'ENHANCED' | 'PREMIUM';
  crossChainHistory: CrossChainTransfer[];
}
```

#### CCIP Integration API
```typescript
interface CCIPService {
  // Message sending
  sendCrossChainMessage(params: CCIPMessageParams): Promise<CCIPResponse>;
  
  // Message tracking
  trackMessage(messageId: string): Promise<MessageStatus>;
  
  // Fee estimation
  estimateFees(destinationChain: number, dataSize: number): Promise<FeeEstimate>;
  
  // Supported chains
  getSupportedChains(): Promise<ChainInfo[]>;
}

interface CCIPMessageParams {
  destinationChain: number;
  receiver: string;
  passportData: PassportMessage;
  gasLimit: number;
  feeToken: string;
}

interface MessageStatus {
  messageId: string;
  status: 'PENDING' | 'IN_PROGRESS' | 'SUCCESS' | 'FAILED';
  sourceChain: number;
  destinationChain: number;
  timestamp: number;
  fees: string;
  errorReason?: string;
}
```

### Oracle Integration Specification

#### Chainlink Oracle Configuration
```yaml
oracle_config:
  job_type: "directrequest"
  external_adapters:
    - name: "art_authentication"
      endpoint: "https://api.artverify.com/authenticate"
      method: "POST"
      headers:
        - "Content-Type: application/json"
        - "Authorization: Bearer ${API_KEY}"
    
    - name: "property_verification"
      endpoint: "https://api.propertyregistry.gov/verify"
      method: "GET"
      parameters:
        - "property_id"
        - "verification_level"
    
    - name: "carbon_credit_validation"
      endpoint: "https://api.carbonregistry.org/validate"
      method: "POST"
      authentication: "bearer_token"

  price_feeds:
    - pair: "AVAX/USD"
      decimals: 8
      heartbeat: 3600
    - pair: "LINK/USD"
      decimals: 8
      heartbeat: 3600
```

#### Oracle Response Format
```json
{
  "verification_id": "uuid",
  "data_hash": "0x...",
  "verification_result": {
    "is_valid": true,
    "confidence_score": 0.95,
    "verification_level": "ENHANCED",
    "sources": [
      {
        "source_name": "Primary Registry",
        "verification_status": "VERIFIED",
        "timestamp": "2025-05-23T10:30:00Z"
      }
    ]
  },
  "metadata": {
    "oracle_address": "0x...",
    "signature": "0x...",
    "timestamp": "2025-05-23T10:30:00Z"
  }
}
```

## 📊 Data Models

### Passport Metadata Schema
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "RWA Passport Metadata",
  "type": "object",
  "properties": {
    "passportId": {
      "type": "string",
      "description": "Unique passport identifier"
    },
    "version": {
      "type": "string",
      "enum": ["1.0", "1.1", "2.0"]
    },
    "assetType": {
      "type": "string",
      "enum": ["art", "property", "carbon_credit", "commodity", "security", "other"]
    },
    "basicInfo": {
      "type": "object",
      "properties": {
        "title": {"type": "string"},
        "description": {"type": "string"},
        "category": {"type": "string"},
        "subcategory": {"type": "string"},
        "tags": {
          "type": "array",
          "items": {"type": "string"}
        }
      },
      "required": ["title", "description", "category"]
    },
    "verificationData": {
      "type": "object",
      "properties": {
        "attestations": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "issuer": {"type": "string"},
              "signature": {"type": "string"},
              "timestamp": {"type": "string", "format": "date-time"},
              "verificationLevel": {"type": "string", "enum": ["BASIC", "ENHANCED", "PREMIUM"]}
            }
          }
        },
        "certifications": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "certificationId": {"type": "string"},
              "issuer": {"type": "string"},
              "type": {"type": "string"},
              "validUntil": {"type": "string", "format": "date-time"},
              "documentHash": {"type": "string"}
            }
          }
        },
        "lastVerified": {"type": "string", "format": "date-time"},
        "nextVerificationDue": {"type": "string", "format": "date-time"}
      }
    },
    "provenance": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "owner": {"type": "string"},
          "timestamp": {"type": "string", "format": "date-time"},
          "transactionHash": {"type": "string"},
          "verificationLevel": {"type": "string"},
          "transferReason": {"type": "string"},
          "additionalNotes": {"type": "string"}
        }
      }
    },
    "crossChainHistory": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "sourceChain": {"type": "string"},
          "destinationChain": {"type": "string"},
          "timestamp": {"type": "string", "format": "date-time"},
          "ccipMessageId": {"type": "string"},
          "transferType": {"type": "string", "enum": ["VERIFICATION", "OWNERSHIP", "UPDATE"]},
          "status": {"type": "string", "enum": ["PENDING", "COMPLETED", "FAILED"]}
        }
      }
    },
    "additionalMetadata": {
      "type": "object",
      "description": "Asset-specific additional metadata",
      "properties": {}
    }
  },
  "required": ["passportId", "version", "assetType", "basicInfo", "verificationData"]
}
```

## 🔒 Security Specifications

### Access Control Matrix
| Role | Create Passport | Verify Passport | Update Passport | Cross-Chain Transfer | Admin Functions |
|------|----------------|-----------------|-----------------|---------------------|-----------------|
| Asset Owner | ✅ (own assets) | ✅ | ✅ (own assets) | ✅ (own assets) | ❌ |
| Authorized Issuer | ✅ | ✅ | ✅ | ✅ | ❌ |
| Oracle Provider | ❌ | ✅ | ❌ | ❌ | ❌ |
| Contract Owner | ✅ | ✅ | ✅ | ✅ | ✅ |
| Validator | ❌ | ✅ | ❌ | ❌ | ❌ |

### Cryptographic Requirements
- **Hash Function**: SHA-256 for metadata hashing
- **Signature Scheme**: ECDSA with secp256k1 curve
- **Oracle Signatures**: Multi-signature with 2/3 threshold
- **Message Authentication**: HMAC-SHA256 for API communications
- **Cross-Chain Verification**: Merkle proof validation

### Gas Optimization
| Operation | Estimated Gas | Optimization Notes |
|-----------|---------------|-------------------|
| Create Passport | ~150,000 | Batch multiple operations |
| Verify Passport | ~80,000 | Use packed structs |
| CCIP Send | ~200,000 | Optimize message size |
| Oracle Request | ~120,000 | Cache verification results |
| Suzaku Stake | ~100,000 | Batch staking operations |

---

This technical specification provides the foundation for implementing the Cross-Chain RWA Passport system during the hackathon while ensuring enterprise-grade security and scalability for future development. 