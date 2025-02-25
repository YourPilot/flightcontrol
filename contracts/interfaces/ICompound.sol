// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface ICompound {
    function collateralBalanceOf(address account, address asset) external view returns (uint256);
    function borrowBalanceOf(address account) external view returns (uint256);
    function getCollateralReserves(address asset) external view returns (uint256);
    function getPrice(address asset) external view returns (uint256);
    function getSupplyRate(uint256 utilization) external view returns (uint256);
    function getBorrowRate(uint256 utilization) external view returns (uint256);
    function baseTokenPriceFeed() external view returns (address);
    function baseToken() external view returns (address);
    function getCollateralFactor(address token) external view returns (uint256);
    function getCompAccrued(address account) external view returns (uint256);
    function supply(address asset, uint256 amount) external;
    function borrow(address asset, uint256 amount) external;
    function repay(address asset, uint256 amount) external;
    function getBorrowValue(address account) external view returns (uint256);
    function getCollateralValue(address account) external view returns (uint256);
    function getBorrowBalance(address account, address asset) external view returns (uint256);
    function getAeroPrice() external view returns (uint256);
    function getPendingRewards(address account) external view returns (uint256);
    function claimRewards() external;
    function harvest() external returns (uint256);
    function rewardsToken() external view returns (address);
}  