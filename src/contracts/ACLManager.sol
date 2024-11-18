// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../interfaces/IACLManager.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract ACLManager is AccessControl, IACLManager {
    bytes32 public constant override INDEX_ADMIN_ROLE = keccak256("INDEX_ADMIN");
    bytes32 public constant override INDEX_MANAGER_ROLE = keccak256("INDEX_MANAGER");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(INDEX_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(INDEX_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
    }

    /// @inheritdoc IACLManager
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }

    /// @inheritdoc IACLManager
    function addIndexAdmin(address admin) external override onlyRole(getRoleAdmin(INDEX_ADMIN_ROLE)) {
        grantRole(INDEX_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IACLManager
    function removeIndexAdmin(address admin) external override onlyRole(getRoleAdmin(INDEX_ADMIN_ROLE)) {
        revokeRole(INDEX_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IACLManager
    function addIndexManager(address manager) external override onlyRole(getRoleAdmin(INDEX_ADMIN_ROLE)) {
        grantRole(INDEX_MANAGER_ROLE, manager);
    }

    /// @inheritdoc IACLManager
    function removeIndexManager(address manager) external override onlyRole(getRoleAdmin(INDEX_ADMIN_ROLE)) {
        revokeRole(INDEX_MANAGER_ROLE, manager);
    }
}
