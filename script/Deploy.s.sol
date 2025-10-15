// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/B_Evoke_Registry_ECC.sol";

contract DeployScript is Script {
    function run() external {
        // Read deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the B_Evoke_Registry_ECC contract (with real ECC)
        B_Evoke_Registry_ECC registry = new B_Evoke_Registry_ECC();

        // Log the deployed address
        console.log("B_Evoke_Registry_ECC deployed to:", address(registry));
        console.log("Contract owner:", registry.owner());

        // Stop broadcast
        vm.stopBroadcast();
    }
}