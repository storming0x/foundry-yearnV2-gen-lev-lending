// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.12;

/************
@title IPriceOracleGetter interface
@notice Interface for the Aave price oracle.*/
interface IPriceOracleGetter {
    function getAssetPrice(address _asset) external view returns (uint256);

    function getAssetsPrices(address[] calldata _assets)
        external
        view
        returns (uint256[] memory);

    function getSourceOfAsset(address _asset) external view returns (address);

    function getFallbackOracle() external view returns (address);
}
