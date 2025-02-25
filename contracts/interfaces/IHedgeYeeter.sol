// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IHedgeYeeter {
    function deposit() external payable;
    function withdrawDeposit() external;
    function deposits(address) external view returns (uint256);
    function totalDeposits() external view returns (uint256);
} 