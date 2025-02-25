// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IBaal {
    function submitProposal(bytes[] calldata proposalData, uint256 expiration) external returns (uint256);
    function sponsorProposal(uint256 id) external;
    function executeProposal(uint256 id, bytes[] memory proposalData) external;
    function shamans(address) external view returns (uint256);
    function setRageQuit(bool enabled) external;
} 