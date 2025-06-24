// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AccessControlUpgradeable} from "@oz-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title AccessManager
 * @notice Centralized access control management
 */
contract AccessManager is AccessControlUpgradeable {
    mapping(address => mapping(bytes4 => bool)) public permissions;
    
    event PermissionGranted(address indexed account, bytes4 indexed selector);
    event PermissionRevoked(address indexed account, bytes4 indexed selector);
    
    function grantPermission(address account, bytes4 selector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        permissions[account][selector] = true;
        emit PermissionGranted(account, selector);
    }
    
    function revokePermission(address account, bytes4 selector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        permissions[account][selector] = false;
        emit PermissionRevoked(account, selector);
    }
    
    function hasPermission(address account, bytes4 selector) external view returns (bool) {
        return permissions[account][selector];
    }
}
