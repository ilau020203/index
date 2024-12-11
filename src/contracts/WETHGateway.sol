// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ITokenIndex.sol";
import "../interfaces/IWETHGateway.sol";

/// @title WETHGateway
/// @notice Gateway contract for wrapping/unwrapping ETH when interacting with the index
contract WETHGateway is IWETHGateway {
    using SafeERC20 for IERC20;

    IIndexManager public immutable override indexManager;
    IWETH public immutable override WETH;

    constructor(address _indexManager, address _weth) {
        indexManager = IIndexManager(_indexManager);
        WETH = IWETH(_weth);
        WETH.approve(address(indexManager), type(uint256).max);
        indexManager.tokenIndex().approve(address(indexManager), type(uint256).max);
    }

    receive() external payable {}

    /// @inheritdoc IWETHGateway
    function depositETH(address recipient) external payable {
        _depositETH(recipient);
    }

    /// @inheritdoc IWETHGateway
    function withdrawETH(uint256 shares, address payable recipient) external {
        // Transfer shares from user to this contract
        indexManager.tokenIndex().transferFrom(msg.sender, address(this), shares);

        // Withdraw to get WETH
        indexManager.withdraw(shares, address(this));

        // Convert WETH to ETH and send to recipient
        uint256 wethBalance = WETH.balanceOf(address(this));

        WETH.withdraw(wethBalance);

        recipient.transfer(wethBalance);
    }

    function _depositETH(address recipient) internal {
        if (msg.value == 0) revert InsufficientETH();

        // Wrap ETH to WETH
        WETH.deposit{value: msg.value}();

        // Deposit WETH into index
        indexManager.deposit(msg.value, recipient);
    }
}
