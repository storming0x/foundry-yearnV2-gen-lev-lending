// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyParams} from "../interfaces/Vault.sol";
import {StrategyFixture} from "./utils/StrategyFixture.sol";

// contract StrategyDeleverage is StrategyFixture {
//     function setUp() public override {
//         super.setUp();
//     }

//     function testDeleverageToZero() public {
//         tip(address(want), user, bigAmount);

//         // Deposit to the vault and harvest
//         actions.userDeposit(user, vault, want, bigAmount);
//         skip(1);
//         vm_std_cheats.prank(strategist);
//         strategy.harvest();

//         assertRelApproxEq(strategy.estimatedTotalAssets(), bigAmount, DELTA);

//         skip(1 weeks);
//         utils.strategyStatus(vault, strategy);

//         vm_std_cheats.prank(gov);
//         vault.revokeStrategy(address(strategy));
//         uint256 i = 0;
//         while (vault.debtOutstanding(address(strategy)) > 0 && i < 5) {
//             skip(1);
//             vm_std_cheats.prank(strategist);
//             strategy.harvest();
//             utils.strategyStatus(vault, strategy);
//             i++;
//         }

//         skip(6 hours);
//         utils.strategyStatus(vault, strategy);
//         assertLt(strategy.estimatedTotalAssets(), strategy.minWant());

//         StrategyParams memory sp = vault.strategies(address(strategy));
//         assertRelApproxEq(sp.totalLoss, 0, DELTA);
//     }

//     function testLargeDeleverageParameterChange() public {
//         tip(address(want), user, bigAmount);

//         // Deposit to the vault and harvest
//         actions.userDeposit(user, vault, want, bigAmount);
//         skip(1);
//         vm_std_cheats.prank(strategist);
//         strategy.harvest();

//         assertRelApproxEq(strategy.estimatedTotalAssets(), bigAmount, DELTA);

//         skip(1 weeks);

//         vm_std_cheats.startPrank(gov);
//         strategy.setCollateralTargets(
//             strategy.targetCollatRatio() / 2,
//             strategy.maxCollatRatio(),
//             strategy.maxBorrowCollatRatio(),
//             strategy.daiBorrowCollatRatio()
//         );
//         vm_std_cheats.stopPrank();

//         utils.strategyStatus(vault, strategy);

//         uint256 i = 0;
//         while (
//             !_assertRelApproxEq(
//                 strategy.getCurrentCollatRatio(),
//                 strategy.targetCollatRatio(),
//                 DELTA
//             )
//         ) {
//             skip(1);
//             vm_std_cheats.prank(strategist);
//             strategy.harvest();
//             utils.strategyStatus(vault, strategy);
//             i++;
//         }

//         assertRelApproxEq(
//             strategy.getCurrentCollatRatio(),
//             strategy.targetCollatRatio(),
//             DELTA
//         );
//         skip(6 hours);
//         utils.strategyStatus(vault, strategy);

//         StrategyParams memory sp = vault.strategies(address(strategy));
//         assertRelApproxEq(sp.totalLoss, 0, DELTA);
//     }

//     function testLargeManualDeleverageToZero() public {
//         tip(address(want), user, bigAmount);

//         // Deposit to the vault and harvest
//         actions.userDeposit(user, vault, want, bigAmount);
//         skip(1);
//         vm_std_cheats.prank(strategist);
//         strategy.harvest();

//         assertRelApproxEq(strategy.estimatedTotalAssets(), bigAmount, DELTA);

//         skip(1 weeks);
//         utils.strategyStatus(vault, strategy);

//         uint256 i = 0;
//         while (strategy.getCurrentSupply() > strategy.minWant()) {
//             skip(1);

//             (uint256 deposit, uint256 borrow) = strategy.getCurrentPosition();
//             uint256 theoMinDeposit = (borrow * 10**18) /
//                 strategy.maxCollatRatio();
//             uint256 stepSize = _min(uint256(deposit - theoMinDeposit), borrow);

//             vm_std_cheats.prank(gov);
//             strategy.manualDeleverage(stepSize);

//             i++;
//             (, uint256 borrows) = strategy.getCurrentPosition();
//             if (_assertRelApproxEq(borrows, 0, DELTA)) {
//                 break;
//             }
//         }

//         utils.strategyStatus(vault, strategy);

//         skip(1);
//         (uint256 deposits, ) = strategy.getCurrentPosition();
//         while (deposits > strategy.minWant()) {
//             vm_std_cheats.prank(gov);
//             strategy.manualReleaseWant(deposits);
//             (deposits, ) = strategy.getCurrentPosition();
//         }
//         assertLe(strategy.getCurrentSupply(), strategy.minWant());

//         if (strategy.estimatedRewardsInWant() >= strategy.minRewardToSell()) {
//             vm_std_cheats.prank(gov);
//             strategy.manualClaimAndSellRewards();
//         }

//         skip(6 hours);
//         utils.strategyStatus(vault, strategy);
//         assertGt(strategy.estimatedTotalAssets(), bigAmount);

//         vm_std_cheats.prank(gov);
//         vault.revokeStrategy(address(strategy));
//         skip(1);
//         vm_std_cheats.prank(strategist);
//         strategy.harvest();

//         assertLt(strategy.estimatedTotalAssets(), strategy.minWant());
//         StrategyParams memory sp = vault.strategies(address(strategy));
//         assertRelApproxEq(sp.totalLoss, 0, DELTA);
//     }

//     function _min(uint256 a, uint256 b) internal pure returns (uint256) {
//         return a > b ? b : a;
//     }

//     function _assertRelApproxEq(
//         uint256 a,
//         uint256 b,
//         uint256 maxPercentDelta
//     ) internal pure returns (bool) {
//         uint256 delta = a > b ? a - b : b - a;
//         uint256 maxRelDelta = b / maxPercentDelta;

//         if (delta > maxRelDelta) {
//             return false;
//         }
//         return true;
//     }
// }
