// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyFixture} from "./utils/StrategyFixture.sol";

contract StrategyHealthCheck is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    function testHealthCheck(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), user, _amount);

        vm_std_cheats.prank(gov);
        strategy.setHealthCheck(0xDDCea799fF1699e98EDF118e0629A974Df7DF012);
        vm_std_cheats.prank(gov);
        strategy.setDoHealthCheck(true);

        // Deposit to the vault
        actions.userDeposit(user, vault, want, _amount);
        assertTrue(strategy.doHealthCheck());
        assertTrue(
            strategy.healthCheck() == 0xDDCea799fF1699e98EDF118e0629A974Df7DF012
        );

        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();

        skip(1 days);

        vm_std_cheats.prank(gov);
        strategy.setDoHealthCheck(true);

        uint256 lossAmount = (_amount * 5) / 100;
        actions.generateLoss(strategy, lossAmount);

        // Harvest should revert because the loss is unacceptable.
        // Revert crashes
        skip(1);
        vm_std_cheats.prank(strategist);
        vm_std_cheats.expectRevert("!healthcheck");
        strategy.harvest();

        // disable healthcheck
        vm_std_cheats.prank(gov);
        strategy.setDoHealthCheck(false);

        skip(1);
        // harvest should go through, taking the loss
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        // TODO: Check loss logged in event is less than or equal to lossAmount
    }
}
