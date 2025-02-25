// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/ICompound.sol";
import "../interfaces/IAerodrome.sol";

contract NAVCalculator {
    address public immutable priceOracle;
    address public immutable lootToken;
    
    address public owner;
    mapping(address => bool) public authorized;

    ICompound public immutable compound;
    IAerodrome public immutable aerodrome;
    IERC20 public immutable aeroToken;
    IERC20 public immutable wethToken;
    IERC20 public immutable usdcToken;
    address public immutable hedgeBaal;
    
    AggregatorV3Interface public immutable aeroUsdPriceFeed;
    AggregatorV3Interface public immutable ethUsdPriceFeed;

    modifier onlyAuthorized() {
        require(authorized[msg.sender] || msg.sender == owner, "Not authorized");
        _;
    }

    constructor(
        address _priceOracle,
        address _lootToken,
        address _compound,
        address _aerodrome,
        address _aeroToken,
        address _wethToken,
        address _usdcToken,
        address _hedgeBaal,
        address _aeroUsdPriceFeed,
        address _ethUsdPriceFeed
    ) {
        priceOracle = _priceOracle;
        lootToken = _lootToken;
        compound = ICompound(_compound);
        aerodrome = IAerodrome(_aerodrome);
        aeroToken = IERC20(_aeroToken);
        wethToken = IERC20(_wethToken);
        usdcToken = IERC20(_usdcToken);
        hedgeBaal = _hedgeBaal;
        aeroUsdPriceFeed = AggregatorV3Interface(_aeroUsdPriceFeed);
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        owner = msg.sender;
        authorized[msg.sender] = true;
    }
    
    /**
     * @notice Add or remove authorized addresses
     * @param account Address to modify authorization for
     * @param isAuthorized True to authorize, false to revoke
     */
    function setAuthorized(address account, bool isAuthorized) external {
        require(msg.sender == owner, "Only owner");
        authorized[account] = isAuthorized;
    }
    
    function calculateNAV() external view returns (uint256) {
        uint256 totalValue = _calculateTotalValue();
        uint256 totalSupply = IERC20(lootToken).totalSupply();
        return totalSupply > 0 ? (totalValue * 1e18) / totalSupply : 0;
    }
    
    function getHistoricalPerformance(uint256 startTime, uint256 endTime) 
        external 
        view 
        returns (int256) 
    {
        require(startTime < endTime, "Invalid time range");
        require(endTime <= block.timestamp, "End time in future");
        
        // This would need historical price data storage
        // Could be implemented by storing periodic snapshots of NAV
        revert("Historical performance tracking not implemented");
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
        amount = compound.collateralBalanceOf(address(hedgeBaal), address(usdcToken));
        collateralFactor = compound.getCollateralFactor(address(usdcToken));
    }
    
    /**
     * @notice Get AERO debt from Compound
     * @return amount AERO borrowed (18 decimals)
     * @return valueInUSD Debt value in USD (6 decimals)
     */
    function getAERODebt() external view returns (uint256 amount, uint256 valueInUSD) {
        amount = compound.borrowBalanceOf(address(hedgeBaal));
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
        address ethAeroLP = aerodrome.poolFor(address(wethToken), address(aeroToken));
        address usdcAeroLP = aerodrome.poolFor(address(usdcToken), address(aeroToken));
        
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
        uint256 utilization = compound.borrowBalanceOf(address(hedgeBaal)) * 1e18 / compound.getCollateralReserves(address(aeroToken));
        borrowAPR = compound.getBorrowRate(utilization);
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
        address ethAeroLP = aerodrome.poolFor(address(wethToken), address(aeroToken));
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
            compound.collateralBalanceOf(address(hedgeBaal), address(usdcToken)),
            compound.borrowBalanceOf(address(hedgeBaal))
        );
        healthFactor = debtValue > 0 ? (collateralValue * 10000) / debtValue : type(uint256).max;
        liquidationThreshold = compound.getCollateralFactor(address(usdcToken));
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
        address ethAeroLP = aerodrome.poolFor(address(wethToken), address(aeroToken));
        aeroRewards = aerodrome.pendingRewards(ethAeroLP, address(hedgeBaal));
        compRewards = compound.getCompAccrued(address(hedgeBaal));
        
        (, int256 aeroPrice,,,) = aeroUsdPriceFeed.latestRoundData();
        totalValueUSD = (aeroRewards * uint256(aeroPrice)) / 1e30;
        
        // Add COMP rewards value
        (, int256 ethPrice,,,) = ethUsdPriceFeed.latestRoundData();
        // Assuming COMP price is denominated in ETH, convert to USD
        uint256 compValueUSD = (compRewards * uint256(ethPrice)) / 1e18;
        totalValueUSD += compValueUSD;
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
        require(entryValueInETH > 0, "No entry value recorded");
        
        uint256 currentValueUSD = _calculateTotalValue();
        (, int256 ethPrice,,,) = ethUsdPriceFeed.latestRoundData();
        uint256 currentValueETH = (currentValueUSD * 1e18) / uint256(ethPrice);
        
        unrealizedPnL = int256(currentValueETH) - int256(entryValueInETH);
        
        // These values are returned but not calculated yet
        realizedPnL = 0;
        currentDrawdown = 0; // Needs peak value tracking
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

    /**
     * @notice Calculate value of a single LP position
     * @param lpToken Address of LP token
     * @param balance Balance of LP tokens
     * @return valueUSD Value in USD (6 decimals)
     */
    function _calculateSingleLPValue(address lpToken, uint256 balance) internal view returns (uint256 valueUSD) {
        if (balance == 0) return 0;
        
        (uint256 reserve0, uint256 reserve1,) = IAerodrome(lpToken).getReserves();
        uint256 totalSupply = IERC20(lpToken).totalSupply();
        
        // Calculate share of reserves
        uint256 share0 = (reserve0 * balance) / totalSupply;
        uint256 share1 = (reserve1 * balance) / totalSupply;
        
        // Get token prices and calculate value
        (, int256 aeroPrice,,,) = aeroUsdPriceFeed.latestRoundData();
        
        // Assuming one token is always AERO, adjust calculation based on pair
        if (IAerodrome(lpToken).token0() == address(aeroToken)) {
            valueUSD = (share0 * uint256(aeroPrice)) / 1e30;
            // Add value of other token (ETH or USDC)
            if (IAerodrome(lpToken).token1() == address(wethToken)) {
                (, int256 ethPrice,,,) = ethUsdPriceFeed.latestRoundData();
                valueUSD += (share1 * uint256(ethPrice)) / 1e30;
            } else {
                valueUSD += share1; // USDC is already in USD terms with 6 decimals
            }
        } else {
            valueUSD = (share1 * uint256(aeroPrice)) / 1e30;
            // Add value of other token (ETH or USDC)
            if (IAerodrome(lpToken).token0() == address(wethToken)) {
                (, int256 ethPrice,,,) = ethUsdPriceFeed.latestRoundData();
                valueUSD += (share0 * uint256(ethPrice)) / 1e30;
            } else {
                valueUSD += share0; // USDC is already in USD terms with 6 decimals
            }
        }
    }

    /**
     * @notice Calculate total value of all positions
     * @return totalValueUSD Total value in USD (6 decimals)
     */
    function _calculateTotalValue() internal view returns (uint256 totalValueUSD) {
        (, uint256 spotValue) = this.getSpotAEROPosition();
        
        (,, uint256 totalLpValue) = this.getLPPositions();
        
        (uint256 usdcCollateral,) = this.getUSDCCollateral();
        
        (, uint256 debtValue) = this.getAERODebt();
        
        totalValueUSD = spotValue + totalLpValue + usdcCollateral - debtValue;
    }
} 