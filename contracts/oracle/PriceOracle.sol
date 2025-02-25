// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/**
 * @title PriceOracle
 * @notice Provides price data for the HedgeBaal system
 * 
 * Required Chainlink Price Feeds on Base:
 * - ETH/USD: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70
 * - AERO/USD: Not yet available - will need Chainlink to deploy
 * 
 * Alternative Sources if needed:
 * 1. Aerodrome TWAP
 *    - Can use LP spot price + TWAP for AERO
 *    - Requires implementing IUniswapV2Pair interface
 * 
 * 2. Redstone Oracles
 *    - Could provide AERO price feed
 *    - Requires RedstoneConsumerBase implementation
 * 
 * 3. API3 QRNG
 *    - Could provide additional price verification
 *    - Requires QRNG consumer contract
 * 
 * Current Implementation:
 * - Uses Chainlink as primary source
 * - 1 hour freshness threshold
 * - Normalizes all prices to USD with 6 decimals
 */

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PriceOracle is Ownable {
    // Current Price Feeds
    AggregatorV3Interface public immutable ethUsdFeed;
    AggregatorV3Interface public immutable aeroUsdFeed;
    
    /**
     * Future Price Feeds to Consider:
     * 
     * Stablecoins (for deviation checking):
     * - USDC/USD
     * - DAI/USD
     * 
     * L1 Tokens:
     * - BTC/USD
     * - CRV/USD
     * 
     * Base Ecosystem:
     * - COMP/USD
     * - Other Base native tokens
     * 
     * LP Token Pricing:
     * - Could add specific LP token pricing logic
     * - Would need spot + TWAP implementation
     * - Consider Aerodrome's volatile vs stable pairs
     */
    
    // Stale price threshold
    uint256 public constant PRICE_FRESHNESS_THRESHOLD = 1 hours;
    
    // Events
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);
    event FeedUpdated(address indexed token, address feed);
    
    constructor(
        address _ethUsdFeed,
        address _aeroUsdFeed
    ) {
        ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
        aeroUsdFeed = AggregatorV3Interface(_aeroUsdFeed);
    }
    
    /**
     * @notice Get the USD price of ETH
     * @return price ETH/USD price with 8 decimals
     */
    function getEthPrice() public view returns (uint256 price) {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethUsdFeed.latestRoundData();
        
        require(answer > 0, "ETH price <= 0");
        require(updatedAt >= block.timestamp - PRICE_FRESHNESS_THRESHOLD, "Stale ETH price");
        require(answeredInRound >= roundId, "Stale ETH round");
        
        return uint256(answer);
    }
    
    /**
     * @notice Get the USD price of AERO
     * @return price AERO/USD price with 8 decimals
     */
    function getAeroPrice() public view returns (uint256 price) {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aeroUsdFeed.latestRoundData();
        
        require(answer > 0, "AERO price <= 0");
        require(updatedAt >= block.timestamp - PRICE_FRESHNESS_THRESHOLD, "Stale AERO price");
        require(answeredInRound >= roundId, "Stale AERO round");
        
        return uint256(answer);
    }
    
    /**
     * @notice Get both ETH and AERO prices
     * @return ethPrice ETH/USD price with 8 decimals
     * @return aeroPrice AERO/USD price with 8 decimals
     */
    function getBothPrices() external view returns (uint256 ethPrice, uint256 aeroPrice) {
        return (getEthPrice(), getAeroPrice());
    }
    
    /**
     * @notice Convert ETH amount to USD
     * @param ethAmount Amount of ETH (18 decimals)
     * @return usdAmount Amount in USD (6 decimals)
     */
    function ethToUsd(uint256 ethAmount) external view returns (uint256 usdAmount) {
        uint256 ethPrice = getEthPrice();
        return (ethAmount * ethPrice) / 1e20; // Convert to 6 decimals
    }
    
    /**
     * @notice Convert AERO amount to USD
     * @param aeroAmount Amount of AERO (18 decimals)
     * @return usdAmount Amount in USD (6 decimals)
     */
    function aeroToUsd(uint256 aeroAmount) external view returns (uint256 usdAmount) {
        uint256 aeroPrice = getAeroPrice();
        return (aeroAmount * aeroPrice) / 1e20; // Convert to 6 decimals
    }
    
    /**
     * @notice Check if prices are fresh
     * @return ethFresh Whether ETH price is fresh
     * @return aeroFresh Whether AERO price is fresh
     */
    function arePricesFresh() external view returns (bool ethFresh, bool aeroFresh) {
        (, , , uint256 ethUpdatedAt, ) = ethUsdFeed.latestRoundData();
        (, , , uint256 aeroUpdatedAt, ) = aeroUsdFeed.latestRoundData();
        
        ethFresh = ethUpdatedAt >= block.timestamp - PRICE_FRESHNESS_THRESHOLD;
        aeroFresh = aeroUpdatedAt >= block.timestamp - PRICE_FRESHNESS_THRESHOLD;
    }
    
    /**
     * @notice Get price feed details
     * @return ethDecimals ETH feed decimals
     * @return aeroDecimals AERO feed decimals
     * @return ethDescription ETH feed description
     * @return aeroDescription AERO feed description
     */
    function getFeedDetails() external view returns (
        uint8 ethDecimals,
        uint8 aeroDecimals,
        string memory ethDescription,
        string memory aeroDescription
    ) {
        ethDecimals = ethUsdFeed.decimals();
        aeroDecimals = aeroUsdFeed.decimals();
        ethDescription = ethUsdFeed.description();
        aeroDescription = aeroUsdFeed.description();
    }
} 