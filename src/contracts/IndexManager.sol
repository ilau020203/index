// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../interfaces/IIndexManager.sol";
import "../interfaces/ITokenIndex.sol";
import "../interfaces/IPriceOracleGetter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract IndexManager is IIndexManager {
    using SafeERC20 for IERC20;

    ITokenIndex public tokenIndex;
    IPriceOracleGetter public priceOracle;
    ISwapRouter public swapRouter;
    IERC20 public baseToken;

    constructor(address _tokenIndex, address _priceOracle, address _swapRouter, address _baseToken) {
        tokenIndex = ITokenIndex(_tokenIndex);
        priceOracle = IPriceOracleGetter(_priceOracle);
        swapRouter = ISwapRouter(_swapRouter);
        baseToken = IERC20(_baseToken);
    }

    function deposit(uint256 amount) external {
        baseToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 indexTokenAmount = calculateMintAmount(amount);
        tokenIndex.mint(msg.sender, indexTokenAmount);
    }

    function withdraw(uint256 indexTokenAmount) external {
        tokenIndex.burn(msg.sender, indexTokenAmount);
        uint256[] memory assetAmounts = calculateWithdrawAmounts(indexTokenAmount);
        for (uint256 i = 0; i < assetAmounts.length; i++) {
            IERC20(tokenIndex.tokens(i).token).safeTransfer(msg.sender, assetAmounts[i]);
        }
    }

    function rebalance() external {
        uint256[] memory currentProportions = getCurrentProportions();
        uint256[] memory targetProportions = getTargetProportions();
        for (uint256 i = 0; i < currentProportions.length; i++) {
            if (currentProportions[i] != targetProportions[i]) {
                performSwap(i, currentProportions[i], targetProportions[i]);
            }
        }
    }

    function calculateMintAmount(uint256 amount) internal view returns (uint256) {
        uint256 totalValue = 0;
        uint256[] memory prices = new uint256[](tokenIndex.totalTokens());
        for (uint256 i = 0; i < tokenIndex.totalTokens(); i++) {
            prices[i] = priceOracle.getAssetPrice(address(tokenIndex.tokens(i).token));
            totalValue += prices[i] * tokenIndex.tokens(i).proportion;
        }
        return (amount * totalValue) / 1e18; 
    }

    function calculateWithdrawAmounts(uint256 indexTokenAmount) internal view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](tokenIndex.totalTokens());
        for (uint256 i = 0; i < tokenIndex.totalTokens(); i++) {
            amounts[i] = (indexTokenAmount * tokenIndex.tokens(i).proportion) / 1e18;
        }
        return amounts;
    }

    function getCurrentProportions() internal view returns (uint256[] memory) {
        uint256[] memory proportions = new uint256[](tokenIndex.totalTokens());
        for (uint256 i = 0; i < tokenIndex.totalTokens(); i++) {
            proportions[i] = tokenIndex.tokens(i).proportion;
        }
        return proportions;
    }

    function getTargetProportions() internal view returns (uint256[] memory) {
        uint256[] memory targetProportions = new uint256[](tokenIndex.totalTokens());
        for (uint256 i = 0; i < tokenIndex.totalTokens(); i++) {
            targetProportions[i] = tokenIndex.tokens(i).proportion;
        }
        return targetProportions;
    }

    function performSwap(uint256 index, uint256 currentProportion, uint256 targetProportion) internal {
        uint256 amountToSwap = calculateSwapAmount(index, currentProportion, targetProportion);

        IERC20 token = tokenIndex.tokens(index).token;

        token.safeApprove(address(swapRouter), amountToSwap);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token),
            tokenOut: address(baseToken),
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 1, 
            amountIn: amountToSwap,
            amountOutMinimum: 0, 
            sqrtPriceLimitX96: 0 
        });

        swapRouter.exactInputSingle(params);
    }

    function calculateSwapAmount(uint256 index, uint256 currentProportion, uint256 targetProportion) internal view returns (uint256) {
        uint256 totalSupply = tokenIndex.totalSupply();
        uint256 currentAmount = (totalSupply * currentProportion) / 1e18;
        uint256 targetAmount = (totalSupply * targetProportion) / 1e18;
        return currentAmount > targetAmount ? currentAmount - targetAmount : targetAmount - currentAmount;
    }
}
