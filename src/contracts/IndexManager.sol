// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../interfaces/IIndexManager.sol";
import "../interfaces/ITokenIndex.sol";
import "../interfaces/IPriceOracleGetter.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/console.sol";

contract IndexManager is IIndexManager {
    using SafeERC20 for IERC20Metadata;

    ITokenIndex public override tokenIndex;
    IPriceOracleGetter public override priceOracle;
    ISwapRouter public override swapRouter;
    IERC20Metadata public override baseToken;
    IACLManager public override aclManager;

    bytes32 public immutable override INDEX_ADMIN_ROLE;
    uint256 public immutable override TOKEN_INDEX_DECIMALS;
    uint256 public immutable BASE_TOKEN_DECIMALS;
    uint256 public constant override FEE_PERIOD = 30 days;
    uint256 public constant override PRICE_ORACLE_DECIMALS = 1e8;
    uint256 private constant PROPORTION_DECIMALS = 1e18;
    uint256 public constant override FEE_DENOMINATOR = 10000; // 10000 represents 100%
    uint256 public override lastFeeWithdrawal;
    uint256 public override feePercentage; // Fee percentage in basis points (1% = 100 basis points)
    // Mapping to store paths for token pairs
    mapping(address => mapping(address => bytes)) public override tokenPaths;

    modifier onlyIndexAdmin() {
        require(aclManager.hasRole(INDEX_ADMIN_ROLE, msg.sender), OnlyIndexAdmins());
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
        baseToken = IERC20Metadata(_baseToken);
        feePercentage = _feePercentage;
        lastFeeWithdrawal = block.timestamp;
        aclManager = IACLManager(_aclManager);
        INDEX_ADMIN_ROLE = tokenIndex.INDEX_ADMIN_ROLE();
        TOKEN_INDEX_DECIMALS = 10 ** tokenIndex.decimals();
        BASE_TOKEN_DECIMALS = 10 ** baseToken.decimals();
    }

    /// @inheritdoc IIndexManager
    function deposit(uint256 amount, address to) external override {
        baseToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 totalUSD = (amount * priceOracle.getAssetPrice(address(baseToken)) * TOKEN_INDEX_DECIMALS)
            / BASE_TOKEN_DECIMALS / PRICE_ORACLE_DECIMALS;

        SwapInfo[] memory swaps = calculateRequiredSwaps(amount);

        for (uint256 i = 0; i < swaps.length; i++) {
            if (swaps[i].tokenIn == swaps[i].tokenOut) {
                IERC20Metadata(swaps[i].tokenIn).safeTransfer(address(tokenIndex), swaps[i].amountIn);
                continue;
            }
            swapTokens(swaps[i].tokenIn, swaps[i].tokenOut, swaps[i].amountIn, address(tokenIndex));
        }

        uint256 indexTokenAmount = calculateMintAmount(totalUSD);
        tokenIndex.mint(to, indexTokenAmount);

        emit Deposit(msg.sender, amount, to);
    }

    /// @inheritdoc IIndexManager
    function withdraw(uint256 indexTokenAmount, address to) external override {
        uint256 userShare = (indexTokenAmount * TOKEN_INDEX_DECIMALS) / tokenIndex.totalSupply();
        tokenIndex.burn(msg.sender, indexTokenAmount);

        SwapInfo[] memory swaps = calculateRequiredSwapsForSurplusTokens(userShare);
        console.log("Swaps:");
        for (uint256 i = 0; i < swaps.length; i++) {
            console.log("Swap index:", i);
            console.log("Token in:", swaps[i].tokenIn);
            console.log("Token out:", swaps[i].tokenOut);
            console.log("Amount in:", swaps[i].amountIn);
        }
        bytes[] memory calls = new bytes[](swaps.length);
        address[] memory targets = new address[](swaps.length);
        for (uint256 i = 0; i < swaps.length; i++) {
            if (swaps[i].tokenIn == swaps[i].tokenOut) {
                calls[i] = abi.encodeWithSelector(IERC20.transfer.selector, to, swaps[i].amountIn);
                targets[i] = address(swaps[i].tokenIn);
                continue;
            }
            bytes memory path = tokenPaths[swaps[i].tokenIn][swaps[i].tokenOut];

            require(path.length > 0, PathNotSet());
            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: path,
                recipient: to,
                deadline: block.timestamp + 1,
                amountIn: swaps[i].amountIn,
                amountOutMinimum: 0
            });

            // Encode swap call
            calls[i] = abi.encodeWithSelector(swapRouter.exactInput.selector, params);
            targets[i] = address(swapRouter);
        }

        // Execute all swaps through multicall
        tokenIndex.multicall(calls, targets);

        emit Withdraw(msg.sender, indexTokenAmount, to);
    }

    /// @inheritdoc IIndexManager
    function withdrawFees() external override {
        require(block.timestamp >= lastFeeWithdrawal + FEE_PERIOD, FeeWithdrawalTooSoon());

        lastFeeWithdrawal = block.timestamp;

        ITokenIndex.TokenInfo[] memory tokenInfos = tokenIndex.getTokenProportions();
        for (uint256 i = 0; i < tokenInfos.length; i++) {
            IERC20Metadata token = tokenInfos[i].token;
            uint256 balance = token.balanceOf(address(tokenIndex));
            uint256 feeAmount = (balance * feePercentage) / FEE_DENOMINATOR;
            token.safeTransferFrom(address(tokenIndex), msg.sender, feeAmount);
        }

        emit FeeWithdrawn(msg.sender);
    }

    /// @inheritdoc IIndexManager
    function rebalance(SwapParams[] calldata swapParams) external override onlyIndexAdmin {
        bytes[] memory calls = new bytes[](swapParams.length);
        address[] memory to = new address[](swapParams.length);

        for (uint256 i = 0; i < swapParams.length; i++) {
            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: swapParams[i].path,
                recipient: address(tokenIndex),
                deadline: swapParams[i].deadline,
                amountIn: swapParams[i].amountIn,
                amountOutMinimum: swapParams[i].amountOutMinimum
            });

            // Encode swap call
            calls[i] = abi.encodeWithSelector(swapRouter.exactInput.selector, params);
            to[i] = address(swapRouter);
        }

        // Execute all swaps through multicall
        tokenIndex.multicall(calls, to);

        emit Rebalanced(swapParams);
    }

    /// @inheritdoc IIndexManager
    function setTokenPath(address tokenIn, address tokenOut, bytes calldata path) external override onlyIndexAdmin {
        tokenPaths[tokenIn][tokenOut] = path;
        emit TokenPathSet(tokenIn, tokenOut, path);
    }
    /// @inheritdoc IIndexManager

    function approveToken(address token, address manager) external override onlyIndexAdmin {
        IERC20Metadata(token).safeIncreaseAllowance(manager, type(uint256).max);
    }

    /// @inheritdoc IIndexManager
    function revokeTokenApproval(address token, address manager) external override onlyIndexAdmin {
        IERC20Metadata(token).safeDecreaseAllowance(manager, type(uint256).max);
    }

    function calculateMintAmount(uint256 totalUSD) internal view returns (uint256) {
        if (tokenIndex.totalSupply() == 0) {
            return totalUSD;
        } else {
            uint256 currentIndexTokenPrice = getCurrentIndexTokenPrice();
            return (totalUSD * 1e18) / currentIndexTokenPrice;
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
        return (totalValue * 1e18) / tokenIndex.totalSupply();
    }

    function findDeficitTokens(ITokenIndex.TokenInfo[] memory tokenInfos)
        internal
        view
        returns (uint256[] memory deficitTokenIds, uint256[] memory deficitDeltas, uint256 totalDeficit)
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
        deficitDeltas = new uint256[](deficitCount);

        uint256 deficitIndex = 0;

        // Calculate total value in USD of all tokens
        uint256 totalValue = 0;
        for (uint256 i = 0; i < tokenInfos.length; i++) {
            uint256 balance = tokenInfos[i].token.balanceOf(address(tokenIndex));
            uint256 price = priceOracle.getAssetPrice(address(tokenInfos[i].token));
            uint256 decimals = tokenInfos[i].token.decimals();
            totalValue += (balance * price * TOKEN_INDEX_DECIMALS) / 10 ** decimals / PRICE_ORACLE_DECIMALS;
        }

        // Fill deficit arrays and calculate total deficit in USD
        for (uint256 i = 0; i < currentProportions.length; i++) {
            if (currentProportions[i] < tokenInfos[i].proportion) {
                deficitTokenIds[deficitIndex] = i;
                // Convert proportion delta to USD value
                uint256 delta = ((tokenInfos[i].proportion - currentProportions[i]) * totalValue) / PROPORTION_DECIMALS;
                deficitDeltas[deficitIndex] = delta;
                totalDeficit += delta;
                deficitIndex++;
            }
        }
    }

    function findSurplusTokens(ITokenIndex.TokenInfo[] memory tokenInfos)
        internal
        view
        returns (
            uint256[] memory surplusTokenIds,
            uint256[] memory surplusDeltas,
            uint256 totalSurplus,
            uint256 totalValue
        )
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
        surplusDeltas = new uint256[](surplusCount);

        uint256 surplusIndex = 0;

        // Calculate total value in USD of all tokens
        totalValue = 0;
        for (uint256 i = 0; i < tokenInfos.length; i++) {
            uint256 balance = tokenInfos[i].token.balanceOf(address(tokenIndex));
            uint256 price = priceOracle.getAssetPrice(address(tokenInfos[i].token));
            uint256 decimals = tokenInfos[i].token.decimals();
            totalValue += (balance * price * TOKEN_INDEX_DECIMALS) / 10 ** decimals / PRICE_ORACLE_DECIMALS;
        }

        // Fill surplus arrays and calculate total surplus in USD
        for (uint256 i = 0; i < currentProportions.length; i++) {
            if (currentProportions[i] > tokenInfos[i].proportion) {
                surplusTokenIds[surplusIndex] = i;
                // Convert proportion delta to USD value
                uint256 delta = ((currentProportions[i] - tokenInfos[i].proportion) * totalValue) / PROPORTION_DECIMALS;
                surplusDeltas[surplusIndex] = delta;
                totalSurplus += delta;
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
        uint256[] memory decimals = new uint256[](tokenInfos.length);

        // First calculate total value in USD of all tokens
        for (uint256 i = 0; i < tokenInfos.length; i++) {
            balances[i] = tokenInfos[i].token.balanceOf(address(tokenIndex));
            prices[i] = priceOracle.getAssetPrice(address(tokenInfos[i].token));
            decimals[i] = tokenInfos[i].token.decimals();
            totalValue += (balances[i] * prices[i]) / 10 ** decimals[i];
        }

        // Then calculate each token's proportion based on its USD value
        for (uint256 i = 0; i < tokenInfos.length; i++) {
            uint256 tokenValue = (balances[i] * prices[i]) / 10 ** decimals[i];
            proportions[i] = totalValue > 0 ? (tokenValue * PROPORTION_DECIMALS) / totalValue : 0;
        }
    }

    function swapTokens(address tokenIn, address tokenOut, uint256 amountIn, address recipient) internal {
        bytes memory path = tokenPaths[tokenIn][tokenOut];
        require(amountIn > 0, SwapAmountZero());

        require(path.length > 0, PathNotSet());
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: recipient,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        uint256 amountOut = swapRouter.exactInput(params);
        emit TokenSwapped(tokenIn, tokenOut, amountIn, amountOut);
    }

    function calculateRequiredSwapsForSurplusTokens(uint256 userShare) internal view returns (SwapInfo[] memory) {
        ITokenIndex.TokenInfo[] memory tokenInfos = tokenIndex.getTokenProportions();
        SwapInfo[] memory swaps;
        if (tokenIndex.totalSupply() == 0) {
            swaps = new SwapInfo[](tokenInfos.length);
            for (uint256 i = 0; i < tokenInfos.length; i++) {
                swaps[i] = SwapInfo({
                    tokenIn: address(tokenInfos[i].token),
                    tokenOut: address(baseToken),
                    amountIn: tokenInfos[i].token.balanceOf(address(tokenIndex))
                });
            }
            return swaps;
        }
        (uint256[] memory surplusTokenIds, uint256[] memory surplusDeltas, uint256 totalSurplus, uint256 totalIndexUsd)
        = findSurplusTokens(tokenInfos);

        // Calculate total USD value of base token amount
        uint256 totalUSD = (userShare * totalIndexUsd) / tokenIndex.totalSupply();

        if (totalSurplus >= totalUSD) {
            uint256 swapCount = 0;
            // If total surplus is less than total USD, swap all surplus tokens
            swaps = new SwapInfo[](surplusTokenIds.length);
            uint256 totalRequiredUsd = 0;

            for (uint256 i = 0; i < surplusTokenIds.length - 1; i++) {
                uint256 requiredUSD = uint256(surplusDeltas[i]);
                uint256 tokenPrice = priceOracle.getAssetPrice(address(tokenInfos[surplusTokenIds[i]].token));
                uint256 amount = (requiredUSD * (10 ** tokenInfos[surplusTokenIds[i]].token.decimals()))
                    * PRICE_ORACLE_DECIMALS / tokenPrice / TOKEN_INDEX_DECIMALS;

                if (totalRequiredUsd + requiredUSD > totalUSD) {
                    break;
                }

                swaps[swapCount] = SwapInfo({
                    tokenIn: address(tokenInfos[surplusTokenIds[i]].token),
                    tokenOut: address(baseToken),
                    amountIn: amount
                });
                swapCount++;
                totalRequiredUsd += requiredUSD;
            }

            // Handle the last token separately
            if (surplusTokenIds.length > 0 && totalRequiredUsd < totalUSD) {
                uint256 lastIndex = surplusTokenIds.length - 1;
                uint256 remainingUsd = totalUSD - totalRequiredUsd;
                swaps[swapCount] = SwapInfo({
                    tokenIn: address(tokenInfos[surplusTokenIds[lastIndex]].token),
                    tokenOut: address(baseToken),
                    amountIn: (remainingUsd * (10 ** tokenInfos[surplusTokenIds[lastIndex]].token.decimals()))
                        * PRICE_ORACLE_DECIMALS / priceOracle.getAssetPrice(address(tokenInfos[surplusTokenIds[lastIndex]].token)) / TOKEN_INDEX_DECIMALS
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
            console.log("3");
            swaps = new SwapInfo[](tokenInfos.length);

            for (uint256 i = 0; i < surplusTokenIds.length; i++) {
                if (surplusDeltas[i] > 0) {
                    uint256 requiredUSD = uint256(surplusDeltas[i]);
                    console.log("requiredUSD:", requiredUSD);
                    uint256 tokenPrice = priceOracle.getAssetPrice(address(tokenInfos[surplusTokenIds[i]].token));
                    console.log("tokenPrice:", tokenPrice);
                    uint256 amount = (requiredUSD * (10 ** tokenInfos[surplusTokenIds[i]].token.decimals()))
                        * PRICE_ORACLE_DECIMALS / tokenPrice / TOKEN_INDEX_DECIMALS;
                    console.log("amount:", amount);

                    swaps[surplusTokenIds[i]] = SwapInfo({
                        tokenIn: address(tokenInfos[surplusTokenIds[i]].token),
                        tokenOut: address(baseToken),
                        amountIn: amount
                    });
                    totalUSD -= requiredUSD;
                }
            }

            // If there's remaining amount, distribute across all surplus tokens
            if (totalUSD > 0 && surplusTokenIds.length > 0) {
                uint256 totalDistributedAmount = 0;
                for (uint256 i = 0; i < tokenInfos.length - 1; i++) {
                    uint256 tokenPrice = priceOracle.getAssetPrice(address(tokenInfos[i].token));
                    uint256 amountToSwap = totalUSD * (10 ** tokenInfos[i].token.decimals())
                        / tokenInfos.length * PRICE_ORACLE_DECIMALS / tokenPrice / TOKEN_INDEX_DECIMALS;
                    totalDistributedAmount += amountToSwap;

                    swaps[i] = SwapInfo({
                        tokenIn: address(tokenInfos[i].token),
                        tokenOut: address(baseToken),
                        amountIn: swaps[i].amountIn + amountToSwap
                    });
                }
                // Handle the last token separately with the remaining amount
                uint256 lastIndex = tokenInfos.length - 1;
                uint256 remainingAmount = totalUSD - totalDistributedAmount;
                swaps[lastIndex] = SwapInfo({
                    tokenIn: address(tokenInfos[lastIndex].token),
                    tokenOut: address(baseToken),
                    amountIn: swaps[lastIndex].amountIn + remainingAmount
                });
            }

            console.log("32");

            return swaps;
        }
    }

    function calculateRequiredSwaps(uint256 amount) internal view returns (SwapInfo[] memory) {
        ITokenIndex.TokenInfo[] memory tokenInfos = tokenIndex.getTokenProportions();
        SwapInfo[] memory swaps;

        if (tokenIndex.totalSupply() == 0) {
            swaps = new SwapInfo[](tokenInfos.length);
            uint256 totalDistributedAmount = 0;

            // Distribute amount proportionally across all tokens except the last one
            for (uint256 i = 0; i < tokenInfos.length - 1; i++) {
                uint256 amountToSwap = (amount * tokenInfos[i].proportion) / PROPORTION_DECIMALS;
                totalDistributedAmount += amountToSwap;

                swaps[i] = SwapInfo({
                    tokenIn: address(baseToken),
                    tokenOut: address(tokenInfos[i].token),
                    amountIn: amountToSwap
                });
            }

            // Handle last token with remaining amount to ensure full amount is used
            uint256 lastIndex = tokenInfos.length - 1;
            uint256 remainingAmount = amount - totalDistributedAmount;
            swaps[lastIndex] = SwapInfo({
                tokenIn: address(baseToken),
                tokenOut: address(tokenInfos[lastIndex].token),
                amountIn: remainingAmount
            });
            return swaps;
        }
        (uint256[] memory deficitTokenIds, uint256[] memory deficitDeltas, uint256 totalDeficit) =
            findDeficitTokens(tokenInfos);

        // Calculate total USD value of base token amount
        uint256 baseTokenPrice = priceOracle.getAssetPrice(address(baseToken));
        uint256 totalUSD =
            (amount * baseTokenPrice * TOKEN_INDEX_DECIMALS) / BASE_TOKEN_DECIMALS / PRICE_ORACLE_DECIMALS;

        if (totalDeficit >= totalUSD) {
            uint256 swapCount = 0;
            // If total deficit is less than total USD, swap for all deficit tokens
            swaps = new SwapInfo[](deficitTokenIds.length);
            uint256 totalRequiredAmount = 0;

            for (uint256 i = 0; i < deficitTokenIds.length - 1; i++) {
                uint256 requiredUSD = deficitDeltas[i];
                uint256 requiredAmount =
                    requiredUSD * BASE_TOKEN_DECIMALS * PRICE_ORACLE_DECIMALS / baseTokenPrice / TOKEN_INDEX_DECIMALS;

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
            uint256 totalRequiredAmount = 0;
            swaps = new SwapInfo[](tokenInfos.length);
            for (uint256 i = 0; i < deficitTokenIds.length; i++) {
                uint256 requiredUSD = deficitDeltas[i];
                uint256 requiredAmount =
                    requiredUSD * BASE_TOKEN_DECIMALS * PRICE_ORACLE_DECIMALS / baseTokenPrice / TOKEN_INDEX_DECIMALS;
                swaps[deficitTokenIds[i]] = SwapInfo({
                    tokenIn: address(baseToken),
                    tokenOut: address(tokenInfos[deficitTokenIds[i]].token),
                    amountIn: requiredAmount
                });
                totalUSD -= requiredUSD;
                totalRequiredAmount += requiredAmount;
            }

            // If there's remaining amount, distribute across all tokens
            if (totalUSD > 0 && tokenInfos.length > 0) {
                for (uint256 i = 0; i < tokenInfos.length - 1; i++) {
                    uint256 amountToSwap =
                        totalUSD * PRICE_ORACLE_DECIMALS / tokenInfos.length / baseTokenPrice / TOKEN_INDEX_DECIMALS;
                    totalRequiredAmount += amountToSwap;
                    swaps[i] = SwapInfo({
                        tokenIn: address(baseToken),
                        tokenOut: address(tokenInfos[i].token),
                        amountIn: amountToSwap + swaps[i].amountIn
                    });
                }

                // Handle the last token separately with the remaining amount
                uint256 lastIndex = tokenInfos.length - 1;
                uint256 remainingAmount = amount - totalRequiredAmount;
                swaps[lastIndex] = SwapInfo({
                    tokenIn: address(baseToken),
                    tokenOut: address(tokenInfos[lastIndex].token),
                    amountIn: remainingAmount + swaps[lastIndex].amountIn
                });
            }
            return swaps;
        }
    }
}
