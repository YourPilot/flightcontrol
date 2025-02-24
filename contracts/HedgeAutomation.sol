// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import "./HedgeBaal.sol";
import "./HedgeStaking.sol";

contract HedgeAutomation is AutomationCompatibleInterface {
    HedgeBaal public hedgeBaal;
    HedgeStaking public staking;
    
    constructor(address _hedgeBaal, address _staking) {
        hedgeBaal = HedgeBaal(_hedgeBaal);
        staking = HedgeStaking(_staking);
    }
    
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory) {
        HedgeBaal.FlightState state = hedgeBaal.currentState();
        
        if (state == HedgeBaal.FlightState.PEAK_ALTITUDE) {
            return (true, abi.encode("INITIATE_DESCENT"));
        }
        
        if (state == HedgeBaal.FlightState.LANDING) {
            return (true, abi.encode("ENTER_TERMINAL"));
        }
        
        return (false, "");
    }
    
    function performUpkeep(bytes calldata) external override {
        HedgeBaal.FlightState state = hedgeBaal.currentState();
        
        if (state == HedgeBaal.FlightState.PEAK_ALTITUDE) {
            hedgeBaal.initiateDescentStrategy();
        } else if (state == HedgeBaal.FlightState.LANDING) {
            hedgeBaal.enterTerminal();
        }
    }
} 