// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/contracts/WETHGateway.sol";
import "../src/interfaces/IIndexManager.sol";
import "../src/interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockTokenIndex is ERC20 {
    constructor() ERC20("Mock Index Token", "IDX") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
}

contract MockIndexManager {
    MockTokenIndex public tokenIndex;
    MockWETH public weth;

    constructor() {
        tokenIndex = new MockTokenIndex();
        weth = new MockWETH();
    }

    function deposit(uint256 amount, address recipient) external {
        // Transfer WETH from sender to this contract
        weth.transferFrom(msg.sender, address(this), amount);
        // Mint index tokens to recipient
        tokenIndex.mint(recipient, amount);
    }

    function withdraw(uint256 shares, address recipient) external {
        // Burn index tokens
        tokenIndex.burn(msg.sender, shares);
        // Transfer WETH to recipient
        weth.transfer(recipient, shares);
    }
}

contract WETHGatewayTest is Test {
    WETHGateway public wethGateway;
    MockIndexManager public indexManager;
    MockWETH public weth;
    address public user;

    function setUp() public {
        user = makeAddr("user");
        indexManager = new MockIndexManager();
        weth = indexManager.weth();
        wethGateway = new WETHGateway(address(indexManager), address(weth));

        vm.deal(user, 100 ether);
        vm.deal(address(weth), 100 ether);
    }

    function testConstructor() public {
        assertEq(address(wethGateway.indexManager()), address(indexManager));
        assertEq(address(wethGateway.WETH()), address(weth));
    }

    function testDepositETH() public {
        vm.startPrank(user);

        uint256 depositAmount = 1 ether;
        wethGateway.depositETH{value: depositAmount}(user);

        assertEq(weth.balanceOf(address(wethGateway)), 0); // WETH should be transferred to index
        assertEq(address(wethGateway).balance, 0); // ETH should be wrapped
        assertEq(indexManager.tokenIndex().balanceOf(user), depositAmount); // User should receive index tokens

        vm.stopPrank();
    }

    function testWithdrawETH() public {
        vm.startPrank(user);

        // First deposit some ETH
        uint256 depositAmount = 1 ether;
        wethGateway.depositETH{value: depositAmount}(user);

        // Approve gateway to spend index tokens
        indexManager.tokenIndex().approve(address(wethGateway), depositAmount);

        uint256 balanceBefore = user.balance;

        // Withdraw ETH
        wethGateway.withdrawETH(depositAmount, payable(user));

        assertEq(user.balance - balanceBefore, depositAmount);
        assertEq(weth.balanceOf(address(wethGateway)), 0);
        assertEq(indexManager.tokenIndex().balanceOf(user), 0);

        vm.stopPrank();
    }

    function testFailDepositZeroETH() public {
        vm.prank(user);
        wethGateway.depositETH{value: 0}(user);
    }

    receive() external payable {}
}
