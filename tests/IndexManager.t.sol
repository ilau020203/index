// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/contracts/IndexManager.sol";
import "../src/contracts/TokenIndex.sol";
import "../src/contracts/PriceOracle.sol";
import "../src/contracts/ACLManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract IndexManagerTest is Test {
    using SafeERC20 for IERC20;

    IndexManager public indexManager;
    TokenIndex public tokenIndex;
    PriceOracle public priceOracle;
    ACLManager public aclManager;

    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant GRT = 0xc944E90C64B2c07662A292be6244BDf05Cda44a7;

    address public constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address public constant WHALE = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503; // Binance wallet with lots of tokens
    address public admin = address(1);

    uint256 mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork("mainnet", 21335898);
        vm.selectFork(mainnetFork);

        // Deploy contracts
        aclManager = new ACLManager();
        tokenIndex = new TokenIndex("Test Index", "TI", address(aclManager));
        priceOracle = new PriceOracle(address(aclManager));

        indexManager = new IndexManager(
            address(tokenIndex),
            address(priceOracle),
            UNISWAP_ROUTER,
            USDT,
            100, // 1% fee
            address(aclManager)
        );

        // Setup roles
        aclManager.grantRole(aclManager.INDEX_ADMIN_ROLE(), admin);
        aclManager.grantRole(aclManager.INDEX_ADMIN_ROLE(), address(this));
        aclManager.grantRole(aclManager.INDEX_MANAGER_ROLE(), address(indexManager));

        // Add tokens to index with proportions
        tokenIndex.addToken(USDT, 2 * 10 ** 17); // 20%
        tokenIndex.addToken(DAI, 2 * 10 ** 17); // 20%
        tokenIndex.addToken(WBTC, 2 * 10 ** 17); // 20%
        tokenIndex.addToken(USDC, 2 * 10 ** 17); // 20%
        tokenIndex.addToken(GRT, 2 * 10 ** 17); // 20%

        indexManager.approveToken(USDT, address(tokenIndex));
        indexManager.approveToken(DAI, address(tokenIndex));
        indexManager.approveToken(WBTC, address(tokenIndex));
        indexManager.approveToken(USDC, address(tokenIndex));
        indexManager.approveToken(GRT, address(tokenIndex));

        indexManager.approveToken(USDT, address(UNISWAP_ROUTER));
        indexManager.approveToken(DAI, address(UNISWAP_ROUTER));
        indexManager.approveToken(WBTC, address(UNISWAP_ROUTER));
        indexManager.approveToken(USDC, address(UNISWAP_ROUTER));
        indexManager.approveToken(GRT, address(UNISWAP_ROUTER));

        tokenIndex.approveToken(USDT, address(indexManager));
        tokenIndex.approveToken(DAI, address(indexManager));
        tokenIndex.approveToken(WBTC, address(indexManager));
        tokenIndex.approveToken(USDC, address(indexManager));
        tokenIndex.approveToken(GRT, address(indexManager));

        tokenIndex.approveToken(USDT, address(UNISWAP_ROUTER));
        tokenIndex.approveToken(DAI, address(UNISWAP_ROUTER));
        tokenIndex.approveToken(WBTC, address(UNISWAP_ROUTER));
        tokenIndex.approveToken(USDC, address(UNISWAP_ROUTER));
        tokenIndex.approveToken(GRT, address(UNISWAP_ROUTER));

        // Setup price oracle sources
        address[] memory assets = new address[](5);
        address[] memory sources = new address[](5);

        assets[0] = USDT;
        assets[1] = DAI;
        assets[2] = WBTC;
        assets[3] = USDC;
        assets[4] = GRT;

        // Chainlink price feeds
        sources[0] = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D; // USDT/USD
        sources[1] = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9; // DAI/USD
        sources[2] = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // BTC/USD
        sources[3] = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6; // USDC/USD
        sources[4] = 0x86cF33a451dE9dc61a2862FD94FF4ad4Bd65A5d2; // GRT/USD

        priceOracle.setAssetSources(assets, sources);
        // Setup token paths for Uniswap
        // USDT -> Other tokens
        bytes memory path1 = abi.encodePacked(
            USDT,
            uint24(3000),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            uint24(3000),
            DAI
        );
        indexManager.setTokenPath(USDT, DAI, path1);

        bytes memory path2 = abi.encodePacked(
            USDT,
            uint24(3000),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            uint24(3000),
            WBTC
        );
        indexManager.setTokenPath(USDT, WBTC, path2);

        bytes memory path3 = abi.encodePacked(
            USDT,
            uint24(3000),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            uint24(3000),
            USDC
        );
        indexManager.setTokenPath(USDT, USDC, path3);

        bytes memory path4 = abi.encodePacked(
            USDT,
            uint24(3000),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            uint24(3000),
            GRT
        );
        indexManager.setTokenPath(USDT, GRT, path4);

        // Other tokens -> USDT
        bytes memory path5 = abi.encodePacked(
            DAI,
            uint24(3000),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            uint24(3000),
            USDT
        );
        indexManager.setTokenPath(DAI, USDT, path5);

        bytes memory path6 = abi.encodePacked(
            WBTC,
            uint24(3000),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            uint24(3000),
            USDT
        );
        indexManager.setTokenPath(WBTC, USDT, path6);

        bytes memory path7 = abi.encodePacked(
            USDC,
            uint24(3000),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            uint24(3000),
            USDT
        );
        indexManager.setTokenPath(USDC, USDT, path7);

        bytes memory path8 = abi.encodePacked(
            GRT,
            uint24(3000),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            uint24(3000),
            USDT
        );
        indexManager.setTokenPath(GRT, USDT, path8);

        IERC20(USDT).balanceOf(WHALE);
        // Impersonate whale account and transfer tokens
        vm.startPrank(WHALE);
        IERC20(USDT).safeTransfer(address(this), 1000000 * 1e6); // 1M USDT
        vm.stopPrank();

        // Approve tokens
        IERC20(USDT).safeIncreaseAllowance(address(indexManager), type(uint256).max);

        // Make contracts persistent across fork block changes
        vm.makePersistent(address(tokenIndex));
        vm.makePersistent(address(indexManager));
        vm.makePersistent(address(aclManager));
        vm.makePersistent(address(priceOracle));

        // Make tokens persistent
        vm.makePersistent(USDT);
        vm.makePersistent(DAI);
        vm.makePersistent(WBTC);
        vm.makePersistent(USDC);
        vm.makePersistent(GRT);
    }

    function testDeposit() public {
        uint256 amount = 1000 * 1e6; // 1000 USDT
        uint256 balanceBefore = IERC20(USDT).balanceOf(address(this));

        indexManager.deposit(amount, address(this));

        uint256 balanceAfter = IERC20(USDT).balanceOf(address(this));
        assertEq(balanceAfter, balanceBefore - amount, "USDT not transferred");
        assertTrue(IERC20(USDT).balanceOf(address(tokenIndex)) > 0, "USDT balance should be greater than 0");
        assertTrue(IERC20(DAI).balanceOf(address(tokenIndex)) > 0, "DAI balance should be greater than 0");
        assertTrue(IERC20(WBTC).balanceOf(address(tokenIndex)) > 0, "WBTC balance should be greater than 0");
        assertTrue(IERC20(USDC).balanceOf(address(tokenIndex)) > 0, "USDC balance should be greater than 0");
        assertTrue(IERC20(GRT).balanceOf(address(tokenIndex)) > 0, "GRT balance should be greater than 0");
        assertTrue(tokenIndex.balanceOf(address(this)) > 0, "No index tokens minted");
    }

    function testDepositDouble() public {
        uint256 amount = 1000 * 1e6; // 1000 USDT
        uint256 amount2 = 2000 * 1e6; // 1000 USDT
        uint256 balanceBefore = IERC20(USDT).balanceOf(address(this));

        indexManager.deposit(amount, address(this));
        indexManager.deposit(amount2, address(this));

        uint256 balanceAfter = IERC20(USDT).balanceOf(address(this));
        assertEq(balanceAfter, balanceBefore - amount - amount2, "USDT not transferred");
        assertEq(IERC20(USDT).balanceOf(address(indexManager)), 0, "USDT balance should be 0");
        assertEq(IERC20(DAI).balanceOf(address(indexManager)), 0, "DAI balance should be 0");
        assertEq(IERC20(WBTC).balanceOf(address(indexManager)), 0, "WBTC balance should be 0");
        assertEq(IERC20(USDC).balanceOf(address(indexManager)), 0, "USDC balance should be 0");
        assertEq(IERC20(GRT).balanceOf(address(indexManager)), 0, "GRT balance should be 0");
        assertTrue(IERC20(USDT).balanceOf(address(tokenIndex)) > 0, "USDT balance should be greater than 0");
        assertTrue(IERC20(DAI).balanceOf(address(tokenIndex)) > 0, "DAI balance should be greater than 0");
        assertTrue(IERC20(WBTC).balanceOf(address(tokenIndex)) > 0, "WBTC balance should be greater than 0");
        assertTrue(IERC20(USDC).balanceOf(address(tokenIndex)) > 0, "USDC balance should be greater than 0");
        assertTrue(IERC20(GRT).balanceOf(address(tokenIndex)) > 0, "GRT balance should be greater than 0");
        assertTrue(tokenIndex.balanceOf(address(this)) > 0, "No index tokens minted");
    }

    function testDepositDoubleInDifferentTime() public {
        uint256 amount = 1000 * 1e6; // 1000 USDT
        uint256 amount2 = 2000 * 1e6; // 1000 USDT
        uint256 balanceBefore = IERC20(USDT).balanceOf(address(this));

        indexManager.deposit(amount, address(this));

        vm.rollFork(block.number + 1000);

        indexManager.deposit(amount2, address(this));

        uint256 balanceAfter = IERC20(USDT).balanceOf(address(this));
        assertEq(balanceAfter, balanceBefore - amount - amount2, "USDT not transferred");
        assertTrue(IERC20(USDT).balanceOf(address(tokenIndex)) > 0, "USDT balance should be greater than 0");
        assertTrue(IERC20(DAI).balanceOf(address(tokenIndex)) > 0, "DAI balance should be greater than 0");
        assertTrue(IERC20(WBTC).balanceOf(address(tokenIndex)) > 0, "WBTC balance should be greater than 0");
        assertTrue(IERC20(USDC).balanceOf(address(tokenIndex)) > 0, "USDC balance should be greater than 0");
        assertTrue(IERC20(GRT).balanceOf(address(tokenIndex)) > 0, "GRT balance should be greater than 0");
        assertTrue(tokenIndex.balanceOf(address(this)) > 0, "No index tokens minted");
    }

    function testDepositDoubleInDifferentTimeWithSmallAmount() public {
        uint256 amount = 1000 * 1e6; // 1000 USDT
        uint256 amount2 = 1000000; // 1000 USDT
        uint256 balanceBefore = IERC20(USDT).balanceOf(address(this));

        indexManager.deposit(amount, address(this));

        vm.rollFork(block.number + 1000);

        indexManager.deposit(amount2, address(this));

        uint256 balanceAfter = IERC20(USDT).balanceOf(address(this));
        assertEq(balanceAfter, balanceBefore - amount - amount2, "USDT not transferred");
        assertTrue(IERC20(USDT).balanceOf(address(tokenIndex)) > 0, "USDT balance should be greater than 0");
        assertTrue(IERC20(DAI).balanceOf(address(tokenIndex)) > 0, "DAI balance should be greater than 0");
        assertTrue(IERC20(WBTC).balanceOf(address(tokenIndex)) > 0, "WBTC balance should be greater than 0");
        assertTrue(IERC20(USDC).balanceOf(address(tokenIndex)) > 0, "USDC balance should be greater than 0");
        assertTrue(IERC20(GRT).balanceOf(address(tokenIndex)) > 0, "GRT balance should be greater than 0");
        assertTrue(tokenIndex.balanceOf(address(this)) > 0, "No index tokens minted");
    }

    function testWithdraw() public {
        // First deposit
        uint256 depositAmount = 1000 * 1e6; // 1000 USDT
        indexManager.deposit(depositAmount, address(this));

        uint256 indexTokens = tokenIndex.balanceOf(address(this));
        address recipient = address(0xfffffffffffffff);
        // Then withdraw
        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(recipient);

        indexManager.withdraw(indexTokens, recipient);

        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(recipient);
        assertTrue(usdtBalanceAfter > usdtBalanceBefore, "No USDT received");

        // Check all token balances in index are now 0
        assertEq(IERC20(USDT).balanceOf(address(tokenIndex)), 0, "USDT balance not 0");
        assertEq(IERC20(WBTC).balanceOf(address(tokenIndex)), 0, "WBTC balance not 0");
        assertEq(IERC20(USDC).balanceOf(address(tokenIndex)), 0, "USDC balance not 0");
        assertEq(IERC20(DAI).balanceOf(address(tokenIndex)), 0, "DAI balance not 0");
        assertEq(IERC20(GRT).balanceOf(address(tokenIndex)), 0, "GRT balance not 0");
        assertEq(tokenIndex.balanceOf(address(this)), 0, "Index tokens not burned");
    }

    function testWithdrawDouble() public {
        // First deposit
        uint256 depositAmount = 1000 * 1e6; // 1000 USDT
        indexManager.deposit(depositAmount, address(this));

        uint256 indexTokens = tokenIndex.balanceOf(address(this));
        address recipient = address(0xfffffffffffffff);
        // Then withdraw
        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(recipient);

        indexManager.withdraw(indexTokens - 1e19, recipient);

        vm.rollFork(block.number + 1000);
        indexTokens = tokenIndex.balanceOf(address(this));

        indexManager.withdraw(indexTokens, recipient);

        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(recipient);
        assertTrue(usdtBalanceAfter > usdtBalanceBefore, "No USDT received");

        // Check all token balances in index are now 0
        assertEq(IERC20(USDT).balanceOf(address(tokenIndex)), 0, "USDT balance not 0");
        assertEq(IERC20(WBTC).balanceOf(address(tokenIndex)), 0, "WBTC balance not 0");
        assertEq(IERC20(USDC).balanceOf(address(tokenIndex)), 0, "USDC balance not 0");
        assertEq(IERC20(DAI).balanceOf(address(tokenIndex)), 0, "DAI balance not 0");
        assertEq(IERC20(GRT).balanceOf(address(tokenIndex)), 0, "GRT balance not 0");
        assertEq(tokenIndex.balanceOf(address(this)), 0, "Index tokens not burned");
    }

    function testWithdrawDoubleWithSmallAmount() public {
        // First deposit
        uint256 depositAmount = 1000 * 1e6; // 1000 USDT
        indexManager.deposit(depositAmount, address(this));

        uint256 indexTokens = tokenIndex.balanceOf(address(this));
        address recipient = address(0xfffffffffffffff);
        // Then withdraw
        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(recipient);

        indexManager.withdraw(44*1e19, recipient);

        vm.rollFork(block.number + 1000);
        indexTokens = tokenIndex.balanceOf(address(this));

        indexManager.withdraw(indexTokens, recipient);

        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(recipient);
        assertTrue(usdtBalanceAfter > usdtBalanceBefore, "No USDT received");

        // Check all token balances in index are now 0
        assertEq(IERC20(USDT).balanceOf(address(tokenIndex)), 0, "USDT balance not 0");
        assertEq(IERC20(WBTC).balanceOf(address(tokenIndex)), 0, "WBTC balance not 0");
        assertEq(IERC20(USDC).balanceOf(address(tokenIndex)), 0, "USDC balance not 0");
        assertEq(IERC20(DAI).balanceOf(address(tokenIndex)), 0, "DAI balance not 0");
        assertEq(IERC20(GRT).balanceOf(address(tokenIndex)), 0, "GRT balance not 0");
        assertEq(tokenIndex.balanceOf(address(this)), 0, "Index tokens not burned");
    }
    function testWithdrawDoubleWithSmallAmount2() public {
        // First deposit
        uint256 depositAmount = 1000 * 1e6; // 1000 USDT
        indexManager.deposit(depositAmount, address(this));

        uint256 indexTokens = tokenIndex.balanceOf(address(this));
        address recipient = address(0xfffffffffffffff);
        // Then withdraw
        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(recipient);

        indexManager.withdraw(4*1e19, recipient);

        vm.rollFork(block.number + 1000);
        indexTokens = tokenIndex.balanceOf(address(this));

        indexManager.withdraw(indexTokens, recipient);

        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(recipient);
        assertTrue(usdtBalanceAfter > usdtBalanceBefore, "No USDT received");

        // Check all token balances in index are now 0
        assertEq(IERC20(USDT).balanceOf(address(tokenIndex)), 0, "USDT balance not 0");
        assertEq(IERC20(WBTC).balanceOf(address(tokenIndex)), 0, "WBTC balance not 0");
        assertEq(IERC20(USDC).balanceOf(address(tokenIndex)), 0, "USDC balance not 0");
        assertEq(IERC20(DAI).balanceOf(address(tokenIndex)), 0, "DAI balance not 0");
        assertEq(IERC20(GRT).balanceOf(address(tokenIndex)), 0, "GRT balance not 0");
        assertEq(tokenIndex.balanceOf(address(this)), 0, "Index tokens not burned");
    }

    function testWithdrawFees() public {
        // Deposit and wait for fee period
        uint256 depositAmount = 1000 * 1e6; // 1000 USDT
        indexManager.deposit(depositAmount, address(this));

        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);

        uint256 balanceBefore = IERC20(USDT).balanceOf(address(this));
        indexManager.withdrawFees();
        uint256 balanceAfter = IERC20(USDT).balanceOf(address(this));

        assertTrue(balanceAfter > balanceBefore, "No fees withdrawn");
    }

    function testRebalance() public {
        // First deposit to have tokens in the index
        uint256 depositAmount = 1000 * 1e6; // 1000 USDT
        indexManager.deposit(depositAmount, address(this));

        // Create swap parameters for rebalancing
        IIndexManager.SwapParams[] memory params = new IIndexManager.SwapParams[](1);

        // Example swap USDT -> DAI
        bytes memory path = abi.encodePacked(
            USDT,
            uint24(3000),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            uint24(3000),
            DAI
        );
        params[0] = IIndexManager.SwapParams({
            path: path,
            amountIn: 100 * 1e6, // 100 USDT
            amountOutMinimum: 90 * 1e18, // 90 DAI minimum
            deadline: block.timestamp + 1 hours
        });
        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(address(tokenIndex));
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(address(tokenIndex));

        vm.prank(admin);
        indexManager.rebalance(params);

        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(address(tokenIndex));
        uint256 daiBalanceAfter = IERC20(DAI).balanceOf(address(tokenIndex));

        assertEq(usdtBalanceBefore - usdtBalanceAfter, 100 * 1e6, "USDT balance did not decrease by expected amount");
        assertTrue(daiBalanceAfter - daiBalanceBefore >= 90 * 1e18, "DAI balance did not increase by expected amount");
    }

    function testRevokeTokenApproval() public {
        // First approve a token to a manager
        address manager = address(0x123);
        vm.startPrank(admin);
        indexManager.approveToken(USDT, manager);

        // Verify initial approval
        uint256 initialAllowance = IERC20(USDT).allowance(address(indexManager), manager);
        assertEq(initialAllowance, type(uint256).max);

        // Revoke approval
        indexManager.revokeTokenApproval(USDT, manager);

        // Verify approval was revoked
        uint256 finalAllowance = IERC20(USDT).allowance(address(indexManager), manager);
        assertEq(finalAllowance, 0);
        vm.stopPrank();
    }

    function testRevokeTokenApprovalRevertsForNonAdmin() public {
        address badManager = address(0x1223);
        vm.startPrank(badManager);
        vm.expectRevert(IIndexManager.OnlyIndexAdmins.selector);
        indexManager.revokeTokenApproval(USDT, badManager);
    }
}
