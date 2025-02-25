// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IBaal.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IHedgeYeeter.sol";

interface IAvatar {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) external returns (bool success);
}

interface IModule {
    function avatar() external view returns (address);
    function target() external view returns (address);
}

enum Operation {
    Call,
    DelegateCall
}

contract HedgeBaal is ReentrancyGuard {
    address public owner;
    IAvatar public avatar;  // The Gnosis Safe
    address public target;  // Usually same as avatar
    IBaal public baal;
    IHedgeYeeter public yeeter;  // Add yeeter reference
    
    // Boarding state
    uint256 public constant BOARDING_DURATION = 3 days;
    uint256 public boardingStartTime;
    uint256 public boardingTarget;
    bool public boardingSuccessful;
    
    enum FlightState {
        BOARDING,       // Initial deposits
        TAKE_OFF,      // Moving to LP
        ASCENT,        // Farming LP
        PEAK_ALTITUDE, // Ready for Short
        DESCENT,       // Short active
        LANDING,       // Closing positions
        TERMINAL       // Done
    }

    FlightState public currentState;
    IStrategy public lpStrategy;
    IStrategy public shortStrategy;
    IStrategy public rebalanceStrategy;
    
    event StateTransition(FlightState from, FlightState to);
    event BoardingSuccessful(uint256 amount, uint256 timestamp);
    event ForcedTakeoff(uint256 amount, uint256 timestamp);
    
    constructor(
        address _owner,
        address _avatar,
        address _target,
        address _baal,
        address _yeeter
    ) {
        owner = _owner;
        avatar = IAvatar(_avatar);
        target = _target;
        baal = IBaal(_baal);
        yeeter = IHedgeYeeter(_yeeter);
        currentState = FlightState.BOARDING;
        boardingStartTime = block.timestamp;
    }
    
    // Add these modifiers
    modifier onlyAvatar() {
        require(msg.sender == address(avatar), "Only avatar can call");
        _;
    }

    modifier onlyValidStateTransition(FlightState nextState) {
        require(
            uint256(nextState) == uint256(currentState) + 1,
            "Invalid state transition"
        );
        _;
    }

    function initiateFlightPlan() public onlyAvatar onlyValidStateTransition(FlightState.TAKE_OFF) {
        require(currentState == FlightState.BOARDING, "Must be in BOARDING state");
        require(boardingSuccessful, "Boarding must be successful");
        
        // Execute LP strategy
        _executeLPStrategy();
        
        // Update state
        FlightState previousState = currentState;
        currentState = FlightState.TAKE_OFF;
        emit StateTransition(previousState, currentState);
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
            uint256 minViableAmount = (boardingTarget * 75) / 100; // 75% of target
            if (currentAmount >= minViableAmount) {
                boardingSuccessful = true;
                emit ForcedTakeoff(currentAmount, block.timestamp);
                initiateFlightPlan();
            }
        }
    }
    
    function _executeLPStrategy() internal {
        require(address(lpStrategy) != address(0), "LP strategy not set");
        require(lpStrategy.execute(), "LP strategy failed");
    }
    
    function executeTransaction(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) internal returns (bool success) {
        success = avatar.execTransactionFromModule(
            to,
            value,
            data,
            operation
        );
        require(success, "Transaction execution failed");
    }
}
