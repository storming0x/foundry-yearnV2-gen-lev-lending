// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.12;

import "./CTokenI.sol";

interface CEtherI is CTokenI {
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function liquidateBorrow(address borrower, CTokenI cTokenCollateral)
        external
        payable;

    function borrow(uint256 borrowAmount) external returns (uint256);

    function mint() external payable;

    function repayBorrow() external payable;
}
