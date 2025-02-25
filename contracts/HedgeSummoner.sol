// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@daohaus/baal-contracts/contracts/BaalSummoner.sol";
import "@daohaus/baal-contracts/contracts/LootERC20.sol";

contract HedgeSummoner {
    BaalSummoner public immutable baalSummoner;
    
    struct InitialSettings {
        string lootTokenName;
        string lootTokenSymbol;
        address[] initShaman;        // Will include our HedgeBaal module
        uint256 votingPeriod;       // Set to 0 since we're not using voting
        uint256 gracePeriod;        // Set to 0 since we're not using voting
        uint256 proposalOffering;    // Set to 0 since we're not using proposals
        uint256 quorumPercent;      // Set to 0 since we're not using voting
        uint256 sponsorThreshold;    // Set to 0 since we're not using proposals
        uint256 minRetentionPercent; // Important for rage quit mechanics
    }
    
    constructor(address _baalSummoner) {
        baalSummoner = BaalSummoner(_baalSummoner);
    }
    
    function summonHedgeDAO(
        InitialSettings memory settings,
        uint256 initialLoot,
        address[] calldata initialLootRecipients,
        uint256[] calldata initialLootAmounts
    ) external returns (address baal, address lootToken) {
        // Setup initial parameters for Baal
        bytes memory initParams = abi.encode(
            settings.lootTokenName,
            settings.lootTokenSymbol,
            "",     // Shares name (unused)
            "",     // Shares symbol (unused)
            settings.initShaman,
            settings.votingPeriod,
            settings.gracePeriod,
            settings.proposalOffering,
            settings.quorumPercent,
            settings.sponsorThreshold,
            settings.minRetentionPercent
        );
        
        // Initial member setup - only Loot, no Shares
        bytes memory initializationActions = abi.encode(
            initialLootRecipients,
            uint256[](0),           // No shares amounts
            initialLootAmounts
        );
        
        // Summon the Baal DAO
        (baal, , lootToken) = baalSummoner.summonBaalAndSafe(
            initParams,
            initializationActions,
            address(0)              // No multisend
        );
        
        return (baal, lootToken);
    }
} 