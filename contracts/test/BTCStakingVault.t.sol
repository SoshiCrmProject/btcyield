// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {BTCStakingVault} from "../src/core/BTCStakingVault.sol";
import {StBTC} from "../src/core/StBTC.sol";
import {StrategyManager} from "../src/strategies/StrategyManager.sol";
import {MockWBTC} from "./mocks/MockWBTC.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BTCStakingVaultTest is Test {
    BTCStakingVault public vault;
    StBTC public stBTC;
    StrategyManager public strategyManager;
    MockWBTC public wBTC;
    MockOracle public oracle;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public treasury = address(0x3);
    
    function setUp() public {
        // Deploy mocks
        wBTC = new MockWBTC();
        oracle = new MockOracle();
        
        // Deploy implementations
        BTCStakingVault vaultImpl = new BTCStakingVault();
        StBTC stBTCImpl = new StBTC();
        StrategyManager strategyManagerImpl = new StrategyManager();
        
        // Deploy proxies
        bytes memory stBTCData = abi.encodeWithSelector(StBTC.initialize.selector, address(0));
        ERC1967Proxy stBTCProxy = new ERC1967Proxy(address(stBTCImpl), stBTCData);
        stBTC = StBTC(address(stBTCProxy));
        
        bytes memory strategyData = abi.encodeWithSelector(
            StrategyManager.initialize.selector,
            address(wBTC),
            address(0),
            treasury
        );
        ERC1967Proxy strategyProxy = new ERC1967Proxy(address(strategyManagerImpl), strategyData);
        strategyManager = StrategyManager(address(strategyProxy));
        
        bytes memory vaultData = abi.encodeWithSelector(
            BTCStakingVault.initialize.selector,
            address(wBTC),
            address(stBTC),
            address(strategyManager),
            treasury,
            address(oracle)
        );
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), vaultData);
        vault = BTCStakingVault(address(vaultProxy));
        
        // Configure contracts
        stBTC.setStakingVault(address(vault));
        strategyManager.grantRole(strategyManager.VAULT_ROLE(), address(vault));
        
        // Fund test users
        wBTC.mint(alice, 100 * 10**8);
        wBTC.mint(bob, 100 * 10**8);
        
        // Approve vault
        vm.prank(alice);
        wBTC.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        wBTC.approve(address(vault), type(uint256).max);
    }
    
    function test_Stake() public {
        vm.prank(alice);
        uint256 stakeId = vault.stake(1 * 10**8, 0, false, 0);
        
        assertEq(stakeId, 0);
        assertEq(stBTC.balanceOf(alice), 1 * 10**8);
        assertEq(vault.totalAssets(), 1 * 10**8);
    }
    
    function test_StakeWithLock() public {
        vm.prank(alice);
        uint256 stakeId = vault.stake(1 * 10**8, 365, true, 1);
        
        (uint256 amount, uint256 shares, uint256 lockEnd,,,) = vault.getStakeInfo(alice, stakeId);
        
        assertEq(amount, 1 * 10**8);
        assertGt(shares, amount); // Should have lock boost
        assertEq(lockEnd, block.timestamp + 365 days);
    }
    
    function testFuzz_Stake(uint256 amount, uint256 lockDays) public {
        amount = bound(amount, 1e5, 10 * 10**8);
        lockDays = bound(lockDays, 0, 1095);
        
        vm.prank(alice);
        vault.stake(amount, lockDays, false, 0);
        
        assertGe(stBTC.balanceOf(alice), amount);
    }
}
