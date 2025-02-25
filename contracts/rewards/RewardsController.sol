// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../HedgeBaal.sol";

contract RewardsController is ReentrancyGuard {
    IERC20 public immutable flightToken;
    HedgeBaal public immutable hedgeBaal;
    
    // Reward amounts
    uint256 public constant STAKING_REWARD_PER_TRANSITION = 1000 ether;  // 1000 FLIGHT
    uint256 public constant ACTION_REWARD = 100 ether;                   // 100 FLIGHT
    
    // Track rewards per state and action
    struct StateRewards {
        uint256 totalReward;
        uint256 totalStaked;
        bool distributed;
        mapping(address => uint256) stakes;
    }
    
    struct ActionRewards {
        address actor;
        uint256 amount;
        uint256 timestamp;
        bool claimed;
    }
    
    // Mappings for rewards
    mapping(HedgeBaal.FlightState => StateRewards) public stateRewards;
    mapping(bytes32 => ActionRewards[]) public actionRewards; // action -> rewards
    mapping(address => uint256) public pendingRewards;
    
    // Action types
    bytes32 public constant DESCENT_INITIATION = keccak256("DESCENT_INITIATION");
    bytes32 public constant TERMINAL_ENTRY = keccak256("TERMINAL_ENTRY");
    bytes32 public constant DEBT_REPAYMENT = keccak256("DEBT_REPAYMENT");
    bytes32 public constant REWARDS_CLAIMED = keccak256("REWARDS_CLAIMED");
    
    event StakingRewardDistributed(
        HedgeBaal.FlightState state,
        uint256 totalReward,
        uint256 stakersCount
    );
    
    event ActionRewardGranted(
        address indexed actor,
        bytes32 actionType,
        uint256 amount,
        uint256 timestamp
    );
    
    event RewardsClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    
    constructor(address _flightToken, address _hedgeBaal) {
        flightToken = IERC20(_flightToken);
        hedgeBaal = HedgeBaal(_hedgeBaal);
    }
    
    /**
     * @notice Record action reward for token-gated function caller
     * @param actor Address that performed the action
     * @param actionType Type of action performed
     */
    function recordAction(address actor, bytes32 actionType) external {
        require(msg.sender == address(hedgeBaal), "Only HedgeBaal");
        
        actionRewards[actionType].push(ActionRewards({
            actor: actor,
            amount: ACTION_REWARD,
            timestamp: block.timestamp,
            claimed: false
        }));
        
        pendingRewards[actor] += ACTION_REWARD;
        
        emit ActionRewardGranted(actor, actionType, ACTION_REWARD, block.timestamp);
    }
    
    /**
     * @notice Distribute staking rewards for state transition
     * @param state The state that was transitioned from
     */
    function distributeStakingRewards(HedgeBaal.FlightState state) external {
        require(msg.sender == address(hedgeBaal), "Only HedgeBaal");
        
        StateRewards storage rewards = stateRewards[state];
        require(!rewards.distributed, "Already distributed");
        require(rewards.totalStaked > 0, "No stakes");
        
        uint256 totalReward = STAKING_REWARD_PER_TRANSITION;
        rewards.totalReward = totalReward;
        
        address[] memory stakers = _getStakers(state);
        for (uint256 i = 0; i < stakers.length; i++) {
            address staker = stakers[i];
            uint256 stake = rewards.stakes[staker];
            if (stake == 0) continue;
            
            uint256 reward = (totalReward * stake) / rewards.totalStaked;
            pendingRewards[staker] += reward;
        }
        
        rewards.distributed = true;
        
        emit StakingRewardDistributed(
            state,
            totalReward,
            stakers.length
        );
    }
    
    /**
     * @notice Claim accumulated rewards
     */
    function claimRewards() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "No rewards");
        
        pendingRewards[msg.sender] = 0;
        
        require(
            flightToken.transfer(msg.sender, amount),
            "Transfer failed"
        );
        
        emit RewardsClaimed(msg.sender, amount, block.timestamp);
    }
    
    /**
     * @notice Get pending rewards for an account
     */
    function getPendingRewards(address account) external view returns (uint256) {
        return pendingRewards[account];
    }
    
    /**
     * @notice Get action rewards for a specific type
     */
    function getActionRewards(bytes32 actionType) external view returns (ActionRewards[] memory) {
        return actionRewards[actionType];
    }
    
    /**
     * @notice Get all stakers for a given state
     * @param state The flight state to check
     * @return Array of staker addresses
     */
    function _getStakers(HedgeBaal.FlightState state) internal view returns (address[] memory) {
        // Get total stakers count first (to size array)
        uint256 stakerCount = 0;
        uint256 maxIterations = 1000; // Prevent infinite loops
        
        // First pass: count stakers
        for (uint256 i = 0; i < maxIterations; i++) {
            address potentialStaker = hedgeBaal.lootToken().ownerOf(i);
            if (potentialStaker == address(0)) break;
            
            if (stateRewards[state].stakes[potentialStaker] > 0) {
                stakerCount++;
            }
        }
        
        // Create array of correct size
        address[] memory stakers = new address[](stakerCount);
        uint256 currentIndex = 0;
        
        // Second pass: fill array
        for (uint256 i = 0; i < maxIterations; i++) {
            address potentialStaker = hedgeBaal.lootToken().ownerOf(i);
            if (potentialStaker == address(0)) break;
            
            if (stateRewards[state].stakes[potentialStaker] > 0) {
                stakers[currentIndex] = potentialStaker;
                currentIndex++;
            }
            
            if (currentIndex == stakerCount) break;
        }
        
        return stakers;
    }
} 