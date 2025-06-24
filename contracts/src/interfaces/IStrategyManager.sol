// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IStrategyManager {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external returns (uint256);
    function getTotalAssets() external view returns (uint256);
    function getCurrentAPY() external view returns (uint256);
    function getAvailableLiquidity() external view returns (uint256);
    function harvest(address strategy) external;
    function harvestAll() external;
    function rebalance() external;
    function emergencyWithdrawAll() external;
}
