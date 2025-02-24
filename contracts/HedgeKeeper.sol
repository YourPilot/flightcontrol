// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

contract HedgeKeeper is AutomationCompatibleInterface {
    HedgeDAO public dao;
    
    function checkUpkeep(bytes calldata) external view override returns (bool, bytes memory) {
        // Check if staking threshold is met
        VaultInfo memory info = dao.vaultInfo();
        bool thresholdMet = info.totalStaked >= 
            (info.stakingThreshold * dao.lootToken().totalSupply()) / 100;
            
        return (thresholdMet, "");
    }
    
    function performUpkeep(bytes calldata) external override {
        // Trigger strategy transition
        dao.executeNextStrategy();
    }
} 