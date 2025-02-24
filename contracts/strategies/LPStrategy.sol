// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IGelato.sol"; // For DCA automation
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LPStrategy is IStrategy, ReentrancyGuard {
    enum ExitState {
        NOT_STARTED,
        UNSTAKED,
        WITHDRAWN,
        DCA_ETH_STARTED,
        DCA_GHST_STARTED,
        COMPLETED
    }
    
    ExitState public exitState;
    uint256 public constant DCA_INTERVALS = 24; // 24 hour DCA
    uint256 public constant INTERVAL_SPACING = 1 hours;
    
    IGelato public gelato;
    address public treasury;
    address public lpToken;
    address public farmingContract;
    
    IERC20 public immutable lootToken;
    
    // Track claims
    struct ClaimInfo {
        address claimer;
        uint256 aeroAmount;
        uint256 timestamp;
    }
    
    ClaimInfo[] public claimHistory;
    
    event LPUnstaked(uint256 lpAmount, uint256 rewards, uint256 timestamp);
    event LPRemoved(uint256 amount0, uint256 amount1, uint256 timestamp);
    event DCAStarted(address token, uint256 amount, uint256 intervals);
    event DCACompleted(address token, uint256 finalUsdcAmount);
    event ExitCompleted(uint256 totalUsdc);
    event RewardsClaimed(
        address indexed claimer,
        uint256 aeroAmount,
        uint256 timestamp
    );
    
    constructor(
        address _treasury, 
        address _lpToken, 
        address _farmingContract,
        address _lootToken
    ) {
        treasury = _treasury;
        lpToken = _lpToken;
        farmingContract = _farmingContract;
        lootToken = IERC20(_lootToken);
    }
    
    function execute() external override returns (bool) {
        // 1. Add liquidity to create LP tokens
        // 2. Stake LP tokens in Aerodrome farm
        // ... implementation ...
        return true;
    }
    
    function validate() external view override returns (bool) {
        // Check if treasury has enough ETH and GHST
        // Check if Aerodrome farm is still active
        return true;
    }
    
    function getState() external pure override returns (bytes memory) {
        // Return current LP and farming positions
        return "";
    }
    
    function initiateExit() external onlyAuthorized {
        require(exitState == ExitState.NOT_STARTED, "Exit already started");
        
        // Unstake LP from farming contract
        _unstakeLP();
        exitState = ExitState.UNSTAKED;
        
        // Withdraw from LP
        _withdrawLP();
        exitState = ExitState.WITHDRAWN;
        
        // Start DCA for ETH
        _startDCAForToken(address(0), "ETH_TO_USDC");
        exitState = ExitState.DCA_ETH_STARTED;
        
        // Start DCA for GHST
        _startDCAForToken(ghstToken, "GHST_TO_USDC");
        exitState = ExitState.DCA_GHST_STARTED;
    }
    
    function _startDCAForToken(address token, string memory taskId) internal {
        uint256 amount = IERC20(token).balanceOf(address(this));
        uint256 amountPerInterval = amount / DCA_INTERVALS;
        
        // Setup Gelato DCA task
        gelato.createTask(
            taskId,
            address(this),
            abi.encodeWithSelector(
                this.executeDCAInterval.selector,
                token,
                amountPerInterval
            ),
            INTERVAL_SPACING
        );
        
        emit DCAStarted(token, amount, DCA_INTERVALS);
    }
    
    function executeDCAInterval(address token, uint256 amount) external {
        require(msg.sender == address(gelato), "Only Gelato");
        
        // Use 0x/1inch API for best execution
        // Convert token amount to USDC
        // ... implementation ...
        
        if (_isDCAComplete(token)) {
            emit DCACompleted(token, totalUsdcForToken);
            _checkExitComplete();
        }
    }
    
    function _checkExitComplete() internal {
        if (_isDCAComplete(address(0)) && _isDCAComplete(ghstToken)) {
            exitState = ExitState.COMPLETED;
            emit ExitCompleted(totalUsdcBalance);
            
            // Signal HedgeBaal to move to next state
            hedgeBaal.confirmPeakAltitude();
        }
    }
    
    /**
     * @notice Allow any LOOT holder to claim AERO rewards to treasury
     */
    function claimRewards() external nonReentrant {
        require(lootToken.balanceOf(msg.sender) > 0, "Not a LOOT holder");
        
        // Get pending rewards
        uint256 pendingAero = aerodrome.pendingRewards(lpToken, address(this));
        require(pendingAero > 0, "No rewards to claim");
        
        // Claim rewards
        aerodrome.claim(lpToken);
        
        // Transfer to treasury
        uint256 aeroBalance = aeroToken.balanceOf(address(this));
        require(
            aeroToken.transfer(treasury, aeroBalance),
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
        require(exitState == ExitState.NOT_STARTED, "Already unstaked");
        
        // Claim any pending rewards first
        uint256 pendingRewards = aerodrome.pendingRewards(lpToken, address(this));
        if (pendingRewards > 0) {
            aerodrome.claim(lpToken);
            rewards = aeroToken.balanceOf(address(this));
            require(
                aeroToken.transfer(treasury, rewards),
                "Reward transfer failed"
            );
        }
        
        // Get LP balance and unstake
        uint256 lpBalance = IERC20(lpToken).balanceOf(address(this));
        require(lpBalance > 0, "No LP to unstake");
        
        aerodrome.unstake(lpBalance);
        exitState = ExitState.UNSTAKED;
        
        emit LPUnstaked(lpBalance, rewards, block.timestamp);
        return rewards;
    }
    
    /**
     * @notice Remove liquidity from Aerodrome pair
     * @param minToken0 Minimum amount of token0 to receive
     * @param minToken1 Minimum amount of token1 to receive
     * @return amount0 Amount of token0 received
     * @return amount1 Amount of token1 received
     */
    function removeLP(uint256 minToken0, uint256 minToken1) 
        external 
        onlyAuthorized 
        returns (uint256 amount0, uint256 amount1) 
    {
        require(exitState == ExitState.UNSTAKED, "Must unstake first");
        
        uint256 lpBalance = IERC20(lpToken).balanceOf(address(this));
        require(lpBalance > 0, "No LP to remove");
        
        // Approve LP tokens
        IERC20(lpToken).approve(address(aerodrome), lpBalance);
        
        // Remove liquidity
        (amount0, amount1) = aerodrome.removeLiquidity(
            lpToken,
            lpBalance,
            minToken0,
            minToken1,
            address(this)
        );
        
        exitState = ExitState.WITHDRAWN;
        
        emit LPRemoved(amount0, amount1, block.timestamp);
        return (amount0, amount1);
    }
} 