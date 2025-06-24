// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IRewardDistributor {
    function notifyRewardAmount(uint256 reward) external;
    function getRewardForDuration() external view returns (uint256);
    function lastTimeRewardApplicable() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function claimReward(address account) external returns (uint256);
    function setRewardsDuration(uint256 _rewardsDuration) external;
}
