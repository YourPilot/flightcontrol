// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IAerodrome.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LPStrategy is IStrategy, ReentrancyGuard {
    enum ExitState {
        NOT_STARTED,
        UNSTAKED,
        WITHDRAWN,
        COMPLETED
    }
    
    ExitState public exitState;
    address public treasury;
    address public lpToken;
    address public token0;
    address public token1;
    bool public isStable;
    
    IERC20 public immutable lootToken;
    IERC20 public immutable aeroToken;
    IAerodrome public immutable aerodrome;
    
    // Track claims
    struct ClaimInfo {
        address claimer;
        uint256 aeroAmount;
        uint256 timestamp;
    }
    
    ClaimInfo[] public claimHistory;
    
    event LPUnstaked(uint256 lpAmount, uint256 rewards, uint256 timestamp);
    event LPRemoved(uint256 amount0, uint256 amount1, uint256 timestamp);
    event ExitCompleted(uint256 totalUsdc);
    event RewardsClaimed(
        address indexed claimer,
        uint256 aeroAmount,
        uint256 timestamp
    );
    
    constructor(
        address _treasury,
        address _lpToken,
        address _token0,
        address _token1,
        address _lootToken,
        address _aeroToken,
        address _aerodrome,
        bool _isStable
    ) {
        treasury = _treasury;
        lpToken = _lpToken;
        token0 = _token0;
        token1 = _token1;
        lootToken = IERC20(_lootToken);
        aeroToken = IERC20(_aeroToken);
        aerodrome = IAerodrome(_aerodrome);
        isStable = _isStable;
    }
    
    function execute() external override returns (bool) {
        // Get balances
        uint256 amount0 = IERC20(token0).balanceOf(address(this));
        uint256 amount1 = IERC20(token1).balanceOf(address(this));
        
        // Add liquidity to Aerodrome
        (,, uint256 liquidity) = aerodrome.addLiquidity(
            token0,
            token1,
            isStable,
            amount0,
            amount1,
            0, // amountAMin
            0, // amountBMin
            address(this),
            block.timestamp
        );
        
        // Stake LP tokens in Aerodrome farm
        aerodrome.deposit(lpToken, liquidity);
        
        return true;
    }
    
    function validate() external view override returns (bool) {
        // Check if we have tokens to provide liquidity
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        
        return balance0 > 0 && balance1 > 0;
    }
    
    function getState() external pure override returns (bytes memory) {
        // Return current LP and farming positions
        return "";
    }
    
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
    
    function getClaimHistory() external view returns (ClaimInfo[] memory) {
        return claimHistory;
    }
} 