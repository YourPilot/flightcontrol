// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/**
 * @title IStrategy
 * @notice Interface for flight path strategies
 */
interface IStrategy {
    /**
     * @notice Check if conditions are met to execute this strategy
     * @return bool True if strategy can be executed
     */
    function validate() external view returns (bool);
    
    /**
     * @notice Execute the strategy's actions for the current flight state
     * @return bool True if execution successful
     */
    function execute() external returns (bool);
    
    /**
     * @notice Get current strategy position/state
     * @return bytes Encoded position data
     */
    function getState() external view returns (bytes memory);
} 