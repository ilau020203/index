// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '../interfaces/AggregatorV3Interface.sol';
import '../interfaces/IPriceOracleGetter.sol';
import '../interfaces/IPriceOracle.sol';

contract PriceOracle is IPriceOracle {
    IACLManager public immutable ACL_MANAGER;
    mapping(address => AggregatorV3Interface) internal assetsSources;
    IPriceOracleGetter private _fallbackOracle;
    
    uint256 public constant BASE_CURRENCY_UNIT = 1e18;
    address public immutable BASE_CURRENCY;

    error OnlyIndexAdmins();
    error InconsistentParamsLength();

    constructor(address aclManager, address baseCurrency) {
        ACL_MANAGER = IACLManager(aclManager);
        BASE_CURRENCY = baseCurrency;
    }

    modifier onlyIndexAdmins() {
        require(ACL_MANAGER.hasRole(ACL_MANAGER.INDEX_ADMIN_ROLE(), msg.sender), OnlyIndexAdmins());
        _;
    }
    /// @inheritdoc IPriceOracle
    function setAssetSources(
        address[] calldata assets,
        address[] calldata sources
    ) external override onlyIndexAdmins {
        _setAssetsSources(assets, sources);
    }

    /// @inheritdoc IPriceOracle
    function setFallbackOracle(
        address fallbackOracle
    ) external override onlyIndexAdmins {
        _setFallbackOracle(fallbackOracle);
    }

    /**
     * @notice Internal function to set the sources for each asset
     * @param assets The addresses of the assets
     * @param sources The address of the source of each asset
     */
    function _setAssetsSources(address[] memory assets, address[] memory sources) internal {
        require(assets.length == sources.length, InconsistentParamsLength());
        for (uint256 i = 0; i < assets.length; i++) {
            assetsSources[assets[i]] = AggregatorV3Interface(sources[i]);
            emit AssetSourceUpdated(assets[i], sources[i]);
        }
    }

    /**
     * @notice Internal function to set the fallback oracle
     * @param fallbackOracle The address of the fallback oracle
     */
    function _setFallbackOracle(address fallbackOracle) internal {
        _fallbackOracle = IPriceOracleGetter(fallbackOracle);
        emit FallbackOracleUpdated(fallbackOracle);
    }

    /// @inheritdoc IPriceOracleGetter
    function getAssetPrice(address asset) public view override returns (uint256) {
        AggregatorV3Interface source = assetsSources[asset];

        if (asset == BASE_CURRENCY) {
            return BASE_CURRENCY_UNIT;
        } else if (address(source) == address(0)) {
            return _fallbackOracle.getAssetPrice(asset);
        } else {
            int256 price = source.latestAnswer();
            if (price > 0) {
                return uint256(price);
            } else {
                return _fallbackOracle.getAssetPrice(asset);
            }
        }
    }

    /// @inheritdoc IPriceOracle
    function getAssetsPrices(
        address[] calldata assets
    ) external view override returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = getAssetPrice(assets[i]);
        }
        return prices;
    }

    /// @inheritdoc IPriceOracle
    function getSourceOfAsset(address asset) external view override returns (address) {
        return address(assetsSources[asset]);
    }

    /// @inheritdoc IPriceOracle
    function getFallbackOracle() external view returns (address) {
        return address(_fallbackOracle);
    }
}
