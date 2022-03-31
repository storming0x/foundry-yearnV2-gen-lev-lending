// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyFixture} from "./utils/StrategyFixture.sol";

// TODO: Add tests that show proper operation of this strategy through "emergencyExit"
//       Make sure to demonstrate the "worst case losses" as well as the time it takes

contract StrategyShutdownTest is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    function testShutdown(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), address(user), _amount);

        // Deposit to the vault and harvest
        actions.userDeposit(user, vault, want, _amount);
        skip(1);
        vm_std_cheats.prank(gov);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        // Generate profit
        uint256 profitAmount = (_amount * 10) / 100;
        actions.generateProfit(strategy, whale, profitAmount);

        skip(1);
        vm_std_cheats.prank(gov);
        strategy.harvest();
        skip(6 hours);

        uint256 totalGain = profitAmount;
        uint256 totalLoss = 0;
        uint256 totalDebt = _amount;
        checks.checkAccounting(
            vault,
            strategy,
            totalGain,
            totalLoss,
            totalDebt,
            DELTA
        );
    }
}
