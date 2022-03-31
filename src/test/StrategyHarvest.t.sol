// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

// import {StrategyParams} from "../interfaces/Vault.sol";
import {StrategyFixture} from "./utils/StrategyFixture.sol";

contract StrategyHarvest is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    function testProfitableHarvest(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), user, _amount);

        // Deposit to the vault
        actions.userDeposit(user, vault, want, _amount);

        // Harvest 1: Send funds through the strategy
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        uint256 totalAssets = strategy.estimatedTotalAssets();
        assertRelApproxEq(totalAssets, _amount, DELTA);

        uint256 profitAmount = (_amount * 5) / 100;
        actions.generateProfit(strategy, whale, profitAmount);

        // check that estimatedTotalAssets estimates correctly
        assertRelApproxEq(
            strategy.estimatedTotalAssets(),
            totalAssets + profitAmount,
            DELTA
        );

        uint256 beforePps = vault.pricePerShare();
        // Harvest 2: Realize profit
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        // TODO: get profit from harvest event and assert equal to profitAmount

        skip(6 hours);
        uint256 profit = want.balanceOf(address(vault)); // Profits go to vault
        assertGt(strategy.estimatedTotalAssets() + profit, _amount);
        assertGt(vault.pricePerShare(), beforePps);
    }

    function testLossyHarvest(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), user, _amount);

        // Deposit to the vault
        actions.userDeposit(user, vault, want, _amount);

        // Harvest 1: Send funds through the strategy
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        uint256 totalAssets = strategy.estimatedTotalAssets();
        assertRelApproxEq(totalAssets, _amount, DELTA);

        uint256 lossAmount = (_amount * 5) / 100;
        actions.generateLoss(strategy, lossAmount);

        // check that estimatedTotalAssets estimates correctly
        assertRelApproxEq(
            totalAssets - lossAmount,
            strategy.estimatedTotalAssets(),
            DELTA
        );

        // Harvest 2: Realize loss
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        // TODO: get loss from harvest event and assert equal to lossAmount

        // User will withdraw accepting losses
        uint256 userBalance = vault.balanceOf(user);
        vm_std_cheats.prank(user);
        vault.withdraw(userBalance, user, 10_000);
        assertRelApproxEq(want.balanceOf(user) + lossAmount, _amount, DELTA);
    }

    // tests harvesting a strategy twice, once with loss and another with profit
    // it checks that even with previous profit and losses, accounting works as expected
    function testChoppyHarvest(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), user, _amount);

        // Deposit to the vault
        actions.userDeposit(user, vault, want, _amount);

        // Harvest 1: Send funds through the strategy
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        uint256 lossAmount = (_amount * 5) / 100;
        actions.generateLoss(strategy, lossAmount);

        // Harvest 2: Realize loss
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        // TODO: get loss from harvest event and assert equal to lossAmount

        uint256 profitAmount = (_amount * 10) / 100;
        actions.generateProfit(strategy, whale, profitAmount);

        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        // TODO: get profit from harvest event and assert equal to profitAmount

        skip(6 hours);

        // User will withdraw accepting losses
        vm_std_cheats.prank(user);
        vault.withdraw();
        // User will take 100% losses and 100% profits
        // assertRelApproxEq(
        //     want.balanceOf(user),
        //     _amount + profitAmount - lossAmount,
        //     DELTA
        // );
    }
}
