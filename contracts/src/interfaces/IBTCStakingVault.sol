// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IBTCStakingVault {
    struct StakeInfo {
        uint256 amount;
        uint256 shares;
        uint256 lockEndTime;
        uint256 lastRewardTime;
        uint256 accumulatedRewards;
        bool autoCompound;
    }

    function stake(uint256 amount, uint256 lockPeriod, bool autoCompound) external returns (uint256);
    function unstake(uint256 stakeId, uint256 shares) external;
    function claimRewards(uint256 stakeId) external;
    function getUserTotalStaked(address user) external view returns (uint256);
    function getPendingRewards(address user, uint256 stakeId) external view returns (uint256);
    function getExchangeRate() external view returns (uint256);
    function totalAssets() external view returns (uint256);
}
