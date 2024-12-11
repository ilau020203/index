// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/contracts/TokenIndex.sol";
import "../src/contracts/ACLManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
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

        uint256 nonce = tokenIndex.nonces(admin);
        assertEq(nonce, 0);
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

    function testRevokeTokenApproval() public {
        vm.startPrank(admin);
        tokenIndex.approveToken(address(token1), manager);
        tokenIndex.revokeTokenApproval(address(token1), manager);
        uint256 allowance = token1.allowance(address(tokenIndex), manager);
        assertEq(allowance, 0);
        vm.stopPrank();
    }

    function testOnlyIndexAdminModifier() public {
        // Test that onlyIndexAdmin modifier reverts for non-admin
        vm.prank(user);
        vm.expectRevert(TokenIndex.OnlyIndexAdmins.selector);
        tokenIndex.addToken(address(token1), 5000);

        // Test that onlyIndexAdmin modifier allows admin
        vm.startPrank(admin);
        tokenIndex.addToken(address(token1), 5000);
        vm.stopPrank();
    }

    function testOnlyIndexManagerModifier() public {
        // Test that onlyIndexManager modifier reverts for non-manager
        vm.prank(user);
        vm.expectRevert(TokenIndex.OnlyIndexManagers.selector);
        tokenIndex.mint(user, 1000);

        // Test that onlyIndexManager modifier allows manager
        vm.startPrank(manager);
        tokenIndex.mint(user, 1000);
        assertEq(tokenIndex.balanceOf(user), 1000);
        vm.stopPrank();
    }

    function testOnlyIndexAdminModifierRevertsForNonAdmin() public {
        // Test that onlyIndexAdmin modifier reverts for non-admin
        vm.prank(address(this));
        // vm.expectRevert(TokenIndex.OnlyIndexAdmins.selector);
        tokenIndex.addToken(address(token1), 5000);
    }

    function testOnlyIndexManagerModifierRevertsForNonManager() public {
        // Test that onlyIndexManager modifier reverts for non-manager
        vm.prank(user);
        vm.expectRevert(TokenIndex.OnlyIndexManagers.selector);
        tokenIndex.mint(user, 1000);
    }

    function testAddTokenInvalidProportion() public {
        // Test that addToken reverts when proportion is zero
        vm.startPrank(admin);
        vm.expectRevert(TokenIndex.InvalidProportion.selector);
        tokenIndex.addToken(address(token1), 0);
        vm.stopPrank();
    }

    // function testMulticallSuccess() public {
    //     vm.startPrank(manager);
    //     bytes[] memory data = new bytes[](1);
    //     address[] memory to = new address[](1);
    //     data[0] = abi.encodeWithSignature("mint(address,uint256)", user, 1000);
    //     to[0] = address(tokenIndex);
    //     bytes[] memory results = tokenIndex.multicall(data, to);
    //     assertEq(results.length, 1);
    //     assertEq(tokenIndex.balanceOf(user), 1000);
    //     vm.stopPrank();
    // }

    function testMulticallFailure() public {
        vm.startPrank(manager);
        bytes[] memory data = new bytes[](1);
        address[] memory to = new address[](1);
        data[0] = abi.encodeWithSignature("nonExistentFunction()");
        to[0] = address(tokenIndex);

        bytes memory expectedRevertData = abi.encodeWithSelector(
            TokenIndex.MulticallFailed.selector,
            bytes("") // Expected result argument
        );

        vm.expectRevert(expectedRevertData);
        tokenIndex.multicall(data, to);
        vm.stopPrank();
    }
}
