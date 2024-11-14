// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

/**
 * @title IPriceOracleGetter
 * @notice Interface for the Atleta Lending price oracle.
 */
interface IPriceOracleGetter {
  /**
   * @notice Returns the asset price in the base currency
   * @param asset The address of the asset
   * @return The price of the asset
   */
  function getAssetPrice(address asset) external view returns (uint256);
}
