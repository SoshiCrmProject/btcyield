// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Initializable} from "@oz-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@oz-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@oz-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@oz-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStBTC} from "../interfaces/IStBTC.sol";
import {IStrategyManager} from "../interfaces/IStrategyManager.sol";
import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";

/**
 * @title BTCStakingVault
 * @author BTCYield Team
 * @notice Main staking vault for Bitcoin yield generation
 * @dev Implements UUPS upgradeable pattern with comprehensive security features
 */
contract BTCStakingVault is 
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public constant MAX_FEE = 1000; // 10%
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MIN_DEPOSIT = 0.001 ether; // 0.001 BTC minimum
    uint256 public constant LOCK_PERIOD_MULTIPLIER = 365 days;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Wrapped Bitcoin token
    IERC20 public wBTC;
    
    /// @notice Liquid staking token
    IStBTC public stBTC;
    
    /// @notice Strategy manager for yield generation
    IStrategyManager public strategyManager;
    
    /// @notice Reward distributor contract
    IRewardDistributor public rewardDistributor;
    
    /// @notice Total assets under management
    uint256 public totalAssets;
    
    /// @notice Platform fee (in basis points)
    uint256 public platformFee;
    
    /// @notice Performance fee (in basis points)
    uint256 public performanceFee;
    
    /// @notice Treasury address for fee collection
    address public treasury;
    
    /// @notice Emergency withdrawal enabled flag
    bool public emergencyWithdrawEnabled;

    /// @notice User stake information
    struct StakeInfo {
        uint256 amount;          // Amount of wBTC staked
        uint256 shares;          // Amount of stBTC received
        uint256 lockEndTime;     // Lock period end timestamp
        uint256 lastRewardTime;  // Last reward calculation time
        uint256 accumulatedRewards; // Accumulated rewards
        bool autoCompound;       // Auto-compound rewards flag
    }

    /// @notice Mapping of user addresses to their stakes
    mapping(address => StakeInfo[]) public userStakes;
    
    /// @notice Total shares minted
    uint256 public totalShares;
    
    /// @notice Withdrawal queue for large withdrawals
    struct WithdrawalRequest {
        address user;
        uint256 shares;
        uint256 requestTime;
        bool processed;
    }
    
    WithdrawalRequest[] public withdrawalQueue;
    
    /// @notice Deposit limits
    uint256 public maxDepositAmount;
    uint256 public dailyDepositLimit;
    mapping(uint256 => uint256) public dailyDeposits; // day => amount

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Staked(
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 lockPeriod,
        uint256 indexed stakeId
    );
    
    event Unstaked(
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 indexed stakeId
    );
    
    event RewardsClaimed(
        address indexed user,
        uint256 amount,
        uint256 indexed stakeId
    );
    
    event StrategyUpdated(
        address indexed oldStrategy,
        address indexed newStrategy
    );
    
    event FeesUpdated(
        uint256 platformFee,
        uint256 performanceFee
    );
    
    event EmergencyWithdraw(
        address indexed user,
        uint256 amount
    );
    
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount();
    error InsufficientBalance();
    error StakeLocked();
    error InvalidAddress();
    error FeeTooHigh();
    error DepositLimitExceeded();
    error WithdrawalRequestPending();
    error NoRewardsToClaim();
    error InvalidStakeId();
    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the staking vault
     * @param _wBTC Address of wrapped Bitcoin token
     * @param _stBTC Address of liquid staking token
     * @param _strategyManager Address of strategy manager
     * @param _treasury Address of treasury
     */
    function initialize(
        address _wBTC,
        address _stBTC,
        address _strategyManager,
        address _treasury
    ) public initializer {
        if (_wBTC == address(0) || _stBTC == address(0) || 
            _strategyManager == address(0) || _treasury == address(0)) {
            revert InvalidAddress();
        }

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        wBTC = IERC20(_wBTC);
        stBTC = IStBTC(_stBTC);
        strategyManager = IStrategyManager(_strategyManager);
        treasury = _treasury;

        platformFee = 200; // 2%
        performanceFee = 2000; // 20%
        maxDepositAmount = 100 ether; // 100 BTC per transaction
        dailyDepositLimit = 1000 ether; // 1000 BTC per day

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(GUARDIAN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake wBTC tokens for stBTC
     * @param amount Amount of wBTC to stake
     * @param lockPeriod Lock period in days (0 for flexible)
     * @param autoCompound Enable auto-compounding
     * @return stakeId The ID of the created stake
     */
    function stake(
        uint256 amount,
        uint256 lockPeriod,
        bool autoCompound
    ) external nonReentrant whenNotPaused returns (uint256 stakeId) {
        if (amount < MIN_DEPOSIT) revert InvalidAmount();
        if (amount > maxDepositAmount) revert DepositLimitExceeded();
        
        // Check daily limit
        uint256 today = block.timestamp / 1 days;
        if (dailyDeposits[today] + amount > dailyDepositLimit) {
            revert DepositLimitExceeded();
        }
        dailyDeposits[today] += amount;

        // Transfer wBTC from user
        wBTC.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate shares based on current exchange rate
        uint256 shares = _convertToShares(amount);
        
        // Mint stBTC to user
        stBTC.mint(msg.sender, shares);

        // Create stake record
        StakeInfo memory newStake = StakeInfo({
            amount: amount,
            shares: shares,
            lockEndTime: lockPeriod > 0 ? block.timestamp + (lockPeriod * 1 days) : 0,
            lastRewardTime: block.timestamp,
            accumulatedRewards: 0,
            autoCompound: autoCompound
        });

        stakeId = userStakes[msg.sender].length;
        userStakes[msg.sender].push(newStake);

        // Update totals
        totalAssets += amount;
        totalShares += shares;

        // Deploy funds to strategy
        strategyManager.deposit(amount);

        emit Staked(msg.sender, amount, shares, lockPeriod, stakeId);
    }

    /**
     * @notice Unstake tokens and burn stBTC
     * @param stakeId ID of the stake to withdraw
     * @param shares Amount of shares to unstake
     */
    function unstake(
        uint256 stakeId,
        uint256 shares
    ) external nonReentrant whenNotPaused {
        StakeInfo storage stakeInfo = _getStake(msg.sender, stakeId);
        
        if (shares > stakeInfo.shares) revert InsufficientBalance();
        if (block.timestamp < stakeInfo.lockEndTime) revert StakeLocked();

        // Calculate amount to return based on current exchange rate
        uint256 amount = _convertToAssets(shares);
        
        // Update stake info
        stakeInfo.shares -= shares;
        stakeInfo.amount = _convertToAssets(stakeInfo.shares);
        
        // Update totals
        totalShares -= shares;
        totalAssets -= amount;

        // Burn stBTC from user
        stBTC.burn(msg.sender, shares);

        // Process withdrawal
        if (amount > _getAvailableLiquidity()) {
            // Queue for withdrawal if not enough liquidity
            withdrawalQueue.push(WithdrawalRequest({
                user: msg.sender,
                shares: shares,
                requestTime: block.timestamp,
                processed: false
            }));
            revert WithdrawalRequestPending();
        } else {
            // Withdraw from strategy and transfer to user
            strategyManager.withdraw(amount);
            wBTC.safeTransfer(msg.sender, amount);
        }

        emit Unstaked(msg.sender, amount, shares, stakeId);
    }

    /**
     * @notice Claim accumulated rewards
     * @param stakeId ID of the stake to claim rewards for
     */
    function claimRewards(uint256 stakeId) external nonReentrant whenNotPaused {
        StakeInfo storage stakeInfo = _getStake(msg.sender, stakeId);
        
        uint256 rewards = _calculateRewards(msg.sender, stakeId);
        if (rewards == 0) revert NoRewardsToClaim();

        stakeInfo.lastRewardTime = block.timestamp;
        stakeInfo.accumulatedRewards = 0;

        if (stakeInfo.autoCompound) {
            // Convert rewards to shares and add to stake
            uint256 newShares = _convertToShares(rewards);
            stakeInfo.shares += newShares;
            totalShares += newShares;
            stBTC.mint(msg.sender, newShares);
        } else {
            // Transfer rewards to user
            wBTC.safeTransfer(msg.sender, rewards);
        }

        emit RewardsClaimed(msg.sender, rewards, stakeId);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Convert assets to shares based on current exchange rate
     */
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        if (totalAssets == 0 || totalShares == 0) {
            return assets;
        }
        return assets.mulDiv(totalShares, totalAssets, Math.Rounding.Down);
    }

    /**
     * @dev Convert shares to assets based on current exchange rate
     */
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        if (totalShares == 0) {
            return shares;
        }
        return shares.mulDiv(totalAssets, totalShares, Math.Rounding.Down);
    }

    /**
     * @dev Get user stake by ID with validation
     */
    function _getStake(address user, uint256 stakeId) internal view returns (StakeInfo storage) {
        if (stakeId >= userStakes[user].length) revert InvalidStakeId();
        return userStakes[user][stakeId];
    }

    /**
     * @dev Calculate pending rewards for a stake
     */
    function _calculateRewards(address user, uint256 stakeId) internal view returns (uint256) {
        StakeInfo memory stakeInfo = userStakes[user][stakeId];
        
        uint256 timeElapsed = block.timestamp - stakeInfo.lastRewardTime;
        uint256 shareValue = _convertToAssets(stakeInfo.shares);
        
        // Get APY from strategy manager
        uint256 apy = strategyManager.getCurrentAPY();
        
        // Calculate rewards (simplified - actual implementation would be more complex)
        uint256 rewards = shareValue.mulDiv(apy * timeElapsed, 365 days * FEE_DENOMINATOR);
        
        // Add lock bonus (up to 50% extra for 1 year lock)
        if (stakeInfo.lockEndTime > 0) {
            uint256 lockDuration = stakeInfo.lockEndTime - (stakeInfo.lastRewardTime + timeElapsed);
            uint256 lockBonus = rewards.mulDiv(lockDuration, 2 * LOCK_PERIOD_MULTIPLIER);
            rewards += lockBonus;
        }
        
        return rewards + stakeInfo.accumulatedRewards;
    }

    /**
     * @dev Get available liquidity in the vault
     */
    function _getAvailableLiquidity() internal view returns (uint256) {
        return wBTC.balanceOf(address(this)) + strategyManager.getAvailableLiquidity();
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update strategy manager
     * @param newStrategyManager Address of new strategy manager
     */
    function setStrategyManager(address newStrategyManager) external onlyRole(ADMIN_ROLE) {
        if (newStrategyManager == address(0)) revert InvalidAddress();
        
        address oldStrategy = address(strategyManager);
        strategyManager = IStrategyManager(newStrategyManager);
        
        emit StrategyUpdated(oldStrategy, newStrategyManager);
    }

    /**
     * @notice Update fees
     * @param _platformFee New platform fee
     * @param _performanceFee New performance fee
     */
    function setFees(uint256 _platformFee, uint256 _performanceFee) external onlyRole(ADMIN_ROLE) {
        if (_platformFee > MAX_FEE || _performanceFee > MAX_FEE) revert FeeTooHigh();
        
        platformFee = _platformFee;
        performanceFee = _performanceFee;
        
        emit FeesUpdated(_platformFee, _performanceFee);
    }

    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(ADMIN_ROLE) {
        if (newTreasury == address(0)) revert InvalidAddress();
        
        address oldTreasury = treasury;
        treasury = newTreasury;
        
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                         EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enable emergency withdrawals
     */
    function enableEmergencyWithdraw() external onlyRole(GUARDIAN_ROLE) {
        emergencyWithdrawEnabled = true;
    }

    /**
     * @notice Emergency withdraw function
     * @param stakeId ID of stake to emergency withdraw
     */
    function emergencyWithdraw(uint256 stakeId) external nonReentrant {
        if (!emergencyWithdrawEnabled) revert Unauthorized();
        
        StakeInfo storage stakeInfo = _getStake(msg.sender, stakeId);
        uint256 amount = stakeInfo.amount;
        uint256 shares = stakeInfo.shares;
        
        // Clear stake
        delete userStakes[msg.sender][stakeId];
        
        // Update totals
        totalAssets -= amount;
        totalShares -= shares;
        
        // Burn stBTC
        stBTC.burn(msg.sender, shares);
        
        // Transfer available balance
        uint256 available = Math.min(amount, wBTC.balanceOf(address(this)));
        if (available > 0) {
            wBTC.safeTransfer(msg.sender, available);
        }
        
        emit EmergencyWithdraw(msg.sender, available);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get user's total staked amount
     * @param user Address of the user
     * @return total Total staked amount in wBTC
     */
    function getUserTotalStaked(address user) external view returns (uint256 total) {
        StakeInfo[] memory stakes = userStakes[user];
        for (uint256 i = 0; i < stakes.length; i++) {
            total += _convertToAssets(stakes[i].shares);
        }
    }

    /**
     * @notice Get pending rewards for a user's stake
     * @param user Address of the user
     * @param stakeId ID of the stake
     * @return rewards Pending rewards amount
     */
    function getPendingRewards(address user, uint256 stakeId) external view returns (uint256) {
        return _calculateRewards(user, stakeId);
    }

    /**
     * @notice Get current exchange rate (assets per share)
     * @return rate Current exchange rate
     */
    function getExchangeRate() external view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return totalAssets.mulDiv(1e18, totalShares);
    }

    /**
     * @notice Get user's stakes count
     * @param user Address of the user
     * @return count Number of stakes
     */
    function getUserStakesCount(address user) external view returns (uint256) {
        return userStakes[user].length;
    }

    /*//////////////////////////////////////////////////////////////
                          UPGRADE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Authorize upgrade to a new implementation
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}