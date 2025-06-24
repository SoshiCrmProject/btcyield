// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Initializable} from "@oz-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@oz-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@oz-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@oz-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@oz-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@oz-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@oz-upgradeable/security/PausableUpgradeable.sol";

/**
 * @title StBTC - Staked Bitcoin Token
 * @author BTCYield Team
 * @notice Liquid staking token representing staked Bitcoin in the BTCYield protocol
 * @dev ERC20 token with minting/burning restricted to the staking vault
 */
contract StBTC is
    Initializable,
    UUPSUpgradeable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The staking vault contract address
    address public stakingVault;

    /// @notice Blacklisted addresses that cannot transfer tokens
    mapping(address => bool) public blacklisted;

    /// @notice Transfer allowlist for restricted mode
    mapping(address => bool) public transferAllowlist;

    /// @notice Whether transfers are restricted to allowlist only
    bool public restrictedMode;

    /// @notice Maximum supply cap (0 = no cap)
    uint256 public maxSupply;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event StakingVaultUpdated(address indexed oldVault, address indexed newVault);
    event BlacklistUpdated(address indexed account, bool blacklisted);
    event TransferAllowlistUpdated(address indexed account, bool allowed);
    event RestrictedModeUpdated(bool enabled);
    event MaxSupplyUpdated(uint256 oldMaxSupply, uint256 newMaxSupply);
    event EmergencyTransfer(address indexed from, address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAddress();
    error Unauthorized();
    error Blacklisted();
    error TransferRestricted();
    error MaxSupplyExceeded();
    error AmountExceedsBalance();

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
     * @notice Initialize the StBTC token
     * @param _stakingVault Address of the staking vault
     */
    function initialize(address _stakingVault) public initializer {
        if (_stakingVault == address(0)) revert InvalidAddress();

        __ERC20_init("Staked Bitcoin", "stBTC");
        __ERC20Burnable_init();
        __ERC20Permit_init("Staked Bitcoin");
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        stakingVault = _stakingVault;
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, _stakingVault);
        _grantRole(BURNER_ROLE, _stakingVault);
        _grantRole(GUARDIAN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        
        // Initialize with no max supply cap
        maxSupply = 0;
    }

    /*//////////////////////////////////////////////////////////////
                           MINTING/BURNING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint new stBTC tokens
     * @dev Only callable by addresses with MINTER_ROLE (staking vault)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert InvalidAddress();
        
        // Check max supply if cap is set
        if (maxSupply > 0 && totalSupply() + amount > maxSupply) {
            revert MaxSupplyExceeded();
        }
        
        _mint(to, amount);
    }

    /**
     * @notice Burn stBTC tokens from a specific address
     * @dev Only callable by addresses with BURNER_ROLE (staking vault)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) whenNotPaused {
        if (from == address(0)) revert InvalidAddress();
        if (balanceOf(from) < amount) revert AmountExceedsBalance();
        
        _burn(from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          TRANSFER OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Override transfer to add blacklist and restricted mode checks
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);

        // Check blacklist
        if (blacklisted[from] || blacklisted[to]) {
            revert Blacklisted();
        }

        // Check restricted mode (skip for minting/burning)
        if (restrictedMode && from != address(0) && to != address(0)) {
            if (!transferAllowlist[from] && !transferAllowlist[to]) {
                revert TransferRestricted();
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the staking vault address
     * @param newVault New staking vault address
     */
    function setStakingVault(address newVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newVault == address(0)) revert InvalidAddress();
        
        address oldVault = stakingVault;
        
        // Revoke roles from old vault
        _revokeRole(MINTER_ROLE, oldVault);
        _revokeRole(BURNER_ROLE, oldVault);
        
        // Grant roles to new vault
        _grantRole(MINTER_ROLE, newVault);
        _grantRole(BURNER_ROLE, newVault);
        
        stakingVault = newVault;
        
        emit StakingVaultUpdated(oldVault, newVault);
    }

    /**
     * @notice Update blacklist status for an address
     * @param account Address to update
     * @param _blacklisted Whether the address should be blacklisted
     */
    function setBlacklisted(address account, bool _blacklisted) external onlyRole(GUARDIAN_ROLE) {
        blacklisted[account] = _blacklisted;
        emit BlacklistUpdated(account, _blacklisted);
    }

    /**
     * @notice Update transfer allowlist for an address
     * @param account Address to update
     * @param allowed Whether the address should be allowed to transfer in restricted mode
     */
    function setTransferAllowlist(address account, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        transferAllowlist[account] = allowed;
        emit TransferAllowlistUpdated(account, allowed);
    }

    /**
     * @notice Enable or disable restricted transfer mode
     * @param enabled Whether restricted mode should be enabled
     */
    function setRestrictedMode(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        restrictedMode = enabled;
        emit RestrictedModeUpdated(enabled);
    }

    /**
     * @notice Set maximum supply cap
     * @param _maxSupply New maximum supply (0 = no cap)
     */
    function setMaxSupply(uint256 _maxSupply) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldMaxSupply = maxSupply;
        maxSupply = _maxSupply;
        emit MaxSupplyUpdated(oldMaxSupply, _maxSupply);
    }

    /**
     * @notice Pause token transfers
     */
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause token transfers
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                         EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emergency transfer function for stuck tokens
     * @dev Only callable by guardian in extreme circumstances
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount to transfer
     */
    function emergencyTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyRole(GUARDIAN_ROLE) whenPaused {
        if (from == address(0) || to == address(0)) revert InvalidAddress();
        if (balanceOf(from) < amount) revert AmountExceedsBalance();
        
        _transfer(from, to, amount);
        emit EmergencyTransfer(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if an address can transfer tokens
     * @param account Address to check
     * @return canTransfer Whether the address can transfer
     */
    function canTransfer(address account) external view returns (bool) {
        if (paused()) return false;
        if (blacklisted[account]) return false;
        if (restrictedMode && !transferAllowlist[account]) return false;
        return true;
    }

    /**
     * @notice Get the current circulating supply
     * @return supply Current total supply
     */
    function circulatingSupply() external view returns (uint256) {
        return totalSupply();
    }

    /**
     * @notice Calculate how many more tokens can be minted
     * @return available Tokens that can still be minted
     */
    function availableToMint() external view returns (uint256) {
        if (maxSupply == 0) return type(uint256).max;
        uint256 current = totalSupply();
        if (current >= maxSupply) return 0;
        return maxSupply - current;
    }

    /*//////////////////////////////////////////////////////////////
                          UPGRADE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Authorize upgrade to a new implementation
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /*//////////////////////////////////////////////////////////////
                            OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Required override for ERC20Upgradeable
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Upgradeable) {
        super._afterTokenTransfer(from, to, amount);
    }
}