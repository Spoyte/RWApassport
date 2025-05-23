// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title CCIPGateway
 * @dev Handles cross-chain passport verification and messaging via Chainlink CCIP
 * @notice This contract enables passport data to be verified across different blockchain networks
 */
contract CCIPGateway is Ownable, ReentrancyGuard {
    // CCIP Router
    IRouterClient private immutable ccipRouter;
    LinkTokenInterface private immutable linkToken;
    
    // State variables
    mapping(uint64 => bool) public allowlistedChains;
    mapping(address => bool) public allowlistedSenders;
    mapping(bytes32 => PassportMessage) public receivedMessages;
    mapping(bytes32 => bool) public processedMessages;
    
    struct PassportMessage {
        uint256 passportId;
        bytes32 metadataHash;
        address originalOwner;
        address issuer;
        string assetType;
        uint256 createdAt;
        uint256 lastVerified;
        bool isActive;
        uint8 verificationLevel;
    }
    
    struct CrossChainRequest {
        uint64 destinationChain;
        address recipient;
        uint256 passportId;
        bytes32 metadataHash;
        bytes additionalData;
    }
    
    // Events
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChain,
        address indexed recipient,
        uint256 passportId,
        uint256 fees
    );
    
    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChain,
        address indexed sender,
        uint256 passportId
    );
    
    event ChainAllowlisted(uint64 indexed chainSelector, bool allowed);
    event SenderAllowlisted(address indexed sender, bool allowed);
    
    // Errors
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, address target, uint256 value);
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector);
    error SourceChainNotAllowlisted(uint64 sourceChainSelector);
    error SenderNotAllowlisted(address sender);
    error InvalidRouter(address router);
    
    // Constructor
    constructor(address _router, address _link) {
        if (_router == address(0)) revert InvalidRouter(_router);
        ccipRouter = IRouterClient(_router);
        linkToken = LinkTokenInterface(_link);
        _transferOwnership(msg.sender);
    }
    
    // Modifiers
    modifier onlyAllowlistedChain(uint64 _chainSelector) {
        if (!allowlistedChains[_chainSelector])
            revert DestinationChainNotAllowlisted(_chainSelector);
        _;
    }
    
    modifier onlyAllowlistedSender(address _sender) {
        if (!allowlistedSenders[_sender]) revert SenderNotAllowlisted(_sender);
        _;
    }
    
    // Core Functions
    function sendPassportMessage(
        CrossChainRequest memory request
    ) external nonReentrant onlyAllowlistedChain(request.destinationChain) returns (bytes32 messageId) {
        // Encode the passport data
        PassportMessage memory passportMsg = PassportMessage({
            passportId: request.passportId,
            metadataHash: request.metadataHash,
            originalOwner: msg.sender,
            issuer: msg.sender,
            assetType: "cross-chain-passport",
            createdAt: block.timestamp,
            lastVerified: block.timestamp,
            isActive: true,
            verificationLevel: 1
        });
        
        bytes memory encodedMessage = abi.encode(passportMsg, request.additionalData);
        
        // Create CCIP message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(request.recipient),
            data: encodedMessage,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 500_000})
            ),
            feeToken: address(linkToken)
        });
        
        // Calculate fees
        uint256 fees = ccipRouter.getFee(request.destinationChain, evm2AnyMessage);
        
        // Check balance
        if (fees > linkToken.balanceOf(address(this)))
            revert NotEnoughBalance(linkToken.balanceOf(address(this)), fees);
        
        // Approve the Router to transfer LINK tokens
        linkToken.approve(address(ccipRouter), fees);
        
        // Send the message
        messageId = ccipRouter.ccipSend(request.destinationChain, evm2AnyMessage);
        
        emit MessageSent(
            messageId,
            request.destinationChain,
            request.recipient,
            request.passportId,
            fees
        );
        
        return messageId;
    }
    
    function ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        external
        onlyRouter
    {
        bytes32 messageId = any2EvmMessage.messageId;
        uint64 sourceChainSelector = any2EvmMessage.sourceChainSelector;
        address sender = abi.decode(any2EvmMessage.sender, (address));
        
        // Validate source chain and sender
        if (!allowlistedChains[sourceChainSelector])
            revert SourceChainNotAllowlisted(sourceChainSelector);
        if (!allowlistedSenders[sender])
            revert SenderNotAllowlisted(sender);
        
        // Prevent duplicate processing
        require(!processedMessages[messageId], "Message already processed");
        processedMessages[messageId] = true;
        
        // Decode the message
        (PassportMessage memory passportMsg, bytes memory additionalData) = 
            abi.decode(any2EvmMessage.data, (PassportMessage, bytes));
        
        // Store the received message
        receivedMessages[messageId] = passportMsg;
        
        emit MessageReceived(
            messageId,
            sourceChainSelector,
            sender,
            passportMsg.passportId
        );
        
        // Process the passport verification
        _processPassportVerification(messageId, passportMsg, additionalData);
    }
    
    function _processPassportVerification(
        bytes32 messageId,
        PassportMessage memory passportMsg,
        bytes memory additionalData
    ) internal {
        // In a full implementation, this would:
        // 1. Verify the passport data against the source chain
        // 2. Update local verification records
        // 3. Emit verification events
        // 4. Potentially mint a local verification token
        
        // For MVP, we simply store the verification
        // This can be extended to integrate with local passport registry
    }
    
    // View Functions
    function getReceivedMessage(bytes32 messageId) external view returns (PassportMessage memory) {
        return receivedMessages[messageId];
    }
    
    function isMessageProcessed(bytes32 messageId) external view returns (bool) {
        return processedMessages[messageId];
    }
    
    function getFee(
        uint64 destinationChainSelector,
        CrossChainRequest memory request
    ) external view returns (uint256 fee) {
        PassportMessage memory passportMsg = PassportMessage({
            passportId: request.passportId,
            metadataHash: request.metadataHash,
            originalOwner: msg.sender,
            issuer: msg.sender,
            assetType: "cross-chain-passport",
            createdAt: block.timestamp,
            lastVerified: block.timestamp,
            isActive: true,
            verificationLevel: 1
        });
        
        bytes memory encodedMessage = abi.encode(passportMsg, request.additionalData);
        
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(request.recipient),
            data: encodedMessage,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 500_000})
            ),
            feeToken: address(linkToken)
        });
        
        return ccipRouter.getFee(destinationChainSelector, evm2AnyMessage);
    }
    
    // Admin Functions
    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedChains[_destinationChainSelector] = allowed;
        emit ChainAllowlisted(_destinationChainSelector, allowed);
    }
    
    function allowlistSender(address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
        emit SenderAllowlisted(_sender, allowed);
    }
    
    function withdrawToken(address _beneficiary, address _token) public onlyOwner {
        uint256 amount = LinkTokenInterface(_token).balanceOf(address(this));
        
        if (amount == 0) revert NothingToWithdraw();
        
        LinkTokenInterface(_token).transfer(_beneficiary, amount);
    }
    
    function withdraw(address _beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;
        
        if (amount == 0) revert NothingToWithdraw();
        
        (bool sent, ) = _beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }
    
    // Router validation
    modifier onlyRouter() {
        require(msg.sender == address(ccipRouter), "Only router can call");
        _;
    }
    
    // Receive function to accept ETH
    receive() external payable {}
    
    // Fallback function
    fallback() external payable {}
} 