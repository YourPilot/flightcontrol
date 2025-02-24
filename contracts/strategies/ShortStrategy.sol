// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/**
 * @title ShortStrategy
 * @notice Manages short position against AERO using USDC collateral
 * 
 * Safety Valve Mechanism:
 * This contract includes two key permissionless safety features:
 * 
 * 1. LOOT Holder Debt Repayment
 * - Any LOOT holder can repay AERO debt using treasury AERO
 * - This allows community-driven de-risking if short position becomes concerning
 * - Repayments are tracked and can be monitored by the community
 * 
 * 2. LOOT Holder Reward Claims
 * - Any LOOT holder can claim accumulated rewards to treasury
 * - Ensures rewards aren't stranded in strategy contracts
 * - Provides additional AERO to treasury for potential debt repayment
 * 
 * Safety Valve Scenario:
 * If LOOT holders decide to fully repay the AERO debt early:
 * - Position becomes un-leveraged but remains productive
 * - USDC collateral continues earning Compound supply yield
 * - USDC-AERO LP continues earning trading fees and farming rewards
 * - No liquidation risk as debt is eliminated
 * - Strategy can continue until next flight phase
 * 
 * This creates an organic risk management mechanism where:
 * - Community can actively manage risk exposure
 * - Yield generation continues even in de-risked state
 * - Strategy remains productive while awaiting next phase
 */

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/ICompound.sol";
import "../interfaces/IAerodrome.sol";

