// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.12;

library SupportStructs {
    struct CalcMaxDebtLocalVars {
        uint256 availableLiquidity;
        uint256 totalStableDebt;
        uint256 totalVariableDebt;
        uint256 totalDebt;
        uint256 utilizationRate;
        uint256 totalLiquidity;
        uint256 targetUtilizationRate;
        uint256 maxProtocolDebt;
    }

    struct IrsVars {
        uint256 optimalRate;
        uint256 baseRate;
        uint256 slope1;
        uint256 slope2;
    }
}
