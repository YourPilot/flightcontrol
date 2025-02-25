// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IHedgeYeeter {
    function getTotalDeposits() external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
} 