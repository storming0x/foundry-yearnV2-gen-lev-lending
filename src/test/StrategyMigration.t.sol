// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyFixture} from "./utils/StrategyFixture.sol";

// NOTE: if the name of the strat or file changes this needs to be updated
import {Strategy} from "../Strategy.sol";

contract StrategyMigrationTest is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    // TODO: Add tests that show proper migration of the strategy to a newer one
    // Use another copy of the strategy to simmulate the migration
    // Show that nothing is lost.
    function testMigration(uint256 _amount) public {
        vm_std_cheats.assume(
            _amount > 0.1 ether && _amount < 100_000_000 ether
        );
        tip(address(want), user, _amount);

        // Deposit to the vault and harvest
        actions.userDeposit(user, vault, want, _amount);
        skip(1);
        vm_std_cheats.prank(gov);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        uint256 preWantBalance = want.balanceOf(address(strategy));

        vm_std_cheats.prank(strategist);
        Strategy newStrategy = Strategy(deployStrategy(address(vault)));
        tip(address(weth), whale, 1e6);
        vm_std_cheats.prank(whale);
        weth.transfer(address(newStrategy), 1e6);

        // migration with more than dust reverts, there is no way to transfer the debt position
        vm_std_cheats.prank(gov);
        vm_std_cheats.expectRevert(bytes(""));
        vault.migrateStrategy(address(strategy), address(newStrategy));

        vm_std_cheats.prank(gov);
        vault.revokeStrategy(address(strategy));
        skip(1);
        vm_std_cheats.prank(gov);
        strategy.harvest();

        vm_std_cheats.prank(gov);
        vault.migrateStrategy(address(strategy), address(newStrategy));
        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(newStrategy), 10_000);
        skip(1);
        vm_std_cheats.prank(gov);
        newStrategy.harvest();

        assertRelApproxEq(newStrategy.estimatedTotalAssets(), _amount, DELTA);
        assertRelApproxEq(
            preWantBalance,
            want.balanceOf(address(newStrategy)),
            DELTA
        );

        vm_std_cheats.prank(gov);
        newStrategy.harvest();
    }
}
