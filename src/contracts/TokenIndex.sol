// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../interfaces/ITokenIndex.sol";

/// @title TokenIndex
/// @dev Implementation of a token index that represents a basket of tokens with specified proportions
/// @notice This contract allows creation and management of token indices with customizable token weights
contract TokenIndex is ERC20, ERC20Burnable, ERC20Permit, ITokenIndex {
    TokenInfo[] private _tokens;
    IACLManager public override aclManager;

    bytes32 public immutable override INDEX_ADMIN_ROLE;
    bytes32 public immutable override INDEX_MANAGER_ROLE;

    error OnlyIndexAdmins();
    error InvalidProportion();
    error OnlyIndexManagers();
    error InvalidIndex();

    /// @dev Constructor to initialize the token index
    /// @param name The name of the index token
    /// @param symbol The symbol of the index token
    /// @param _aclManager The address of the ACL manager contract
    constructor(string memory name, string memory symbol, address _aclManager) ERC20(name, symbol) ERC20Permit(name) {
        aclManager = IACLManager(_aclManager);
        INDEX_ADMIN_ROLE = aclManager.INDEX_ADMIN_ROLE();
    }

    /// @dev Modifier to restrict access to index admins only
    modifier onlyIndexAdmin() {
        require(aclManager.hasRole(INDEX_ADMIN_ROLE, msg.sender), OnlyIndexAdmins());
        _;
    }

    /// @dev Modifier to restrict access to index managers only
    modifier onlyIndexManager() {
        require(aclManager.hasRole(INDEX_MANAGER_ROLE, msg.sender), OnlyIndexManagers());
        _;
    }

    /// @inheritdoc ITokenIndex
    function approveToken(address token, address manager) external onlyIndexAdmin {
        IERC20(token).approve(manager, type(uint256).max);
    }

    /// @inheritdoc ITokenIndex
    function revokeTokenApproval(address token, address manager) external onlyIndexAdmin {
        IERC20(token).approve(manager, 0);
    }

    /// @inheritdoc ITokenIndex
    function addToken(address token, uint256 proportion) external onlyIndexAdmin {
        require(proportion > 0, InvalidProportion());
        _tokens.push(TokenInfo({token: IERC20(token), proportion: proportion}));
    }

    /// @inheritdoc ITokenIndex
    function removeToken(uint256 index) external onlyIndexAdmin {
        require(index < _tokens.length, InvalidIndex());
        for (uint256 i = index; i < _tokens.length - 1; i++) {
            _tokens[i] = _tokens[i + 1];
        }
        _tokens.pop();
    }

    /// @inheritdoc ITokenIndex
    function editToken(uint256 index, uint256 proportion) external onlyIndexAdmin {
        require(index < _tokens.length, InvalidIndex());
        _tokens[index].proportion = proportion;
    }

    /// @inheritdoc ITokenIndex
    function getTokenProportions() external view returns (TokenInfo[] memory) {
        return _tokens;
    }

    /// @inheritdoc ITokenIndex
    function totalTokens() external view returns (uint256) {
        return _tokens.length;
    }

    /// @inheritdoc ITokenIndex
    function tokens(uint256 index) external view returns (TokenInfo memory) {
        return _tokens[index];
    }

    /// @inheritdoc ITokenIndex
    function mint(address to, uint256 amount) external onlyIndexManager {
        _mint(to, amount);
    }

    /// @inheritdoc ITokenIndex
    function burn(address from, uint256 amount) external onlyIndexManager {
        _burn(from, amount);
    }

    /// @inheritdoc IERC20Permit
    function nonces(address owner) public view override(ERC20Permit, IERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc ITokenIndex
    function multicall(bytes[] calldata data) external override onlyIndexManager returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            require(success, "Multicall: call failed");
            results[i] = result;
        }
        return results;
    }
}
