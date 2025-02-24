// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

contract NAVCalculator {
    address public immutable priceOracle;
    address public immutable lootToken;
    
    constructor(address _priceOracle, address _lootToken) {
        priceOracle = _priceOracle;
        lootToken = _lootToken;
    }
    
    function calculateNAV() external view returns (uint256) {
        // Get total vault value from oracle
        // Divide by total loot supply
        // Return NAV per loot token
        return 0;
    }
    
    function getHistoricalPerformance(uint256 startTime, uint256 endTime) 
        external 
        view 
        returns (int256) 
    {
        // Calculate performance over time period
        return 0;
    }
    
    /**
     * @notice Get spot AERO balance in treasury
     * @return amount AERO amount (18 decimals)
     * @return valueInUSD AERO value in USD (6 decimals)
     */
    function getSpotAEROPosition() external view returns (uint256 amount, uint256 valueInUSD) {
        amount = aeroToken.balanceOf(address(hedgeBaal));
        (, int256 aeroPrice,,,) = aeroUsdPriceFeed.latestRoundData();
        valueInUSD = (amount * uint256(aeroPrice)) / 1e30; // Convert to 6 decimals
    }
    
    /**
     * @notice Get USDC collateral in Compound
     * @return amount USDC amount (6 decimals)
     * @return collateralFactor Current collateral factor (percentage)
     */
    function getUSDCCollateral() external view returns (uint256 amount, uint256 collateralFactor) {
        amount = compound.getCollateralAmount(address(hedgeBaal), address(usdcToken));
        collateralFactor = compound.getCollateralFactor(address(usdcToken));
    }
    
    /**
     * @notice Get AERO debt from Compound
     * @return amount AERO borrowed (18 decimals)
     * @return valueInUSD Debt value in USD (6 decimals)
     */
    function getAERODebt() external view returns (uint256 amount, uint256 valueInUSD) {
        amount = compound.getBorrowAmount(address(hedgeBaal), address(aeroToken));
        (, int256 aeroPrice,,,) = aeroUsdPriceFeed.latestRoundData();
        valueInUSD = (amount * uint256(aeroPrice)) / 1e30;
    }
    
    /**
     * @notice Get LP position details
     * @return ethAeroLPValue Value of ETH-AERO LP in USD (6 decimals)
     * @return usdcAeroLPValue Value of USDC-AERO LP in USD (6 decimals)
     * @return totalLPValue Combined LP value in USD (6 decimals)
     */
    function getLPPositions() external view returns (
        uint256 ethAeroLPValue,
        uint256 usdcAeroLPValue,
        uint256 totalLPValue
    ) {
        address ethAeroLP = aerodrome.getPair(address(wethToken), address(aeroToken));
        address usdcAeroLP = aerodrome.getPair(address(usdcToken), address(aeroToken));
        
        ethAeroLPValue = _calculateSingleLPValue(ethAeroLP, IERC20(ethAeroLP).balanceOf(address(hedgeBaal)));
        usdcAeroLPValue = _calculateSingleLPValue(usdcAeroLP, IERC20(usdcAeroLP).balanceOf(address(hedgeBaal)));
        totalLPValue = ethAeroLPValue + usdcAeroLPValue;
    }
    
    /**
     * @notice Get current borrow rate from Compound
     * @return borrowAPR Annual borrow rate (percentage with 2 decimals)
     * @return borrowAPY Annual borrow APY (percentage with 2 decimals)
     */
    function getBorrowRates() external view returns (uint256 borrowAPR, uint256 borrowAPY) {
        borrowAPR = compound.getBorrowRate(address(aeroToken));
        borrowAPY = _calculateAPY(borrowAPR);
    }
    
    /**
     * @notice Get current yield rates from Aerodrome
     * @return baseAPR Base LP fees APR (percentage with 2 decimals)
     * @return rewardAPR AERO rewards APR (percentage with 2 decimals)
     * @return totalAPY Combined APY (percentage with 2 decimals)
     */
    function getYieldRates() external view returns (
        uint256 baseAPR,
        uint256 rewardAPR,
        uint256 totalAPY
    ) {
        address ethAeroLP = aerodrome.getPair(address(wethToken), address(aeroToken));
        baseAPR = aerodrome.getBaseAPR(ethAeroLP);
        rewardAPR = aerodrome.getRewardAPR(ethAeroLP);
        totalAPY = _calculateAPY(baseAPR + rewardAPR);
    }
    
    /**
     * @notice Get health factor of the position
     * @return healthFactor Current health factor (percentage with 2 decimals)
     * @return liquidationThreshold Liquidation threshold (percentage with 2 decimals)
     */
    function getHealthFactor() external view returns (uint256 healthFactor, uint256 liquidationThreshold) {
        (uint256 collateralValue, uint256 debtValue) = (
            compound.getCollateralValue(address(hedgeBaal)),
            compound.getBorrowValue(address(hedgeBaal))
        );
        healthFactor = debtValue > 0 ? (collateralValue * 10000) / debtValue : type(uint256).max;
        liquidationThreshold = compound.getLiquidationThreshold(address(aeroToken));
    }
    
    /**
     * @notice Get pending rewards
     * @return aeroRewards Unclaimed AERO rewards (18 decimals)
     * @return compRewards Unclaimed COMP rewards (18 decimals)
     * @return totalValueUSD Total rewards value in USD (6 decimals)
     */
    function getPendingRewards() external view returns (
        uint256 aeroRewards,
        uint256 compRewards,
        uint256 totalValueUSD
    ) {
        address ethAeroLP = aerodrome.getPair(address(wethToken), address(aeroToken));
        aeroRewards = aerodrome.pendingRewards(ethAeroLP, address(hedgeBaal));
        compRewards = compound.getPendingRewards(address(hedgeBaal));
        
        (, int256 aeroPrice,,,) = aeroUsdPriceFeed.latestRoundData();
        totalValueUSD = (aeroRewards * uint256(aeroPrice)) / 1e30;
        // Add COMP rewards value if needed
    }
    
    /**
     * @notice Get current profit/loss metrics
     * @return unrealizedPnL Unrealized PnL in USD (6 decimals, signed)
     * @return realizedPnL Realized PnL in USD (6 decimals)
     * @return currentDrawdown Current drawdown from peak (percentage with 2 decimals)
     */
    function getProfitMetrics() external view returns (
        int256 unrealizedPnL,
        uint256 realizedPnL,
        uint256 currentDrawdown
    ) {
        // Implementation depends on how you want to track P&L
    }
    
    /**
     * @notice Helper to calculate APY from APR
     */
    function _calculateAPY(uint256 apr) internal pure returns (uint256) {
        return ((1e4 + (apr / 365)) ** 365) - 1e4;
    }

    // Entry value tracking
    uint256 public entryValueInETH;
    uint256 public entryTimestamp;
    
    event EntryValueRecorded(uint256 valueInETH, uint256 timestamp);
    
    /**
     * @notice Record entry value in ETH terms for PnL tracking
     */
    function recordEntryValue() external onlyAuthorized {
        // Calculate total value in USD
        uint256 totalValueUSD = _calculateTotalValue();
        
        // Convert to ETH using price feed
        (, int256 ethPrice,,,) = ethUsdPriceFeed.latestRoundData();
        entryValueInETH = (totalValueUSD * 1e18) / uint256(ethPrice);
        entryTimestamp = block.timestamp;
        
        emit EntryValueRecorded(entryValueInETH, block.timestamp);
    }
    
    /**
     * @notice Calculate PnL in ETH terms
     * @return pnlInETH Current PnL in ETH (18 decimals, signed)
     * @return pnlPercent Percentage return (2 decimals, signed)
     */
    function calculatePnL() external view returns (int256 pnlInETH, int256 pnlPercent) {
        require(entryValueInETH > 0, "No entry value recorded");
        
        uint256 currentValueUSD = _calculateTotalValue();
        (, int256 ethPrice,,,) = ethUsdPriceFeed.latestRoundData();
        uint256 currentValueETH = (currentValueUSD * 1e18) / uint256(ethPrice);
        
        pnlInETH = int256(currentValueETH) - int256(entryValueInETH);
        pnlPercent = (pnlInETH * 10000) / int256(entryValueInETH);
    }
} 