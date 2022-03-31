// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyParams} from "../interfaces/Vault.sol";
import {StrategyFixture} from "./utils/StrategyFixture.sol";

contract StrategyAirdrop is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    function testAirdrop(uint256 _amount) public {
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

        // we airdrop tokens to strategy
        uint256 airdropAmount = (_amount * 10) / 100;
        tip(address(want), whale, airdropAmount);
        vm_std_cheats.prank(whale);
        want.transfer(address(strategy), airdropAmount);

        // check that estimatedTotalAssets estimates correctly
        assertRelApproxEq(
            strategy.estimatedTotalAssets(),
            (totalAssets + airdropAmount + strategy.estimatedRewardsInWant()),
            DELTA
        );

        uint256 beforePps = vault.pricePerShare();
        // Harvest 2: Realize profit
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        skip(6 hours);
        uint256 profit = want.balanceOf(address(vault));
        StrategyParams memory sp = vault.strategies(address(strategy));
        assertGt(sp.totalDebt + profit, _amount);
        assertGt(vault.pricePerShare(), beforePps);
    }
}
