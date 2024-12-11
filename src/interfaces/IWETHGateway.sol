// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./IIndexManager.sol";
import "./IWETH.sol";

/// @title IWETHGateway
/// @notice Interface for the WETHGateway contract that handles wrapping/unwrapping ETH when interacting with the index
interface IWETHGateway {
    /// @notice Error thrown when ETH amount is insufficient
    error InsufficientETH();

    /// @notice Error thrown when ETH transfer fails
    error ETHTransferFailed();

    /// @notice Returns the index manager contract address
    function indexManager() external view returns (IIndexManager);

    /// @notice Returns the WETH contract address
    function WETH() external view returns (IWETH);

    /// @notice Deposits ETH into the index by first wrapping to WETH
    /// @param recipient Address to receive the index tokens
    function depositETH(address recipient) external payable;

    /// @notice Withdraws from index and receives ETH
    /// @param shares Amount of index shares to withdraw
    /// @param recipient Address to receive the ETH
    function withdrawETH(uint256 shares, address payable recipient) external;

    /// @notice Deposits ETH into the index by first wrapping to WETH
    receive() external payable;
}
