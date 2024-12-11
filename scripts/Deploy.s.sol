// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {PriceOracle} from "../src/contracts/PriceOracle.sol";
import {ACLManager} from "../src/contracts/ACLManager.sol";
import {TokenIndex} from "../src/contracts/TokenIndex.sol";
import {IndexManager} from "../src/contracts/IndexManager.sol";
import {console} from "forge-std/console.sol";

contract Deploy is Script {
    // Deploy constants
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Mainnet USDC
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Mainnet WETH
    address constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // Mainnet Uniswap V3 Router

    uint256 constant FEE_PERCENTAGE = 30; // 0.3%

    function run() external {
        vm.startBroadcast();

        // Deploy ACL Manager
        ACLManager aclManager = new ACLManager();

        // Deploy Price Oracle with price feed addresses
        PriceOracle priceOracle = new PriceOracle(address(aclManager));

        // Deploy Token Index
        TokenIndex tokenIndex = new TokenIndex("Test Index", "TI", address(aclManager));

        // Deploy Index Manager using existing contracts
        IndexManager indexManager = new IndexManager(
            address(tokenIndex),
            address(priceOracle),
            UNISWAP_ROUTER, // Use existing Uniswap V3 Router
            USDC, // Use USDC as base token
            FEE_PERCENTAGE,
            address(aclManager)
        );

        // Setup roles
        bytes32 indexAdminRole = tokenIndex.INDEX_ADMIN_ROLE();
        aclManager.grantRole(indexAdminRole, msg.sender);
        aclManager.grantRole(indexAdminRole, address(indexManager));

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("Deployed contracts:");
        console.log("ACL Manager:", address(aclManager));
        console.log("Price Oracle:", address(priceOracle));
        console.log("Token Index:", address(tokenIndex));
        console.log("Index Manager:", address(indexManager));
    }
}
