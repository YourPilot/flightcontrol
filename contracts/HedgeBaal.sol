// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@gnosis.pm/zodiac/contracts/core/Module.sol";
import "./interfaces/IBaal.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IHedgeStaking.sol";
import "./interfaces/IStrategy.sol";

contract HedgeBaal is Module {
    enum FlightState {
        BOARDING,       // 0: Initial deposits, RQ allowed
        TAKE_OFF,       // 1: Moving to LP, triggers LP Strategy
        ASCENT,         // 2: Farming LP, staking enabled
        PEAK_ALTITUDE,  // 3: Threshold met, triggers Short Strategy
        DESCENT,        // 4: Short active, staking enabled
        LANDING,        // 5: Threshold met, triggers Rebalance
        TERMINAL        // 6: RQ enabled, can cycle to TAKE_OFF
    }
    
    FlightState public currentState;
    IBaal public baal;
    
    address public stakingContract;
    address public yeeter;
    
    // Cycle tracking
    uint256 public currentCycle;
    mapping(uint256 => uint256) public cycleStartTime;
    
    uint256 public constant BOARDING_DURATION = 3 days;
    uint256 public boardingStartTime;
    uint256 public boardingTarget;
    bool public boardingSuccessful;
    
    uint256 public constant TERMINAL_COOLDOWN = 5 days;
    uint256 public terminalEntryTime;
    
    IERC20 public immutable lootToken;
    uint256 public constant STAKING_THRESHOLD = 60; // 60%
    
    // Strategy contracts
    IStrategy public lpStrategy;
    IStrategy public shortStrategy;
    IStrategy public rebalanceStrategy;
    
    event FlightStateChanged(FlightState newState, uint256 cycle, uint256 timestamp);
    event NewCycleStarted(uint256 cycleNumber, uint256 timestamp);
    event BoardingStarted(uint256 startTime, uint256 target);
    event BoardingSuccessful(uint256 amountRaised, uint256 timestamp);
    event ForcedTakeoff(uint256 amountRaised, uint256 timestamp);
    event DescentInitiated(address indexed caller, uint256 timestamp);
    event TerminalEntered(address indexed caller, uint256 timestamp);
    event LPRewardsClaimed(address indexed caller, uint256 amount, uint256 timestamp);
    event ShortRewardsClaimed(address indexed caller, uint256 amount, uint256 timestamp);
    event DebtRepaid(address indexed caller, uint256 amount, uint256 timestamp);
    event StrategySet(string strategyType, address strategy);
    
    modifier onlyValidStateTransition(FlightState nextState) {
        require(_isValidTransition(currentState, nextState), "Invalid state transition");
        _;
    }
    
    modifier onlyYeeter() {
        require(msg.sender == yeeter, "Only yeeter");
        _;
    }
    
    modifier onlyStaking() {
        require(msg.sender == stakingContract, "Only staking");
        _;
    }
    
    modifier onlyLootHolder() {
        uint256 directBalance = lootToken.balanceOf(msg.sender);
        uint256 stakedBalance = IHedgeStaking(stakingContract).balanceOf(msg.sender);
        require(directBalance > 0 || stakedBalance > 0, "Not a LOOT holder");
        _;
    }
    
    modifier sufficientStaking() {
        uint256 totalStaked = IHedgeStaking(stakingContract).totalStaked();
        uint256 totalSupply = lootToken.totalSupply();
        require(totalStaked >= (totalSupply * STAKING_THRESHOLD) / 100, "Insufficient staking");
        _;
    }
    
    constructor(
        address _owner, 
        address _avatar, 
        address _target, 
        address _baal,
        address _stakingContract,
        address _yeeter,
        address _lootToken
    ) Module(_owner, _avatar, _target) {
        baal = IBaal(_baal);
        stakingContract = _stakingContract;
        yeeter = _yeeter;
        currentState = FlightState.BOARDING;
        currentCycle = 1;
        cycleStartTime[currentCycle] = block.timestamp;
        lootToken = IERC20(_lootToken);
    }
    
    function _isValidTransition(FlightState current, FlightState next) 
        internal 
        pure 
        returns (bool) 
    {
        if (next == FlightState.TAKE_OFF && current == FlightState.TERMINAL) {
            return true; // Allow cycling from TERMINAL to TAKE_OFF
        }
        return uint256(next) == uint256(current) + 1; // Must progress sequentially
    }
    
    // Called by Yeeter when capacity reached
    function initiateFlightPlan() 
        external 
        onlyYeeter 
        onlyValidStateTransition(FlightState.TAKE_OFF) 
    {
        currentState = FlightState.TAKE_OFF;
        _disableRageQuit();
        _executeLPStrategy();
        emit FlightStateChanged(FlightState.TAKE_OFF, currentCycle, block.timestamp);
    }
    
    // Automation confirms LP is active
    function confirmAscent() 
        external 
        onlyStaking 
        onlyValidStateTransition(FlightState.ASCENT) 
    {
        currentState = FlightState.ASCENT;
        emit FlightStateChanged(FlightState.ASCENT, currentCycle, block.timestamp);
    }
    
    // Called when staking threshold met during ASCENT
    function reachPeakAltitude() 
        external 
        onlyStaking 
        onlyValidStateTransition(FlightState.PEAK_ALTITUDE) 
    {
        require(currentState == FlightState.ASCENT, "Not in ascent");
        currentState = FlightState.PEAK_ALTITUDE;
        
        // Start LP exit process
        lpStrategy.initiateExit();
        
        emit FlightStateChanged(FlightState.PEAK_ALTITUDE, currentCycle, block.timestamp);
    }
    
    // Called by LPStrategy when DCA is complete
    function confirmPeakAltitude() external {
        require(msg.sender == address(lpStrategy), "Only LP Strategy");
        require(currentState == FlightState.PEAK_ALTITUDE, "Not at peak");
        
        // Initialize short strategy
        shortStrategy.initialize();
        
        currentState = FlightState.DESCENT;
        emit FlightStateChanged(FlightState.DESCENT, currentCycle, block.timestamp);
    }
    
    // Automation confirms short is active
    function confirmDescent() 
        external 
        onlyStaking 
        onlyValidStateTransition(FlightState.DESCENT) 
    {
        currentState = FlightState.DESCENT;
        emit FlightStateChanged(FlightState.DESCENT, currentCycle, block.timestamp);
    }
    
    // Called when staking threshold met during DESCENT
    function initiateLanding() 
        external 
        onlyStaking 
        onlyValidStateTransition(FlightState.LANDING) 
    {
        currentState = FlightState.LANDING;
        _executeRebalanceStrategy();
        emit FlightStateChanged(FlightState.LANDING, currentCycle, block.timestamp);
    }
    
    // Automation confirms rebalancing complete
    function enterTerminal() 
        external 
        onlyLootHolder 
        sufficientStaking 
        onlyValidStateTransition(FlightState.TERMINAL) 
    {
        require(currentState == FlightState.LANDING, "Not landing");
        currentState = FlightState.TERMINAL;
        terminalEntryTime = block.timestamp;
        _enableRageQuit();
        emit FlightStateChanged(FlightState.TERMINAL, currentCycle, block.timestamp);
        emit TerminalEntered(msg.sender, block.timestamp);
    }
    
    // Start new cycle from Terminal
    function startNewCycle() 
        external 
        onlyStaking 
        onlyValidStateTransition(FlightState.TAKE_OFF) 
    {
        require(currentState == FlightState.TERMINAL, "Must be in Terminal");
        require(
            block.timestamp >= terminalEntryTime + TERMINAL_COOLDOWN,
            "Terminal cooldown active"
        );
        
        currentCycle += 1;
        cycleStartTime[currentCycle] = block.timestamp;
        currentState = FlightState.TAKE_OFF;
        
        _disableRageQuit();
        _executeLPStrategy();
        
        emit NewCycleStarted(currentCycle, block.timestamp);
        emit FlightStateChanged(FlightState.TAKE_OFF, currentCycle, block.timestamp);
    }
    
    // Strategy execution functions
    function _executeLPStrategy() internal {
        // Execute LP strategy
    }
    
    function _executeShortStrategy() internal {
        // Execute short strategy
    }
    
    function _executeRebalanceStrategy() internal {
        // Execute rebalance strategy
    }
    
    function _enableRageQuit() internal {
        bytes memory data = abi.encodeWithSelector(
            IBaal.setRageQuit.selector,
            true
        );
        exec(address(baal), 0, data, Enum.Operation.Call);
    }
    
    function _disableRageQuit() internal {
        bytes memory data = abi.encodeWithSelector(
            IBaal.setRageQuit.selector,
            false
        );
        exec(address(baal), 0, data, Enum.Operation.Call);
    }
    
    function startBoarding(uint256 _target) external onlyOwner {
        require(currentState == FlightState.BOARDING, "Not in boarding state");
        require(boardingStartTime == 0, "Boarding already started");
        
        boardingStartTime = block.timestamp;
        boardingTarget = _target;
        
        emit BoardingStarted(boardingStartTime, boardingTarget);
    }
    
    function checkBoardingStatus() public {
        if (currentState != FlightState.BOARDING) return;
        
        bool timeExpired = block.timestamp > boardingStartTime + BOARDING_DURATION;
        uint256 currentAmount = yeeter.getTotalDeposits();
        
        if (currentAmount >= boardingTarget) {
            boardingSuccessful = true;
            emit BoardingSuccessful(currentAmount, block.timestamp);
            initiateFlightPlan();
        } else if (timeExpired) {
            // Force takeoff after 3 days if minimum viable amount reached
            uint256 minViableAmount = (boardingTarget * 75) / 100; // 75% of target
            if (currentAmount >= minViableAmount) {
                boardingSuccessful = true;
                emit ForcedTakeoff(currentAmount, block.timestamp);
                initiateFlightPlan();
            }
        }
    }
    
    function initiateDescentStrategy() 
        external 
        onlyLootHolder 
        sufficientStaking 
        onlyValidStateTransition(FlightState.DESCENT) 
    {
        require(currentState == FlightState.PEAK_ALTITUDE, "Not at peak");
        currentState = FlightState.DESCENT;
        _executeShortStrategy();
        emit FlightStateChanged(FlightState.DESCENT, currentCycle, block.timestamp);
        emit DescentInitiated(msg.sender, block.timestamp);
    }
    
    function claimLPRewards() external onlyLootHolder {
        uint256 amountClaimed = lpStrategy.claimRewards();
        emit LPRewardsClaimed(msg.sender, amountClaimed, block.timestamp);
    }
    
    function claimShortRewards() external onlyLootHolder {
        uint256 amountClaimed = shortStrategy.claimRewards();
        emit ShortRewardsClaimed(msg.sender, amountClaimed, block.timestamp);
    }
    
    function repayShortDebt(uint256 amount) external onlyLootHolder {
        shortStrategy.repayDebt(amount);
        emit DebtRepaid(msg.sender, amount, block.timestamp);
    }
    
    // Setters for strategies (onlyOwner)
    function setLPStrategy(address _strategy) external onlyOwner {
        require(_strategy != address(0), "Invalid address");
        lpStrategy = IStrategy(_strategy);
        emit StrategySet("LP", _strategy);
    }
    
    function setShortStrategy(address _strategy) external onlyOwner {
        require(_strategy != address(0), "Invalid address");
        shortStrategy = IStrategy(_strategy);
        emit StrategySet("Short", _strategy);
    }
    
    function setRebalanceStrategy(address _strategy) external onlyOwner {
        require(_strategy != address(0), "Invalid address");
        rebalanceStrategy = IStrategy(_strategy);
        emit StrategySet("Rebalance", _strategy);
    }
}
