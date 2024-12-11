// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {PriceOracle} from "../src/contracts/PriceOracle.sol";
import {ACLManager} from "../src/contracts/ACLManager.sol";
import {AggregatorV3Mock} from "../src/mocks/AggregatorV3Mock.sol";

contract PriceOracleTest is Test {
    PriceOracle public priceOracle;
    PriceOracle public fallbackOracle;
    ACLManager public aclManager;
    AggregatorV3Mock public aggregatorMock;
    AggregatorV3Mock public fallbackAggregatorMock;
    AggregatorV3Mock public badAggregatorMock;
    address public constant ASSET = address(0x1);
    int256 public constant INITIAL_PRICE = 100;
    int256 public constant BAD_PRICE = 0;
    int256 public constant FALLBACK_PRICE = 150;

    function setUp() public {
        aclManager = new ACLManager();
        priceOracle = new PriceOracle(address(aclManager));
        fallbackOracle = new PriceOracle(address(aclManager));
        aggregatorMock = new AggregatorV3Mock(INITIAL_PRICE);
        badAggregatorMock = new AggregatorV3Mock(BAD_PRICE);
        fallbackAggregatorMock = new AggregatorV3Mock(FALLBACK_PRICE);

        aclManager.addIndexAdmin(address(this));
    }

    function testSetAssetSource() public {
        address[] memory assets = new address[](1);
        assets[0] = ASSET;

        address[] memory sources = new address[](1);
        sources[0] = address(aggregatorMock);

        priceOracle.setAssetSources(assets, sources);

        assertEq(priceOracle.getSourceOfAsset(ASSET), address(aggregatorMock));
    }

    function testGetAssetPrice() public {
        address[] memory assets = new address[](1);
        assets[0] = ASSET;

        address[] memory sources = new address[](1);
        sources[0] = address(aggregatorMock);

        priceOracle.setAssetSources(assets, sources);

        uint256 price = priceOracle.getAssetPrice(ASSET);
        assertEq(price, uint256(INITIAL_PRICE));

        int256 newPrice = 200;
        aggregatorMock.setAnswer(newPrice);
        price = priceOracle.getAssetPrice(ASSET);
        assertEq(price, uint256(newPrice));
    }

    function testGetAssetsPrices() public {
        address[] memory assets = new address[](1);
        assets[0] = ASSET;

        address[] memory sources = new address[](1);
        sources[0] = address(aggregatorMock);

        priceOracle.setAssetSources(assets, sources);

        uint256[] memory prices = priceOracle.getAssetsPrices(assets);
        assertEq(prices.length, 1);
        assertEq(prices[0], uint256(INITIAL_PRICE));
    }

    function testSetAssetSourcesRevertOnLengthMismatch() public {
        address[] memory assets = new address[](2);
        assets[0] = ASSET;
        assets[1] = address(0x2);

        address[] memory sources = new address[](1);
        sources[0] = address(aggregatorMock);

        vm.expectRevert(PriceOracle.InconsistentParamsLength.selector);
        priceOracle.setAssetSources(assets, sources);
    }

    function testSetAssetSourcesRevertOnNonAdmin() public {
        address[] memory assets = new address[](1);
        assets[0] = ASSET;

        address[] memory sources = new address[](1);
        sources[0] = address(aggregatorMock);

        vm.prank(address(0xdead));
        vm.expectRevert(PriceOracle.OnlyIndexAdmins.selector);
        priceOracle.setAssetSources(assets, sources);
    }

    function testSetFallbackOracle() public {
        priceOracle.setFallbackOracle(address(fallbackOracle));
        assertEq(priceOracle.getFallbackOracle(), address(fallbackOracle));
    }

    function testSetFallbackOracleRevertOnNonAdmin() public {
        vm.prank(address(0xdead));
        vm.expectRevert(PriceOracle.OnlyIndexAdmins.selector);
        priceOracle.setFallbackOracle(address(fallbackOracle));
    }

    function testGetAssetPriceFromFallback() public {
        // Set up fallback oracle with price source
        address[] memory assets = new address[](1);
        assets[0] = ASSET;
        address[] memory sources = new address[](1);
        sources[0] = address(fallbackAggregatorMock);
        fallbackOracle.setAssetSources(assets, sources);

        // Set fallback oracle
        priceOracle.setFallbackOracle(address(fallbackOracle));

        // Get price from fallback since main oracle has no source
        uint256 price = priceOracle.getAssetPrice(ASSET);
        assertEq(price, uint256(FALLBACK_PRICE));
    }

    function testGetAssetsPricesFromFallback() public {
        // Set up fallback oracle with price source
        address[] memory assets = new address[](1);
        assets[0] = ASSET;
        address[] memory sources = new address[](1);
        sources[0] = address(fallbackAggregatorMock);
        fallbackOracle.setAssetSources(assets, sources);

        // Set fallback oracle
        priceOracle.setFallbackOracle(address(fallbackOracle));

        // Get prices from fallback since main oracle has no source
        uint256[] memory prices = priceOracle.getAssetsPrices(assets);
        assertEq(prices.length, 1);
        assertEq(prices[0], uint256(FALLBACK_PRICE));
    }

    function testGetAssetPriceFromFallbackWithBadPrice() public {
        // Set up main oracle with bad price source
        address[] memory assets = new address[](1);
        assets[0] = ASSET;
        address[] memory sources = new address[](1);
        sources[0] = address(badAggregatorMock);
        priceOracle.setAssetSources(assets, sources);

        // Set up fallback oracle with good price source
        sources[0] = address(fallbackAggregatorMock);
        fallbackOracle.setAssetSources(assets, sources);

        // Set fallback oracle
        priceOracle.setFallbackOracle(address(fallbackOracle));

        // Should get price from fallback since main oracle has bad price
        uint256 price = priceOracle.getAssetPrice(ASSET);
        assertEq(price, uint256(FALLBACK_PRICE));
    }
}
