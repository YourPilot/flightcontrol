// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IStrategy {
    function execute() external returns (bool);
    function validate() external view returns (bool);
    function getState() external view returns (bytes memory);
} 