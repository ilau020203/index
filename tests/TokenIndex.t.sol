// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/contracts/TokenIndex.sol";
import "../src/contracts/ACLManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TokenIndexTest is Test {
    TokenIndex public tokenIndex;
    ACLManager public aclManager;
    MockToken public token1;
    MockToken public token2;
    address public admin = address(1);
    address public user = address(2);
    address public manager = address(3);

    function setUp() public {
        // Deploy contracts
        aclManager = new ACLManager();
        tokenIndex = new TokenIndex("Test Index", "TI", address(aclManager));
        token1 = new MockToken("Token1", "T1");
        token2 = new MockToken("Token2", "T2");

        // Setup roles
        vm.startPrank(address(this));
        aclManager.addIndexAdmin(admin);
        aclManager.addIndexManager(manager);
        vm.stopPrank();
    }

    function testAddToken() public {
        vm.startPrank(admin);
        tokenIndex.addToken(address(token1), 5000); // 50%
        tokenIndex.addToken(address(token2), 5000); // 50%
        vm.stopPrank();

        assertEq(tokenIndex.totalTokens(), 2);

        ITokenIndex.TokenInfo memory info = tokenIndex.tokens(0);
        assertEq(address(info.token), address(token1));
        assertEq(info.proportion, 5000);
    }

    function testAddTokenNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(TokenIndex.OnlyIndexAdmins.selector);
        tokenIndex.addToken(address(token1), 5000);
    }

    function testRemoveToken() public {
        vm.startPrank(admin);
        tokenIndex.addToken(address(token1), 5000);
        tokenIndex.addToken(address(token2), 5000);
        tokenIndex.removeToken(0);
        vm.stopPrank();

        assertEq(tokenIndex.totalTokens(), 1);
        ITokenIndex.TokenInfo memory info = tokenIndex.tokens(0);
        assertEq(address(info.token), address(token2));
    }

    function testEditToken() public {
        vm.startPrank(admin);
        tokenIndex.addToken(address(token1), 5000);
        tokenIndex.editToken(0, 7000);
        vm.stopPrank();

        ITokenIndex.TokenInfo memory info = tokenIndex.tokens(0);
        assertEq(info.proportion, 7000);
    }

    function testMintAndBurn() public {
        vm.startPrank(manager);
        tokenIndex.mint(user, 1000);
        assertEq(tokenIndex.balanceOf(user), 1000);

        tokenIndex.burn(user, 500);
        assertEq(tokenIndex.balanceOf(user), 500);
        vm.stopPrank();
    }

    function testGetTokenProportions() public {
        vm.startPrank(admin);
        tokenIndex.addToken(address(token1), 5000);
        tokenIndex.addToken(address(token2), 5000);
        vm.stopPrank();

        ITokenIndex.TokenInfo[] memory tokens = tokenIndex.getTokenProportions();
        assertEq(tokens.length, 2);
        assertEq(address(tokens[0].token), address(token1));
        assertEq(tokens[0].proportion, 5000);
        assertEq(address(tokens[1].token), address(token2));
        assertEq(tokens[1].proportion, 5000);
    }

    function testRemoveTokenInvalidIndex() public {
        vm.startPrank(admin);
        vm.expectRevert(TokenIndex.InvalidIndex.selector);
        tokenIndex.removeToken(0); // Should fail as no tokens exist
        vm.stopPrank();
    }

    function testEditTokenInvalidIndex() public {
        vm.startPrank(admin);
        vm.expectRevert(TokenIndex.InvalidIndex.selector);
        tokenIndex.editToken(0, 5000); // Should fail as no tokens exist
        vm.stopPrank();
    }
}
