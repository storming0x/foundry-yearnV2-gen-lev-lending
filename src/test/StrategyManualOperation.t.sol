// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyFixture} from "./utils/StrategyFixture.sol";

// TODO: check that all manual operation works as expected
// manual operation: those functions that are called by management to affect strategy's position
// e.g. repay debt manually
// e.g. emergency unstake
// contract StrategyManualOperation is StrategyFixture {
//     function setUp() public override {
//         super.setUp();
//     }

//     function testManualFunction1(uint256 _amount) public {
//         vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
//         tip(address(want), user, _amount);

//         // set up steady state
//         actions.userDeposit(user, vault, want, _amount);
//         skip(1);
//         vm_std_cheats.prank(strategist);
//         strategy.harvest();
//         uint256 totalAssets = strategy.estimatedTotalAssets();
//         assertRelApproxEq(totalAssets, _amount, DELTA);

//         // use manual function
//         // vm_std_cheats.prank(management);
//         // strategy.manualFunction(arg1, arg2);

//         // shut down strategy and check accounting
//         vm_std_cheats.prank(gov);
//         strategy.updateStrategyDebtRatio(address(strategy), 0);
//         vm_std_cheats.prank(strategist);
//         strategy.harvest();
//         skip(6 hours);
//     }
// }
