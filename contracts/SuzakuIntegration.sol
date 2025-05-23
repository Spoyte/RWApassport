// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SuzakuIntegration
 * @dev Basic integration with Suzaku restaking protocol for L1 security
 * @notice This contract provides security features through validator management and restaking
 */
contract SuzakuIntegration is Ownable, ReentrancyGuard {
    // Staking token (could be AVAX or other tokens)
    IERC20 public immutable stakingToken;
    
    // Validator management
    mapping(address => Validator) public validators;
    mapping(address => bool) public authorizedValidators;
    address[] public validatorList;
    
    // Staking and slashing
    mapping(address => uint256) public stakedAmounts;
    mapping(address => uint256) public rewardBalances;
    mapping(bytes32 => bool) public processedSlashingEvents;
    
    // Security parameters
    uint256 public minimumStake;
    uint256 public slashingPercentage;
    uint256 public rewardRate;
    uint256 public totalStaked;
    uint256 public lastRewardUpdate;
    
    struct Validator {
        address validatorAddress;
        uint256 stakedAmount;
        uint256 joinedAt;
        uint256 lastActivity;
        bool isActive;
        uint256 slashingCount;
        string metadata;
    }
    
    struct SecurityAttestation {
        bytes32 dataHash;
        address validator;
        uint256 timestamp;
        bool isValid;
        string attestationType;
    }
    
    // Events
    event ValidatorRegistered(address indexed validator, uint256 stakedAmount);
    event ValidatorSlashed(address indexed validator, uint256 slashedAmount, string reason);
    event StakeAdded(address indexed validator, uint256 amount);
    event StakeWithdrawn(address indexed validator, uint256 amount);
    event SecurityAttestationCreated(bytes32 indexed dataHash, address indexed validator);
    event RewardsDistributed(uint256 totalRewards, uint256 validatorCount);
    
    // Constructor
    constructor(
        address _stakingToken,
        uint256 _minimumStake,
        uint256 _slashingPercentage,
        uint256 _rewardRate
    ) {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_minimumStake > 0, "Invalid minimum stake");
        require(_slashingPercentage <= 100, "Invalid slashing percentage");
        
        stakingToken = IERC20(_stakingToken);
        minimumStake = _minimumStake;
        slashingPercentage = _slashingPercentage;
        rewardRate = _rewardRate;
        lastRewardUpdate = block.timestamp;
        
        _transferOwnership(msg.sender);
    }
    
    // Validator registration and management
    function registerValidator(
        uint256 stakeAmount,
        string memory metadata
    ) external nonReentrant {
        require(stakeAmount >= minimumStake, "Insufficient stake amount");
        require(!authorizedValidators[msg.sender], "Validator already registered");
        require(stakingToken.transferFrom(msg.sender, address(this), stakeAmount), "Stake transfer failed");
        
        validators[msg.sender] = Validator({
            validatorAddress: msg.sender,
            stakedAmount: stakeAmount,
            joinedAt: block.timestamp,
            lastActivity: block.timestamp,
            isActive: true,
            slashingCount: 0,
            metadata: metadata
        });
        
        authorizedValidators[msg.sender] = true;
        validatorList.push(msg.sender);
        stakedAmounts[msg.sender] = stakeAmount;
        totalStaked += stakeAmount;
        
        emit ValidatorRegistered(msg.sender, stakeAmount);
    }
    
    function addStake(uint256 amount) external nonReentrant {
        require(authorizedValidators[msg.sender], "Not a registered validator");
        require(amount > 0, "Invalid stake amount");
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Stake transfer failed");
        
        validators[msg.sender].stakedAmount += amount;
        stakedAmounts[msg.sender] += amount;
        totalStaked += amount;
        
        emit StakeAdded(msg.sender, amount);
    }
    
    function withdrawStake(uint256 amount) external nonReentrant {
        require(authorizedValidators[msg.sender], "Not a registered validator");
        require(amount > 0, "Invalid withdrawal amount");
        require(stakedAmounts[msg.sender] >= amount, "Insufficient staked amount");
        require(stakedAmounts[msg.sender] - amount >= minimumStake, "Cannot withdraw below minimum stake");
        
        validators[msg.sender].stakedAmount -= amount;
        stakedAmounts[msg.sender] -= amount;
        totalStaked -= amount;
        
        require(stakingToken.transfer(msg.sender, amount), "Withdrawal transfer failed");
        
        emit StakeWithdrawn(msg.sender, amount);
    }
    
    // Security attestation functions
    function createSecurityAttestation(
        bytes32 dataHash,
        string memory attestationType
    ) external returns (bool) {
        require(authorizedValidators[msg.sender], "Not an authorized validator");
        require(validators[msg.sender].isActive, "Validator not active");
        
        // Update validator activity
        validators[msg.sender].lastActivity = block.timestamp;
        
        // For MVP, we accept all attestations from authorized validators
        // In production, this would include more sophisticated validation
        
        emit SecurityAttestationCreated(dataHash, msg.sender);
        return true;
    }
    
    function validatePassportSecurity(
        bytes32 passportHash,
        address[] memory attestingValidators
    ) external view returns (bool) {
        require(attestingValidators.length > 0, "No attesting validators");
        
        uint256 validAttestations = 0;
        uint256 totalStakeAttesting = 0;
        
        for (uint256 i = 0; i < attestingValidators.length; i++) {
            address validator = attestingValidators[i];
            if (authorizedValidators[validator] && validators[validator].isActive) {
                validAttestations++;
                totalStakeAttesting += stakedAmounts[validator];
            }
        }
        
        // Require at least 2/3 of validators by stake to attest
        return (totalStakeAttesting * 3) >= (totalStaked * 2);
    }
    
    // Slashing functions
    function slashValidator(
        address validator,
        string memory reason
    ) external onlyOwner {
        require(authorizedValidators[validator], "Not a registered validator");
        require(validators[validator].isActive, "Validator already inactive");
        
        uint256 slashAmount = (stakedAmounts[validator] * slashingPercentage) / 100;
        
        validators[validator].stakedAmount -= slashAmount;
        validators[validator].slashingCount++;
        stakedAmounts[validator] -= slashAmount;
        totalStaked -= slashAmount;
        
        // If stake falls below minimum, deactivate validator
        if (stakedAmounts[validator] < minimumStake) {
            validators[validator].isActive = false;
        }
        
        emit ValidatorSlashed(validator, slashAmount, reason);
    }
    
    function deactivateValidator(address validator) external onlyOwner {
        require(authorizedValidators[validator], "Not a registered validator");
        validators[validator].isActive = false;
    }
    
    function reactivateValidator(address validator) external onlyOwner {
        require(authorizedValidators[validator], "Not a registered validator");
        require(stakedAmounts[validator] >= minimumStake, "Insufficient stake for reactivation");
        validators[validator].isActive = true;
    }
    
    // Reward distribution
    function distributeRewards() external onlyOwner {
        uint256 timeSinceLastUpdate = block.timestamp - lastRewardUpdate;
        uint256 totalRewards = (totalStaked * rewardRate * timeSinceLastUpdate) / (365 days * 100);
        
        if (totalRewards == 0) return;
        
        uint256 activeValidators = 0;
        for (uint256 i = 0; i < validatorList.length; i++) {
            if (validators[validatorList[i]].isActive) {
                activeValidators++;
            }
        }
        
        if (activeValidators == 0) return;
        
        for (uint256 i = 0; i < validatorList.length; i++) {
            address validator = validatorList[i];
            if (validators[validator].isActive) {
                uint256 validatorReward = (totalRewards * stakedAmounts[validator]) / totalStaked;
                rewardBalances[validator] += validatorReward;
            }
        }
        
        lastRewardUpdate = block.timestamp;
        emit RewardsDistributed(totalRewards, activeValidators);
    }
    
    function claimRewards() external nonReentrant {
        require(authorizedValidators[msg.sender], "Not a registered validator");
        uint256 rewards = rewardBalances[msg.sender];
        require(rewards > 0, "No rewards to claim");
        
        rewardBalances[msg.sender] = 0;
        
        // In a real implementation, rewards would be minted or transferred
        // For MVP, we'll emit an event
        // require(stakingToken.transfer(msg.sender, rewards), "Reward transfer failed");
    }
    
    // View functions
    function getValidator(address validator) external view returns (Validator memory) {
        return validators[validator];
    }
    
    function getActiveValidatorCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < validatorList.length; i++) {
            if (validators[validatorList[i]].isActive) {
                count++;
            }
        }
        return count;
    }
    
    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }
    
    function getValidatorStake(address validator) external view returns (uint256) {
        return stakedAmounts[validator];
    }
    
    function getValidatorRewards(address validator) external view returns (uint256) {
        return rewardBalances[validator];
    }
    
    function isValidatorActive(address validator) external view returns (bool) {
        return authorizedValidators[validator] && validators[validator].isActive;
    }
    
    // Admin functions
    function updateSecurityParameters(
        uint256 _minimumStake,
        uint256 _slashingPercentage,
        uint256 _rewardRate
    ) external onlyOwner {
        require(_slashingPercentage <= 100, "Invalid slashing percentage");
        
        minimumStake = _minimumStake;
        slashingPercentage = _slashingPercentage;
        rewardRate = _rewardRate;
    }
    
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != address(stakingToken), "Cannot withdraw staking token");
        IERC20(token).transfer(msg.sender, amount);
    }
} 