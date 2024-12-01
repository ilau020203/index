// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../interfaces/IIndexManager.sol";
import "../interfaces/ITokenIndex.sol";
import "../interfaces/IPriceOracleGetter.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @inheritdoc IIndexManager
contract IndexManager is IIndexManager {
    using SafeERC20 for IERC20;

    ITokenIndex public override tokenIndex;
    IPriceOracleGetter public override priceOracle;
    ISwapRouter public override swapRouter;
    IERC20 public override baseToken;
    IACLManager public override aclManager;

    bytes32 public immutable override INDEX_ADMIN_ROLE;
    uint256 public constant override FEE_PERIOD = 30 days;
    uint256 public constant override FEE_DENOMINATOR = 10000; // 10000 represents 100%
    uint256 public override lastFeeWithdrawal;
    uint256 public override feePercentage; // Fee percentage in basis points (1% = 100 basis points)
    // Mapping to store paths for token pairs
    mapping(address => mapping(address => bytes)) public override tokenPaths;

    modifier onlyIndexAdmin() {
        require(aclManager.hasRole(INDEX_ADMIN_ROLE, msg.sender), "Only index admins can call this function");
        _;
    }

    constructor(
        address _tokenIndex,
        address _priceOracle,
        address _swapRouter,
        address _baseToken,
        uint256 _feePercentage,
        address _aclManager
    ) {
        tokenIndex = ITokenIndex(_tokenIndex);
        priceOracle = IPriceOracleGetter(_priceOracle);
        swapRouter = ISwapRouter(_swapRouter);
        baseToken = IERC20(_baseToken);
        feePercentage = _feePercentage;
        lastFeeWithdrawal = block.timestamp;
        aclManager = IACLManager(_aclManager);
        INDEX_ADMIN_ROLE = tokenIndex.INDEX_ADMIN_ROLE();
    }

    /// @inheritdoc IIndexManager
    function calculateRequiredSwaps(uint256 amount) public view override returns (SwapInfo[] memory) {
        ITokenIndex.TokenInfo[] memory tokenInfos = tokenIndex.getTokenProportions();
        (uint256[] memory deficitTokenIds, int256[] memory deficitDeltas, uint256 totalDeficit) =
            findDeficitTokens(tokenInfos);

        // Calculate total USD value of base token amount
        uint256 totalUSD = amount * priceOracle.getAssetPrice(address(baseToken));

        SwapInfo[] memory swaps;

        if (totalDeficit < totalUSD) {
            uint256 swapCount = 0;
            // If total deficit is less than total USD, swap for all deficit tokens
            swaps = new SwapInfo[](deficitTokenIds.length);
            uint256 totalRequiredAmount = 0;

            for (uint256 i = 0; i < deficitTokenIds.length - 1; i++) {
                uint256 requiredUSD = uint256(-deficitDeltas[i]) * totalUSD / 1e18;
                uint256 tokenPrice = priceOracle.getAssetPrice(address(tokenInfos[deficitTokenIds[i]].token));
                uint256 requiredAmount = requiredUSD / tokenPrice;

                if (totalRequiredAmount + requiredAmount > amount) {
                    break;
                }

                swaps[swapCount] = SwapInfo({
                    tokenIn: address(baseToken),
                    tokenOut: address(tokenInfos[deficitTokenIds[i]].token),
                    amountIn: requiredAmount
                });
                swapCount++;
                totalRequiredAmount += requiredAmount;
            }

            // Handle the last token separately
            if (deficitTokenIds.length > 0 && totalRequiredAmount < amount) {
                uint256 lastIndex = deficitTokenIds.length - 1;
                uint256 remainingAmount = amount - totalRequiredAmount;
                swaps[swapCount] = SwapInfo({
                    tokenIn: address(baseToken),
                    tokenOut: address(tokenInfos[deficitTokenIds[lastIndex]].token),
                    amountIn: remainingAmount
                });
                swapCount++;
            }
            // Resize array to actual swap count
            SwapInfo[] memory finalSwaps = new SwapInfo[](swapCount);
            for (uint256 i = 0; i < swapCount; i++) {
                finalSwaps[i] = swaps[i];
            }

            return finalSwaps;
        } else {
            // First try to cover imbalances
            swaps = new SwapInfo[](tokenInfos.length);
            for (uint256 i = 0; i < deficitTokenIds.length; i++) {
                if (deficitDeltas[i] < 0) {
                    uint256 requiredUSD = uint256(-deficitDeltas[i]) * totalUSD / 1e18;
                    uint256 tokenPrice = priceOracle.getAssetPrice(address(tokenInfos[deficitTokenIds[i]].token));
                    uint256 requiredAmount = requiredUSD / tokenPrice;

                    if (totalUSD >= requiredUSD) {
                        swaps[deficitTokenIds[i]] = SwapInfo({
                            tokenIn: address(baseToken),
                            tokenOut: address(tokenInfos[deficitTokenIds[i]].token),
                            amountIn: requiredAmount
                        });
                        totalUSD -= requiredUSD;
                    }
                }
            }

            // If there's remaining amount, distribute across all tokens
            if (totalUSD > 0 && tokenInfos.length > 0) {
                uint256 totalDistributedAmount = 0;
                for (uint256 i = 0; i < tokenInfos.length - 1; i++) {
                    uint256 tokenPrice = priceOracle.getAssetPrice(address(tokenInfos[i].token));
                    uint256 amountToSwap = totalUSD / tokenInfos.length / tokenPrice;
                    totalDistributedAmount += amountToSwap;

                    swaps[i] = SwapInfo({
                        tokenIn: address(baseToken),
                        tokenOut: address(tokenInfos[i].token),
                        amountIn: amountToSwap
                    });
                }

                // Handle the last token separately with the remaining amount
                uint256 lastIndex = tokenInfos.length - 1;
                uint256 remainingAmount = totalUSD - totalDistributedAmount;
                swaps[lastIndex] = SwapInfo({
                    tokenIn: address(baseToken),
                    tokenOut: address(tokenInfos[lastIndex].token),
                    amountIn: remainingAmount
                });
            }
            return swaps;
        }
    }

    /// @inheritdoc IIndexManager
    function deposit(uint256 amount, address to) external override {
        baseToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 totalUSD = amount * priceOracle.getAssetPrice(address(baseToken));
        uint256 timeSinceLastFee = block.timestamp - lastFeeWithdrawal;
        uint256 effectiveFeePercentage = (feePercentage * timeSinceLastFee) / FEE_PERIOD;
        uint256 effectiveTotalUSD = totalUSD * (FEE_DENOMINATOR - effectiveFeePercentage) / FEE_DENOMINATOR;

        SwapInfo[] memory swaps = calculateRequiredSwaps(amount);

        for (uint256 i = 0; i < swaps.length; i++) {
            swapTokens(swaps[i].tokenIn, swaps[i].tokenOut, swaps[i].amountIn);
            IERC20(swaps[i].tokenOut).safeTransfer(address(tokenIndex), swaps[i].amountIn);
        }

        uint256 indexTokenAmount = calculateMintAmount(effectiveTotalUSD);
        tokenIndex.mint(to, indexTokenAmount);
    }

    /// @inheritdoc IIndexManager
    function withdraw(uint256 indexTokenAmount, address to) external override {
        tokenIndex.burn(msg.sender, indexTokenAmount);
        uint256 userShare = indexTokenAmount * 1e18 / tokenIndex.totalSupply();
        uint256 timeSinceLastFee = block.timestamp - lastFeeWithdrawal;
        uint256 effectiveFeePercentage = (feePercentage * timeSinceLastFee) / FEE_PERIOD;

        ITokenIndex.TokenInfo[] memory tokenInfos = tokenIndex.getTokenProportions();
        for (uint256 i = 0; i < tokenInfos.length; i++) {
            uint256 tokenBalance = tokenInfos[i].token.balanceOf(address(tokenIndex));
            uint256 tokenAmount = userShare * tokenBalance / 1e18;
            uint256 effectiveTokenAmount = tokenAmount * (FEE_DENOMINATOR - effectiveFeePercentage) / FEE_DENOMINATOR;
            tokenInfos[i].token.safeTransfer(to, effectiveTokenAmount);
        }

        SwapInfo[] memory swaps = calculateRequiredSwapsForSurplusTokens(userShare);

        for (uint256 i = 0; i < swaps.length; i++) {
            swapTokens(swaps[i].tokenIn, swaps[i].tokenOut, swaps[i].amountIn);
            IERC20(swaps[i].tokenOut).safeTransfer(to, swaps[i].amountIn);
        }
    }

    /// @inheritdoc IIndexManager
    function rebalance(SwapParams[] calldata swapParams) external override onlyIndexAdmin {
        bytes[] memory calls = new bytes[](swapParams.length);

        for (uint256 i = 0; i < swapParams.length; i++) {
            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: swapParams[i].path,
                recipient: address(tokenIndex),
                deadline: block.timestamp,
                amountIn: swapParams[i].amountIn,
                amountOutMinimum: swapParams[i].amountOutMinimum
            });

            // Encode swap call
            calls[i] = abi.encodeWithSelector(swapRouter.exactInput.selector, params);
        }

        // Execute all swaps through multicall
        tokenIndex.multicall(calls);
    }

    function calculateMintAmount(uint256 totalUSD) internal view returns (uint256) {
        if (tokenIndex.totalSupply() == 0) {
            return totalUSD;
        } else {
            uint256 currentIndexTokenPrice = getCurrentIndexTokenPrice();
            return totalUSD * 1e18 / currentIndexTokenPrice;
        }
    }

    function getCurrentIndexTokenPrice() internal view returns (uint256) {
        uint256 totalValue = 0;
        ITokenIndex.TokenInfo[] memory tokenInfos = tokenIndex.getTokenProportions();
        for (uint256 i = 0; i < tokenInfos.length; i++) {
            uint256 tokenPrice = priceOracle.getAssetPrice(address(tokenInfos[i].token));
            uint256 tokenBalance = tokenInfos[i].token.balanceOf(address(tokenIndex));
            totalValue += tokenPrice * tokenBalance;
        }
        return totalValue * 1e18 / tokenIndex.totalSupply();
    }

    function findDeficitTokens(ITokenIndex.TokenInfo[] memory tokenInfos)
        internal
        view
        returns (uint256[] memory deficitTokenIds, int256[] memory deficitDeltas, uint256 totalDeficit)
    {
        uint256[] memory currentProportions = getCurrentProportions(tokenInfos);

        uint256 deficitCount = 0;
        totalDeficit = 0;

        // Count deficit tokens
        for (uint256 i = 0; i < currentProportions.length; i++) {
            if (currentProportions[i] < tokenInfos[i].proportion) {
                deficitCount++;
            }
        }

        deficitTokenIds = new uint256[](deficitCount);
        deficitDeltas = new int256[](deficitCount);

        uint256 deficitIndex = 0;

        // Fill deficit arrays and calculate total deficit
        for (uint256 i = 0; i < currentProportions.length; i++) {
            int256 delta = int256(currentProportions[i]) - int256(tokenInfos[i].proportion);
            if (delta < 0) {
                deficitTokenIds[deficitIndex] = i;
                deficitDeltas[deficitIndex] = delta;
                totalDeficit += uint256(-delta);
                deficitIndex++;
            }
        }
    }

    function findSurplusTokens(ITokenIndex.TokenInfo[] memory tokenInfos)
        internal
        view
        returns (uint256[] memory surplusTokenIds, int256[] memory surplusDeltas, uint256 totalSurplus)
    {
        uint256[] memory currentProportions = getCurrentProportions(tokenInfos);

        uint256 surplusCount = 0;
        totalSurplus = 0;

        // Count surplus tokens
        for (uint256 i = 0; i < currentProportions.length; i++) {
            if (currentProportions[i] > tokenInfos[i].proportion) {
                surplusCount++;
            }
        }

        surplusTokenIds = new uint256[](surplusCount);
        surplusDeltas = new int256[](surplusCount);

        uint256 surplusIndex = 0;

        // Fill surplus arrays and calculate total surplus
        for (uint256 i = 0; i < currentProportions.length; i++) {
            int256 delta = int256(currentProportions[i]) - int256(tokenInfos[i].proportion);
            if (delta > 0) {
                surplusTokenIds[surplusIndex] = i;
                surplusDeltas[surplusIndex] = delta;
                totalSurplus += uint256(delta);
                surplusIndex++;
            }
        }
    }

    function getCurrentProportions(ITokenIndex.TokenInfo[] memory tokenInfos)
        internal
        view
        returns (uint256[] memory proportions)
    {
        proportions = new uint256[](tokenInfos.length);
        uint256 totalValue = 0;
        uint256[] memory balances = new uint256[](tokenInfos.length);
        uint256[] memory prices = new uint256[](tokenInfos.length);

        // First calculate total value in USD of all tokens
        for (uint256 i = 0; i < tokenInfos.length; i++) {
            balances[i] = tokenInfos[i].token.balanceOf(address(tokenIndex));
            prices[i] = priceOracle.getAssetPrice(address(tokenInfos[i].token));
            totalValue += balances[i] * prices[i];
        }

        // Then calculate each token's proportion based on its USD value
        for (uint256 i = 0; i < tokenInfos.length; i++) {
            uint256 tokenValue = balances[i] * prices[i];
            proportions[i] = totalValue > 0 ? (tokenValue * 1e18) / totalValue : 0;
        }
    }

    function swapTokens(address tokenIn, address tokenOut, uint256 amountIn) internal {
        bytes memory path = tokenPaths[tokenIn][tokenOut];
        require(path.length > 0, "Path not set for token pair");

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(this),
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        swapRouter.exactInput(params);
    }

    /// @inheritdoc IIndexManager
    function setTokenPath(address tokenIn, address tokenOut, bytes calldata path) external override onlyIndexAdmin {
        tokenPaths[tokenIn][tokenOut] = path;
    }

    /// @inheritdoc IIndexManager
    function withdrawFees() external override {
        uint256 periodsElapsed = (block.timestamp - lastFeeWithdrawal) / FEE_PERIOD;
        if (periodsElapsed == 0) {
            revert FeeWithdrawalTooSoon();
        }

        lastFeeWithdrawal += periodsElapsed * FEE_PERIOD;

        ITokenIndex.TokenInfo[] memory tokenInfos = tokenIndex.getTokenProportions();
        for (uint256 i = 0; i < tokenInfos.length; i++) {
            IERC20 token = tokenInfos[i].token;
            uint256 balance = token.balanceOf(address(tokenIndex));
            uint256 feeAmount = (balance * feePercentage * periodsElapsed) / FEE_DENOMINATOR;
            token.safeTransfer(msg.sender, feeAmount);
        }
    }

    function calculateRequiredSwapsForSurplusTokens(uint256 amount) internal view returns (SwapInfo[] memory) {
        ITokenIndex.TokenInfo[] memory tokenInfos = tokenIndex.getTokenProportions();
        (uint256[] memory surplusTokenIds, int256[] memory surplusDeltas, uint256 totalSurplus) =
            findSurplusTokens(tokenInfos);

        // Calculate total USD value of base token amount
        uint256 totalUSD = amount * priceOracle.getAssetPrice(address(baseToken));

        SwapInfo[] memory swaps;

        if (totalSurplus < totalUSD) {
            uint256 swapCount = 0;
            // If total surplus is less than total USD, swap all surplus tokens
            swaps = new SwapInfo[](surplusTokenIds.length);
            uint256 totalRequiredAmount = 0;

            for (uint256 i = 0; i < surplusTokenIds.length - 1; i++) {
                uint256 requiredUSD = uint256(surplusDeltas[i]) * totalUSD / 1e18;
                uint256 tokenPrice = priceOracle.getAssetPrice(address(tokenInfos[surplusTokenIds[i]].token));
                uint256 requiredAmount = requiredUSD / tokenPrice;

                if (totalRequiredAmount + requiredAmount > amount) {
                    break;
                }

                swaps[swapCount] = SwapInfo({
                    tokenIn: address(tokenInfos[surplusTokenIds[i]].token),
                    tokenOut: address(baseToken),
                    amountIn: requiredAmount
                });
                swapCount++;
                totalRequiredAmount += requiredAmount;
            }

            // Handle the last token separately
            if (surplusTokenIds.length > 0 && totalRequiredAmount < amount) {
                uint256 lastIndex = surplusTokenIds.length - 1;
                uint256 remainingAmount = amount - totalRequiredAmount;
                swaps[swapCount] = SwapInfo({
                    tokenIn: address(tokenInfos[surplusTokenIds[lastIndex]].token),
                    tokenOut: address(baseToken),
                    amountIn: remainingAmount
                });
                swapCount++;
            }

            // Resize array to actual swap count
            SwapInfo[] memory finalSwaps = new SwapInfo[](swapCount);
            for (uint256 i = 0; i < swapCount; i++) {
                finalSwaps[i] = swaps[i];
            }

            return finalSwaps;
        } else {
            // First try to cover imbalances
            swaps = new SwapInfo[](tokenInfos.length);
            for (uint256 i = 0; i < surplusTokenIds.length; i++) {
                if (surplusDeltas[i] > 0) {
                    uint256 requiredUSD = uint256(surplusDeltas[i]) * totalUSD / 1e18;
                    uint256 tokenPrice = priceOracle.getAssetPrice(address(tokenInfos[surplusTokenIds[i]].token));
                    uint256 requiredAmount = requiredUSD / tokenPrice;

                    if (totalUSD >= requiredUSD) {
                        swaps[surplusTokenIds[i]] = SwapInfo({
                            tokenIn: address(tokenInfos[surplusTokenIds[i]].token),
                            tokenOut: address(baseToken),
                            amountIn: requiredAmount
                        });
                        totalUSD -= requiredUSD;
                    }
                }
            }

            // If there's remaining amount, distribute across all surplus tokens
            if (totalUSD > 0 && surplusTokenIds.length > 0) {
                uint256 totalDistributedAmount = 0;
                for (uint256 i = 0; i < surplusTokenIds.length - 1; i++) {
                    uint256 tokenPrice = priceOracle.getAssetPrice(address(tokenInfos[surplusTokenIds[i]].token));
                    uint256 amountToSwap = totalUSD / surplusTokenIds.length / tokenPrice;
                    totalDistributedAmount += amountToSwap;

                    swaps[i] = SwapInfo({
                        tokenIn: address(tokenInfos[surplusTokenIds[i]].token),
                        tokenOut: address(baseToken),
                        amountIn: amountToSwap
                    });
                }

                // Handle the last token separately with the remaining amount
                uint256 lastIndex = surplusTokenIds.length - 1;
                uint256 remainingAmount = totalUSD - totalDistributedAmount;
                swaps[lastIndex] = SwapInfo({
                    tokenIn: address(tokenInfos[surplusTokenIds[lastIndex]].token),
                    tokenOut: address(baseToken),
                    amountIn: remainingAmount
                });
            }
            return swaps;
        }
    }
}
