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

import {IStrategy} from "../interfaces/IStrategy.sol";

/**
 * @title StrategyManager
 * @author BTCYield Team
 * @notice Manages multiple yield strategies and optimizes capital allocation
 * @dev Implements sophisticated allocation algorithms with risk management
 */
contract StrategyManager is
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

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public constant MAX_STRATEGIES = 20;
    uint256 public constant ALLOCATION_PRECISION = 10000; // 100.00%
    uint256 public constant MAX_SLIPPAGE = 300; // 3%
    uint256 public constant REBALANCE_THRESHOLD = 500; // 5%

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Wrapped Bitcoin token
    IERC20 public wBTC;

    /// @notice BTCYield staking vault
    address public vault;

    /// @notice Active strategies
    address[] public strategies;

    /// @notice Strategy information
    struct StrategyInfo {
        bool isActive;
        uint256 allocation; // Target allocation in basis points
        uint256 deposited; // Amount currently deposited
        uint256 debt; // Outstanding debt to vault
        uint256 lastReport; // Last report timestamp
        uint256 performanceFee; // Strategy performance fee
        uint256 riskScore; // Risk score (1-100)
        uint256 maxDeposit; // Maximum deposit allowed
    }

    /// @notice Mapping of strategy addresses to their info
    mapping(address => StrategyInfo) public strategyInfo;

    /// @notice Total assets under management
    uint256 public totalDeposited;

    /// @notice Harvest cooldown period
    uint256 public harvestCooldown;

    /// @notice Last harvest timestamp for each strategy
    mapping(address => uint256) public lastHarvest;

    /// @notice Emergency exit mode
    bool public emergencyExit;

    /// @notice Profit sharing configuration
    uint256 public platformFee; // Fee taken from profits
    address public treasury; // Treasury address for fees

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event StrategyAdded(
        address indexed strategy,
        uint256 allocation,
        uint256 performanceFee
    );

    event StrategyRemoved(address indexed strategy);

    event StrategyUpdated(
        address indexed strategy,
        uint256 allocation,
        uint256 performanceFee
    );

    event Deposited(
        address indexed strategy,
        uint256 amount
    );

    event Withdrawn(
        address indexed strategy,
        uint256 amount
    );

    event Harvested(
        address indexed strategy,
        uint256 profit,
        uint256 loss,
        uint256 fee
    );

    event Rebalanced(
        uint256 totalDeposited,
        uint256 timestamp
    );

    event EmergencyExitEnabled();

    event FeesUpdated(
        uint256 platformFee,
        address treasury
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidStrategy();
    error StrategyNotActive();
    error TooManyStrategies();
    error InvalidAllocation();
    error InvalidAddress();
    error InsufficientBalance();
    error HarvestCooldown();
    error WithdrawalFailed();
    error StrategyLimitExceeded();
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
     * @notice Initialize the strategy manager
     * @param _wBTC Address of wrapped Bitcoin token
     * @param _vault Address of the staking vault
     * @param _treasury Address of the treasury
     */
    function initialize(
        address _wBTC,
        address _vault,
        address _treasury
    ) public initializer {
        if (_wBTC == address(0) || _vault == address(0) || _treasury == address(0)) {
            revert InvalidAddress();
        }

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        wBTC = IERC20(_wBTC);
        vault = _vault;
        treasury = _treasury;

        harvestCooldown = 6 hours;
        platformFee = 1000; // 10%

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(STRATEGIST_ROLE, msg.sender);
        _grantRole(GUARDIAN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                         STRATEGY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a new strategy
     * @param strategy Address of the strategy contract
     * @param allocation Target allocation in basis points
     * @param performanceFee Performance fee for the strategy
     * @param riskScore Risk score (1-100)
     * @param maxDeposit Maximum deposit allowed
     */
    function addStrategy(
        address strategy,
        uint256 allocation,
        uint256 performanceFee,
        uint256 riskScore,
        uint256 maxDeposit
    ) external onlyRole(STRATEGIST_ROLE) {
        if (strategy == address(0)) revert InvalidAddress();
        if (strategies.length >= MAX_STRATEGIES) revert TooManyStrategies();
        if (strategyInfo[strategy].isActive) revert InvalidStrategy();
        if (allocation > ALLOCATION_PRECISION) revert InvalidAllocation();
        if (riskScore == 0 || riskScore > 100) revert InvalidStrategy();

        strategies.push(strategy);
        
        strategyInfo[strategy] = StrategyInfo({
            isActive: true,
            allocation: allocation,
            deposited: 0,
            debt: 0,
            lastReport: block.timestamp,
            performanceFee: performanceFee,
            riskScore: riskScore,
            maxDeposit: maxDeposit
        });

        emit StrategyAdded(strategy, allocation, performanceFee);
    }

    /**
     * @notice Remove a strategy
     * @param strategy Address of the strategy to remove
     */
    function removeStrategy(address strategy) external onlyRole(STRATEGIST_ROLE) {
        StrategyInfo storage info = strategyInfo[strategy];
        if (!info.isActive) revert StrategyNotActive();

        // Withdraw all funds from strategy
        if (info.deposited > 0) {
            _withdrawFromStrategy(strategy, info.deposited);
        }

        // Remove from active strategies array
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i] == strategy) {
                strategies[i] = strategies[strategies.length - 1];
                strategies.pop();
                break;
            }
        }

        // Mark as inactive
        info.isActive = false;
        info.allocation = 0;

        emit StrategyRemoved(strategy);
    }

    /**
     * @notice Update strategy allocation
     * @param strategy Address of the strategy
     * @param allocation New allocation in basis points
     */
    function updateStrategyAllocation(
        address strategy,
        uint256 allocation
    ) external onlyRole(STRATEGIST_ROLE) {
        StrategyInfo storage info = strategyInfo[strategy];
        if (!info.isActive) revert StrategyNotActive();
        if (allocation > ALLOCATION_PRECISION) revert InvalidAllocation();

        info.allocation = allocation;

        emit StrategyUpdated(strategy, allocation, info.performanceFee);
    }

    /*//////////////////////////////////////////////////////////////
                          DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit funds from vault
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external onlyRole(VAULT_ROLE) nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAllocation();
        
        // Transfer wBTC from vault
        wBTC.safeTransferFrom(msg.sender, address(this), amount);
        
        // Allocate to strategies based on target allocations
        _allocateToStrategies(amount);
        
        totalDeposited += amount;
    }

    /**
     * @notice Withdraw funds to vault
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external onlyRole(VAULT_ROLE) nonReentrant returns (uint256) {
        if (amount == 0) revert InvalidAllocation();
        
        uint256 available = wBTC.balanceOf(address(this));
        
        // If not enough idle funds, withdraw from strategies
        if (available < amount) {
            uint256 needed = amount - available;
            _withdrawFromStrategies(needed);
            available = wBTC.balanceOf(address(this));
        }
        
        uint256 toWithdraw = Math.min(amount, available);
        if (toWithdraw == 0) revert InsufficientBalance();
        
        // Transfer to vault
        wBTC.safeTransfer(vault, toWithdraw);
        totalDeposited -= toWithdraw;
        
        return toWithdraw;
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allocate funds to strategies based on target allocations
     */
    function _allocateToStrategies(uint256 amount) internal {
        uint256 totalAllocation = _getTotalAllocation();
        if (totalAllocation == 0) return;

        uint256 remaining = amount;

        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            StrategyInfo storage info = strategyInfo[strategy];
            
            if (!info.isActive || info.allocation == 0) continue;

            // Calculate amount for this strategy
            uint256 strategyAmount = amount.mulDiv(info.allocation, totalAllocation);
            
            // Check max deposit limit
            if (info.deposited + strategyAmount > info.maxDeposit) {
                strategyAmount = info.maxDeposit > info.deposited ? 
                    info.maxDeposit - info.deposited : 0;
            }

            if (strategyAmount > 0 && strategyAmount <= remaining) {
                // Approve and deposit to strategy
                wBTC.safeApprove(strategy, strategyAmount);
                IStrategy(strategy).deposit(strategyAmount);
                
                info.deposited += strategyAmount;
                remaining -= strategyAmount;
                
                emit Deposited(strategy, strategyAmount);
            }
        }

        // Keep any remaining as idle balance for liquidity
    }

    /**
     * @dev Withdraw from strategies proportionally
     */
    function _withdrawFromStrategies(uint256 amount) internal {
        uint256 totalInStrategies = _getTotalDeposited();
        if (totalInStrategies == 0) return;

        uint256 withdrawn = 0;

        for (uint256 i = 0; i < strategies.length && withdrawn < amount; i++) {
            address strategy = strategies[i];
            StrategyInfo storage info = strategyInfo[strategy];
            
            if (!info.isActive || info.deposited == 0) continue;

            // Calculate proportional withdrawal
            uint256 strategyShare = amount.mulDiv(info.deposited, totalInStrategies);
            uint256 toWithdraw = Math.min(strategyShare, info.deposited);
            
            if (toWithdraw > 0) {
                uint256 balanceBefore = wBTC.balanceOf(address(this));
                
                // Withdraw from strategy
                uint256 actualWithdrawn = IStrategy(strategy).withdraw(toWithdraw);
                
                uint256 balanceAfter = wBTC.balanceOf(address(this));
                uint256 received = balanceAfter - balanceBefore;
                
                info.deposited -= actualWithdrawn;
                withdrawn += received;
                
                emit Withdrawn(strategy, actualWithdrawn);
            }
        }
    }

    /**
     * @dev Withdraw from a specific strategy
     */
    function _withdrawFromStrategy(address strategy, uint256 amount) internal returns (uint256) {
        uint256 balanceBefore = wBTC.balanceOf(address(this));
        
        uint256 withdrawn = IStrategy(strategy).withdraw(amount);
        
        uint256 balanceAfter = wBTC.balanceOf(address(this));
        uint256 received = balanceAfter - balanceBefore;
        
        strategyInfo[strategy].deposited -= withdrawn;
        
        emit Withdrawn(strategy, withdrawn);
        
        return received;
    }

    /**
     * @dev Get total allocation across all strategies
     */
    function _getTotalAllocation() internal view returns (uint256 total) {
        for (uint256 i = 0; i < strategies.length; i++) {
            StrategyInfo storage info = strategyInfo[strategies[i]];
            if (info.isActive) {
                total += info.allocation;
            }
        }
    }

    /**
     * @dev Get total deposited across all strategies
     */
    function _getTotalDeposited() internal view returns (uint256 total) {
        for (uint256 i = 0; i < strategies.length; i++) {
            StrategyInfo storage info = strategyInfo[strategies[i]];
            if (info.isActive) {
                total += info.deposited;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                          HARVEST FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Harvest profits from a strategy
     * @param strategy Address of the strategy to harvest
     */
    function harvest(address strategy) external nonReentrant whenNotPaused {
        StrategyInfo storage info = strategyInfo[strategy];
        if (!info.isActive) revert StrategyNotActive();
        
        // Check cooldown
        if (block.timestamp < lastHarvest[strategy] + harvestCooldown) {
            revert HarvestCooldown();
        }
        
        lastHarvest[strategy] = block.timestamp;
        
        // Get current value in strategy
        uint256 currentValue = IStrategy(strategy).estimatedTotalAssets();
        uint256 debt = info.deposited;
        
        uint256 profit = 0;
        uint256 loss = 0;
        
        if (currentValue > debt) {
            profit = currentValue - debt;
        } else {
            loss = debt - currentValue;
        }
        
        // Report to strategy and collect profits
        uint256 harvested = IStrategy(strategy).harvest();
        
        // Calculate fees
        uint256 performanceFee = 0;
        uint256 platformFeeAmount = 0;
        
        if (profit > 0) {
            performanceFee = profit.mulDiv(info.performanceFee, ALLOCATION_PRECISION);
            platformFeeAmount = profit.mulDiv(platformFee, ALLOCATION_PRECISION);
            
            // Transfer platform fee to treasury
            if (platformFeeAmount > 0 && wBTC.balanceOf(address(this)) >= platformFeeAmount) {
                wBTC.safeTransfer(treasury, platformFeeAmount);
            }
        }
        
        // Update debt
        info.deposited = currentValue - performanceFee;
        info.lastReport = block.timestamp;
        
        emit Harvested(strategy, profit, loss, performanceFee + platformFeeAmount);
    }

    /**
     * @notice Harvest all strategies
     */
    function harvestAll() external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            if (strategyInfo[strategy].isActive && 
                block.timestamp >= lastHarvest[strategy] + harvestCooldown) {
                try this.harvest(strategy) {} catch {}
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         REBALANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Rebalance strategies to match target allocations
     */
    function rebalance() external onlyRole(STRATEGIST_ROLE) nonReentrant whenNotPaused {
        uint256 totalValue = getTotalAssets();
        uint256 totalAllocation = _getTotalAllocation();
        
        if (totalValue == 0 || totalAllocation == 0) return;
        
        // Calculate target amounts for each strategy
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            StrategyInfo storage info = strategyInfo[strategy];
            
            if (!info.isActive) continue;
            
            uint256 targetAmount = totalValue.mulDiv(info.allocation, totalAllocation);
            uint256 currentAmount = info.deposited;
            
            // Check if rebalance is needed (> 5% deviation)
            uint256 deviation = targetAmount > currentAmount ? 
                targetAmount - currentAmount : currentAmount - targetAmount;
                
            if (deviation.mulDiv(ALLOCATION_PRECISION, targetAmount) > REBALANCE_THRESHOLD) {
                if (targetAmount > currentAmount) {
                    // Need to deposit more
                    uint256 toDeposit = targetAmount - currentAmount;
                    uint256 available = wBTC.balanceOf(address(this));
                    
                    if (available >= toDeposit) {
                        wBTC.safeApprove(strategy, toDeposit);
                        IStrategy(strategy).deposit(toDeposit);
                        info.deposited += toDeposit;
                        emit Deposited(strategy, toDeposit);
                    }
                } else {
                    // Need to withdraw
                    uint256 toWithdraw = currentAmount - targetAmount;
                    _withdrawFromStrategy(strategy, toWithdraw);
                }
            }
        }
        
        emit Rebalanced(totalValue, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                         EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enable emergency exit mode
     */
    function enableEmergencyExit() external onlyRole(GUARDIAN_ROLE) {
        emergencyExit = true;
        _pause();
        emit EmergencyExitEnabled();
    }

    /**
     * @notice Emergency withdraw all funds from strategies
     */
    function emergencyWithdrawAll() external onlyRole(GUARDIAN_ROLE) {
        if (!emergencyExit) revert Unauthorized();
        
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            StrategyInfo storage info = strategyInfo[strategy];
            
            if (info.deposited > 0) {
                try IStrategy(strategy).emergencyWithdraw() returns (uint256 withdrawn) {
                    info.deposited = 0;
                    emit Withdrawn(strategy, withdrawn);
                } catch {
                    // Strategy doesn't support emergency withdraw
                    try this._withdrawFromStrategy(strategy, info.deposited) {} catch {}
                }
            }
        }
        
        // Transfer all funds back to vault
        uint256 balance = wBTC.balanceOf(address(this));
        if (balance > 0) {
            wBTC.safeTransfer(vault, balance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update harvest cooldown
     * @param _cooldown New cooldown period in seconds
     */
    function setHarvestCooldown(uint256 _cooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        harvestCooldown = _cooldown;
    }

    /**
     * @notice Update fees
     * @param _platformFee New platform fee in basis points
     * @param _treasury New treasury address
     */
    function setFees(uint256 _platformFee, address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_platformFee > 3000) revert InvalidAllocation(); // Max 30%
        if (_treasury == address(0)) revert InvalidAddress();
        
        platformFee = _platformFee;
        treasury = _treasury;
        
        emit FeesUpdated(_platformFee, _treasury);
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
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        emergencyExit = false;
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get total assets across all strategies
     * @return total Total value of assets
     */
    function getTotalAssets() public view returns (uint256 total) {
        // Idle balance
        total = wBTC.balanceOf(address(this));
        
        // Assets in strategies
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            if (strategyInfo[strategy].isActive) {
                try IStrategy(strategy).estimatedTotalAssets() returns (uint256 assets) {
                    total += assets;
                } catch {
                    // If strategy fails, use last known deposited amount
                    total += strategyInfo[strategy].deposited;
                }
            }
        }
    }

    /**
     * @notice Get current APY across all strategies
     * @return apy Weighted average APY
     */
    function getCurrentAPY() external view returns (uint256 apy) {
        uint256 totalAllocation = _getTotalAllocation();
        if (totalAllocation == 0) return 0;
        
        uint256 weightedAPY = 0;
        
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            StrategyInfo storage info = strategyInfo[strategy];
            
            if (info.isActive && info.allocation > 0) {
                try IStrategy(strategy).estimatedAPY() returns (uint256 strategyAPY) {
                    weightedAPY += strategyAPY.mulDiv(info.allocation, totalAllocation);
                } catch {
                    // Strategy doesn't report APY
                }
            }
        }
        
        return weightedAPY;
    }

    /**
     * @notice Get available liquidity
     * @return available Amount available for immediate withdrawal
     */
    function getAvailableLiquidity() external view returns (uint256) {
        return wBTC.balanceOf(address(this));
    }

    /**
     * @notice Get number of active strategies
     * @return count Number of strategies
     */
    function getStrategiesCount() external view returns (uint256) {
        return strategies.length;
    }

    /**
     * @notice Get strategy at index
     * @param index Index in strategies array
     * @return strategy Strategy address
     */
    function getStrategy(uint256 index) external view returns (address) {
        return strategies[index];
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