contract ShortStrategy is IStrategy, ReentrancyGuard {
    enum ShortState {
        NOT_STARTED,
        USDC_SUPPLIED,    // USDC supplied to Compound
        AERO_BORROWED,    // AERO borrowed
        AERO_SOLD,        // Half AERO sold for USDC
        LP_CREATED,       // AERO-USDC LP created
        LP_STAKED,        // LP staked in farm
        COMPLETED
    }
    
    struct PositionInfo {
        uint256 usdcSupplied;
        uint256 aeroBorrowed;
        uint256 aeroSold;
        uint256 lpTokens;
        uint256 timestamp;
    }
    
    struct LTVInfo {
        uint256 currentLTV;
        uint256 lastUpdate;
        uint256 highWaterMark;
        uint256 lowWaterMark;
    }
    
    // Constants
    uint256 public constant LTV_TARGET = 10; // 10% LTV
    uint256 public constant LTV_MAX = 15;    // 15% max LTV
    uint256 public constant LTV_MIN = 5;     // 5% min LTV
    uint256 public constant LTV_REBALANCE_THRESHOLD = 2; // Rebalance if +/- 2% from target
    uint256 public constant AERO_SELL_PERCENTAGE = 50; // Sell 50% of borrowed AERO
    
    // Contracts
    ICompound public compound;
    IAerodrome public aerodrome;
    IERC20 public usdc;
    IERC20 public aero;
    address public treasury;
    address public hedgeBaal;
    IERC20 public immutable lootToken;
    
    // State
    ShortState public currentState;
    PositionInfo public position;
    LTVInfo public ltvInfo;
    uint256 public lastHarvestTime;
    uint256 public constant HARVEST_DELAY = 1 days;
    
    // Track repayments
    struct RepaymentInfo {
        address repayer;
        uint256 amount;
        uint256 timestamp;
    }
    
    RepaymentInfo[] public repaymentHistory;
    
    // Track claims
    struct ClaimInfo {
        address claimer;
        uint256 aeroAmount;
        uint256 timestamp;
    }
    
    ClaimInfo[] public claimHistory;
    
    // Events
    event USDCSupplied(uint256 amount);
    event AEROBorrowed(uint256 amount);
    event AEROSold(uint256 amount, uint256 usdcReceived);
    event LPCreated(uint256 aeroAmount, uint256 usdcAmount, uint256 lpTokens);
    event LPStaked(uint256 lpTokens);
    event StrategyCompleted(PositionInfo position);
    event LTVUpdated(uint256 newLTV, uint256 timestamp);
    event PositionRebalanced(uint256 fromLTV, uint256 toLTV);
    event RewardsHarvested(uint256 aeroAmount, uint256 timestamp);
    event CompoundRewardsReinvested(uint256 amount, uint256 timestamp);
    event DebtRepaid(
        address indexed repayer, 
        uint256 amount, 
        uint256 remainingDebt,
        uint256 timestamp
    );
    event RewardsClaimed(
        address indexed claimer,
        uint256 aeroAmount,
        uint256 timestamp
    );
    event LPUnstaked(uint256 lpAmount, uint256 rewards, uint256 timestamp);
    event LPRemoved(uint256 aeroAmount, uint256 usdcAmount, uint256 timestamp);
    event EmergencyLPRemoved(uint256 aeroAmount, uint256 usdcAmount, uint256 timestamp);
    
    constructor(
        address _compound,
        address _aerodrome,
        address _usdc,
        address _aero,
        address _treasury,
        address _hedgeBaal,
        address _lootToken
    ) {
        compound = ICompound(_compound);
        aerodrome = IAerodrome(_aerodrome);
        usdc = IERC20(_usdc);
        aero = IERC20(_aero);
        treasury = _treasury;
        hedgeBaal = _hedgeBaal;
        lootToken = IERC20(_lootToken);
    }
    
    function initialize() external onlyHedgeBaal {
        require(currentState == ShortState.NOT_STARTED, "Already initialized");
        
        // Supply USDC to Compound
        uint256 usdcBalance = usdc.balanceOf(address(this));
        require(usdcBalance > 0, "No USDC to supply");
        
        _supplyUSDC(usdcBalance);
        currentState = ShortState.USDC_SUPPLIED;
        
        // Calculate and borrow AERO
        uint256 aeroBorrowAmount = _calculateBorrowAmount(usdcBalance);
        _borrowAERO(aeroBorrowAmount);
        currentState = ShortState.AERO_BORROWED;
        
        // Sell half of AERO for USDC
        uint256 aeroToSell = (aeroBorrowAmount * AERO_SELL_PERCENTAGE) / 100;
        _sellAERO(aeroToSell);
        currentState = ShortState.AERO_SOLD;
        
        // Create LP position
        _createAndStakeLP();
        
        emit StrategyCompleted(position);
    }
    
    function _supplyUSDC(uint256 amount) internal {
        usdc.approve(address(compound), amount);
        compound.supply(address(usdc), amount);
        
        position.usdcSupplied = amount;
        emit USDCSupplied(amount);
    }
    
    function _calculateBorrowAmount(uint256 collateralAmount) internal view returns (uint256) {
        uint256 aeroPrice = compound.getAeroPrice();
        uint256 maxBorrow = (collateralAmount * LTV_TARGET) / 100;
        return maxBorrow / aeroPrice;
    }
    
    function _borrowAERO(uint256 amount) internal {
        compound.borrow(address(aero), amount);
        
        position.aeroBorrowed = amount;
        emit AEROBorrowed(amount);
    }
    
    function _sellAERO(uint256 amount) internal {
        // Use 0x/1inch API for best execution
        aero.approve(address(aerodrome), amount);
        uint256 usdcReceived = aerodrome.swapExactTokensForTokens(
            amount,
            0, // Min amount out - should use actual slippage protection
            address(aero),
            address(usdc),
            address(this)
        );
        
        position.aeroSold = amount;
        emit AEROSold(amount, usdcReceived);
    }
    
    function _createAndStakeLP() internal {
        uint256 remainingAero = aero.balanceOf(address(this));
        uint256 availableUsdc = usdc.balanceOf(address(this));
        
        // Approve tokens for LP creation
        aero.approve(address(aerodrome), remainingAero);
        usdc.approve(address(aerodrome), availableUsdc);
        
        // Create LP tokens
        uint256 lpTokens = aerodrome.addLiquidity(
            address(aero),
            address(usdc),
            remainingAero,
            availableUsdc,
            0, // Min AERO - should use actual slippage protection
            0, // Min USDC - should use actual slippage protection
            address(this)
        );
        
        position.lpTokens = lpTokens;
        emit LPCreated(remainingAero, availableUsdc, lpTokens);
        
        // Stake LP tokens in farm
        aerodrome.stake(lpTokens);
        currentState = ShortState.LP_STAKED;
        emit LPStaked(lpTokens);
    }
    
    // Position Management Functions
    
    function updateLTV() public {
        uint256 borrowValue = compound.getBorrowValue(address(this));
        uint256 collateralValue = compound.getCollateralValue(address(this));
        uint256 newLTV = (borrowValue * 100) / collateralValue;
        
        ltvInfo.currentLTV = newLTV;
        ltvInfo.lastUpdate = block.timestamp;
        
        if (newLTV > ltvInfo.highWaterMark) {
            ltvInfo.highWaterMark = newLTV;
        }
        if (newLTV < ltvInfo.lowWaterMark || ltvInfo.lowWaterMark == 0) {
            ltvInfo.lowWaterMark = newLTV;
        }
        
        emit LTVUpdated(newLTV, block.timestamp);
        
        // Check if rebalance is needed
        if (_shouldRebalance()) {
            rebalancePosition();
        }
    }
    
    function _shouldRebalance() internal view returns (bool) {
        uint256 ltvDiff = ltvInfo.currentLTV > LTV_TARGET ? 
            ltvInfo.currentLTV - LTV_TARGET : 
            LTV_TARGET - ltvInfo.currentLTV;
            
        return ltvDiff > LTV_REBALANCE_THRESHOLD;
    }
    
    function rebalancePosition() public {
        require(_shouldRebalance(), "No rebalance needed");
        uint256 oldLTV = ltvInfo.currentLTV;
        
        if (ltvInfo.currentLTV > LTV_TARGET) {
            _reduceExposure();
        } else {
            _increaseExposure();
        }
        
        updateLTV();
        emit PositionRebalanced(oldLTV, ltvInfo.currentLTV);
    }
    
    function _reduceExposure() internal {
        // Calculate how much AERO to repay
        uint256 excessLTV = ltvInfo.currentLTV - LTV_TARGET;
        uint256 borrowValue = compound.getBorrowValue(address(this));
        uint256 repayAmount = (borrowValue * excessLTV) / ltvInfo.currentLTV;
        
        // Unstake some LP, break it, and repay
        uint256 lpToUnstake = (position.lpTokens * excessLTV) / ltvInfo.currentLTV;
        _unstakeAndBreakLP(lpToUnstake, repayAmount);
    }
    
    function _increaseExposure() internal {
        // Calculate how much more to borrow
        uint256 deficitLTV = LTV_TARGET - ltvInfo.currentLTV;
        uint256 collateralValue = compound.getCollateralValue(address(this));
        uint256 borrowAmount = (collateralValue * deficitLTV) / 100;
        
        // Borrow more AERO and create LP
        _borrowAERO(borrowAmount);
        _sellAERO(borrowAmount / 2);
        _createAndStakeLP();
    }
    
    function harvestAndReinvest() external {
        require(
            block.timestamp >= lastHarvestTime + HARVEST_DELAY,
            "Harvest delay not met"
        );
        
        // Harvest AERO rewards from LP staking
        uint256 aeroRewards = aerodrome.harvest();
        emit RewardsHarvested(aeroRewards, block.timestamp);
        
        // Sell half of rewards for USDC
        uint256 aeroToSell = aeroRewards / 2;
        _sellAERO(aeroToSell);
        
        // Create new LP position with rewards
        _createAndStakeLP();
        
        // Harvest Compound rewards if any
        uint256 compoundRewards = compound.harvest();
        if (compoundRewards > 0) {
            _reinvestCompoundRewards(compoundRewards);
        }
        
        lastHarvestTime = block.timestamp;
    }
    
    function _reinvestCompoundRewards(uint256 amount) internal {
        // Sell rewards for USDC and supply to Compound
        uint256 usdcReceived = _sellRewardsForUSDC(amount);
        _supplyUSDC(usdcReceived);
        
        emit CompoundRewardsReinvested(usdcReceived, block.timestamp);
    }
    
    // Emergency Functions
    function emergencyRepay() external onlyHedgeBaal {
        // Unstake all LP
        aerodrome.unstake(position.lpTokens);
        
        // Break LP
        (uint256 aeroAmount, uint256 usdcAmount) = aerodrome.removeLiquidity(
            position.lpTokens,
            0,
            0
        );
        
        // Repay AERO loan
        aero.approve(address(compound), aeroAmount);
        compound.repay(address(aero), aeroAmount);
        
        // Update state
        updateLTV();
    }
    
    // View Functions
    function getPositionInfo() external view returns (PositionInfo memory) {
        return position;
    }
    
    function getCurrentLTV() external view returns (uint256) {
        uint256 borrowValue = compound.getBorrowValue(address(this));
        uint256 collateralValue = compound.getCollateralValue(address(this));
        return (borrowValue * 100) / collateralValue;
    }
    
    function getFullPositionInfo() external view returns (
        PositionInfo memory pos,
        LTVInfo memory ltv,
        uint256 aeroRewards,
        uint256 compoundRewards
    ) {
        return (
            position,
            ltvInfo,
            aerodrome.pendingRewards(address(this)),
            compound.pendingRewards(address(this))
        );
    }
    
    function healthFactor() external view returns (uint256) {
        return (LTV_MAX * 100) / ltvInfo.currentLTV; // > 100 is healthy
    }
    
    /**
     * @notice Allows any Loot holder to repay AERO debt using treasury AERO
     * @param amount Amount of AERO to repay
     */
    function repayDebtFromTreasury(uint256 amount) external nonReentrant {
        // Check caller has Loot tokens
        require(lootToken.balanceOf(msg.sender) > 0, "Must hold Loot tokens");
        
        // Get current debt
        uint256 currentDebt = compound.getBorrowBalance(address(this), address(aero));
        require(currentDebt > 0, "No debt to repay");
        
        // Cap amount to current debt
        uint256 repayAmount = amount > currentDebt ? currentDebt : amount;
        
        // Check treasury has enough AERO
        uint256 treasuryAero = aero.balanceOf(treasury);
        require(treasuryAero >= repayAmount, "Insufficient AERO in treasury");
        
        // Transfer AERO from treasury
        bytes memory data = abi.encodeWithSelector(
            IERC20.transfer.selector,
            address(this),
            repayAmount
        );
        require(
            hedgeBaal.executeTransaction(
                address(aero),
                0,
                data
            ),
            "Treasury transfer failed"
        );
        
        // Repay debt
        aero.approve(address(compound), repayAmount);
        compound.repay(address(aero), repayAmount);
        
        // Update LTV
        updateLTV();
        
        // Record repayment
        repaymentHistory.push(RepaymentInfo({
            repayer: msg.sender,
            amount: repayAmount,
            timestamp: block.timestamp
        }));
        
        emit DebtRepaid(
            msg.sender,
            repayAmount,
            compound.getBorrowBalance(address(this), address(aero)),
            block.timestamp
        );
    }
    
    /**
     * @notice Get all historical repayments
     */
    function getRepaymentHistory() external view returns (RepaymentInfo[] memory) {
        return repaymentHistory;
    }
    
    /**
     * @notice Get current debt information
     */
    function getDebtInfo() external view returns (
        uint256 totalDebt,
        uint256 debtValue,
        uint256 currentLTV,
        uint256 treasuryAero
    ) {
        totalDebt = compound.getBorrowBalance(address(this), address(aero));
        debtValue = compound.getBorrowValue(address(this));
        currentLTV = ltvInfo.currentLTV;
        treasuryAero = aero.balanceOf(treasury);
    }
    
    /**
     * @notice Allow any LOOT holder to claim AERO rewards to treasury
     */
    function claimRewards() external nonReentrant {
        require(lootToken.balanceOf(msg.sender) > 0, "Not a LOOT holder");
        
        // Get pending rewards from Compound
        uint256 pendingAero = compound.getPendingRewards(address(this));
        require(pendingAero > 0, "No rewards to claim");
        
        // Claim rewards
        compound.claimRewards();
        
        // Transfer to treasury
        uint256 aeroBalance = aero.balanceOf(address(this));
        require(
            aero.transfer(treasury, aeroBalance),
            "AERO transfer failed"
        );
        
        // Record claim
        claimHistory.push(ClaimInfo({
            claimer: msg.sender,
            aeroAmount: aeroBalance,
            timestamp: block.timestamp
        }));
        
        emit RewardsClaimed(msg.sender, aeroBalance, block.timestamp);
    }
    
    /**
     * @notice Get all historical claims
     */
    function getClaimHistory() external view returns (ClaimInfo[] memory) {
        return claimHistory;
    }
    
    /**
     * @notice Unstake LP tokens and claim pending rewards
     * @return rewards Amount of AERO rewards claimed
     */
    function unstakeLP() external onlyAuthorized returns (uint256 rewards) {
        require(currentState == ShortState.LP_STAKED, "Not staked");
        
        // Claim pending rewards
        uint256 pendingRewards = aerodrome.pendingRewards(lpToken, address(this));
        if (pendingRewards > 0) {
            aerodrome.claim(lpToken);
            rewards = aeroToken.balanceOf(address(this));
            require(
                aeroToken.transfer(treasury, rewards),
                "Reward transfer failed"
            );
        }
        
        // Unstake LP
        aerodrome.unstake(position.lpTokens);
        currentState = ShortState.AERO_SOLD;
        
        emit LPUnstaked(position.lpTokens, rewards, block.timestamp);
        return rewards;
    }
    
    /**
     * @notice Remove liquidity from USDC-AERO pair
     * @param minAero Minimum AERO to receive
     * @param minUsdc Minimum USDC to receive
     * @return aeroAmount AERO received
     * @return usdcAmount USDC received
     */
    function removeLP(uint256 minAero, uint256 minUsdc) 
        external 
        onlyAuthorized 
        returns (uint256 aeroAmount, uint256 usdcAmount) 
    {
        require(currentState == ShortState.AERO_SOLD, "Must unstake first");
        
        // Approve LP tokens
        IERC20(lpToken).approve(address(aerodrome), position.lpTokens);
        
        // Remove liquidity
        (aeroAmount, usdcAmount) = aerodrome.removeLiquidity(
            address(aero),
            address(usdc),
            position.lpTokens,
            minAero,
            minUsdc,
            address(this)
        );
        
        currentState = ShortState.AERO_BORROWED;
        
        emit LPRemoved(aeroAmount, usdcAmount, block.timestamp);
        return (aeroAmount, usdcAmount);
    }
    
    /**
     * @notice Emergency function to unstake and remove LP
     * @dev Uses no slippage protection - only for emergencies
     */
    function emergencyRemoveLP() external onlyHedgeBaal {
        // Unstake LP
        aerodrome.unstake(position.lpTokens);
        
        // Remove liquidity with no slippage protection
        (uint256 aeroAmount, uint256 usdcAmount) = aerodrome.removeLiquidity(
            address(aero),
            address(usdc),
            position.lpTokens,
            0,
            0,
            address(this)
        );
        
        emit EmergencyLPRemoved(aeroAmount, usdcAmount, block.timestamp);
    }
} 