// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyFixture} from "./utils/StrategyFixture.sol";
import "forge-std/console.sol";

contract StrategyRevokeTest is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    function testRevokeStrategyFromVault(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), address(user), _amount);

        // Deposit to the vault and harvest
        actions.userDeposit(user, vault, want, _amount);
        skip(1);
        vm_std_cheats.prank(gov);
        strategy.harvest();

        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        vm_std_cheats.prank(gov);
        vault.revokeStrategy(address(strategy));
        skip(1);
        vm_std_cheats.prank(gov);
        strategy.harvest();
        assertRelApproxEq(want.balanceOf(address(vault)), _amount, DELTA);
    }

    function testRevokeStrategyFromStrategy(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), address(user), _amount);

        actions.userDeposit(user, vault, want, _amount);
        skip(1);
        vm_std_cheats.prank(gov);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        vm_std_cheats.prank(gov);
        strategy.setEmergencyExit();
        skip(1);
        vm_std_cheats.prank(gov);
        strategy.harvest();
        assertRelApproxEq(want.balanceOf(address(vault)), _amount, DELTA);
    }

    function testRevokeWithProfit(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), address(user), _amount);

        actions.userDeposit(user, vault, want, _amount);
        skip(1);
        vm_std_cheats.prank(gov);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        uint256 profitAmount = (_amount * 5) / 100; // generating a 5% profit
        actions.generateProfit(strategy, whale, profitAmount);

        // Revoke strategy
        vm_std_cheats.prank(gov);
        vault.revokeStrategy(address(strategy));
        skip(1);
        vm_std_cheats.prank(gov);
        strategy.harvest();
        checks.checkRevokedStrategy(vault, strategy);
    }
}
