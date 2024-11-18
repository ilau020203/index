// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title IACLManager
 * @dev Interface for the Access Control List (ACL) Manager
 * @notice Manages roles and permissions for the protocol
 */
interface IACLManager is IAccessControl {
    /**
     * @dev Returns the keccak256 hash of the index admin role
     * @return bytes32 The role identifier for index admin
     */
    function INDEX_ADMIN_ROLE() external view returns (bytes32);

    /**
     * @dev Returns the keccak256 hash of the index manager role
     * @return bytes32 The role identifier for index manager
     */
    function INDEX_MANAGER_ROLE() external view returns (bytes32);

    /**
     * @dev Adds a new index admin
     * @param admin Address of the admin to add
     */
    function addIndexAdmin(address admin) external;

    /**
     * @dev Removes an index admin
     * @param admin Address of the admin to remove
     */
    function removeIndexAdmin(address admin) external;

    /**
     * @dev Adds a new index manager
     * @param manager Address of the manager to add
     */
    function addIndexManager(address manager) external;

    /**
     * @dev Removes an index manager
     * @param manager Address of the manager to remove
     */
    function removeIndexManager(address manager) external;

    /**
     * @dev Sets the admin role that manages a role
     * @param role The role that the admin role will manage
     * @param adminRole The admin role that will be granted permission to manage role
     */
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;
}
