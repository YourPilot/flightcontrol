// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "../interfaces/IStrategy.sol";
import "../oracle/NAVCalculator.sol";

contract RebalanceStrategy is IStrategy {
    NAVCalculator public immutable navCalculator;
    address public immutable treasury;
    
    enum RebalanceState {
        NOT_STARTED,
        AERO_PURCHASED,    // Buy AERO for veAERO
        AERO_LOCKED,       // Lock AERO in veAERO
        ETH_CONVERTED,     // Convert remaining to ETH
        COMPLETED
    }
    
    RebalanceState public currentState;
    uint256 public constant AERO_ALLOCATION_PERCENT = 20; // 20% to veAERO
    
    constructor(address _navCalculator, address _treasury) {
        navCalculator = NAVCalculator(_navCalculator);
        treasury = _treasury;
    }
    
    function execute() external override returns (bool) {
        require(currentState == RebalanceState.NOT_STARTED, "Already started");
        
        // Get current value and PnL
        (int256 pnlInETH,) = navCalculator.calculatePnL();
        require(pnlInETH > 0, "Negative PnL");
        
        // Calculate AERO allocation from profits
        uint256 aeroAllocation = (uint256(pnlInETH) * AERO_ALLOCATION_PERCENT) / 100;
        
        // Buy and lock AERO
        _purchaseAERO(aeroAllocation);
        currentState = RebalanceState.AERO_PURCHASED;
        
        _lockAERO();
        currentState = RebalanceState.AERO_LOCKED;
        
        // Convert everything else to ETH
        _convertRemainingToETH();
        currentState = RebalanceState.ETH_CONVERTED;
        
        currentState = RebalanceState.COMPLETED;
        return true;
    }
    
    function validate() external view override returns (bool) {
        // Check if rebalancing is needed based on NAV
        (int256 pnlInETH,) = navCalculator.calculatePnL();
        return pnlInETH > 0; // Only rebalance if profitable
    }
    
    function getState() external view override returns (bytes memory) {
        return abi.encode(currentState);
    }
} 