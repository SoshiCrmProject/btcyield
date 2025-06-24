// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AccessControlUpgradeable} from "@oz-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title RateLimiter
 * @notice Advanced rate limiting for protocol security
 */
contract RateLimiter is AccessControlUpgradeable {
    mapping(address => mapping(bytes4 => uint256)) public lastCall;
    mapping(bytes4 => uint256) public cooldowns;
    
    modifier rateLimited(bytes4 selector) {
        require(
            block.timestamp >= lastCall[msg.sender][selector] + cooldowns[selector],
            "Rate limited"
        );
        lastCall[msg.sender][selector] = block.timestamp;
        _;
    }
    
    function setCooldown(bytes4 selector, uint256 cooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        cooldowns[selector] = cooldown;
    }
}
