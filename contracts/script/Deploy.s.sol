// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {BTCStakingVault} from "../src/core/BTCStakingVault.sol";
import {StBTC} from "../src/core/StBTC.sol";
import {StrategyManager} from "../src/strategies/StrategyManager.sol";

// Import strategies
import {AaveV3Strategy} from "../src/strategies/AaveV3Strategy.sol";
import {CompoundV3Strategy} from "../src/strategies/CompoundV3Strategy.sol";
import {YearnV3Strategy} from "../src/strategies/YearnV3Strategy.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    // Configuration
    address constant WBTC_MAINNET = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant CHAINLINK_BTC_USD = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        
        console.log("Deploying BTCYield Protocol...");
        console.log("Deployer:", deployer);
        console.log("Treasury:", treasury);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy implementations
        BTCStakingVault vaultImpl = new BTCStakingVault();
        StBTC stBTCImpl = new StBTC();
        StrategyManager strategyManagerImpl = new StrategyManager();
        
        // 2. Deploy proxies
        ERC1967Proxy stBTCProxy = new ERC1967Proxy(
            address(stBTCImpl),
            abi.encodeWithSelector(StBTC.initialize.selector, address(0))
        );
        
        ERC1967Proxy strategyManagerProxy = new ERC1967Proxy(
            address(strategyManagerImpl),
            abi.encodeWithSelector(
                StrategyManager.initialize.selector,
                WBTC_MAINNET,
                address(0),
                treasury
            )
        );
        
        ERC1967Proxy vaultProxy = new ERC1967Proxy(
            address(vaultImpl),
            abi.encodeWithSelector(
                BTCStakingVault.initialize.selector,
                WBTC_MAINNET,
                address(stBTCProxy),
                address(strategyManagerProxy),
                treasury,
                CHAINLINK_BTC_USD
            )
        );
        
        // 3. Configure contracts
        StBTC(address(stBTCProxy)).setStakingVault(address(vaultProxy));
        StrategyManager(address(strategyManagerProxy)).grantRole(
            StrategyManager(address(strategyManagerProxy)).VAULT_ROLE(),
            address(vaultProxy)
        );
        
        // 4. Deploy strategies
        _deployStrategies(address(strategyManagerProxy));
        
        vm.stopBroadcast();
        
        // 5. Save deployment addresses
        _saveDeployment(address(vaultProxy), address(stBTCProxy), address(strategyManagerProxy));
    }
    
    function _deployStrategies(address strategyManager) internal {
        // Deploy and add strategies
        console.log("Deploying strategies...");
        
        // Example: Deploy Aave strategy
        // AaveV3Strategy aaveStrategy = new AaveV3Strategy();
        // Initialize and add to strategy manager
    }
    
    function _saveDeployment(address vault, address stBTC, address strategyManager) internal {
        string memory json = string(abi.encodePacked(
            '{"vault":"', vm.toString(vault), '",',
            '"stBTC":"', vm.toString(stBTC), '",',
            '"strategyManager":"', vm.toString(strategyManager), '"}'
        ));
        
        vm.writeFile("./deployments/latest.json", json);
    }
}
