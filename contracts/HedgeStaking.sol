// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./HedgeBaal.sol";

/**
 * @title HedgeStaking
 * @notice Manages staking and reward distribution using FLIGHT tokens
 * 
 * FLIGHT Token Distribution per Flight:
 * Each successful flight distributes FLIGHT tokens to participants:
 * - ASCENT -> PEAK_ALTITUDE: 1000 FLIGHT tokens (signals move to short)
 * - DESCENT -> LANDING: 1000 FLIGHT tokens (signals time to land)
 * - TERMINAL -> TAKE_OFF: 1000 FLIGHT tokens (signals new cycle)
 *
 * FLIGHT tokens represent participation in successful state transitions
 * and can be used for:
 * - Governance weight in future decisions
 * - Claim on future revenue share
 * - Access to premium features
 */
contract HedgeStaking is ReentrancyGuard {
    struct StateRewards {
        uint256 totalReward;        // Total FLIGHT tokens for this state change
        uint256 totalStaked;        // Total LOOT staked for this state change
        bool distributed;           // Whether rewards have been distributed
        mapping(address => uint256) stakes;  // User stakes for this state change
    }
    
    struct UserReward {
        HedgeBaal.FlightState state;
        uint256 amount;
        bool claimed;
    }
    
    // Token addresses
    IERC20 public immutable lootToken;
    IERC20 public immutable flightToken;  // FLIGHT token for rewards
    HedgeBaal public immutable hedgeBaal;
    
    // Reward tracking
    mapping(HedgeBaal.FlightState => StateRewards) public stateRewards;
    mapping(address => UserReward[]) public userRewards;
    
    // Fixed FLIGHT rewards per state transition
    uint256 public constant FLIGHT_REWARD_PER_TRANSITION = 1000 ether; // 1000 FLIGHT tokens (18 decimals)
    
    // Events
    event Staked(
        address indexed user, 
        uint256 amount, 
        HedgeBaal.FlightState state,
        uint256 flightNumber
    );
    
    event Unstaked(
        address indexed user, 
        uint256 amount, 
        HedgeBaal.FlightState state,
        uint256 flightNumber
    );
    
    event FlightRewardsDistributed(
        HedgeBaal.FlightState state, 
        uint256 totalFlightTokens,
        uint256 stakersCount,
        uint256 flightNumber
    );
    
    event FlightRewardClaimed(
        address indexed user, 
        uint256 amount, 
        uint256 flightNumber
    );
    
    constructor(
        address _lootToken, 
        address _flightToken,
        address _hedgeBaal
    ) {
        lootToken = IERC20(_lootToken);
        flightToken = IERC20(_flightToken);
        hedgeBaal = HedgeBaal(_hedgeBaal);
    }
    
    /**
     * @notice Fixed reward amount per state transition
     * @param state Current flight state
     * @return rewardAmount Amount of FLIGHT tokens to distribute
     */
    function _calculateStateRewards(HedgeBaal.FlightState state) 
        internal 
        pure 
        returns (uint256 rewardAmount) 
    {
        if (state == HedgeBaal.FlightState.ASCENT ||
            state == HedgeBaal.FlightState.DESCENT ||
            state == HedgeBaal.FlightState.TERMINAL) {
            return FLIGHT_REWARD_PER_TRANSITION;
        }
        return 0;
    }
    
    /**
     * @notice Distribute FLIGHT tokens for a completed state transition
     * @param state The state that was successfully transitioned from
     */
    function distributeRewards(HedgeBaal.FlightState state) external {
        require(msg.sender == address(hedgeBaal), "Only HedgeBaal");
        StateRewards storage rewards = stateRewards[state];
        require(!rewards.distributed, "Rewards already distributed");
        require(rewards.totalStaked > 0, "No stakes for reward");
        
        uint256 totalReward = _calculateStateRewards(state);
        require(
            flightToken.balanceOf(address(this)) >= totalReward,
            "Insufficient FLIGHT tokens"
        );
        
        rewards.totalReward = totalReward;
        
        // Get stakers for this transition
        address[] memory stakers = _getStakers(state);
        
        // Distribute FLIGHT tokens
        for (uint256 i = 0; i < stakers.length; i++) {
            address staker = stakers[i];
            uint256 userStake = rewards.stakes[staker];
            if (userStake == 0) continue;
            
            uint256 userReward = (totalReward * userStake) / rewards.totalStaked;
            userRewards[staker].push(UserReward({
                state: state,
                amount: userReward,
                claimed: false
            }));
        }
        
        rewards.distributed = true;
        emit FlightRewardsDistributed(
            state, 
            totalReward,
            stakers.length,
            hedgeBaal.currentCycle()
        );
    }
    
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        
        HedgeBaal.FlightState state = hedgeBaal.currentState();
        uint256 currentCycle = hedgeBaal.currentCycle();
        
        // Validate staking is allowed in current state
        require(
            state == HedgeBaal.FlightState.ASCENT || 
            state == HedgeBaal.FlightState.DESCENT ||
            state == HedgeBaal.FlightState.TERMINAL,
            "Staking not active"
        );
        
        // Transfer tokens
        require(lootToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Update staking state for current cycle
        stateRewards[state].stakes[msg.sender] += amount;
        stateRewards[state].totalStaked += amount;
        
        emit Staked(msg.sender, amount, state, currentCycle);
    }
    
    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot unstake 0");
        
        HedgeBaal.FlightState state = hedgeBaal.currentState();
        require(stateRewards[state].stakes[msg.sender] >= amount, "Insufficient balance");
        
        // Update staking state
        stateRewards[state].stakes[msg.sender] -= amount;
        stateRewards[state].totalStaked -= amount;
        
        // Transfer tokens back
        require(lootToken.transfer(msg.sender, amount), "Transfer failed");
        
        emit Unstaked(msg.sender, amount, state, hedgeBaal.currentCycle());
    }
    
    /**
     * @notice Claim accumulated FLIGHT token rewards
     */
    function claimRewards() external nonReentrant {
        UserReward[] storage rewards = userRewards[msg.sender];
        uint256 totalToClaim = 0;
        
        for (uint256 i = 0; i < rewards.length; i++) {
            if (!rewards[i].claimed) {
                totalToClaim += rewards[i].amount;
                rewards[i].claimed = true;
            }
        }
        
        require(totalToClaim > 0, "No rewards to claim");
        require(
            flightToken.transfer(msg.sender, totalToClaim),
            "FLIGHT transfer failed"
        );
        
        emit FlightRewardClaimed(
            msg.sender, 
            totalToClaim,
            hedgeBaal.currentCycle()
        );
    }
    
    // View functions
    function getStakePercentage(HedgeBaal.FlightState state) public view returns (uint256) {
        uint256 totalSupply = lootToken.totalSupply();
        if (totalSupply == 0) return 0;
        return (stateRewards[state].totalStaked * 100) / totalSupply;
    }
    
    function getCurrentStakePercentage() external view returns (uint256) {
        return getStakePercentage(hedgeBaal.currentState());
    }
    
    function isThresholdMet(HedgeBaal.FlightState state) public view returns (bool) {
        return getStakePercentage(state) >= 100; // Assuming 100% as the threshold
    }
    
    function isNewCycleThresholdMet() public view returns (bool) {
        return getStakePercentage(HedgeBaal.FlightState.TERMINAL) >= 100; // Assuming 100% as the threshold
    }
    
    // Clear staking data when transitioning states
    function clearStakingData(HedgeBaal.FlightState state) external {
        require(msg.sender == address(hedgeBaal), "Only HedgeBaal");
        delete stateRewards[state].totalStaked;
        // Note: Individual balances are kept for history
    }
    
    function _getStakers(HedgeBaal.FlightState state) internal view returns (address[] memory) {
        // Implementation of _getStakers function
        // This function should return an array of addresses that have stakes in the given state
        // For now, we'll return an empty array as the implementation is not provided
        return new address[](0);
    }
} 