// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IStrategy {
    function deposit(uint256 amount) external returns (uint256);
    function withdraw(uint256 amount) external returns (uint256);
    function harvest() external returns (uint256);
    function emergencyWithdraw() external returns (uint256);
    function estimatedTotalAssets() external view returns (uint256);
    function estimatedAPY() external view returns (uint256);
    function isActive() external view returns (bool);
    function name() external view returns (string memory);
}
