// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ACLManager} from "../src/contracts/ACLManager.sol";

contract ACLManagerTest is Test {
    ACLManager public aclManager;
    address public admin;
    address public user;

    function setUp() public {
        admin = address(1);
        user = address(2);
        vm.startPrank(admin);
        aclManager = new ACLManager();
        vm.stopPrank();
    }

    function testInitialRoles() public {
        assertTrue(aclManager.hasRole(aclManager.DEFAULT_ADMIN_ROLE(), admin));

        assertTrue(aclManager.hasRole(aclManager.INDEX_ADMIN_ROLE(), admin));

        assertEq(aclManager.getRoleAdmin(aclManager.INDEX_ADMIN_ROLE()), aclManager.DEFAULT_ADMIN_ROLE());
    }

    function testSetRoleAdminRevertWhenCalledByNonAdmin() public {
        bytes32 newRole = keccak256("NEW_ROLE");
        bytes32 indexAdminRole = aclManager.INDEX_ADMIN_ROLE();

        vm.prank(user);
        vm.expectRevert();
        aclManager.setRoleAdmin(newRole, indexAdminRole);
    }

    function testSetRoleAdminSuccessWhenCalledByAdmin() public {
        bytes32 newRole = keccak256("NEW_ROLE");
        bytes32 indexAdminRole = aclManager.INDEX_ADMIN_ROLE();

        vm.prank(admin);
        aclManager.setRoleAdmin(newRole, indexAdminRole);

        assertEq(aclManager.getRoleAdmin(newRole), indexAdminRole);
    }

    function testAddIndexAdminRevertWhenCalledByNonAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        aclManager.addIndexAdmin(user);
    }

    function testAddIndexAdminSuccessWhenCalledByAdmin() public {
        vm.prank(admin);
        aclManager.addIndexAdmin(user);

        assertTrue(aclManager.hasRole(aclManager.INDEX_ADMIN_ROLE(), user));
    }

    function testRemoveIndexAdminRevertWhenCalledByNonAdmin() public {
        vm.prank(admin);
        aclManager.addIndexAdmin(user);

        vm.prank(user);
        vm.expectRevert();
        aclManager.removeIndexAdmin(user);
    }

    function testRemoveIndexAdminSuccessWhenCalledByAdmin() public {
        vm.prank(admin);
        aclManager.addIndexAdmin(user);

        vm.prank(admin);
        aclManager.removeIndexAdmin(user);

        assertFalse(aclManager.hasRole(aclManager.INDEX_ADMIN_ROLE(), user));
    }

    function testRemoveIndexManagerRevertWhenCalledByNonAdmin() public {
        vm.prank(admin);
        aclManager.addIndexManager(user);

        vm.prank(user);
        vm.expectRevert();
        aclManager.removeIndexManager(user);
    }

    function testRemoveIndexManagerSuccessWhenCalledByAdmin() public {
        vm.prank(admin);
        aclManager.addIndexManager(user);

        vm.prank(admin);
        aclManager.removeIndexManager(user);

        assertFalse(aclManager.hasRole(aclManager.INDEX_MANAGER_ROLE(), user));
    }
}
