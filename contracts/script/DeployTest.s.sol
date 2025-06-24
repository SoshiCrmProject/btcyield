// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";
import {Deploy} from "./Deploy.s.sol";
import {MockWBTC} from "../test/mocks/MockWBTC.sol";
import {MockOracle} from "../test/mocks/MockOracle.sol";

contract DeployTest is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy mocks
        MockWBTC wbtc = new MockWBTC();
        MockOracle oracle = new MockOracle();
        
        // Fund test accounts
        address[3] memory testAccounts = [
            0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
            0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
            0x90F79bf6EB2c4f870365E785982E1f101E93b906
        ];
        
        for (uint i = 0; i < testAccounts.length; i++) {
            wbtc.mint(testAccounts[i], 100 * 10**8); // 100 BTC each
        }
        
        vm.stopBroadcast();
        
        // Continue with main deployment
        Deploy deploy = new Deploy();
        deploy.run();
    }
}
