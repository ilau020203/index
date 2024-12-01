// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ITokenIndex} from "./ITokenIndex.sol";
import {IACLManager} from "./IACLManager.sol";
import {IPriceOracleGetter} from "./IPriceOracleGetter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IIndexManager
/// @notice Interface for managing token index operations including deposits, withdrawals, and rebalancing
interface IIndexManager {
    /// @notice Struct containing information for a token swap
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of input token to swap
    struct SwapInfo {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
    }

    /// @notice Struct containing parameters for executing a swap
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of input token to swap
    /// @param amountOutMinimum Minimum amount of output token to receive
    /// @param path Encoded path for the swap
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMinimum;
        bytes path;
    }

    /// @notice Error thrown when attempting to withdraw fees too soon after previous withdrawal
    error FeeWithdrawalTooSoon();

    /// @notice Error thrown when account has insufficient balance for operation
    error InsufficientBalance();

    /// @notice Returns the token index contract
    function tokenIndex() external view returns (ITokenIndex);

    /// @notice Returns the price oracle contract
    function priceOracle() external view returns (IPriceOracleGetter);

    /// @notice Returns the swap router contract
    function swapRouter() external view returns (ISwapRouter);

    /// @notice Returns the base token contract
    function baseToken() external view returns (IERC20);

    /// @notice Returns the ACL manager contract
    function aclManager() external view returns (IACLManager);

    /// @notice Returns the index admin role
    function INDEX_ADMIN_ROLE() external view returns (bytes32);

    /// @notice Returns the fee period
    function FEE_PERIOD() external pure returns (uint256);

    /// @notice Returns the fee denominator
    function FEE_DENOMINATOR() external pure returns (uint256);

    /// @notice Returns the last fee withdrawal timestamp
    function lastFeeWithdrawal() external view returns (uint256);

    /// @notice Returns the fee percentage
    function feePercentage() external view returns (uint256);

    /// @notice Returns the swap path for a token pair
    function tokenPaths(address tokenIn, address tokenOut) external view returns (bytes memory);

    /// @notice Calculates the required swaps needed for a given amount
    /// @param amount The amount to calculate swaps for
    /// @return Array of SwapInfo structs containing required swap details
    function calculateRequiredSwaps(uint256 amount) external view returns (SwapInfo[] memory);

    /// @notice Deposits tokens into the index
    /// @param amount Amount of tokens to deposit
    /// @param to Address to mint index tokens to
    function deposit(uint256 amount, address to) external;

    /// @notice Withdraws tokens from the index
    /// @param indexTokenAmount Amount of index tokens to burn
    /// @param to Address to send withdrawn tokens to
    function withdraw(uint256 indexTokenAmount, address to) external;

    /// @notice Rebalances the index by executing a series of swaps
    /// @param swapParams Array of SwapParams structs containing swap details
    function rebalance(SwapParams[] calldata swapParams) external;

    /// @notice Sets the swap path for a token pair
    /// @param tokenIn Address of input token
    /// @param tokenOut Address of output token
    /// @param path Encoded path for the swap
    function setTokenPath(address tokenIn, address tokenOut, bytes calldata path) external;

    /// @notice Withdraws accumulated fees to the fee recipient
    function withdrawFees() external;
}
