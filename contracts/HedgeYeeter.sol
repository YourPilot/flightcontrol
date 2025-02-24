// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./HedgeBaal.sol";

contract HedgeYeeter is ReentrancyGuard {
    HedgeBaal public hedgeBaal;
    
    uint256 public totalDeposits;
    mapping(address => uint256) public deposits;
    
    event Deposited(address indexed user, uint256 amount);
    
    constructor(address _hedgeBaal) {
        hedgeBaal = HedgeBaal(_hedgeBaal);
    }
    
    function deposit() external payable nonReentrant {
        require(msg.value > 0, "Cannot deposit 0");
        require(hedgeBaal.currentState() == HedgeBaal.FlightState.BOARDING, "Not in boarding");
        require(
            block.timestamp <= hedgeBaal.boardingStartTime() + hedgeBaal.BOARDING_DURATION(),
            "Boarding ended"
        );
        
        deposits[msg.sender] += msg.value;
        totalDeposits += msg.value;
        
        emit Deposited(msg.sender, msg.value);
        
        // Check if we've hit the target
        hedgeBaal.checkBoardingStatus();
    }
    
    function getTotalDeposits() external view returns (uint256) {
        return totalDeposits;
    }
    
    // If boarding fails (didn't reach minimum viable amount)
    function withdrawDeposit() external nonReentrant {
        require(
            block.timestamp > hedgeBaal.boardingStartTime() + hedgeBaal.BOARDING_DURATION(),
            "Boarding still active"
        );
        require(!hedgeBaal.boardingSuccessful(), "Boarding was successful");
        
        uint256 amount = deposits[msg.sender];
        require(amount > 0, "No deposit to withdraw");
        
        deposits[msg.sender] = 0;
        totalDeposits -= amount;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
    }
} 