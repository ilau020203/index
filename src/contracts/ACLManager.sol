// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '../interfaces/IACLManager.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

contract ACLManager is AccessControl, IACLManager {
  bytes32 public constant override INDEX_ADMIN_ROLE = keccak256('INDEX_ADMIN');

  /**
   * @dev Constructor
   * @dev The ACL admin should be initialized at the addressesProvider beforehand
   */
  constructor() {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(INDEX_ADMIN_ROLE, msg.sender);
    _setRoleAdmin(INDEX_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
    _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
  }

  /// @inheritdoc IACLManager
  function setRoleAdmin(
    bytes32 role,
    bytes32 adminRole
  ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    _setRoleAdmin(role, adminRole);
  }

  /// @inheritdoc IACLManager
  function addIndexAdmin(address admin) external onlyRole(getRoleAdmin(INDEX_ADMIN_ROLE)) override {
    grantRole(INDEX_ADMIN_ROLE, admin);
  }

  /// @inheritdoc IACLManager
  function removeIndexAdmin(address admin) external onlyRole(getRoleAdmin(INDEX_ADMIN_ROLE)) override {
    revokeRole(INDEX_ADMIN_ROLE, admin);
  }
}
