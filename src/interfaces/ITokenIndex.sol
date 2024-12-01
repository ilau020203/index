// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "./IACLManager.sol";
/**
 * @title ITokenIndex
 * @dev Interface for the TokenIndex contract
 */

interface ITokenIndex is IERC20, IERC20Permit {
    /**
     * @dev Struct containing information about a token in the index
     */
    struct TokenInfo {
        IERC20 token;
        uint256 proportion; // Proportion in basis points (1% = 100)
    }

    /**
     * @dev Returns the ACLManager contract address
     */
    function aclManager() external view returns (IACLManager);

    /**
     * @dev Returns the INDEX_ADMIN_ROLE bytes32 value
     */
    function INDEX_ADMIN_ROLE() external view returns (bytes32);

    /**
     * @dev Returns the INDEX_MANAGER_ROLE bytes32 value
     */
    function INDEX_MANAGER_ROLE() external view returns (bytes32);

    /**
     * @dev Adds a new token to the index with specified proportion
     * @param token Address of the token to add
     * @param proportion The proportion in basis points for the token
     */
    function addToken(address token, uint256 proportion) external;

    /**
     * @dev Returns array of TokenInfo structs containing all tokens and their proportions
     * @return Array of TokenInfo structs
     */
    function getTokenProportions() external view returns (TokenInfo[] memory);

    /**
     * @dev Mints new index tokens to specified address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @dev Burns index tokens from specified address
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external;

    /**
     * @dev Returns token info at specified index
     * @param index The index in the tokens array
     * @return TokenInfo struct containing token address and proportion
     */
    function tokens(uint256 index) external view returns (TokenInfo memory);

    /**
     * @dev Returns the total number of tokens in the index
     * @return The total number of tokens
     */
    function totalTokens() external view returns (uint256);

    /**
     * @dev Removes a token from the index at specified index
     * @param index The index in the tokens array
     */
    function removeToken(uint256 index) external;

    /**
     * @dev Edits the proportion of a token at specified index
     * @param index The index in the tokens array
     * @param proportion The new proportion in basis points
     */
    function editToken(uint256 index, uint256 proportion) external;

    /**
     * @dev Approves a token for a manager
     * @param token The address of the token to approve
     * @param manager The address of the manager to approve the token
     */
    function approveToken(address token, address manager) external;

    /**
     * @dev Revokes the approval of a token for a manager
     * @param token The address of the token to revoke approval
     * @param manager The address of the manager to revoke approval
     */
    function revokeTokenApproval(address token, address manager) external;

    /**
     * @dev Allows batch execution of multiple index manager functions
     * @param data Array of encoded function calls to execute
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
