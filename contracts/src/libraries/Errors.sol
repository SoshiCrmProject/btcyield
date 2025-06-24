// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title Errors
 * @notice Centralized error definitions for gas-efficient reverts
 * @dev Using custom errors instead of strings saves significant gas
 */
library Errors {
    // General errors
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientBalance();
    error Unauthorized();
    error AlreadyInitialized();
    error NotInitialized();
    error InvalidParameter();
    error DeadlineExpired();

    // Staking errors
    error StakeLocked();
    error NoStakeFound();
    error MinimumStakeNotMet();
    error MaximumStakeExceeded();
    error StakeAlreadyExists();
    error InvalidStakeId();
    error InvalidLockPeriod();

    // Strategy errors
    error StrategyNotActive();
    error TooManyStrategies();
    error InvalidAllocation();
    error StrategyLimitExceeded();
    error WithdrawalFailed();
    error HarvestCooldown();
    error InvalidStrategy();

    // Token errors
    error MintingFailed();
    error BurningFailed();
    error TransferFailed();
    error ApprovalFailed();
    error MaxSupplyExceeded();
    error Blacklisted();
    error TransferRestricted();

    // Fee errors
    error FeeTooHigh();
    error FeeTransferFailed();
    error InvalidFeeRecipient();

    // Security errors
    error ContractPaused();
    error ReentrancyGuard();
    error NotEmergency();
    error EmergencyOnly();

    // Limit errors
    error DailyLimitExceeded();
    error TransactionLimitExceeded();
    error DepositLimitExceeded();
    error WithdrawalLimitExceeded();

    // Oracle errors
    error InvalidOraclePrice();
    error OracleStale();
    error OracleNotSet();

    // Governance errors
    error ProposalNotActive();
    error VotingPeriodEnded();
    error InsufficientVotingPower();
    error ProposalAlreadyExecuted();
    error TimelockNotExpired();
}
