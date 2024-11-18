// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {PriceOracle} from "../src/contracts/PriceOracle.sol";
import {ACLManager} from "../src/contracts/ACLManager.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        new PriceOracle(address(new ACLManager()));
        vm.stopBroadcast();
    }
}
