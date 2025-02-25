// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./HedgeBaal.sol";

/**
 * @title HedgeStaking
 * @notice Manages staking of LOOT tokens for flight state transitions
 */
contract HedgeStaking is ReentrancyGuard {
    struct StakeInfo {
        uint256 totalStaked;        // Total LOOT staked for this state
        mapping(address => uint256) stakes;  // User stakes for this state
    }
    
    // Token addresses
    IERC20 public immutable lootToken;
    HedgeBaal public immutable hedgeBaal;
    
    // Staking tracking
    mapping(HedgeBaal.FlightState => StakeInfo) public stateStakes;
    
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
    
    constructor(
        address _lootToken,
        address _hedgeBaal
    ) {
        lootToken = IERC20(_lootToken);
        hedgeBaal = HedgeBaal(_hedgeBaal);
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
        
        // Update staking state
        stateStakes[state].stakes[msg.sender] += amount;
        stateStakes[state].totalStaked += amount;
        
        emit Staked(msg.sender, amount, state, currentCycle);
    }
    
    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot unstake 0");
        
        HedgeBaal.FlightState state = hedgeBaal.currentState();
        require(stateStakes[state].stakes[msg.sender] >= amount, "Insufficient balance");
        
        // Update staking state
        stateStakes[state].stakes[msg.sender] -= amount;
        stateStakes[state].totalStaked -= amount;
        
        // Transfer tokens back
        require(lootToken.transfer(msg.sender, amount), "Transfer failed");
        
        emit Unstaked(msg.sender, amount, state, hedgeBaal.currentCycle());
    }
    
    // View functions
    function getStakePercentage(HedgeBaal.FlightState state) public view returns (uint256) {
        uint256 totalSupply = lootToken.totalSupply();
        if (totalSupply == 0) return 0;
        return (stateStakes[state].totalStaked * 100) / totalSupply;
    }
    
    function getCurrentStakePercentage() external view returns (uint256) {
        return getStakePercentage(hedgeBaal.currentState());
    }
    
    function isThresholdMet(HedgeBaal.FlightState state) public view returns (bool) {
        return getStakePercentage(state) >= 100; // Assuming 100% as the threshold
    }
    
    function isNewCycleThresholdMet() public view returns (bool) {
        return getStakePercentage(HedgeBaal.FlightState.TERMINAL) >= 100;
    }
    
    // Clear staking data when transitioning states
    function clearStakingData(HedgeBaal.FlightState state) external {
        require(msg.sender == address(hedgeBaal), "Only HedgeBaal");
        delete stateStakes[state].totalStaked;
        // Note: Individual balances are kept for history
    }
    
    function balanceOf(address user) external view returns (uint256) {
        return stateStakes[hedgeBaal.currentState()].stakes[user];
    }
    
    function totalStaked() external view returns (uint256) {
        return stateStakes[hedgeBaal.currentState()].totalStaked;
    }
} 